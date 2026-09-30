import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/advising_case_record.dart';
import '../services/advising_case_excel_service.dart';
import '../services/advising_case_pdf_service.dart';
import '../services/advising_report_repository.dart';
import '../services/course_schedule_repository.dart' show Shatr, ShatrLabel;
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import '../theme/dashboard_table.dart';
import '../theme/dashboard_tokens.dart';
import '../theme/filter_pills.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_header.dart';

/// نفس ترتيب الأقسام العلمية المعتمَد ببقية شاشات الإدارة
/// (`admin_executive_dashboard_screen.dart`) - قيَمه مطابقة تمامًا لمخرجات
/// `normalizeDepartmentName` (`data/academic_department_names.dart`).
const _kDepartmentOrder = [
  'قسم الادارة',
  'قسم المحاسبة',
  'قسم التسويق',
  'قسم الاقتصاد و التمويل',
  'قسم نظم المعلومات الادارية',
];

/// تبويب لكل حالة قيد (10 تبويبات) + تبويب "الكل" أول تبويب (index 0، بلا
/// حالة محدَّدة) - بطلب سليمان الصريح 2026-09-30. المفتاح رقم التبويب،
/// القيمة نص الحالة كما يصل من `AcademicDataRawCsvParserService`.
const _kStatusByTabIndex = <int, String>{
  1: 'منتظم',
  2: 'مفصول أكاديميًا',
  3: 'موقوف تأديبي / مفصول مؤقت',
  4: 'منقطع عن الدراسة',
  5: 'مطوي قيده',
  6: 'متخرج',
  7: 'مؤجل',
  8: 'معتذر',
  9: 'منسحب',
  10: 'متوفى',
};

const _kGraduatesTabIndex = 6;
const _kTabCount = 11;

/// نفس ألوان "النطاق" المعتمَدة بشاشة "بحث عن مرشد"
/// (`advisor_students_lookup_screen.dart`: `_rangeColor`) - أحمر (ضعيف) إلى
/// أخضر داكن (ممتاز)، مطابقة للمنظومة الخارجية للمرشد.
Color _rangeColor(GpaStatus status) => switch (status) {
      GpaStatus.excellent => const Color(0xFF1B5E20),
      GpaStatus.veryGood => const Color(0xFF7CB342),
      GpaStatus.good => const Color(0xFFFBC02D),
      GpaStatus.pass => const Color(0xFFFB8C00),
      GpaStatus.weak => const Color(0xFFE53935),
      GpaStatus.unknown => Colors.grey,
    };

Widget _rangeBar(double? gpa) {
  if (gpa == null) return const Text('—', style: TextStyle(fontSize: 12.5));
  return DashProgressCell(value: gpa / 4.0, color: _rangeColor(gpaStatusOf(gpa)), label: gpa.toStringAsFixed(2));
}

/// يضع TabBar داخل خلفية خضراء صلبة - ألوان TabBar الافتراضية في هذا
/// المشروع (نص أبيض) مصمَّمة لخلفية AppBar الخضراء التقليدية، فتختفي تمامًا
/// (أبيض على أبيض) لو وُضع التبويب مباشرة على خلفية بيضاء بلا هذا الغلاف -
/// نفس السبب الجذري لاختفاء تبويب "الخريجون" بالنسخة الأولى (سليمان
/// 2026-09-30: "ظهر لي بالصدفة"). نسخة مطابقة لـ`_GreenTabBar` الخاصة
/// بـ`course_schedule_admin_screen.dart` (النمط البصري الناجح المعتمَد فعليًا
/// بالموقع).
class _GreenTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabBar tabBar;
  const _GreenTabBar(this.tabBar);

  @override
  Widget build(BuildContext context) => Container(color: AppColors.green, child: tabBar);

  @override
  Size get preferredSize => tabBar.preferredSize;
}

