import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/web_reload.dart';
import '../services/web_version_check_service.dart';
import '../theme/app_theme.dart';
import 'change_password_dialog.dart';
import 'portal_accounts.dart';
import 'portal_footer.dart';
import 'portal_operations_guide_page.dart';
import 'public_landing_screen.dart';
import 'quick_search_index.dart';
import 'round_icon_button.dart';

/// عنصر تنقّل واحد في الشريط العلوي للبوابة (نفس فكرة تبويبات الصفحة
/// العامة `_NavBar` في public_landing_screen.dart، لكن لأقسام البوابة
/// الداخلية بدل صفحات الموقع التعريفي).
class PortalNavItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  const PortalNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
}

/// شارة الهوية - نفس صورة الشعار المعتمدة بالضبط في الشريط العلوي للصفحة
/// العامة (`assets/images/full_logo_green.png`، خلفية خضراء + TU بحلقة
/// ذهبية + اسم الكلية والوحدة) بلا إعادة بنائها يدويًا بخط/تنسيق مختلف،
/// حتى تكون بصمة الهوية مطابقة 100% سواء قبل تسجيل الدخول أو داخل البوابة.
///
/// **داخل تطبيق الجوال فقط** (`!kIsWeb`) تُستبدَل بأيقونة التطبيق المصغَّرة
/// نفسها الظاهرة خارجيًا على شاشة الجهاز (`assets/images/app_icon.png`) -
/// الشعار الكامل العريض (مصمَّم أصلاً لعرض الحاسوب) كان يظهر ضخمًا جدًا على
/// شاشة الجوال الضيقة (سليمان 2026-08-09). الموقع (الويب) يبقى بالشعار
/// الكامل كما هو بلا أي تغيير.
class _PortalBrandBadge extends StatelessWidget {
  const _PortalBrandBadge();

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/images/app_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('TU', style: AppTextStyles.caption(color: Colors.white)),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Image.asset(
        'assets/images/full_logo_green.png',
        height: 40,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Text('TU', style: AppTextStyles.caption(color: Colors.white)),
      ),
    );
  }
}

/// قائمة الحساب الموحّدة (تغيير كلمة المرور، دليل تشغيل البوابة، تسجيل
/// خروج) - جزء ثابت من [PortalHeader] نفسه بدل أن يبنيها كل شاشة رئيسية
/// من الصفر (كانت مكرَّرة بـ4 ملفات مختلفة). تظهر في **كل** صفحات البوابة
/// بلا استثناء (حتى الصفحات الفرعية المفتوحة بـ`Navigator.push`)، لأنها
/// جزء من الهيدر لا من `actions` الاختيارية لكل صفحة - يحل جذريًا مشكلة
/// عدم القدرة على تسجيل الخروج من صفحة فرعية (كانت تتطلب الرجوع أولًا
/// للصفحة الرئيسية التي وحدها كانت تحمل هذه القائمة).
class _PortalAccountMenu extends StatelessWidget {
  const _PortalAccountMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.account_circle_outlined, color: AppColors.green),
      tooltip: 'الحساب',
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => showChangePasswordDialog(context),
          child: const PortalMenuRow(icon: Icons.lock_outline, label: 'تغيير كلمة المرور'),
        ),
        PopupMenuItem(
          value: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PortalOperationsGuidePage()),
          ),
          child: const PortalMenuRow(icon: Icons.menu_book_outlined, label: 'دليل تشغيل البوابة'),
        ),
        PopupMenuItem(
          value: () {
            // تسجيل الخروج ينقل مباشرة للصفحة العامة (لا لشاشة تسجيل
            // الدخول) - قرار سليمان الصريح 2026-08-21: نهاية الجلسة تعني
            // "زائر عادي" فورًا، بلا خطوة وسيطة تُعيد عرض نموذج الدخول قبل
            // أن يقرر المستخدم إن كان يريد الدخول من جديد أصلاً. نستخدم
            // `pushAndRemoveUntil` بدل `popUntil` (كانت المحاولة السابقة)
            // لأنها تضمن تفريغ كل مكدّس التنقّل والوصول للصفحة العامة بشكل
            // مؤكَّد بغض النظر عن نقطة الدخول الأصلية (رابط عادي أو رابط
            // الدخول السرّي)، لا الاعتماد على افتراض أن أول صفحة بالمكدّس
            // هي دائمًا الصفحة العامة.
            FirebaseAuth.instance.signOut();
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
              (route) => false,
            );
          },
          child: PortalMenuRow(icon: Icons.logout, label: 'تسجيل خروج', color: Colors.red.shade700),
        ),
      ],
    );
  }
}

