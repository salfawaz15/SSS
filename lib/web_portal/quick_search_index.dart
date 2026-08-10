import 'package:flutter/material.dart';

import 'academic_services_hub_screen.dart';
import 'admin_reports_screen.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_hub_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'college_roster_admin_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'course_schedule_admin_screen.dart';
import 'hardship_cases_admin_screen.dart';
import 'hardship_cases_coordinator_screen.dart';
import 'portal_operations_guide_page.dart';
import 'portal_sitemap_screen.dart';
import 'reports_hub_screen.dart';
import 'support_cases_admin_screen.dart';
import 'support_cases_coordinator_screen.dart';
import 'viewer_reports_screen.dart';

/// بند واحد في "البحث السريع" (Command Palette) - عنوان + كلمات مفتاحية
/// مرادفة (تُطابَق بلا حساسية لحالة الأحرف أو المسافات) + أيقونة + إجراء
/// تنقّل حقيقي لشاشة موجودة فعليًا بالمشروع. لا يبني أي منطق جديد - كل
/// عنصر يفتح نفس الشاشة التي يفتحها زرها الأصلي في مكانها المعتاد.
class QuickSearchEntry {
  final String title;
  final List<String> keywords;
  final IconData icon;
  final VoidCallback onTap;

  const QuickSearchEntry({
    required this.title,
    required this.keywords,
    required this.icon,
    required this.onTap,
  });

  /// يُطابِق العنوان أو أي كلمة مفتاحية إن احتوت على نص البحث (بعد تطبيع
  /// المسافات وحالة الأحرف) - يكفي تطابق جزئي في أي منهما.
  bool matches(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return true;
    if (_normalize(title).contains(q)) return true;
    return keywords.any((k) => _normalize(k).contains(q));
  }

  static String _normalize(String s) => s.trim().toLowerCase();
}

/// أدوار "البحث السريع" - تحدّد أي مجموعة عناصر تُبنى، مطابقة تمامًا لأدوار
/// [PortalAccounts] الفعلية.
class QuickSearchRole {
  static const String fullAdmin = 'full_admin';
  static const String viewer = 'viewer';
  static const String collegeCoordinator = 'college_coordinator';
  static const String departmentCoordinator = 'department_coordinator';
  static const String unitCoordinator = 'unit_coordinator';
}