/// شاشة "بيانات الطلبة الأكاديمية" - تبويب "الكل" + تبويب مستقل لكل حالة قيد
/// (10 حالات، بطلب سليمان الصريح 2026-09-30: "المفترض يكون لكل حالة تبويب")
/// بدل فلتر حالة واحد. تبويب "متخرج" يحصل إضافيًا على فلتر تخصص، بطاقة توزيع
/// حسب القسم، وتنبيه عدم توفر بيانات تواصل - تمهيدًا لاستخدام هذه البيانات
/// مستقبلاً بمتابعة/تواصل الخريجين متى توفرت بيانات اتصال بالمصدر الخام (لا
/// بريد/جوال بالمصدر الحالي إطلاقًا). تقرأ `AdvisingReportKind.base` مباشرة
/// بلا مرور بـ`AdvisingCaseAnalyzer.analyze` حتى لا يُستبعَد أي طالب.
class StudentDataStatsScreen extends StatefulWidget {
  const StudentDataStatsScreen({super.key});

  @override
  State<StudentDataStatsScreen> createState() => _StudentDataStatsScreenState();
}

class _StudentDataStatsScreenState extends State<StudentDataStatsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: _kTabCount, vsync: this);

  bool _loading = true;
  String? _error;
  List<AdvisingCaseRecord> _all = [];

  // فلاتر شطر/قسم مستقلة لكل تبويب (بفهرس التبويب) - بدل تكرار متغيرات لكل
  // حالة على حدة.
  final Map<int, String?> _deptFilterByTab = {};
  final Map<int, String?> _shatrFilterByTab = {};
  String? _gradSpecializationFilter; // فقط لتبويب "متخرج" (index 6)

  final Map<int, String?> _sortKeyByTab = {};
  final Map<int, bool> _sortAscendingByTab = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.base),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.base),
      ]);
      final seen = <String>{};
      final merged = <AdvisingCaseRecord>[];
      for (final r in [...results[0], ...results[1]]) {
        if (seen.add(r.studentId)) merged.add(r);
      }
      if (!mounted) return;
      setState(() {
        _all = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'بيانات الطلبة الأكاديمية',
      navItems: buildAdminNavItems(context, current: 'reports-hub'),
      bottom: _GreenTabBar(
        TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.gold,
          tabs: [
            const Tab(text: 'الكل'),
            for (var i = 1; i < _kTabCount; i++) Tab(text: _kStatusByTabIndex[i]!),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [for (var i = 0; i < _kTabCount; i++) _buildStatusTab(context, i)],
      ),
    );
  }

  Widget _buildStatusTab(BuildContext context, int tabIndex) {
    return Container(
      color: DashTokens.pageBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
            child: _StatusTabBody(
              key: PageStorageKey('tab-$tabIndex'),
              tabIndex: tabIndex,
              loading: _loading,
              error: _error,
              all: _all,
              onRetry: _load,
              deptFilter: _deptFilterByTab[tabIndex],
              shatrFilter: _shatrFilterByTab[tabIndex],
              specializationFilter: tabIndex == _kGraduatesTabIndex ? _gradSpecializationFilter : null,
              sortKey: _sortKeyByTab[tabIndex],
              sortAscending: _sortAscendingByTab[tabIndex] ?? true,
              onDeptFilterChanged: (v) => setState(() => _deptFilterByTab[tabIndex] = v),
              onShatrFilterChanged: (v) => setState(() => _shatrFilterByTab[tabIndex] = v),
              onSpecializationFilterChanged: (v) => setState(() => _gradSpecializationFilter = v),
              onResetFilters: () => setState(() {
                _deptFilterByTab[tabIndex] = null;
                _shatrFilterByTab[tabIndex] = null;
                if (tabIndex == _kGraduatesTabIndex) _gradSpecializationFilter = null;
              }),
              onSort: (key) => setState(() {
                if (_sortKeyByTab[tabIndex] == key) {
                  _sortAscendingByTab[tabIndex] = !(_sortAscendingByTab[tabIndex] ?? true);
                } else {
                  _sortKeyByTab[tabIndex] = key;
                  _sortAscendingByTab[tabIndex] = true;
                }
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// جسم تبويب حالة واحد (أو "الكل") - مستقل بالكامل عن بقية التبويبات (كل
/// فلاتره/فرزه خاص به فقط، مُمرَّر من الأب عبر خرائط بفهرس التبويب).
class _StatusTabBody extends StatelessWidget {
  final int tabIndex;
  final bool loading;
  final String? error;
  final List<AdvisingCaseRecord> all;
  final VoidCallback onRetry;
  final String? deptFilter;
  final String? shatrFilter;
  final String? specializationFilter;
  final String? sortKey;
  final bool sortAscending;
  final ValueChanged<String?> onDeptFilterChanged;
  final ValueChanged<String?> onShatrFilterChanged;
  final ValueChanged<String?> onSpecializationFilterChanged;
  final VoidCallback onResetFilters;
  final ValueChanged<String> onSort;

  const _StatusTabBody({
    super.key,
    required this.tabIndex,
    required this.loading,
    required this.error,
    required this.all,
    required this.onRetry,
    required this.deptFilter,
    required this.shatrFilter,
    required this.specializationFilter,
    required this.sortKey,
    required this.sortAscending,
    required this.onDeptFilterChanged,
    required this.onShatrFilterChanged,
    required this.onSpecializationFilterChanged,
    required this.onResetFilters,
    required this.onSort,
  });

  bool get isGraduatesTab => tabIndex == _kGraduatesTabIndex;
  String? get status => _kStatusByTabIndex[tabIndex];
  String get title => status ?? 'كل الطلبة';

  List<AdvisingCaseRecord> get _byStatus {
    if (status == null) return all;
    return all.where((r) => r.enrollmentStatus == status || (status == 'منتظم' && r.enrollmentStatus.isEmpty)).toList();
  }

  List<AdvisingCaseRecord> get _scoped {
    var list = _byStatus;
    if (deptFilter != null) list = list.where((r) => r.department == deptFilter).toList();
    if (shatrFilter != null) list = list.where((r) => r.shatr == shatrFilter).toList();
    return list;
  }

  List<AdvisingCaseRecord> get _filtered {
    var list = _scoped;
    if (isGraduatesTab && specializationFilter != null) {
      list = list.where((r) => r.specialization.trim() == specializationFilter).toList();
    }
    return list;
  }

  List<AdvisingCaseRecord> _sorted(List<AdvisingCaseRecord> list) {
    if (sortKey == null) return list;
    final sorted = [...list];
    int cmp(AdvisingCaseRecord a, AdvisingCaseRecord b) {
      switch (sortKey) {
        case 'studentId':
          return a.studentId.compareTo(b.studentId);
        case 'studentName':
          return a.studentName.compareTo(b.studentName);
        case 'department':
          return a.department.compareTo(b.department);
        case 'specialization':
          return a.specialization.compareTo(b.specialization);
        case 'shatr':
          return a.shatr.compareTo(b.shatr);
        case 'gpa':
          return (a.gpa ?? -1).compareTo(b.gpa ?? -1);
        case 'remainingHours':
          return (a.remainingHours ?? -1).compareTo(b.remainingHours ?? -1);
        default:
          return 0;
      }
    }

    sorted.sort(cmp);
    if (!sortAscending) return sorted.reversed.toList();
    return sorted;
  }

  bool get _hasFilter => deptFilter != null || shatrFilter != null || (isGraduatesTab && specializationFilter != null);

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()));
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 32, color: Colors.red.shade400),
              const SizedBox(height: 8),
              Text('تعذّر تحميل بيانات الطلبة: $error'),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final scoped = _scoped;
    final filtered = _sorted(_filtered);
    final showDepartmentColumn = deptFilter == null;
    final showShatrColumn = shatrFilter == null;

    final headers = [
      'الرقم الجامعي',
      'اسم الطالب',
      'القسم',
      'الشطر',
      'المعدل',
      if (!isGraduatesTab) 'الساعات المتبقية',
    ];
    final rows = [
      for (final r in filtered)
        [
          r.studentId,
          r.studentName,
          r.department,
          r.shatr,
          r.gpa?.toStringAsFixed(2) ?? '—',
          if (!isGraduatesTab) r.remainingHours?.toString() ?? '—',
        ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdvisingPageHeader(
          breadcrumbTrail: 'بيانات الطلبة الأكاديمية / $title',
          title: title,
          description: status == null
              ? 'كل طلبة الكلية من "بيانات الطلبة الأكاديمية" الخام - كل حالات القيد معًا.'
              : 'طلبة الكلية بحالة "$title" فقط.',
          icon: isGraduatesTab ? Icons.school_outlined : Icons.groups_2_outlined,
          actions: [
            TextButton.icon(
              onPressed: filtered.isEmpty
                  ? null
                  : () {
                      final bytes = AdvisingCaseExcelService.build(title: title, headers: headers, rows: rows);
                      downloadBytes(bytes, '$title.xlsx');
                    },
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Excel'),
            ),
            TextButton.icon(
              onPressed: filtered.isEmpty
                  ? null
                  : () async {
                      final bytes = await AdvisingCasePdfService.build(title: title, headers: headers, rows: rows);
                      await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
                    },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF/طباعة'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _countCards(scoped),
        if (isGraduatesTab) ...[
          const SizedBox(height: 16),
          _noContactNotice(),
          const SizedBox(height: 16),
          _departmentBreakdownCard(scoped),
        ],
        const SizedBox(height: 16),
        FilterBarShell(
          children: [
            FilterResetChip(active: !_hasFilter, onTap: onResetFilters),
            FilterPillDropdown<String>(
              label: 'الشطر',
              value: shatrFilter,
              items: [Shatr.male.label, Shatr.female.label],
              itemLabel: (v) => v,
              onChanged: onShatrFilterChanged,
            ),
            FilterPillDropdown<String>(
              label: 'القسم العلمي',
              value: deptFilter,
              items: _kDepartmentOrder,
              itemLabel: (v) => v.replaceFirst('قسم ', ''),
              onChanged: onDeptFilterChanged,
            ),
          ],
        ),
        const SizedBox(height: 16),
        KeyedSubtree(
          key: ValueKey('$tabIndex|$deptFilter|$shatrFilter|$sortKey|$sortAscending'),
          child: Builder(builder: (context) {
            // عرض أول 120 نتيجة فقط بالجدول - رسم آلاف الصفوف دفعة واحدة
            // (DashTable يبني كل صف كـWidget فعلي بلا Virtualization) هو ما
            // كان يُجمِّد الصفحة مع بيانات الكلية الكاملة. التصدير Excel/PDF
            // يبقى على القائمة الكاملة غير المقصوصة - القصّ للعرض فقط.
            const cap = 120;
            final tableRows = filtered.length > cap ? filtered.sublist(0, cap) : filtered;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  filtered.length > cap ? '${filtered.length} طالب/طالبة (تُعرَض أول $cap بالجدول - نزّل Excel/PDF لعرض الكل)' : '${filtered.length} طالب/طالبة',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashTokens.textSecondary),
                ),
                const SizedBox(height: 8),
                DashTableCard(
                  table: DashTable(
                    columns: [
                      const DashTableColumn(key: 'studentId', label: 'الرقم الجامعي', flex: 12, sortable: true),
                      const DashTableColumn(key: 'studentName', label: 'اسم الطالب', flex: 22, sortable: true),
                      if (showDepartmentColumn) const DashTableColumn(key: 'department', label: 'القسم', flex: 14, sortable: true),
                      if (showShatrColumn) const DashTableColumn(key: 'shatr', label: 'الشطر', flex: 9, sortable: true),
                      DashTableColumn(key: 'gpa', label: isGraduatesTab ? 'المعدل' : 'النطاق', flex: 11, sortable: true),
                      if (!isGraduatesTab) const DashTableColumn(key: 'remainingHours', label: 'الساعات المتبقية', flex: 11, sortable: true),
                    ],
                    rowCount: tableRows.length,
                    sortKey: sortKey,
                    sortAscending: sortAscending,
                    onSort: onSort,
                    cellBuilder: (context, i, key) {
                      final r = tableRows[i];
                      switch (key) {
                        case 'studentId':
                          return Text(r.studentId, style: const TextStyle(fontSize: 12.5));
                        case 'studentName':
                          return Text(r.studentName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600));
                        case 'department':
                          return Text(r.department, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5));
                        case 'shatr':
                          return Text(r.shatr, style: const TextStyle(fontSize: 12.5));
                        case 'gpa':
                          // تبويب "متخرج": رقم المعدل فقط بلا شريط النطاق
                          // الملوَّن (بطلب سليمان الصريح 2026-09-30 - "لا داعي
                          // للنطاق نهائيًا، يكتفي بالمعدل").
                          return isGraduatesTab
                              ? Text(r.gpa?.toStringAsFixed(2) ?? '—', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))
                              : _rangeBar(r.gpa);
                        case 'remainingHours':
                          return Text(r.remainingHours?.toString() ?? '—', style: const TextStyle(fontSize: 12.5));
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  /// الإجمالي + طلبة شطر الطلاب + طلبة شطر الطالبات بنفس صف واحد - امتداد
  /// أفقي لنمط `_courseCountStat` المعتمَد بـ`upload_hub_screen.dart` (بطلب
  /// سليمان: "عدد الإجمالي يكون تحت طلاب طالبات كالمعتاد").
  Widget _countCards(List<AdvisingCaseRecord> scoped) {
    final male = scoped.where((r) => r.shatr == Shatr.male.label).length;
    final female = scoped.where((r) => r.shatr == Shatr.female.label).length;
    return Row(
      children: [
        Expanded(child: _CountStat(label: 'الإجمالي', count: scoped.length, emoji: '📊')),
        const SizedBox(width: 10),
        Expanded(child: _CountStat(label: 'طلبة شطر الطلاب', count: male, emoji: '👨‍🎓')),
        const SizedBox(width: 10),
        Expanded(child: _CountStat(label: 'طلبة شطر الطالبات', count: female, emoji: '👩‍🎓')),
      ],
    );
  }

  /// تنبيه ثابت: لا تتوفر بيانات تواصل (بريد/جوال) بالمصدر الخام حاليًا -
  /// بطلب سليمان الصريح 2026-09-30 يُسجَّل كملاحظة واضحة بالواجهة بدل أي
  /// وظيفة إرسال وهمية، لحين توفر بيانات الاتصال (انظر بند TODO.md).
  Widget _noContactNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'لا تتوفر حاليًا بيانات تواصل (بريد إلكتروني/جوال) للخريجين بالمصدر الخام - ستُضاف إمكانية التواصل المباشر متى توفرت بيانات الاتصال.',
              style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// توزيع الخريجين حسب القسم (عدد + شريط نسبة من إجمالي [scoped]).
  Widget _departmentBreakdownCard(List<AdvisingCaseRecord> scoped) {
    final total = scoped.length;
    final counts = <String, int>{};
    for (final r in scoped) {
      counts.update(r.department, (v) => v + 1, ifAbsent: () => 1);
    }
    final ordered = [
      for (final d in _kDepartmentOrder)
        if ((counts[d] ?? 0) > 0) d,
      for (final d in counts.keys)
        if (!_kDepartmentOrder.contains(d)) d,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('توزيع الخريجين حسب القسم', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: DashTokens.textSecondary)),
          const SizedBox(height: 10),
          if (ordered.isEmpty) const Text('لا بيانات', style: TextStyle(fontSize: 12.5, color: DashTokens.textSecondary)),
          for (final d in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 140, child: Text(d.replaceFirst('قسم ', ''), style: const TextStyle(fontSize: 12))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : (counts[d] ?? 0) / total,
                        minHeight: 10,
                        backgroundColor: DashTokens.pageBg,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 32, child: Text('${counts[d] ?? 0}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة عدد بسيطة (إيموجي+رقم كبير، تسمية تحتها) - نفس نمط `_courseCountStat`
/// المعتمَد بـ`upload_hub_screen.dart`.
class _CountStat extends StatelessWidget {
  final String label;
  final int count;
  final String emoji;
  const _CountStat({required this.label, required this.count, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      child: Column(
        children: [
          Text('$emoji  $count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.greenDark)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
