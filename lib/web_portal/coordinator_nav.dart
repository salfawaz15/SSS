import 'package:flutter/material.dart';

import 'coordinator_advising_screen.dart';
import 'portal_header.dart';
import 'portal_root.dart';
import 'public_landing_screen.dart';
import 'reports_hub_screen.dart';

/// شريط تنقّل المنسّق الموحّد - نفس فكرة [buildAdminNavItems] لكن لصفحات
/// منسّق القسم (تحتاج شطر وقسم لتوجيه أزرار الحالات إلى قسمه هو بالتحديد).
///
/// نفس ترتيب/إصلاح شريط الإدارة (2026-08-07، انظر توثيق [buildAdminNavItems]
/// لتفصيل السبب): "الموقع العام" أولًا، و"لوحة المنسّق" ثانيًا مع استهداف
/// مسار [PortalRoot] تحديدًا عبر [kPortalRootRouteName] بدل الافتراض الخاطئ
/// أنها أول صفحة بالمكدّس.
///
/// **إعادة بناء كاملة (2026-08-09 بطلب سليمان: "الأصل والمميّز صفحة
/// الإدارة، عدّل صفحة المنسّقين")**: كل وجهات "لوحة المنسّق" بهذا الشريط
/// حصرًا - جسم الصفحة الرئيسية صار إحصائيات + رسم بياني فقط، تمامًا بنفس
/// فلسفة admin_workspace_screen.dart (كل الوجهات بالشريط العلوي، بلا أيقونات
/// وصول بالجسم). "الحذف والإضافة" تحتاج دالة من حالة
/// [CoordinatorWorkspaceScreen] نفسها (فيها حالة تحميل/رفع)، فتُمرَّر كدالة
/// اختيارية.
///
/// **إزالة "حالات الظروف الخاصة" و"الدعم النفسي والاجتماعي" (2026-08-15
/// بطلب سليمان)**: انتقلتا مفهوميًا لتصبحا مسؤولية "منسّق مسار الرعاية
/// الطلابية" الجديد (جزء من إعادة هيكلة الوحدة)، لا منسّق القسم - الشاشتان
/// الفعليتان (`HardshipCasesCoordinatorScreen`/`SupportCasesCoordinatorScreen`)
/// لم تُحذَفا، ستُعاد استخدامهما بصفحة منسّق المسار الجديدة.
List<PortalNavItem> buildCoordinatorNavItems(
  BuildContext context, {
  required String current,
  required String shatr,
  required String department,
  VoidCallback? onDeleteAdd,
}) {
  return [
    PortalNavItem(
      label: 'الرئيسية',
      icon: Icons.public_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
      ),
    ),
    PortalNavItem(
      label: 'لوحة المنسّق',
      icon: Icons.dashboard_outlined,
      selected: current == 'dashboard',
      // `|| r.isFirst` احتياط ضروري منذ (main.dart، سليمان 2026-08-21): عند
      // الدخول التلقائي عبر جلسة محفوظة بعد F5، PortalRoot يُعرَض كصفحة
      // الجذر مباشرة (`MaterialApp.home`) بلا اسم مسار مخصَّص، فلا يطابق
      // الاسم الثابت - بدون هذا الاحتياط `popUntil` يحاول تجاوز المسار
      // الأول فيتعطّل.
      onTap: () => Navigator.of(context).popUntil((r) => r.settings.name == kPortalRootRouteName || r.isFirst),
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
      label: 'تقارير',
      icon: Icons.assessment_outlined,
      selected: current == 'reports-hub',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
      ),
    ),
  ];
}
