import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/excel_parser_service.dart';
import '../theme/app_theme.dart';
import 'hidden_admin_login_screen.dart';
import 'portal_accounts.dart';
import 'portal_footer.dart';

/// مفاتيح تخزين "تذكرني على هذا الجهاز" محليًا في متصفح المستخدم (لا تُرسَل
/// لأي خادم) - تُملأ تلقائيًا في المرة القادمة لتوفير وقت الدخول اليومي.
class _RememberMeKeys {
  static const mode = 'portal_remember_mode';
  static const shatr = 'portal_remember_shatr';
  static const department = 'portal_remember_department';
  static const adminRole = 'portal_remember_admin_role';
  static const password = 'portal_remember_password';
}

/// شاشة دخول بوابة الويب - تصميم بلوحين: جانب تعريفي بهوية الوحدة، وجانب
/// نموذج الدخول (إدارة الوحدة بصلاحياتها المتعددة، أو منسّقي الوحدة).
/// لا علاقة لهذه الشاشة بتطبيق الأندرويد إطلاقًا.
class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key});

  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

enum _LoginMode { admin, coordinator, collegeCoordinator }

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  _LoginMode _mode = _LoginMode.admin;
  String? _shatr;
  String? _department;
  String? _adminRole;
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPassword = prefs.getString(_RememberMeKeys.password);
    if (savedPassword == null) return;

    setState(() {
      _rememberMe = true;
      _passwordCtrl.text = savedPassword;
      final savedMode = prefs.getString(_RememberMeKeys.mode);
      _mode = switch (savedMode) {
        'coordinator' => _LoginMode.coordinator,
        'college_coordinator' => _LoginMode.collegeCoordinator,
        _ => _LoginMode.admin,
      };
      _shatr = prefs.getString(_RememberMeKeys.shatr);
      _department = prefs.getString(_RememberMeKeys.department);
      _adminRole = prefs.getString(_RememberMeKeys.adminRole);
    });
  }

  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_rememberMe) {
      await prefs.remove(_RememberMeKeys.mode);
      await prefs.remove(_RememberMeKeys.shatr);
      await prefs.remove(_RememberMeKeys.department);
      await prefs.remove(_RememberMeKeys.adminRole);
      await prefs.remove(_RememberMeKeys.password);
      return;
    }
    await prefs.setString(
      _RememberMeKeys.mode,
      switch (_mode) {
        _LoginMode.coordinator => 'coordinator',
        _LoginMode.collegeCoordinator => 'college_coordinator',
        _LoginMode.admin => 'admin',
      },
    );
    await prefs.setString(_RememberMeKeys.password, _passwordCtrl.text);
    if (_mode == _LoginMode.coordinator) {
      await prefs.setString(_RememberMeKeys.shatr, _shatr ?? '');
      await prefs.setString(_RememberMeKeys.department, _department ?? '');
      await prefs.remove(_RememberMeKeys.adminRole);
    } else if (_mode == _LoginMode.collegeCoordinator) {
      await prefs.setString(_RememberMeKeys.shatr, _shatr ?? '');
      await prefs.remove(_RememberMeKeys.department);
      await prefs.remove(_RememberMeKeys.adminRole);
    } else {
      await prefs.setString(_RememberMeKeys.adminRole, _adminRole ?? '');
      await prefs.remove(_RememberMeKeys.shatr);
      await prefs.remove(_RememberMeKeys.department);
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_mode == _LoginMode.coordinator &&
        (_shatr == null || _department == null)) {
      setState(() => _error = 'اختر الشطر والقسم أولاً');
      return;
    }
    if (_mode == _LoginMode.collegeCoordinator && _shatr == null) {
      setState(() => _error = 'اختر الشطر أولاً');
      return;
    }
    if (_mode == _LoginMode.admin && _adminRole == null) {
      setState(() => _error = 'اختر الصلاحية أولاً');
      return;
    }

    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = 'أدخل كلمة السر');
      return;
    }

    final String? email = switch (_mode) {
      _LoginMode.admin => PortalAccounts.adminRoleEmails[_adminRole],
      _LoginMode.coordinator => PortalAccounts.coordinatorEmail(_shatr!, _department!),
      _LoginMode.collegeCoordinator => PortalAccounts.collegeCoordinatorEmails[_shatr!],
    };

    if (email == null) {
      setState(() => _error = 'حدث خطأ في تحديد الحساب');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // بدون "تذكرني": الجلسة لا تُحفظ بعد إغلاق التبويب - مهم لأن هذا رابط
      // عام قد يُستخدم من أجهزة مشتركة بين عدة منسّقين. setPersistence مدعومة
      // على الويب فقط - على أندرويد الجلسة تُحفظ محليًا بشكل دائم افتراضيًا
      // بواسطة SDK نفسه، فلا حاجة لاستدعائها إطلاقًا هناك.
      //
      // دائمًا LOCAL (بغضّ النظر عن "تذكرني") - كانت SESSION تسبّب خروج
      // المستخدم فعليًا عند مجرد تحديث الصفحة (F5) بدل البقاء بنفس الجلسة،
      // وهو خلل لاحظه سليمان صراحةً (2026-08-09). الحماية من ترك الجلسة
      // مفتوحة على جهاز مشترك تغطّيها الآن آلية تسجيل الخروج التلقائي بعد 15
      // دقيقة خمول (انظر inactivity_auto_logout.dart) بدل الاعتماد على
      // SESSION فقط.
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _persistRememberedCredentials();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = 'كلمة السر غير صحيحة (${e.code})');
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
      // بلا سهم رجوع إطلاقًا لو ما فيه شيء يُرجَع له فعليًا - في تطبيق الجوال
      // (main_advising_app.dart) هذه الشاشة تُعرَض كجذر التطبيق مباشرة لمن
      // لم يسجّل دخوله بعد (`MobileAdvisingRoot`، بلا صفحة تعريفية قبلها)،
      // فكان السهم يظهر نشطًا لكنه لا يفعل شيئًا (`maybePop` على شاشة جذر
      // بلا مسار سابق) - يبدو للمستخدم وكأنه "عالق" بلا طريقة للخروج
      // (سليمان 2026-08-08). لو فُتحت هذه الشاشة بالدفع من مكان آخر (مثال:
      // إعادة الدخول من داخل البوابة) فالسهم يظهر ويعمل بشكل طبيعي.
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.green,
        automaticallyImplyLeading: false,
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
                    const Expanded(flex: 5, child: _BrandPanel()),
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 32,
                          ),
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
                    const SizedBox(height: 340, child: _BrandPanel()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildFormPanel(),
                    ),
                  ],
                ),
              );
            },
          ),
          // نقطة دخول مخفية تمامًا (شفافة بصريًا) أسفل يمين الشاشة - الضغط
          // المزدوج عليها فقط يفتح شاشة دخول المدير العام الخاصة. لا نص ولا
          // أيقونة ظاهرة لأي مستخدم عادي.
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
                child: Icon(
                  Icons.circle,
                  size: 8,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تسجيل الدخول',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر نوع الدخول لمتابعة العمل على البوابة',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
          ),
          const SizedBox(height: 28),
          _ModeToggle(
            mode: _mode,
            onChanged: (m) => setState(() {
              _mode = m;
              _error = null;
            }),
          ),
          const SizedBox(height: 26),
          if (_mode == _LoginMode.coordinator) ...[
            DropdownButtonFormField<String>(
              initialValue: _shatr,
              hint: const Text('اختر الشطر'),
              decoration: const InputDecoration(labelText: 'الشطر'),
              items: [
                ExcelParserService.shatrMale,
                ExcelParserService.shatrFemale,
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() {
                _shatr = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _department,
              hint: const Text('اختر القسم'),
              decoration: const InputDecoration(labelText: 'القسم'),
              items: ExcelParserService.departments
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() {
                _department = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          if (_mode == _LoginMode.collegeCoordinator) ...[
            DropdownButtonFormField<String>(
              initialValue: _shatr,
              hint: const Text('اختر الشطر'),
              decoration: const InputDecoration(labelText: 'الشطر'),
              items: [
                ExcelParserService.shatrMale,
                ExcelParserService.shatrFemale,
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() {
                _shatr = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          if (_mode == _LoginMode.admin) ...[
            DropdownButtonFormField<String>(
              initialValue: _adminRole,
              hint: const Text('اختر الصلاحية'),
              decoration: const InputDecoration(labelText: 'الصلاحية'),
              items: PortalAccounts.adminRoleEmails.keys
                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                  .toList(),
              onChanged: (v) => setState(() {
                _adminRole = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'كلمة السر',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
              ),
              const Text('تذكرني على هذا الجهاز'),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('تسجيل الدخول', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

/// اللوح التعريفي بهوية الوحدة (أخضر متدرّج + دوائر زخرفية شفافة + الشعار).
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.greenDark, AppColors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -60,
            right: -50,
            child: _decorCircle(160, AppColors.gold.withValues(alpha: 0.12)),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _decorCircle(220, Colors.white.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: 40,
            right: -30,
            child: _decorCircle(90, AppColors.gold.withValues(alpha: 0.1)),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 78,
                    height: 78,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.7),
                        width: 1.6,
                      ),
                    ),
                    child: const Text(
                      'TU',
                      style: TextStyle(
                        color: AppColors.goldLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'وحدة الإرشاد الأكاديمي\nوالخريجين',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'جامعة الطائف — كلية إدارة الأعمال',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 1,
                  width: 60,
                  color: AppColors.gold.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 14),
                Text(
                  'بوابة رفع وتنزيل ملفات\nمتابعة طلبات الإضافة والحذف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decorCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// مفتاح تبديل مخصّص بشريحة متحرّكة (بدل SegmentedButton الافتراضي الشاحب).
class _ModeToggle extends StatelessWidget {
  final _LoginMode mode;
  final ValueChanged<_LoginMode> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  static const _modes = [
    _LoginMode.admin,
    _LoginMode.coordinator,
    _LoginMode.collegeCoordinator,
  ];

  static const _labels = {
    _LoginMode.admin: 'إدارة الوحدة',
    _LoginMode.coordinator: 'منسّقو الأقسام',
    _LoginMode.collegeCoordinator: 'منسّق الكلية',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / _modes.length;
        final selectedIndex = _modes.indexOf(mode);

        return Container(
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                // العنصر الأول (admin) يُرسَم يمينًا في واجهة RTL (Row يعكس
                // ترتيب الرسم تلقائيًا)، فكلما زاد فهرس الوضع المختار انتقلت
                // المحاذاة من +1 (يمين) نحو -1 (يسار).
                alignment: Alignment(1 - (selectedIndex * 2 / (_modes.length - 1)), 0),
                child: Container(
                  width: segmentWidth - 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final m in _modes)
                    Expanded(
                      child: _toggleLabel(
                        _labels[m]!,
                        selected: mode == m,
                        onTap: () => onChanged(m),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toggleLabel(
    String text, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