void _push(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// يبني قائمة عناصر البحث السريع الخاصة بدور المستخدم الحالي فقط - إعادة
/// استخدام كاملة للتنقّل الحقيقي المطبَّق أصلاً في admin_workspace_screen.dart،
/// admin_nav.dart، وreports_hub_screen.dart بلا أي منطق جديد.
///
/// [uid] مطلوب لمنسّق القسم/الكلية (لفتح شاشتهما بمعرّف حسابهما)،
/// [shatr]/[department] مطلوبان فقط لمنسّق القسم (حالات الظروف الخاصة
/// والدعم النفسي تحتاجهما مباشرة بدل معرّف الحساب).
/// منسّق الوحدة (دوره حصرًا رفع الملفات) لا يحصل على أي عنصر بحث عمدًا.
List<QuickSearchEntry> buildQuickSearchEntries(
  BuildContext context, {
  required String role,
  bool isSuperAdmin = false,
  String? uid,
  String? shatr,
  String? department,
}) {
  final entries = <QuickSearchEntry>[];

  if (role == QuickSearchRole.fullAdmin) {
    entries.addAll([
      QuickSearchEntry(
        title: 'تقارير متابعة الحذف والإضافة',
        keywords: ['تقارير', 'تقرير', 'حذف واضافة', 'شامل'],
        icon: Icons.assessment_outlined,
        onTap: () => _push(context, const AdminReportsScreen()),
      ),
      QuickSearchEntry(
        title: 'مركز التقارير',
        keywords: ['تقارير', 'مركز التقارير', 'بحث تقارير'],
        icon: Icons.dashboard_customize_outlined,
        onTap: () => _push(context, const ReportsHubScreen()),
      ),
      QuickSearchEntry(
        title: 'متابعة حالات الإرشاد',
        keywords: ['إرشاد', 'حالات الإرشاد', 'كشف بيانات', 'مرشدين', 'نصاب'],
        icon: Icons.fact_check_outlined,
        onTap: () => _push(context, const AdvisingCasesAdminScreen()),
      ),
      QuickSearchEntry(
        title: 'لوحة الإرشاد',
        keywords: ['إرشاد', 'لوحة الإرشاد', 'ظروف خاصة', 'دعم نفسي'],
        icon: Icons.volunteer_activism_outlined,
        onTap: () => _push(context, const AdvisingHubScreen()),
      ),
      QuickSearchEntry(
        title: 'متابعة حالات الظروف الخاصة',
        keywords: ['ظروف خاصة', 'حالات خاصة'],
        icon: Icons.volunteer_activism_outlined,
        onTap: () => _push(context, const HardshipCasesAdminScreen()),
      ),
      QuickSearchEntry(
        title: 'متابعة حالات الدعم النفسي والاجتماعي',
        keywords: ['دعم نفسي', 'دعم اجتماعي', 'حالات نفسية'],
        icon: Icons.favorite_border,
        onTap: () => _push(context, const SupportCasesAdminScreen()),
      ),
      QuickSearchEntry(
        title: 'دليل تشغيل البوابة',
        keywords: ['دليل', 'مساعدة', 'شرح البوابة'],
        icon: Icons.menu_book_outlined,
        onTap: () => _push(context, const PortalOperationsGuidePage()),
      ),
      QuickSearchEntry(
        title: 'خريطة صفحات الموقع',
        keywords: ['خريطة الموقع', 'sitemap', 'كل الصفحات'],
        icon: Icons.map_outlined,
        onTap: () => _push(context, const PortalSitemapScreen()),
      ),
    ]);

    if (isSuperAdmin) {
      entries.addAll([
        QuickSearchEntry(
          title: 'تسكين المقررات الدراسية',
          keywords: ['تسكين', 'مقررات', 'شعب', 'حويّة'],
          icon: Icons.event_note_outlined,
          onTap: () => _push(
            context,
            const CourseScheduleAdminScreen(initialTabIndex: 0, singleTab: true),
          ),
        ),
        QuickSearchEntry(
          title: 'الجدول الدراسي',
          keywords: ['جداول', 'جدول', 'الجدول الدراسي', 'تسكين', 'مقررات'],
          icon: Icons.person_search_outlined,
          onTap: () => _push(
            context,
            const CourseScheduleAdminScreen(initialTabIndex: 1, singleTab: true),
          ),
        ),
        QuickSearchEntry(
          title: 'المنسوبين',
          keywords: ['منسوبين', 'أعضاء هيئة تدريس', 'موظفين', 'roster'],
          icon: Icons.badge_outlined,
          onTap: () => _push(context, const CollegeRosterAdminScreen()),
        ),
        QuickSearchEntry(
          title: 'توزيع فترات الإرشاد',
          keywords: ['فترات الإرشاد', 'توزيع فترات', 'جدول الإرشاد'],
          icon: Icons.schedule_outlined,
          onTap: () => _push(context, const AdvisingScheduleAdminScreen()),
        ),
        QuickSearchEntry(
          title: 'خدمات أكاديمية',
          keywords: ['خدمات أكاديمية', 'تسكين', 'جداول'],
          icon: Icons.school_outlined,
          onTap: () => _push(context, const AcademicServicesHubScreen()),
        ),
      ]);
    }
  }

  if (role == QuickSearchRole.viewer) {
    entries.add(
      QuickSearchEntry(
        title: 'التقرير الشامل',
        keywords: ['تقرير', 'تقارير', 'شامل'],
        icon: Icons.summarize_outlined,
        onTap: () => _push(context, const ViewerReportsScreen()),
      ),
    );
  }

  if (role == QuickSearchRole.collegeCoordinator && uid != null) {
    entries.addAll([
      QuickSearchEntry(
        title: 'لوحة منسّق الكلية',
        keywords: ['لوحة منسّق الكلية', 'الكلية'],
        icon: Icons.dashboard_outlined,
        onTap: () => _push(context, CollegeCoordinatorWorkspaceScreen(uid: uid)),
      ),
      QuickSearchEntry(
        title: 'تقارير',
        keywords: ['تقارير', 'تقرير'],
        icon: Icons.assessment_outlined,
        onTap: () => _push(context, const ReportsHubScreen()),
      ),
    ]);
  }

  if (role == QuickSearchRole.departmentCoordinator && uid != null) {
    entries.addAll([
      QuickSearchEntry(
        title: 'لوحة المنسّق',
        keywords: ['لوحة المنسّق', 'قسمي'],
        icon: Icons.dashboard_outlined,
        onTap: () => _push(context, CoordinatorWorkspaceScreen(uid: uid)),
      ),
      QuickSearchEntry(
        title: 'تقارير',
        keywords: ['تقارير', 'تقرير'],
        icon: Icons.assessment_outlined,
        onTap: () => _push(context, const ReportsHubScreen()),
      ),
      if (shatr != null && department != null && shatr.isNotEmpty && department.isNotEmpty) ...[
        QuickSearchEntry(
          title: 'حالات الظروف الخاصة',
          keywords: ['ظروف خاصة', 'حالات خاصة'],
          icon: Icons.volunteer_activism_outlined,
          onTap: () => _push(
            context,
            HardshipCasesCoordinatorScreen(shatr: shatr, department: department),
          ),
        ),
        QuickSearchEntry(
          title: 'الدعم النفسي والاجتماعي',
          keywords: ['دعم نفسي', 'دعم اجتماعي'],
          icon: Icons.favorite_border,
          onTap: () => _push(
            context,
            SupportCasesCoordinatorScreen(shatr: shatr, department: department),
          ),
        ),
      ],
    ]);
  }

  // منسّق الوحدة: دوره حصرًا رفع الملفات - بلا أي نتائج بحث عمدًا.
  return entries;
}
