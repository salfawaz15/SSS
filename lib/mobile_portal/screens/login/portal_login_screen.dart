import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../web_portal/portal_accounts.dart' show PortalAccounts;
import '../../theme/portal_theme.dart';

/// شاشة دخول "بوابة الإرشاد" - تخطيط رأسي أصيل للجوال (القسم 7)، لا تقسيم
/// 50/50 كصفحة دخول الموقع. تظهر دائمًا أولًا عند عدم وجود جلسة صالحة
/// (القسم 6) - لا صفحة هبوط ولا زر "العودة للرئيسية".
///
/// **رقم منسوب لا بريد إلكتروني**: نظام الدخول الفعلي بالمشروع
/// (`staff_number_login_screen.dart` بالموقع) يحوّل رقم المنسوب المُدخَل إلى
/// بريد داخلي `<رقم المنسوب>@${PortalAccounts.domain}` قبل مناداة Firebase
/// Auth - بما فيها حساب المدير العام `salfawaz` نفسه (نفس الصيغة بالضبط:
/// `salfawaz@${PortalAccounts.domain}` == `PortalAccounts.superAdminEmail`).
/// نعيد استخدام نفس الصيغة هنا حرفيًا بدل بريد خام، حتى لا يختلف سلوك الدخول
/// بين الموقع والتطبيق.
class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key});

  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _staffNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _staffNumberController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final staffNumber = _staffNumberController.text.trim();
      final email = '$staffNumber@${PortalAccounts.domain}';
      await authService.signInWithEmail(email, _passwordController.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.messageFromError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xl),
                Center(
                  // نفس الشعار الرسمي النظيف (خلفية مُفرَّغة فعليًا) المستخدَم
                  // بشاشة دخول الموقع (`portal_login_screen.dart` بالويب،
                  // BrandPanel) - لا شعار التطبيق المربَّع (`app_icon.png`
                  // خاص فقط بأيقونة الجهاز، ليس علامة العرض داخل الشاشات).
                  child: Image.asset(
                    'assets/images/unit_logo_clean_transparent_cropped.png',
                    height: 90,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(24)),
                      alignment: Alignment.center,
                      child: const Text('TU', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('بوابة الإرشاد', textAlign: TextAlign.center, style: AppTextStyles.h1()),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'وحدة الإرشاد الأكاديمي والخريجين',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(color: Colors.black54),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('مرحبًا بعودتك', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'سجّل دخولك لمتابعة أعمال الإرشاد الأكاديمي',
                  style: AppTextStyles.caption(color: Colors.black54),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.3)),
                    ),
                    child: Text(_errorMessage!, style: AppTextStyles.body(color: AppColors.errorRed)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _staffNumberController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'رقم المنسوب', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل رقم المنسوب' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('تسجيل الدخول'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('جامعة الطائف - كلية إدارة الأعمال', textAlign: TextAlign.center, style: AppTextStyles.caption(color: Colors.black45)),
                const SizedBox(height: AppSpacing.xs),
                Text('جميع الحقوق محفوظة لـ سليمان الفواز © 2026', textAlign: TextAlign.center, style: AppTextStyles.caption(color: Colors.black38)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
