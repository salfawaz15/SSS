import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'academic_services_hub_screen.dart';
import 'admin_workspace_screen.dart';
import 'advising_hub_screen.dart';
import 'college_roster_admin_screen.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';
import 'portal_root.dart';
import 'public_landing_screen.dart';
import 'reports_hub_screen.dart';
import 'test_switcher_screen.dart';
import 'upload_hub_screen.dart';

/// شريط تنقّل الإدارة الموحّد - يُبنى مرة واحدة هنا ويُستخدم في كل صفحات
/// الإدارة (الرئيسية والفرعية) حتى لا يفقد المستخدم القدرة على التنقّل
/// السريع بمجرد الدخول لأي صفحة فرعية.
///
/// ترتيب التبويبات (بطلب صريح من سليمان 2026-08-07): الموقع العام أولًا
/// (كالعادة بالمواقع الاحترافية) ثم لوحة الإدارة، ثم "لوحة الإرشاد" (تجمع
/// متابعة حالات الإرشاد/الظروف الخاصة/الدعم النفسي بدل تبويب مستقل لكل
/// منها) و"خدمات أكاديمية" (تسكين المقررات + الجدول الدراسي) و"المنسوبين" -
/// آخر اثنين حصريان لحساب المدير العام (نفس تقييد وصولهما الأصلي بلوحة
/// الإدارة، انظر [PortalAccounts.superAdminEmail]).
///
/// زر "لوحة الإدارة" كان يستخدم `popUntil((r) => r.isFirst)` ظنًا أن لوحة
/// الإدارة هي أول صفحة بمكدّس التنقّل دائمًا - خطأ فعلي عند الدخول العادي
/// (لا الرابط السرّي): الصفحة العامة [PublicLandingScreen] تبقى تحت
/// [PortalRoot] بالمكدّس، فكان الزر يرجع أبعد من اللازم للصفحة العامة
/// (يشعر المستخدم وكأنه "رجع لتسجيل الدخول" لأنه يحتاج يضغط دخول من جديد).
/// الحل: `popUntil` يستهدف الآن مسار [PortalRoot] تحديدًا عبر اسمه الثابت
/// [kPortalRootRouteName] (يُمرَّر عند كل دفع له - انظر
/// public_landing_screen.dart وhidden_admin_login_screen.dart) بدل الافتراض
/// الموضعي الخاطئ - يعمل صحيحًا من أي نقطة دخول.
List<PortalNavItem> buildAdminNavItems(BuildContext context, {required String current}) {
  final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
      PortalAccounts.isCurrentSessionSuperAdmin;

  return [
    PortalNavItem(
      label: 'الرئيسية',
      icon: Icons.public_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
      ),
    ),
    PortalNavItem(
      label: 'لوحة الإدارة',
      icon: Icons.dashboard_outlined,
      selected: current == 'dashboard',
      // `|| r.isFirst` احتياط ضروري منذ (main.dart، سليمان 2026-08-21): عند
      // الدخول التلقائي عبر جلسة محفوظة بعد F5، PortalRoot يُعرَض كصفحة
      // الجذر مباشرة (`MaterialApp.home`) بلا اسم مسار مخصَّص، فلا يطابق
      // الاسم الثابت - بدون هذا الاحتياط `popUntil` يحاول تجاوز المسار
      // الأول فيتعطّل.
      onTap: () => Navigator.of(context).popUntil((r) => r.settings.name == kPortalRootRouteName || r.isFirst),
    ),
    PortalNavItem(
      label: 'الحذف والإضافة',
      icon: Icons.assignment_outlined,
      selected: current == 'delete-add',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AdminWorkspaceScreen()),
      ),
    ),
    PortalNavItem(
      label: 'تقارير',
      icon: Icons.assessment_outlined,
      selected: current == 'reports-hub',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
      ),
    ),
    PortalNavItem(
      label: 'لوحة الإرشاد',
      icon: Icons.fact_check_outlined,
      selected: current == 'hardship' || current == 'support' || current == 'advising-cases' || current == 'advising-hub',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AdvisingHubScreen()),
      ),
    ),
    if (isSuperAdmin)
      PortalNavItem(
        label: 'خدمات أكاديمية',
        icon: Icons.school_outlined,
        selected: current == 'academic-services',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AcademicServicesHubScreen()),
        ),
      ),
    if (isSuperAdmin)
      PortalNavItem(
        label: 'المنسوبين',
        icon: Icons.badge_outlined,
        selected: current == 'college-roster',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CollegeRosterAdminScreen()),
        ),
      ),
    // صفحة مركزية لكل الملفات التي مصدرها المنظومة الداخلية للجامعة حصرًا
    // (بطلب سليمان 2026-08-17) - نفس تقييد الوصول لحساب المدير العام حاليًا،
    // مع خطة مستقبلية (لم تُنفَّذ بعد) لمنح نفس الصلاحية لمنسّق الوحدة
    // للشؤون الإدارية.
    if (isSuperAdmin)
      PortalNavItem(
        label: 'رفع وتنزيل الملفات',
        icon: Icons.cloud_upload_outlined,
        selected: current == 'upload-hub',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UploadHubScreen()),
        ),
      ),
    // حصريًا حساب المدير العام (salfawaz/super_admin) - ليس حساب "الإدارة"
    // العادي (admin@)، بطلب سليمان صراحةً (2026-08-15). أُعيدت تسميتها من
    // "تجربة الصفحات" إلى "الوصول التشغيلي" (سليمان 2026-08-19) لأن وظيفتها
    // ليست تجربة واجهات بل تمكين صاحب الصلاحية من الدخول لواجهات أدوار أخرى
    // وتنفيذ أعمالها فعليًا عند غياب منسّق أو عضو.
    if (isSuperAdmin)
      PortalNavItem(
        label: 'الوصول التشغيلي',
        icon: Icons.switch_account_outlined,
        selected: current == 'test-switcher',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TestSwitcherScreen()),
        ),
      ),
  ];
}
