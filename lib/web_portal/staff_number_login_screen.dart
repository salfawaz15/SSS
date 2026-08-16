import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hidden_admin_login_screen.dart';
import 'portal_footer.dart';
import 'portal_login_screen.dart' show BrandPanel;

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
      // PortalRoot يعيد بناء نفسه تلقائيًا عند تغيّر حالة الدخول ويوجّه حسب
      // الدور - لكن هذه الشاشة نفسها مدفوعة (Navigator.push) فوقه في نفس
      // المكدّس، فتبقى ظاهرة تغطّيه ما لم نُرجِعها صراحةً (كانت هذه المشكلة
      // الفعلية: "لا يدخلني على الصفحة" رغم نجاح الدخول - سليمان 2026-08-15).
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException {
      setState(() => _error = 'رقم المنسوب أو كلمة المرور غير صحيحة');
    } catch (e) {
      setState(() => _error = 'تعذّر تسجيل الدخول: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildFormPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.badge_outlined, size: 40, color: AppColors.green),
          const SizedBox(height: 12),
          const Text(
            'تسجيل الدخول',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'أدخل رقم المنسوب وكلمة المرور',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
          ),
          const SizedBox(height: 28),
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
              style: ElevatedButton.styleFrom(
                elevation: 2,
                shadowColor: AppColors.green.withValues(alpha: 0.4),
              ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.green,
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: () => Navigator.of(context).maybePop())
            : null,
      ),
      bottomNavigationBar: const PortalFooterBar(),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(flex: 5, child: BrandPanel()),
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: _buildFormPanel(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 280, child: BrandPanel()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildFormPanel(),
                    ),
                  ],
                ),
              );
            },
          ),
          // نقطة دخول مخفية للمدير العام (اسم مستخدم/كلمة مرور نصّيان - بلا
          // قيد لوحة مفاتيح رقمية كخانة "رقم المنسوب" أعلاه) - نفس نمط
          // portal_login_screen.dart بالضبط. سليمان لاحظ صراحةً (2026-08-16)
          // أن خانة رقم المنسوب تفرض لوحة مفاتيح رقمية فيتعذّر كتابة
          // "admin"/"salfawaz" بها مباشرة - هذا المدخل المخفي يتجاوز المشكلة.
          Positioned(
            bottom: 10,
            right: 10,
            child: GestureDetector(
              onDoubleTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HiddenAdminLoginScreen()),
              ),
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Icon(Icons.circle, size: 8, color: Colors.black.withValues(alpha: 0.06)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
