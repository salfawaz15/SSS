import 'package:flutter/material.dart';

import 'hardship_cases_admin_screen.dart';
import 'portal_header.dart';
import 'public_landing_screen.dart';
import 'support_cases_admin_screen.dart';

/// شريط تنقّل الإدارة الموحّد - نفس أربعة تبويبات لوحة الإدارة الرئيسية
/// (لوحة الإدارة/الموقع العام/حالات الظروف الخاصة/الدعم النفسي)، تُبنى مرة
/// واحدة هنا وتُستخدم في كل صفحات الإدارة الفرعية أيضًا (التقارير، تنزيل
/// الملفات، تسكين المقررات...) بدل أن تظهر فقط في الصفحة الرئيسية - حتى لا
/// يفقد المستخدم القدرة على التنقّل السريع بين الأقسام الرئيسية بمجرد
/// الدخول لأي صفحة فرعية. زر "لوحة الإدارة" يعود دائمًا لأول صفحة في مكدّس
/// التنقّل (`popUntil isFirst`) بدل استيراد شاشة الإدارة نفسها هنا (تفاديًا
/// لاستيراد دائري بين الملفين).
List<PortalNavItem> buildAdminNavItems(BuildContext context, {required String current}) {
  return [
    PortalNavItem(
      label: 'لوحة الإدارة',
      icon: Icons.dashboard_outlined,
      selected: current == 'dashboard',
      onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
    ),
    PortalNavItem(
      label: 'الموقع العام',
      icon: Icons.public_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
      ),
    ),
    PortalNavItem(
      label: 'حالات الظروف الخاصة',
      icon: Icons.volunteer_activism_outlined,
      selected: current == 'hardship',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen()),
      ),
    ),
    PortalNavItem(
      label: 'الدعم النفسي والاجتماعي',
      icon: Icons.favorite_border,
      selected: current == 'support',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen()),
      ),
    ),
  ];
}
