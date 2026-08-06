import 'package:flutter/material.dart';

import 'hardship_cases_coordinator_screen.dart';
import 'portal_header.dart';
import 'public_landing_screen.dart';
import 'support_cases_coordinator_screen.dart';

/// شريط تنقّل المنسّق الموحّد - نفس فكرة [buildAdminNavItems] لكن لصفحات
/// منسّق القسم (تحتاج شطر وقسم لتوجيه أزرار الحالات إلى قسمه هو بالتحديد).
List<PortalNavItem> buildCoordinatorNavItems(
  BuildContext context, {
  required String current,
  required String shatr,
  required String department,
}) {
  return [
    PortalNavItem(
      label: 'لوحة المنسّق',
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
  ];
}
