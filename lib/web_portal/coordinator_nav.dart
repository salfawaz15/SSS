import 'package:flutter/material.dart';

import 'coordinator_advising_screen.dart';
import 'hardship_cases_coordinator_screen.dart';
import 'portal_header.dart';
import 'portal_root.dart';
import 'public_landing_screen.dart';
import 'reports_hub_screen.dart';
import 'support_cases_coordinator_screen.dart';

/// شريط تنقّل المنسّق الموحّد - نفس فكرة [buildAdminNavItems] لكن لصفحات
/// منسّق القسم (تحتاج شطر وقسم لتوجيه أزرار الحالات إلى قسمه هو بالتحديد).
///
/// نفس ترتيب/إصلاح شريط الإدارة (2026-08-07، انظر توثيق [buildAdminNavItems]
/// لتفصيل السبب): "الموقع العام" أولًا، و"لوحة المنسّق" ثانيًا مع استهداف
/// مسار [PortalRoot] تحديدًا عبر [kPortalRootRouteName] بدل الافتراض الخاطئ
/// أنها أول صفحة بالمكدّس.
///
/// **إعادة بناء كاملة (2026-08-09 بطلب سليمان: "الأصل والمميّز صفحة
/// الإدارة، عدّل صفحة المنسّقين")**: كل وجهات "لوحة المنسّق" الخمس (الحذف
/// والإضافة، الإرشاد، حالات الظروف الخاصة، الدعم النفسي، التقارير) بهذا
/// الشريط حصرًا - جسم الصفحة الرئيسية صار إحصائيات + رسم بياني فقط، تمامًا
/// بنفس فلسفة admin_workspace_screen.dart (كل الوجهات بالشريط العلوي، بلا
/// أيقونات وصول بالجسم). "الحذف والإضافة" تحتاج دالة من حالة
/// [CoordinatorWorkspaceScreen] نفسها (فيها حالة تحميل/رفع)، فتُمرَّر كدالة
/// اختيارية.
List<PortalNavItem> buildCoordinatorNavItems(
  BuildContext context, {
  required String current,
  required String shatr,
  required String department,
  VoidCallback? onDeleteAdd,
}) {
  return [
    PortalNavItem(
      label: 'الموقع العام',
      icon: Icons.public_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
      ),
    ),
    PortalNavItem(
      label: 'لوحة المنسّق',
      icon: Icons.dashboard_outlined,
      selected: current == 'dashboard',
      onTap: () => Navigator.of(context).popUntil((r) => r.settings.name == kPortalRootRouteName),
    ),
    if (onDeleteAdd != null)
      PortalNavItem(
        label: 'الحذف والإضافة',
        icon: Icons.swap_vert_rounded,
        selected: current == 'delete-add',
        onTap: onDeleteAdd,
      ),
    PortalNavItem(
      label: 'الإرشاد',
      icon: Icons.school_outlined,
      selected: current == 'advising',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CoordinatorAdvisingScreen(shatr: shatr, department: department),
        ),
      ),
    ),
    PortalNavItem(
      label: 'حالات الظروف الخاصة',
      icon: Icons.volunteer_activism_outlined,
      selected: current == 'hardship',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HardshipCasesCoordinatorScreen(shatr: shatr, department: department),
        ),
      ),
    ),
    PortalNavItem(
      label: 'الدعم النفسي والاجتماعي',
      icon: Icons.favorite_border,
      selected: current == 'support',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupportCasesCoordinatorScreen(shatr: shatr, department: department),
        ),
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
  ];
}