/// بيانات الدور المطلوبة لبناء عناصر "البحث السريع" - تُحسَم مرة واحدة عند
/// فتح حوار البحث (منسّق القسم فقط يحتاج جلبًا إضافيًا من Firestore
/// لمعرفة شطره/قسمه، بنفس أسلوب reports_hub_screen.dart).
class _QuickSearchRoleInfo {
  final String role;
  final bool isSuperAdmin;
  final String? uid;
  final String? shatr;
  final String? department;

  const _QuickSearchRoleInfo({
    required this.role,
    this.isSuperAdmin = false,
    this.uid,
    this.shatr,
    this.department,
  });
}

Future<_QuickSearchRoleInfo> _resolveQuickSearchRole() async {
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email;

  if (PortalAccounts.isFullAdmin(email)) {
    return _QuickSearchRoleInfo(
      role: QuickSearchRole.fullAdmin,
      isSuperAdmin: email == PortalAccounts.superAdminEmail || PortalAccounts.isCurrentSessionSuperAdmin,
    );
  }
  if (PortalAccounts.viewerEmails.values.contains(email)) {
    return const _QuickSearchRoleInfo(role: QuickSearchRole.viewer);
  }
  if (PortalAccounts.isCollegeCoordinator(email)) {
    return _QuickSearchRoleInfo(role: QuickSearchRole.collegeCoordinator, uid: user?.uid);
  }
  if (PortalAccounts.isUnitCoordinator(email)) {
    return const _QuickSearchRoleInfo(role: QuickSearchRole.unitCoordinator);
  }

  final uid = user?.uid;
  if (uid == null) return const _QuickSearchRoleInfo(role: QuickSearchRole.unitCoordinator);
  final doc = await FirebaseFirestore.instance.collection('coordinator_accounts').doc(uid).get();
  final data = doc.data();
  return _QuickSearchRoleInfo(
    role: QuickSearchRole.departmentCoordinator,
    uid: uid,
    shatr: data?['shatr']?.toString(),
    department: data?['department']?.toString(),
  );
}

/// أيقونة "بحث سريع" ثابتة بالهيدر (نفس فكرة أيقونة البحث بموقع سدايا
/// المرجعي) - تظهر في كل صفحات البوابة بلا استثناء لأنها جزء من
/// [PortalHeader] نفسه لا من `actions` كل صفحة على حدة. الضغط عليها يفتح
/// حوار بحث فيه اقتراحات جاهزة كشرائح قابلة للضغط قبل الكتابة، وتتحوّل فور
/// الكتابة لقائمة نتائج مطابقة (عنوان أو كلمة مفتاحية) - كل نتيجة تنقل
/// فورًا لشاشتها الحقيقية.
class _PortalQuickSearchButton extends StatelessWidget {
  const _PortalQuickSearchButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.search, color: AppColors.green),
      tooltip: 'بحث سريع',
      onPressed: () => _openQuickSearch(context),
    );
  }

  Future<void> _openQuickSearch(BuildContext context) async {
    showDialog(
      context: context,
      builder: (dialogContext) => FutureBuilder<_QuickSearchRoleInfo>(
        future: _resolveQuickSearchRole(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: SizedBox(
                  height: 40,
                  width: 40,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            );
          }
          final info = snapshot.data!;
          final entries = buildQuickSearchEntries(
            context,
            role: info.role,
            isSuperAdmin: info.isSuperAdmin,
            uid: info.uid,
            shatr: info.shatr,
            department: info.department,
          );
          return _QuickSearchDialog(entries: entries);
        },
      ),
    );
  }
}

