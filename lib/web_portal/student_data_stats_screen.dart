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
import '../utils/name_display.dart';
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

/// حالات القيد الثلاث كما تُستنتَج من اسم كل ملف من الملفات الستة عند الرفع
/// (انظر `upload_flows.dart`: `_enrollmentStatusFromFreeText`).
const _kEnrollmentStatusOrder = ['منتظم', 'مفصول أكاديميًا', 'منقطع عن الدراسة'];

String _dash(String s) => s.trim().isEmpty ? '—' : s;

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

/// شاشة "بيانات الطلبة الأكاديمية" - **كل** طلبة الملفات الستة المرفوعة
/// (منتظم/مفصول أكاديميًا/منقطع عن الدراسة معًا)، بخلاف كل شاشات الإرشاد
/// الأخرى التي تستبعد غير المنتظم كليًا (انظر
/// `AdvisingCaseAnalyzer.isRegularlyEnrolled`) - هذه الشاشة مصدر الرؤية
/// الشاملة لكل حالات القيد معًا، بطلب سليمان صراحةً (2026-08-27). تقرأ
/// `AdvisingReportKind.base` مباشرة بلا مرور بـ`AdvisingCaseAnalyzer.analyze`
/// حتى لا يُستبعَد أي طالب. عمود/فلتر "المرشد" يُثرى إضافيًا من تقرير "كل
/// الكليات" (`AdvisingReportKind.allColleges`) مطابقةً بالرقم الجامعي - غير
/// موجود أصلًا ببيانات "بيانات الطلبة الأكاديمية" نفسها (بطلب سليمان صراحةً
/// 2026-08-27: فلتر شطر/قسم/مرشد/حالة كالمعتاد بشاشة "الخدمات السريعة").
class StudentDataStatsScreen extends StatefulWidget {
  const StudentDataStatsScreen({super.key});

  @override
  State<StudentDataStatsScreen> createState() => _StudentDataStatsScreenState();
}

class _StudentDataStatsScreenState extends State<StudentDataStatsScreen> {
  bool _loading = true;
  String? _error;
  List<AdvisingCaseRecord> _all = [];

  String? _departmentFilter;
  String? _shatrFilter;
  String? _statusFilter;
  String? _advisorFilter;

  String? _sortKey;
  bool _sortAscending = true;

  bool get _hasFilter => _departmentFilter != null || _shatrFilter != null || _statusFilter != null || _advisorFilter != null;

  void _resetFilters() => setState(() {
        _departmentFilter = null;
        _shatrFilter = null;
        _statusFilter = null;
        _advisorFilter = null;
      });

