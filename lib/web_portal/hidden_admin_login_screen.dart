import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'mobile_advising_root.dart';
import 'portal_accounts.dart';
import 'portal_root.dart';

/// شاشة دخول مخفية خاصة بحساب المدير العام (salfawaz) - لا يوجد أي رابط أو
/// زر ظاهر لها في أي مكان بالموقع؛ يُصل إليها فقط عبر معرفة الرابط السرّي
/// مباشرة على الويب (انظر SECRET_PATH في main.dart)، أو عبر نقطة الدخول
/// الخفية أسفل شاشة [PortalLoginScreen] على تطبيق الجوال (نفس الشاشة
/// مُعاد استخدامها هناك أيضًا - انظر mobile_advising_root.dart). تعرض اسم
/// مستخدم وكلمة مرور عاديين بدل قائمة الأدوار المعروضة في شاشة الدخول العامة.
class HiddenAdminLoginScreen extends StatefulWidget {
  const HiddenAdminLoginScreen({super.key});

  @override
  State<HiddenAdminLoginScreen> createState() => _HiddenAdminLoginScreenState();
}

class _HiddenAdminLoginScreenState extends State<HiddenAdminLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (username != 'salfawaz') {
      setState(() => _error = 'بيانات الدخول غير صحيحة');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: PortalAccounts.superAdminEmail,
        password: password,
      );
      if (mounted) {
        // على الويب: PortalRoot (تصميم لوحة الإدارة العريض، بحاجة اسم مسار
        // ثابت [kPortalRootRouteName] يستهدفه زر "لوحة الإدارة" لاحقًا - انظر
        // admin_nav.dart). على تطبيق الجوال: الشاشة الرئيسية الجوّالة الأصلية
        // مباشرة بدل تصميم الويب العريض غير المناسب لشاشة ضيقة.
        Navigator.of(context).pushAndRemoveUntil(
          kIsWeb
              ? MaterialPageRoute(
                  builder: (_) => const PortalRoot(),
                  settings: const RouteSettings(name: kPortalRootRouteName),
                )
              : MaterialPageRoute(builder: (_) => const MobileAdvisingRoot()),
          (route) => false,
        );
      }
    } on FirebaseAuthException {
      setState(() => _error = 'بيانات الدخول غير صحيحة');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1F17),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, color: Colors.white54, size: 40),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0E1F17),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('دخول'),
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