class _QuickSearchDialog extends StatefulWidget {
  final List<QuickSearchEntry> entries;

  const _QuickSearchDialog({required this.entries});

  @override
  State<_QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<_QuickSearchDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(QuickSearchEntry entry) {
    Navigator.of(context).pop();
    entry.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final suggestions = widget.entries.take(8).toList();
    final results = query.isEmpty
        ? const <QuickSearchEntry>[]
        : widget.entries.where((e) => e.matches(query)).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.search, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('بحث سريع', style: AppTextStyles.h3())),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'اكتب اسم الصفحة أو الإجراء (مثال: جداول)',
                  prefixIcon: const Icon(Icons.travel_explore_outlined),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: query.isEmpty
                    ? SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (suggestions.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    'لا توجد اختصارات بحث لدورك الحالي',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                ),
                              )
                            else ...[
                              Text('اقتراحات سريعة', style: AppTextStyles.caption(color: Colors.grey.shade600)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: suggestions
                                    .map(
                                      (e) => ActionChip(
                                        avatar: Icon(e.icon, size: 16, color: AppColors.green),
                                        label: Text(e.title),
                                        onPressed: () => _select(e),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      )
                    : (results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.grey.shade600)),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              final e = results[i];
                              return ListTile(
                                leading: Icon(e.icon, color: AppColors.green),
                                title: Text(e.title),
                                onTap: () => _select(e),
                              );
                            },
                          )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// زر "التقويم الجامعي" ثابت بالهيدر - يظهر في **كل** صفحات البوابة
/// الداخلية بلا استثناء (إدارة/منسّقين/عرض) لأنه جزء من [PortalHeader] نفسه
/// لا من `navItems` كل شاشة على حدة، بنفس فكرة زر البحث السريع. سليمان طلب
/// (2026-08-16) أن يظهر التقويم بكل البوابات من الإدارة حتى صفحات الدخول -
/// هذا الزر يحل الجزء الداخلي، وأزرار مشابهة أُضيفت لصفحتَي الدخول
/// (`portal_login_screen.dart`/`staff_number_login_screen.dart`) للجزء قبل
/// الدخول. يفتح نفس [AcademicCalendarPage] المستخدَمة بالصفحة العامة.
class _PortalCalendarButton extends StatelessWidget {
  const _PortalCalendarButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.calendar_month_outlined, color: AppColors.green),
      tooltip: 'التقويم الجامعي',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PortalAcademicCalendarPage()),
      ),
    );
  }
}

/// زر "يتوفر تحديث" بالشريط العلوي (الويب فقط) - يظهر أصفر فقط عند اكتشاف
/// أن `web/version.json` المنشور بجذر الموقع يحمل رقم بناء أحدث من النسخة
/// المحمَّلة حاليًا بالمتصفح ([kAppBuildNumber])، والضغط عليه يعيد تحميل
/// الصفحة من الخادم مباشرة (لا نسخة مخبَّأة). لا يظهر إطلاقًا إن كانت
/// النسخة الحالية هي الأحدث. سليمان طلب (2026-08-15) إشارة توضح صراحةً
/// وجود إصدار أحدث بدل الاعتماد على تحديث المتصفح يدويًا.
class _PortalUpdateButton extends StatefulWidget {
  const _PortalUpdateButton();

  @override
  State<_PortalUpdateButton> createState() => _PortalUpdateButtonState();
}

