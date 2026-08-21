import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'admin_reports_screen.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_nav.dart';
import 'coordinator_workspace_screen.dart';
import 'course_schedule_admin_screen.dart';
import 'portal_accounts.dart';
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
        ReportHubCategory.report => DashTokens.green900,
        ReportHubCategory.workFile => DashTokens.gold600,
        ReportHubCategory.guide => Colors.blueGrey,
      };
}

/// تطبيع مبسّط للنص العربي للبحث: إزالة التشكيل، توحيد أشكال الألف/الهمزة
/// والياء/التاء المربوطة، وخفض الحالة - حتى تُطابق كلمات مثل "الاعاقة" بحث
/// "الإعاقة" بلا حاجة لمطابقة حرفية.
String _normalizeArabic(String input) {
  var s = input.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[ً-ْٰ]'), ''); // تشكيل
  s = s.replaceAll(RegExp('[إأآا]'), 'ا');
  s = s.replaceAll('ى', 'ي');
  s = s.replaceAll('ة', 'ه');
  s = s.replaceAll('ؤ', 'و');
  s = s.replaceAll('ئ', 'ي');
  return s;
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
  final void Function(BuildContext context) onOpen;
  final List<String> keywords;

  const _ReportEntry({
    required this.title,
    required this.description,
    required this.category,
    required this.subtype,
    required this.icon,
    required this.onOpen,
    this.keywords = const [],
  });

  bool matches(String query) {
    final q = _normalizeArabic(query);
    if (q.isEmpty) return true;
    final haystack = _normalizeArabic('$title $description $subtype ${category.label} ${keywords.join(' ')}');
    return haystack.contains(q);
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
  String _searchQuery = '';
  Timer? _debounce;

  bool get _hasActiveFilters => _categoryFilter != null || _subtypeFilter != null || _searchQuery.trim().isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  void _clearFilters() {
    _debounce?.cancel();
    setState(() {
      _searchCtrl.clear();
      _searchQuery = '';
      _categoryFilter = null;
      _subtypeFilter = null;
    });
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
          keywords: const ['مرشد', 'المرشد الأكاديمي', 'المرشدين', 'قسم', 'شطر', 'كلية'],
          onOpen: (c) => _openScreen(c, const AdminReportsScreen()),
        ),
        _ReportEntry(
          title: 'تقرير متابعة الإنجاز',
          description: 'تقرير إرشاد لمتابعة نسبة إنجاز المرشدين والأقسام',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.fact_check_outlined,
          onOpen: (c) => _openScreen(c, const AdminReportsScreen()),
        ),
        _ReportEntry(
          title: 'تقرير ومتابعة ذوي الإعاقة',
          description: 'حالات خاصة لذوي الإعاقة على مستوى الكلية',
          category: ReportHubCategory.report,
          subtype: 'حالات خاصة',
          icon: Icons.accessible_outlined,
          keywords: const ['اعاقة', 'ذوي الاعاقة'],
          onOpen: (c) => _openScreen(c, const AdminReportsScreen()),
        ),
        _ReportEntry(
          title: 'متابعة حالات الإرشاد',
          description: 'تقرير إرشاد شامل: كشف بيانات الطلبة، طلاب على مرشدهم، طلاب بلا مرشد، طلاب على غير مرشدهم، مرشدون معفَون، مرشدون بلا طلاب، تقرير النصاب، إعادة التوزيع، حالات صحية غير موزَّعة، بيانات منسوبين',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.groups_outlined,
          keywords: const ['مرشد', 'المرشد الأكاديمي', 'المرشدين'],
          onOpen: (c) => _openScreen(c, const AdvisingCasesAdminScreen()),
        ),
        _ReportEntry(
          title: 'تقرير النصاب التدريسي',
          description: 'نصاب تدريسي لأعضاء هيئة التدريس (PDF)',
          category: ReportHubCategory.report,
          subtype: 'نصاب تدريسي',
          icon: Icons.pie_chart_outline,
          onOpen: (c) => _openScreen(c, const CourseScheduleAdminScreen()),
        ),
        _ReportEntry(
          title: 'دليل مقررات الحذف والإضافة',
          description: 'جدول دراسي لتسكين المقررات (PDF)',
          category: ReportHubCategory.report,
          subtype: 'جدول دراسي',
          icon: Icons.table_chart_outlined,
          onOpen: (c) => _openScreen(c, const CourseScheduleAdminScreen()),
        ),
        _ReportEntry(
          title: 'جدول عضو هيئة التدريس',
          description: 'جدول دراسي فردي لعضو هيئة تدريس واحد (PDF)',
          category: ReportHubCategory.report,
          subtype: 'جدول دراسي',
          icon: Icons.person_outline,
          onOpen: (c) => _openScreen(c, const CourseScheduleAdminScreen()),
        ),
        _ReportEntry(
          title: 'تقرير توزيع فترات الإرشاد',
          description: 'جدول دراسي وتقرير إرشاد لفترات الإرشاد لكل قسم وشطر (رسمي/شاشات عرض)',
          category: ReportHubCategory.report,
          subtype: 'تقرير إرشاد',
          icon: Icons.schedule_outlined,
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
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
        _ReportEntry(
          title: 'تنزيل ملف قسمي (ZIP)',
          description: 'ملف عمل مضغوط بملف Excel منفصل لكل مرشد بالقسم',
          category: ReportHubCategory.workFile,
          subtype: 'بيانات منسوبين',
          icon: Icons.folder_zip_outlined,
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
        _ReportEntry(
          title: 'تنزيل حالات ذوي الإعاقة (القسم)',
          description: 'ملف عمل حالات خاصة لذوي الإعاقة داخل قسمك',
          category: ReportHubCategory.workFile,
          subtype: 'حالات خاصة',
          icon: Icons.accessible_outlined,
          onOpen: (c) => _openScreen(c, CoordinatorWorkspaceScreen(uid: uid)),
        ),
        _ReportEntry(
          title: 'تنزيل الملف المدمج لمرحلة القسم',
          description: 'ملف عمل بكل حالات القسم مدمجة لمسار التصعيد',
          category: ReportHubCategory.workFile,
          subtype: 'بيانات منسوبين',
          icon: Icons.merge_type_outlined,
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
        onOpen: (c) => _openScreen(c, const UnitGuidePage()),
      ),
      _ReportEntry(
        title: 'دليل تشغيل البوابة',
        description: 'دليل تشغيلي للمنسّقين لاستخدام البوابة الداخلية',
        category: ReportHubCategory.guide,
        subtype: 'دليل تشغيلي',
        icon: Icons.settings_suggest_outlined,
        onOpen: (c) => _openScreen(c, const PortalOperationsGuidePage()),
      ),
      _ReportEntry(
        title: 'دليل المنظومة الداخلية للمرشد الأكاديمي',
        description: 'دليل تشغيلي للمرشد الأكاديمي',
        category: ReportHubCategory.guide,
        subtype: 'دليل تشغيلي',
        icon: Icons.support_agent_outlined,
        onOpen: (c) => _openScreen(c, const GuidesHubPage()),
      ),
      _ReportEntry(
        title: 'نموذج طلب دعم نفسي واجتماعي',
        description: 'نموذج ورقي حالات خاصة للدعم النفسي والاجتماعي',
        category: ReportHubCategory.guide,
        subtype: 'نموذج ورقي',
        icon: Icons.favorite_border,
        onOpen: (c) => _openScreen(c, const FormsPage()),
      ),
      _ReportEntry(
        title: 'نموذج توثيق حالة طالب',
        description: 'نموذج ورقي حالات خاصة (ظروف خاصة)',
        category: ReportHubCategory.guide,
        subtype: 'نموذج ورقي',
        icon: Icons.volunteer_activism_outlined,
        onOpen: (c) => _openScreen(c, const FormsPage()),
      ),
      _ReportEntry(
        title: 'نموذج الحذف والإضافة الورقي',
        description: 'نموذج ورقي جدول دراسي للحذف والإضافة',
        category: ReportHubCategory.guide,
        subtype: 'نموذج ورقي',
        icon: Icons.description_outlined,
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
        return e.matches(_searchQuery);
      }).toList();

      final resultLabel = filtered.length == 1 ? 'نتيجة واحدة' : '${filtered.length} نتيجة';

      return Container(
        color: DashTokens.pageBg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.summarize_outlined, size: 20, color: DashTokens.green900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('مركز التقارير', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                            const SizedBox(height: 2),
                            Text('كل مخرجات البوابة القابلة للطباعة/التصدير بمكان واحد', style: TextStyle(fontSize: 11.5, color: DashTokens.textSecondary.withValues(alpha: 0.9))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: DashTokens.cardBg,
                      border: Border.all(color: DashTokens.border),
                      borderRadius: BorderRadius.circular(DashTokens.radiusLg),
                      boxShadow: DashTokens.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: DashTokens.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'ابحث في مركز التقارير...',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 4),
                    child: Text('مثال: إرشاد، جدول، نصاب، إعاقة، مرشد', style: TextStyle(fontSize: 10.5, color: DashTokens.textMuted)),
                  ),
                  const SizedBox(height: 16),
                  _FilterGroup(
                    label: 'التصنيف',
                    children: [
                      _FilterChip(
                        label: 'الكل',
                        selected: _categoryFilter == null,
                        level: _FilterLevel.primary,
                        onSelected: () => setState(() => _categoryFilter = null),
                      ),
                      for (final cat in ReportHubCategory.values)
                        _FilterChip(
                          label: cat.label,
                          selected: _categoryFilter == cat,
                          level: _FilterLevel.primary,
                          onSelected: () => setState(() => _categoryFilter = cat),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _FilterGroup(
                    label: 'نوع المحتوى',
                    children: [
                      _FilterChip(
                        label: 'كل الأنواع',
                        selected: _subtypeFilter == null,
                        level: _FilterLevel.secondary,
                        onSelected: () => setState(() => _subtypeFilter = null),
                      ),
                      for (final s in _kAllSubtypes)
                        _FilterChip(
                          label: s,
                          selected: _subtypeFilter == s,
                          level: _FilterLevel.secondary,
                          onSelected: () => setState(() => _subtypeFilter = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(resultLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashTokens.textSecondary)),
                      if (_categoryFilter != null || _subtypeFilter != null) ...[
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: DashTokens.textMuted)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [?_categoryFilter?.label, ?_subtypeFilter].join(' • '),
                            style: const TextStyle(fontSize: 12, color: DashTokens.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (_hasActiveFilters)
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.close, size: 15),
                          label: const Text('مسح الفلاتر', style: TextStyle(fontSize: 12.5)),
                          style: TextButton.styleFrom(
                            foregroundColor: DashTokens.green900,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      decoration: BoxDecoration(
                        color: DashTokens.cardBg,
                        border: Border.all(color: DashTokens.border),
                        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 28, color: DashTokens.textMuted),
                          const SizedBox(height: 10),
                          const Text('لا توجد نتائج مطابقة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                          const SizedBox(height: 4),
                          Text('جرّب تغيير كلمات البحث أو تعديل التصنيف.', style: TextStyle(fontSize: 12, color: DashTokens.textMuted)),
                          if (_hasActiveFilters) ...[
                            const SizedBox(height: 12),
                            TextButton(onPressed: _clearFilters, child: const Text('مسح الفلاتر')),
                          ],
                        ],
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final crossAxisCount = w >= 1400 ? 4 : (w >= 1000 ? 3 : (w >= 640 ? 2 : 1));
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisExtent: 108,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          itemBuilder: (context, i) => _ReportCard(entry: filtered[i], onTap: () => filtered[i].onOpen(context)),
                        );
                      },
                    ),
                ],
              ),
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

/// مستوى وزن الفلتر البصري: أساسي (تصنيف رئيسي) أثقل قليلًا من فرعي (نوع
/// المحتوى) - فرق خفيف يكفي لتمييز الصفّين بلا مبالغة.
enum _FilterLevel { primary, secondary }

/// عنوان مجموعة فلاتر صغير وخافت فوق صفّ الشرائح - يوضّح الفرق بين "التصنيف"
/// و"نوع المحتوى" دون إضافة عنوان قسم كبير.
class _FilterGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _FilterGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2, bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: DashTokens.textMuted)),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}

/// شريحة فلتر واحدة - نفس هوية الشرائح الموحَّدة بكل الموقع (أخضر داكن عند
/// التفعيل، رمادي فاتح عند عدمه) بدل الألوان المتعدّدة حسب التصنيف سابقًا.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final _FilterLevel level;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.level,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = level == _FilterLevel.primary;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(20),
        focusColor: AppColors.greenDark.withValues(alpha: 0.08),
        child: Focus(
          child: Builder(
            builder: (context) {
              final hasFocus = Focus.of(context).hasFocus;
              return Container(
                constraints: BoxConstraints(minHeight: isPrimary ? 38 : 34),
                padding: EdgeInsets.symmetric(horizontal: isPrimary ? 14 : 12, vertical: isPrimary ? 8 : 6),
                decoration: BoxDecoration(
                  color: selected ? AppColors.greenDark : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: hasFocus ? [BoxShadow(color: AppColors.greenDark.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 2)] : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isPrimary ? 11.5 : 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// بطاقة تقرير بهوية "لوحة الإدارة" (بطاقة بيضاء بحدّ رمادي فاتح + أيقونة
/// ملوَّنة بخلفية شفافة 10%) بدل التدرّج اللوني الكامل السابق - بطلب سليمان
/// الصريح (2026-08-20): هذه الصفحة كانت "لا تطابق الهوية" مقارنة بلوحة
/// الإدارة ولوحة الحذف والإضافة. البطاقة كاملةً عنصر تفاعلي واحد (InkWell)
/// مع حالتَي hover/focus صريحتين وسهم اتجاه خفيف يوضّح أنها تفتح شيئًا.
class _ReportCard extends StatefulWidget {
  final _ReportEntry entry;
  final VoidCallback onTap;

  const _ReportCard({required this.entry, required this.onTap});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.entry.category.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: DashTokens.cardBg,
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DashTokens.radiusLg),
          onTap: widget.onTap,
          focusColor: accent.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: _hovered ? accent.withValues(alpha: 0.45) : DashTokens.border),
              borderRadius: BorderRadius.circular(DashTokens.radiusLg),
              boxShadow: _hovered
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.065), blurRadius: 26, offset: const Offset(0, 10))]
                  : DashTokens.cardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Icon(widget.entry.icon, size: 22, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DashTokens.textPrimary, height: 1.25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.entry.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: DashTokens.textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_back_ios_new, size: 12, color: _hovered ? accent : DashTokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
