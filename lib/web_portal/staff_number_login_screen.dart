import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'hidden_admin_login_screen.dart';
import 'portal_footer.dart';
import 'portal_login_screen.dart' show BrandPanel;

/// مفتاح تخزين محلي (متصفح المستخدم فقط) يُسجَّل بعد أول دخول ناجح على هذا
/// الجهاز - يُستخدَم فقط لتخصيص نص الترحيب ("مرحبًا بعودتك" بدل "تسجيل
/// الدخول") لمن يعود لهذه الشاشة بعد تسجيل خروج سابق، ولا علاقة له بحفظ أي
/// بيانات دخول فعلية (بطلب سليمان 2026-08-21).
const _kHasSignedInBeforeKey = 'portal_has_signed_in_before';

/// شاشة الدخول الجديدة برقم المنسوب - المرحلة 3 من إعادة هيكلة الدخول
/// والصلاحيات (2026-08-15). كل شخص له حساب فردي (بريد داخلي مبني على رقم
/// منسوبه)، والتوجيه بعد الدخول تلقائي حسب دوره (Custom Claim) - انظر
/// portal_root.dart. أصبحت (2026-08-16) شاشة الدخول **الوحيدة** بالموقع
/// أيضًا (لا الجوال فقط) بطلب سليمان صراحةً - الموقع كان لا يزال بطور
/// التجربة بلا مستخدمين حقيقيين فعليًا، فلا ضرر من استبدال `PortalLoginScreen`
/// القديمة (بريد/كلمة سر بصلاحية مُختارة من قائمة) كنقطة دخول افتراضية.
/// الحسابات الثابتة القديمة (`admin@`, `ameen@`...) لا تزال تعمل تقنيًا -
/// حقل "رقم المنسوب" هنا مجرد بريد نصي على الويب (لوحة مفاتيح فعلية بلا قيد
/// رقمي)، فيمكن كتابة الجزء الأول من البريد القديم به مباشرة عند الحاجة.
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
  bool _hasSignedInBefore = false;

  @override
  void initState() {
    super.initState();
    _loadReturningVisitorFlag();
  }

  Future<void> _loadReturningVisitorFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSignedInBefore = prefs.getBool(_kHasSignedInBeforeKey) ?? false;
    if (mounted && hasSignedInBefore) setState(() => _hasSignedInBefore = true);
  }

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
      (await SharedPreferences.getInstance()).setBool(_kHasSignedInBeforeKey, true);
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

  static const _kFieldRadius = 10.0;
  static const _kFieldMinHeight = 54.0;

  InputDecoration _fieldDecoration({required String label, required IconData icon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      constraints: const BoxConstraints(minHeight: _kFieldMinHeight),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_kFieldRadius)),
    );
  }

  Widget _buildFormPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.badge_outlined, size: 45, color: AppColors.green),
          const SizedBox(height: 14),
          Text(
            _hasSignedInBefore ? 'مرحبًا بعودتك' : 'تسجيل الدخول',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
          ),
          const SizedBox(height: 7),
          Text(
            _hasSignedInBefore ? 'سجّل دخولك مجددًا للمتابعة' : 'أدخل رقم المنسوب وكلمة المرور',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14.5),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _staffNumberCtrl,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(label: 'رقم المنسوب', icon: Icons.badge_outlined),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            decoration: _fieldDecoration(
              label: 'كلمة المرور',
              icon: Icons.lock_outline,
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
          const SizedBox(height: 22),
          SizedBox(
            height: _kFieldMinHeight,
            child: ElevatedButton(
              onPressed: _loading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                elevation: 2,
                shadowColor: AppColors.green.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kFieldRadius)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('تسجيل الدخول', style: TextStyle(fontSize: 16.5)),
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
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Navigator.of(context).canPop() ? const _BackHomeAction() : null,
        centerTitle: false,
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
                            constraints: const BoxConstraints(maxWidth: 490),
                            child: _buildFormPanel(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // نموذج الدخول أولًا على الجوال/التابلت - المستخدم يصل لحقول
              // الدخول فورًا بلا حاجة للتمرير عبر اللوحة الخضراء، والهوية
              // تظهر بعده كسياق ثانوي (بطلب سليمان الصريح 2026-08-22).
              return SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildFormPanel(),
                    ),
                    const SizedBox(height: 170, child: BrandPanel(compact: true)),
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

/// رابط "العودة للرئيسية" - يستبدل السهم المستقل السابق الذي كان معزولًا
/// بلا توضيح لوجهته (بطلب سليمان الصريح 2026-08-22): إجراء ثانوي مُدمَج
/// (لا زر أساسي بارز) بلون الهوية الأخضر الداكن مع تأثير شفافية خفيف عند
/// المرور بالفأرة.
class _BackHomeAction extends StatefulWidget {
  const _BackHomeAction();

  @override
  State<_BackHomeAction> createState() => _BackHomeActionState();
}

class _BackHomeActionState extends State<_BackHomeAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // InkWell بدل GestureDetector الخام - يمنح تركيز لوحة المفاتيح (Tab)
    // وتفعيلًا بـEnter/Space تلقائيًا، بلا أي تأثير بصري إضافي غير مرغوب
    // (splash/highlight مُعطَّلان صراحةً للحفاظ على نفس مظهر شفافية التمرير
    // السابق فقط - بند "حالات focus/hover/keyboard" 2026-08-22).
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(6),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: AppColors.gold.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _hovered ? 0.78 : 1,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'العودة للرئيسية',
                    style: TextStyle(color: AppColors.greenDark, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_back, size: 17, color: AppColors.greenDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