class _PortalUpdateButtonState extends State<_PortalUpdateButton> {
  bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebVersionCheckService.isNewerVersionAvailable().then((has) {
        if (mounted && has) setState(() => _hasUpdate = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_hasUpdate) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.amber.shade600,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: reloadWebApp,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_outlined, size: 16, color: Colors.black87),
                SizedBox(width: 6),
                Text('يتوفر تحديث', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// الشريط العلوي الموحّد لكل صفحات البوابة الداخلية: خط تمييز رفيع بلون
/// الهوية، ثم شريط أبيض يحمل شارة الهوية أولًا (تظهر دائمًا مهما كانت
/// الصفحة)، وتبويبات تنقّل اختيارية لأقسام البوابة الرئيسية (تتكيّف حسب
/// الدور: مدير/منسّق/عرض)، وإجراءات مساعدة (بحث/إشعارات/قائمة المزيد) على
/// الطرف الآخر. يحلّ محل بناء كل شاشة لشريط هوية/AppBar خاص بها من الصفر.
class PortalHeader extends StatelessWidget implements PreferredSizeWidget {
  final List<PortalNavItem> navItems;
  final List<Widget>? trailing;
  final bool showBackButton;
  final String? fallbackTitle;

  const PortalHeader({
    super.key,
    this.navItems = const [],
    this.trailing,
    this.showBackButton = false,
    this.fallbackTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 4, color: AppColors.greenDark),
        Container(
          width: double.infinity,
          height: 56,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              Widget navButton(PortalNavItem item) {
                return TextButton.icon(
                  onPressed: item.onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: item.selected ? AppColors.green : Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    // خط سفلي رفيع بلون الهوية يميّز التبويب النشط بدل الاعتماد
                    // على وزن الخط وحده - تفريق بصري أوضح بشريط مزدحم (بطلب
                    // سليمان 2026-08-19: العنصر النشط يجب أن يكون واضحًا).
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: item.selected ? AppColors.gold : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  icon: Icon(item.icon, size: 16),
                  label: Text(
                    item.label,
                    style: TextStyle(fontWeight: item.selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13),
                  ),
                );
              }

              final backButton = showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.green),
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : const SizedBox.shrink();

              if (isWide) {
                return Row(
                  children: [
                    backButton,
                    const _PortalBrandBadge(),
                    const SizedBox(width: 18),
                    if (navItems.isNotEmpty)
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: navItems.map(navButton).toList()),
                        ),
                      )
                    else if (fallbackTitle != null)
                      Text(fallbackTitle!, style: AppTextStyles.h3())
                    else
                      const Spacer(),
                    ...?trailing,
                    const _PortalUpdateButton(),
                    const _PortalCalendarButton(),
                    const _PortalQuickSearchButton(),
                    const _PortalAccountMenu(),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [backButton, const _PortalBrandBadge()]),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...?trailing,
                      const _PortalUpdateButton(),
                      const _PortalCalendarButton(),
                      const _PortalQuickSearchButton(),
                      const _PortalAccountMenu(),
                      if (navItems.isNotEmpty)
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.menu, color: AppColors.green),
                          tooltip: 'أقسام البوابة',
                          itemBuilder: (context) => [
                            for (var i = 0; i < navItems.length; i++)
                              PopupMenuItem(
                                value: i,
                                child: Row(
                                  children: [
                                    Icon(navItems[i].icon, size: 18, color: AppColors.green),
                                    const SizedBox(width: 10),
                                    Text(navItems[i].label),
                                  ],
                                ),
                              ),
                          ],
                          onSelected: (i) => navItems[i].onTap(),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(4 + 56);
}

/// إطار صفحة موحّد لكل شاشات البوابة الداخلية: `PortalHeader` (شارة الهوية
/// دائمًا + تبويبات تنقّل اختيارية) أعلى الصفحة بلا استثناء، ثم صف
/// تبويبات فرعية اختياري (`bottom`، مثل TabBar صفحة معيّنة)، ثم المحتوى،
/// ثم تذييل الحقوق `PortalFooterBar` أسفل الصفحة.
class PortalScaffold extends StatelessWidget {
  final String title;
  final List<PortalNavItem> navItems;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showBackButton;
  final Widget body;
  final Widget? floatingActionButton;

  const PortalScaffold({
    super.key,
    required this.title,
    required this.body,
    this.navItems = const [],
    this.actions,
    this.bottom,
    this.showBackButton = true,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final header = PortalHeader(
      navItems: navItems,
      trailing: actions,
      showBackButton: showBackButton,
      fallbackTitle: navItems.isEmpty ? title : null,
    );
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(header.preferredSize.height + bottomHeight),
        child: Column(
          children: [
            header,
            ?bottom,
          ],
        ),
      ),
      bottomNavigationBar: const PortalFooterBar(),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}
