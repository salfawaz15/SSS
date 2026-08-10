import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'admin_reports_screen.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_nav.dart';
import 'coordinator_workspace_screen.dart';
import 'course_schedule_admin_screen.dart';
import 'portal_accounts.dart';
import 'portal_cards.dart';
import 'portal_header.dart';
import 'portal_operations_guide_page.dart';
import 'public_landing_screen.dart';
import 'viewer_reports_screen.dart';

/// تصنيف رئيسي لكل بند في "تقارير" - يحدّد الشارة اللونية ويُستخدم كفلتر
/// أعلى الصفحة.
enum ReportHubCategory { report, workFile, guide }

extension on ReportHubCategory {
  String get label => switch (this) {
        ReportHubCategory.report => 'تقارير',
        ReportHubCategory.workFile => 'ملفات عمل',
        ReportHubCategory.guide => 'أدلة ونماذج',
      };

  Color get color => switch (this) {
        ReportHubCategory.report => AppColors.green,
        ReportHubCategory.workFile => AppColors.gold,
        ReportHubCategory.guide => Colors.blueGrey,
      };
}

/// بند واحد في "مركز التقارير" - يجمع عنوانًا ووصفًا مختصرًا (للبحث)
/// ونوعًا فرعيًا (للفلترة) وإجراء فتح الشاشة/الحوار الأصلي بلا أي إعادة
/// بناء لمنطقه.
class _ReportEntry {
  final String title;
  final String description;
  final ReportHubCategory category;
  final String subtype;
  final IconData icon;
  final List<Color> gradientColors;
  final void Function(BuildContext context) onOpen;

  const _ReportEntry({
    required this.title,
    required this.description,
    required this.category,
    required this.subtype,
    required this.icon,
    required this.gradientColors,
    required this.onOpen,
  });

  bool matches(String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    return title.contains(q) || description.contains(q) || subtype.contains(q);
  }
}

const List<String> _kAllSubtypes = [
  'تقرير إرشاد',
  'جدول دراسي',
  'نصاب تدريسي',
  'حالات خاصة',
  'بيانات منسوبين',
  'دليل تشغيلي',
  'نموذج ورقي',
];

