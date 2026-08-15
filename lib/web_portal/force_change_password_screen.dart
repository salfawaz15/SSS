import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// شاشة إجبارية لتغيير كلمة المرور المبدئية - تظهر تلقائيًا بأول دخول لأي
/// حساب بالنظام الجديد (علم mustChangePassword بوثيقة portal_users)، ولا
/// يمكن تجاوزها لأي صفحة أخرى بالبوابة قبل اختيار كلمة مرور شخصية - المرحلة
/// 3 من إعادة هيكلة الدخول والصلاحيات (2026-08-15).
class ForceChangePasswordScreen extends StatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  State<ForceChangePasswordScreen> createState() => _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState extends State<ForceChangePasswordScreen> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPassword = _newPasswordCtrl.text;
    if (newPassword.length < 6) {
      setState(() => _error = 'كلمة المرور يجب ألا تقل عن 6 أحرف');
      return;
    }
    if (newPassword != _confirmCtrl.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('انتهت الجلسة، سجّل الدخول مجددًا');
      await user.updatePassword(newPassword);
      await FirebaseFirestore.instance.collection('portal_users').doc(user.uid).update({
        'mustChangePassword': false,
      });
      // لا حاجة للتنقّل يدويًا - PortalRoot يعيد البناء تلقائيًا بمجرد تغيّر
      // الوثيقة، وينقل المستخدم لصفحته الحقيقية.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = 'تعذّر تغيير كلمة المرور (${e.code}) - قد تحتاج تسجيل الدخول من جديد ثم إعادة المحاولة');
    } catch (e) {
      setState(() => _error = 'تعذّر تغيير كلمة المرور: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.green,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_reset_outlined, size: 48, color: AppColors.gold),
                const SizedBox(height: 16),
                const Text(
                  'هذا أول دخول لك - اختر كلمة مرورك الخاصة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'لا يمكن المتابعة للبوابة قبل تغيير كلمة المرور المبدئية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _newPasswordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('حفظ ومتابعة', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
