import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'academic_services_hub_screen.dart';
import 'advising_hub_screen.dart';
import 'college_roster_admin_screen.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';
import 'portal_root.dart';
import 'public_landing_screen.dart';
import 'reports_hub_screen.dart';

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
  final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail;

  return [
    PortalNavItem(
      label: 'الموقع العام',
      icon: Icons.public_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
      ),
    ),
    PortalNavItem(
      label: 'لوحة الإدارة',
      icon: Icons.dashboard_outlined,
      selected: current == 'dashboard',
      onTap: () => Navigator.of(context).popUntil((r) => r.settings.name == kPortalRootRouteName),
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
  ];
}
