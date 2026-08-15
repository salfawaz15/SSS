import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'portal_footer.dart';

/// شاشة الدخول الجديدة برقم المنسوب - المرحلة 3 من إعادة هيكلة الدخول
/// والصلاحيات (2026-08-15). كل شخص له حساب فردي (بريد داخلي مبني على رقم
/// منسوبه)، والتوجيه بعد الدخول تلقائي حسب دوره (Custom Claim) - انظر
/// portal_root.dart. مستقلة تمامًا عن شاشة الدخول القديمة عمدًا (بدل دمجها)
/// حتى لا يتأثر من لم يُنقَل حسابه بعد للنظام الجديد.
class StaffNumberLoginScreen extends StatefulWidget {
  const StaffNumberLoginScreen({super.key});

  @override
  State<StaffNumberLoginScreen> createState() => _StaffNumberLoginScreenState();
}

class _StaffNumberLoginScreenState extends State<StaffNumberLoginScreen> {
  final _staffNumberCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _staffNumberCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final staffNumber = _staffNumberCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (staffNumber.isEmpty) {
      setState(() => _error = 'أدخل رقم المنسوب');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: '$staffNumber@sss-advising-tu.internal',
        password: password,
      );
      // لا حاجة للتنقّل يدويًا - PortalRoot يستمع لتغيّر حالة الدخول ويوجّه
      // تلقائيًا حسب الدور.
    } on FirebaseAuthException {
      setState(() => _error = 'رقم المنسوب أو كلمة المرور غير صحيحة');
    } catch (e) {
      setState(() => _error = 'تعذّر تسجيل الدخول: $e');
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
        title: const Text('الدخول برقم المنسوب'),
      ),
      bottomNavigationBar: const PortalFooterBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.badge_outlined, size: 48, color: AppColors.green),
                const SizedBox(height: 16),
                const Text(
                  'تسجيل الدخول',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  'أدخل رقم المنسوب وكلمة المرور',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _staffNumberCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رقم المنسوب',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('تسجيل الدخول', style: TextStyle(fontSize: 16)),
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