  void _onSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = true;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
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
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
      ]);
      final seen = <String>{};
      final merged = <AdvisingCaseRecord>[];
      for (final r in [...results[0], ...results[1]]) {
        if (seen.add(r.studentId)) merged.add(r);
      }
      // إثراء المرشد من تقرير "كل الكليات" - مطابقة بالرقم الجامعي فقط (نفس
      // مبدأ AdvisingCaseAnalyzer.mergeAcademicData لكن بالاتجاه المعاكس:
      // هنا الأساس "بيانات الطلبة الأكاديمية" ونثري منه المرشد، لا العكس).
      final advisorById = {for (final a in [...results[2], ...results[3]]) a.studentId: a.advisorNameRaw};
      final enriched = [
        for (final r in merged)
          if (advisorById[r.studentId]?.trim().isNotEmpty ?? false) r.copyWith(advisorNameRaw: advisorById[r.studentId]) else r,
      ];
      if (!mounted) return;
      setState(() {
        _all = enriched;
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

  List<AdvisingCaseRecord> get _scopedByDeptAndShatr => _all.where((r) {
        if (_departmentFilter != null && r.department != _departmentFilter) return false;
        if (_shatrFilter != null && r.shatr != _shatrFilter) return false;
        return true;
      }).toList();

  List<String> get _advisorFilterOptions => _scopedByDeptAndShatr
      .map((r) => r.advisorNameRaw.trim())
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<AdvisingCaseRecord> get _filtered {
    var scoped = _scopedByDeptAndShatr;
    if (_statusFilter != null) scoped = scoped.where((r) => r.enrollmentStatus.trim() == _statusFilter).toList();
    if (_advisorFilter != null) scoped = scoped.where((r) => r.advisorNameRaw.trim() == _advisorFilter).toList();
    return scoped;
  }

  List<AdvisingCaseRecord> _sorted(List<AdvisingCaseRecord> list) {
    if (_sortKey == null) return list;
    final sorted = [...list];
    int cmp(AdvisingCaseRecord a, AdvisingCaseRecord b) {
      switch (_sortKey) {
        case 'studentId':
          return a.studentId.compareTo(b.studentId);
        case 'studentName':
          return a.studentName.compareTo(b.studentName);
        case 'department':
          return a.department.compareTo(b.department);
        case 'shatr':
          return a.shatr.compareTo(b.shatr);
        case 'advisor':
          return a.advisorNameRaw.compareTo(b.advisorNameRaw);
        case 'status':
          return a.enrollmentStatus.compareTo(b.enrollmentStatus);
        case 'gpa':
          return (a.gpa ?? -1).compareTo(b.gpa ?? -1);
        case 'remainingHours':
          return (a.remainingHours ?? -1).compareTo(b.remainingHours ?? -1);
        default:
          return 0;
      }
    }

    sorted.sort(cmp);
    if (!_sortAscending) return sorted.reversed.toList();
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'بيانات الطلبة الأكاديمية',
      navItems: buildAdminNavItems(context, current: 'reports-hub'),
      body: Container(
        color: DashTokens.pageBg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 32, color: Colors.red.shade400),
              const SizedBox(height: 8),
              Text('تعذّر تحميل بيانات الطلبة: $_error'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final scoped = _scopedByDeptAndShatr;
    final filtered = _sorted(_filtered);
    final showDepartmentColumn = _departmentFilter == null;

    const headers = ['الرقم الجامعي', 'اسم الطالب', 'القسم', 'الشطر', 'المرشد', 'الحالة', 'المعدل', 'الساعات المتبقية'];
    final rows = [
      for (final r in filtered)
        [
          r.studentId,
          r.studentName,
          r.department,
          r.shatr,
          _dash(displayName(r.advisorNameRaw)),
          r.enrollmentStatus.isEmpty ? 'منتظم' : r.enrollmentStatus,
          r.gpa?.toStringAsFixed(2) ?? '—',
          r.remainingHours?.toString() ?? '—',
        ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdvisingPageHeader(
          breadcrumbTrail: 'بيانات الطلبة الأكاديمية',
          title: 'بيانات الطلبة الأكاديمية',
          description: 'كل طلبة الكلية من الملفات الستة المرفوعة (منتظم/مفصول أكاديميًا/منقطع عن الدراسة) - يشمل كل الحالات معًا، بخلاف شاشات الإرشاد التي تستبعد غير المنتظم.',
          icon: Icons.groups_2_outlined,
          actions: [
            TextButton.icon(
              onPressed: filtered.isEmpty
                  ? null
                  : () {
                      final bytes = AdvisingCaseExcelService.build(title: 'بيانات الطلبة الأكاديمية', headers: headers, rows: rows);
                      downloadBytes(bytes, 'بيانات الطلبة الأكاديمية.xlsx');
                    },
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Excel'),
            ),
            TextButton.icon(
              onPressed: filtered.isEmpty
                  ? null
                  : () async {
                      final bytes = await AdvisingCasePdfService.build(title: 'بيانات الطلبة الأكاديمية', headers: headers, rows: rows);
                      await Printing.sharePdf(bytes: bytes, filename: 'بيانات الطلبة الأكاديمية.pdf');
                    },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF/طباعة'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _statCards(scoped),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterResetChip(active: !_hasFilter, onTap: _resetFilters),
            FilterPillDropdown<String>(
              label: 'الشطر',
              value: _shatrFilter,
              items: [Shatr.male.label, Shatr.female.label],
              itemLabel: (v) => v,
              onChanged: (v) => setState(() {
                _shatrFilter = v;
                _advisorFilter = null;
              }),
            ),
            FilterPillDropdown<String>(
              label: 'القسم العلمي',
              value: _departmentFilter,
              items: _kDepartmentOrder,
              itemLabel: (v) => v.replaceFirst('قسم ', ''),
              onChanged: (v) => setState(() {
                _departmentFilter = v;
                _advisorFilter = null;
              }),
            ),
            FilterPillDropdown<String>(
              key: ValueKey('$_departmentFilter|$_shatrFilter'),
              label: 'المرشد',
              value: _advisorFilter,
              items: _advisorFilterOptions,
              itemLabel: displayName,
              onChanged: (v) => setState(() => _advisorFilter = v),
            ),
            FilterPillDropdown<String>(
              label: 'الحالة',
              value: _statusFilter,
              items: _kEnrollmentStatusOrder,
              itemLabel: (v) => v,
              onChanged: (v) => setState(() => _statusFilter = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // مفتاح صريح على كل الفلاتر - يضمن تخلّص Flutter من أي حالة قديمة
        // بالجدول عند أي تغيير فلتر (بطلب سليمان صراحةً 2026-08-27 بعد أن
        // لاحظ أن الجدول أحيانًا لا يعكس الفلتر المختار فورًا).
        KeyedSubtree(
          key: ValueKey('$_departmentFilter|$_shatrFilter|$_statusFilter|$_advisorFilter|$_sortKey|$_sortAscending'),
          child: Builder(builder: (context) {
            // عرض أول 120 نتيجة فقط بالجدول - رسم آلاف الصفوف دفعة واحدة
            // (DashTable يبني كل صف كـWidget فعلي بلا Virtualization) هو ما
            // كان يُجمِّد الصفحة مع بيانات الكلية الكاملة (اقتراح سليمان
            // صراحةً 2026-08-27). التصدير Excel/PDF يبقى على القائمة الكاملة
            // غير المقصوصة (`filtered`/`rows` أعلاه) - القصّ للعرض فقط.
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
                      const DashTableColumn(key: 'studentName', label: 'اسم الطالب', flex: 20, sortable: true),
                      if (showDepartmentColumn) const DashTableColumn(key: 'department', label: 'القسم', flex: 14, sortable: true),
                      const DashTableColumn(key: 'shatr', label: 'الشطر', flex: 9, sortable: true),
                      const DashTableColumn(key: 'advisor', label: 'المرشد', flex: 16, sortable: true),
                      const DashTableColumn(key: 'status', label: 'الحالة', flex: 13, sortable: true),
                      const DashTableColumn(key: 'gpa', label: 'النطاق', flex: 11, sortable: true),
                      const DashTableColumn(key: 'remainingHours', label: 'الساعات المتبقية', flex: 11, sortable: true),
                    ],
                    rowCount: tableRows.length,
                    sortKey: _sortKey,
                    sortAscending: _sortAscending,
                    onSort: _onSort,
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
                      case 'advisor':
                        return Text(_dash(displayName(r.advisorNameRaw)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5));
                      case 'status':
                        return _StatusBadge(status: r.enrollmentStatus);
                      case 'gpa':
                        return _rangeBar(r.gpa);
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

  Widget _statCards(List<AdvisingCaseRecord> scoped) {
    final total = scoped.length;
    final regular = scoped.where((r) => r.enrollmentStatus.isEmpty || r.enrollmentStatus == 'منتظم').length;
    final dismissed = scoped.where((r) => r.isAcademicallyDismissed).length;
    final withdrawn = scoped.where((r) => r.enrollmentStatus.contains('منقطع')).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 900 ? 4 : (w >= 500 ? 2 : 1);
        final cards = [
          _StatCard(label: 'الإجمالي', value: total, color: DashTokens.green900),
          _StatCard(label: 'منتظم', value: regular, color: AppColors.greenDark),
          _StatCard(label: 'مفصول أكاديميًا', value: dismissed, color: Colors.red.shade600),
          _StatCard(label: 'منقطع عن الدراسة', value: withdrawn, color: Colors.orange.shade700),
        ];
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: cards,
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: DashTokens.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final text = status.isEmpty ? 'منتظم' : status;
    final color = status.contains('مفصول')
        ? Colors.red.shade600
        : status.contains('منقطع')
            ? Colors.orange.shade700
            : AppColors.greenDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