/// شاشة "تقارير" الموحّدة: تجمع كل مخرجات البوابة القابلة للطباعة/التصدير
/// بمكان واحد بفلترة حسب الدور + بحث نصي + فلترة تصنيف/نوع، بدل تشتّتها بين
/// شاشات مختلفة. **لا تعيد بناء منطق أي تقرير** - كل بطاقة تفتح الشاشة
/// الأصلية نفسها (أو تستدعي نفس الخدمة مباشرة حين يكون ذلك آمنًا وبسيطًا).
class ReportsHubScreen extends StatefulWidget {
  const ReportsHubScreen({super.key});

  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  final _searchCtrl = TextEditingController();
  ReportHubCategory? _categoryFilter;
  String? _subtypeFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// يبني قائمة كل التقارير المتاحة لدور المستخدم الحالي بالضبط - الأدوار
  /// وتوزيعها مطابقة لما هو مطبَّق فعليًا في portal_root.dart.
  List<_ReportEntry> _entriesFor({
    required bool isFullAdmin,
    required bool isViewer,
    required bool isCollegeCoordinator,
    required bool isDepartmentCoordinator,
    required String? uid,
    required String? shatr,
    required String? department,
  }) {
    final entries = <_ReportEntry>[];

    if (isFullAdmin) {
      entries.addAll([
        _ReportEntry(
          title: 'التقرير الشامل ونطاقاته',
          description: 'تقرير إرشاد شامل حسب القسم أو الشطر أو المرشد الأكاديمي، تصدير Excel/PDF أو طباعة',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.summarize_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const AdminReportsScreen()),
        ),
        _ReportEntry(
          title: 'تقرير متابعة الإنجاز',
          description: 'تقرير إرشاد لمتابعة نسبة إنجاز المرشدين والأقسام',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.fact_check_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const AdminReportsScreen()),
        ),
        _ReportEntry(
          title: 'تقرير ومتابعة ذوي الإعاقة',
          description: 'حالات خاصة لذوي الإعاقة على مستوى الكلية',
          category: ReportHubCategory.report,
          subtype: 'حالات خاصة',
          icon: Icons.accessible_outlined,
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onOpen: (c) => _openScreen(c, const AdminReportsScreen()),
        ),
        _ReportEntry(
          title: 'متابعة حالات الإرشاد',
          description: 'تقرير إرشاد شامل: كشف بيانات الطلبة، طلاب على مرشدهم، طلاب بلا مرشد، طلاب على غير مرشدهم، مرشدون معفَون، مرشدون بلا طلاب، تقرير النصاب، إعادة التوزيع، حالات صحية غير موزَّعة، بيانات منسوبين',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.groups_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const AdvisingCasesAdminScreen()),
        ),
        _ReportEntry(
          title: 'تقرير النصاب التدريسي',
          description: 'نصاب تدريسي لأعضاء هيئة التدريس (PDF)',
          category: ReportHubCategory.report,
          subtype: 'نصاب تدريسي',
          icon: Icons.pie_chart_outline,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const CourseScheduleAdminScreen()),
        ),
        _ReportEntry(
          title: 'دليل مقررات الحذف والإضافة',
          description: 'جدول دراسي لتسكين المقررات (PDF)',
          category: ReportHubCategory.report,
          subtype: 'جدول دراسي',
          icon: Icons.table_chart_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const CourseScheduleAdminScreen()),
        ),
        _ReportEntry(
          title: 'جدول عضو هيئة التدريس',
          description: 'جدول دراسي فردي لعضو هيئة تدريس واحد (PDF)',
          category: ReportHubCategory.report,
          subtype: 'جدول دراسي',
          icon: Icons.person_outline,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const CourseScheduleAdminScreen()),
        ),
        _ReportEntry(
          title: 'تقرير توزيع فترات الإرشاد',
          description: 'جدول دراسي وتقرير إرشاد لفترات الإرشاد لكل قسم وشطر (رسمي/شاشات عرض)',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.schedule_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const AdvisingScheduleAdminScreen()),
        ),
      ]);
    }

    if (isViewer) {
      entries.add(
        _ReportEntry(
          title: 'التقرير الشامل',
          description: 'تقرير إرشاد شامل مبسّط (عرض/طباعة/تصدير فقط)',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.summarize_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, const ViewerReportsScreen()),
        ),
      );
    }

    if (isCollegeCoordinator && uid != null) {
      entries.add(
        _ReportEntry(
          title: 'تنزيل ملف كل الأقسام المدمج (الكلية)',
          description: 'ملف عمل Excel يدمج كل أقسام شطرك لمنسّق الكلية',
          category: ReportHubCategory.workFile,
          subtype: 'بيانات منسوبين',
          icon: Icons.merge_type_outlined,
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onOpen: (c) => _openScreen(c, CollegeCoordinatorWorkspaceScreen(uid: uid)),
        ),
      );
    }

    if (isDepartmentCoordinator && uid != null) {
      entries.addAll([
        _ReportEntry(
          title: 'تقرير متابعة القسم',
          description: 'تقرير إرشاد لمتابعة إنجاز قسمك فقط',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.fact_check_outlined,
          gradientColors: const [AppColors.green, AppColors.greenDark],
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
        _ReportEntry(
          title: 'تنزيل ملف قسمي (ZIP)',
          description: 'ملف عمل مضغوط بملف Excel منفصل لكل مرشد بالقسم',
          category: ReportHubCategory.workFile,
          subtype: 'بيانات منسوبين',
          icon: Icons.folder_zip_outlined,
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
        _ReportEntry(
          title: 'تنزيل حالات ذوي الإعاقة (القسم)',
          description: 'ملف عمل حالات خاصة لذوي الإعاقة داخل قسمك',
          category: ReportHubCategory.workFile,
          subtype: 'حالات خاصة',
          icon: Icons.accessible_outlined,
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
        _ReportEntry(
          title: 'تنزيل الملف المدمج لمرحلة القسم',
          description: 'ملف عمل بكل حالات القسم مدمجة لمسار التصعيد',
          category: ReportHubCategory.workFile,
          subtype: 'بيانات منسوبين',
          icon: Icons.merge_type_outlined,
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
      ]);
    }

    // تصنيف 3: أدلة ونماذج - متاحة للجميع بلا استثناء.
    entries.addAll([
      _ReportEntry(
        title: 'الدليل الإرشادي الرسمي للطالب',
        description: 'دليل تشغيلي رسمي لنموذج الحذف والإضافة',
        category: ReportHubCategory.guide,
        subtype: 'دليل تشغيلي',
        icon: Icons.menu_book_outlined,
        gradientColors: const [Colors.blueGrey, Colors.blueGrey],
        onOpen: (c) => _openScreen(c, const UnitGuidePage()),
      ),
      _ReportEntry(
        title: 'دليل تشغيل البوابة',
        description: 'دليل تشغيلي للمنسّقين لاستخدام البوابة الداخلية',
        category: ReportHubCategory.guide,
        subtype: 'دليل تشغيلي',
        icon: Icons.settings_suggest_outlined,
        gradientColors: const [Colors.blueGrey, Colors.blueGrey],
        onOpen: (c) => _openScreen(c, const PortalOperationsGuidePage()),
      ),
      _ReportEntry(
        title: 'دليل المنظومة الداخلية للمرشد الأكاديمي',
        description: 'دليل تشغيلي للمرشد الأكاديمي',
        category: ReportHubCategory.guide,
        subtype: 'دليل تشغيلي',
        icon: Icons.support_agent_outlined,
        gradientColors: const [Colors.blueGrey, Colors.blueGrey],
        onOpen: (c) => _openScreen(c, const GuidesHubPage()),
      ),
      _ReportEntry(
        title: 'نموذج طلب دعم نفسي واجتماعي',
        description: 'نموذج ورقي حالات خاصة للدعم النفسي والاجتماعي',
        category: ReportHubCategory.guide,
        subtype: 'نموذج ورقي',
        icon: Icons.favorite_border,
        gradientColors: const [Colors.blueGrey, Colors.blueGrey],
        onOpen: (c) => _openScreen(c, const FormsPage()),
      ),
      _ReportEntry(
        title: 'نموذج توثيق حالة طالب',
        description: 'نموذج ورقي حالات خاصة (ظروف خاصة)',
        category: ReportHubCategory.guide,
        subtype: 'نموذج ورقي',
        icon: Icons.volunteer_activism_outlined,
        gradientColors: const [Colors.blueGrey, Colors.blueGrey],
        onOpen: (c) => _openScreen(c, const FormsPage()),
      ),
      _ReportEntry(
        title: 'نموذج الحذف والإضافة الورقي',
        description: 'نموذج ورقي جدول دراسي للحذف والإضافة',
        category: ReportHubCategory.guide,
        subtype: 'نموذج ورقي',
        icon: Icons.description_outlined,
        gradientColors: const [Colors.blueGrey, Colors.blueGrey],
        onOpen: (c) => _openScreen(c, const FormsPage()),
      ),
    ]);

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isFullAdmin = PortalAccounts.isFullAdmin(email);
    final isViewer = PortalAccounts.viewerEmails.values.contains(email);
    final isCollegeCoordinator = PortalAccounts.isCollegeCoordinator(email);
    final isUnitCoordinator = PortalAccounts.isUnitCoordinator(email);
    final isDepartmentCoordinator =
        !isFullAdmin && !isViewer && !isCollegeCoordinator && !isUnitCoordinator;

    List<PortalNavItem> navItems() {
      if (isFullAdmin) return buildAdminNavItems(context, current: 'reports-hub');
      return const [];
    }

    Widget buildBody(String? shatr, String? department) {
      final entries = _entriesFor(
        isFullAdmin: isFullAdmin,
        isViewer: isViewer,
        isCollegeCoordinator: isCollegeCoordinator,
        isDepartmentCoordinator: isDepartmentCoordinator,
        uid: uid,
        shatr: shatr,
        department: department,
      );

      final filtered = entries.where((e) {
        if (_categoryFilter != null && e.category != _categoryFilter) return false;
        if (_subtypeFilter != null && e.subtype != _subtypeFilter) return false;
        return e.matches(_searchCtrl.text);
      }).toList();

      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن تقرير (مثال: جدول، إرشاد، نصاب، إعاقة...)',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _categoryFilter == null,
                      onSelected: (_) => setState(() => _categoryFilter = null),
                    ),
                    for (final cat in ReportHubCategory.values)
                      ChoiceChip(
                        label: Text(cat.label),
                        selected: _categoryFilter == cat,
                        selectedColor: cat.color.withValues(alpha: 0.2),
                        onSelected: (_) => setState(() => _categoryFilter = cat),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('كل الأنواع'),
                      selected: _subtypeFilter == null,
                      onSelected: (_) => setState(() => _subtypeFilter = null),
                    ),
                    for (final s in _kAllSubtypes)
                      ChoiceChip(
                        label: Text(s),
                        selected: _subtypeFilter == s,
                        onSelected: (_) => setState(() => _subtypeFilter = s),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 420,
                      mainAxisExtent: 108,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      return Stack(
                        children: [
                          PortalActionCard(
                            icon: e.icon,
                            title: e.title,
                            subtitle: e.description,
                            // لون موحَّد حسب تصنيف البند (تقرير/ملف عمل/دليل) -
                            // كان كل بند يحمل تدرّجه اللوني المستقل بلا علاقة
                            // بتصنيفه، فتختلط الألوان بلا نمط واضح (سليمان
                            // 2026-08-09).
                            gradientColors: [e.category.color, e.category.color.withValues(alpha: 0.75)],
                            onTap: () => e.onOpen(context),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                e.category.label,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: e.category.color,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (isDepartmentCoordinator && uid != null) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('coordinator_accounts').doc(uid).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final data = snapshot.data!.data();
          final shatr = data?['shatr']?.toString() ?? '';
          final department = data?['department']?.toString() ?? '';
          return PortalScaffold(
            title: 'تقارير',
            navItems: (shatr.isNotEmpty && department.isNotEmpty)
                ? buildCoordinatorNavItems(context, current: 'reports-hub', shatr: shatr, department: department)
                : const [],
            body: buildBody(shatr, department),
          );
        },
      );
    }

    return PortalScaffold(
      title: 'تقارير',
      navItems: navItems(),
      body: buildBody(null, null),
    );
  }
}
