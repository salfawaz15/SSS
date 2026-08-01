import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// نافذة "تغيير كلمة المرور" - متاحة لأي حساب مسجّل دخوله على البوابة
/// (إدارة، منسّق، عرض فقط) ليختار كلمة مرور تناسبه بنفسه بعد أول دخول.
/// تعمل بالكامل من المتصفح دون أي حاجة لصلاحيات إدارية، لأن Firebase Auth
/// يسمح لأي مستخدم بتغيير كلمة مروره الخاصة فقط (وليس كلمة مرور غيره).
Future<void> showChangePasswordDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const _ChangePasswordDialog(),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isSaving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordCtrl.text;
    final newPassword = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    if (currentPassword.isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'يرجى تعبئة كل الحقول');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _error = 'كلمة المرور الجديدة يجب ألا تقل عن 6 أحرف/أرقام');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _error = 'كلمة المرور الجديدة غير متطابقة مع تأكيدها');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = 'تعذّر تحديد الحساب الحالي');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
      _success = null;
    });

    try {
      // Firebase Auth يتطلّب تسجيل دخول "حديث" قبل السماح بتغيير كلمة
      // المرور - لذا نُعيد المصادقة بكلمة المرور الحالية أولًا.
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      setState(() => _success = 'تم تغيير كلمة المرور بنجاح');
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'كلمة المرور الحالية غير صحيحة'
            : 'تعذّر تغيير كلمة المرور، حاول مرة أخرى';
      });
    } catch (_) {
      setState(() => _error = 'تعذّر تغيير كلمة المرور، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير كلمة المرور'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_success != null)
              Text(_success!, style: TextStyle(color: Colors.green.shade700))
            else ...[
              TextField(
                controller: _currentPasswordCtrl,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordCtrl,
                obscureText: _obscureNew,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة'),
                onSubmitted: (_) => _isSaving ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_success != null ? 'إغلاق' : 'إلغاء'),
        ),
        if (_success == null)
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('حفظ'),
          ),
      ],
    );
  }
}
