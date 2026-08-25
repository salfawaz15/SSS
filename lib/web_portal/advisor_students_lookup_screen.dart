import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/advising_case_record.dart';
import '../utils/name_display.dart';
import '../services/advising_case_analyzer.dart';
import '../services/advising_case_excel_service.dart';
import '../services/advising_case_pdf_service.dart';
import '../services/advising_report_repository.dart';
import '../services/course_schedule_repository.dart' show Shatr;
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import '../theme/dashboard_table.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';

class _AdvisorGroup {
  final String name;
  final String advisorId;
  final String shatr;
  final List<AdvisingCaseRecord> students;

  const _AdvisorGroup({
    required this.name,
    required this.advisorId,
    required this.shatr,
    required this.students,
  });
}

/// بحث عن مرشد أكاديمي واحد وعرض قائمة طلابه كاملة - بطلب سليمان صراحةً
/// (2026-08-13): "لو أردت فلترة على اسم معين تظهر لي قائمة طلابه". يُبنى
/// مباشرة على بيانات تقرير "كل الكليات" (`AdvisingReportKind.allColleges`)
/// المرفوعة أصلاً عبر شاشة "متابعة حالات الإرشاد" - بلا أي قارئ أو تخزين
/// جديد، فقط تجميع/فلترة على بيانات موجودة ومُختبَرة فعلاً. أُعيد تصميمها
/// (2026-08-15) بنفس الهوية البصرية لبقية جداول الموقع (جدول أخضر منسَّق +
/// تصدير Excel/PDF) بعد أن لاحظ سليمان أن التصميم السابق (بطاقات قابلة للطي
/// بلا أي تصدير) غير احترافي ولا يمكن طباعته.
class AdvisorStudentsLookupScreen extends StatefulWidget {
  const AdvisorStudentsLookupScreen({super.key});

  @override
  State<AdvisorStudentsLookupScreen> createState() => _AdvisorStudentsLookupScreenState();
}

class _AdvisorStudentsLookupScreenState extends State<AdvisorStudentsLookupScreen> {
  bool _loading = true;
  String? _error;
  List<_AdvisorGroup> _allGroups = [];
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedKey;

  // فرز بالضغط على رأس العمود - نفس الآلية الموحَّدة المعتمَدة بكل جداول
  // الموقع (`DashTable`، أول تطبيق بجدول منسوبي الكلية) - بطلب سليمان
  // صراحةً (2026-08-26). مفتاح دلالي لا رقم عمود ثابت.
  String? _sortKey;
  bool _sortAscending = true;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.base),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.base),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.basePrevious),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.basePrevious),
      ]);
      final academic = [...results[2], ...results[3]];
      final academicPrevious = [...results[4], ...results[5]];
      final all = AdvisingCaseAnalyzer.mergeAcademicData([...results[0], ...results[1]], academic, academicPrevious);

      final byAdvisor = <String, List<AdvisingCaseRecord>>{};
      for (final r in all) {
        if (!r.hasAdvisor) continue;
        final key = '${r.advisorNameRaw}|${r.shatr}';
        byAdvisor.putIfAbsent(key, () => []).add(r);
      }

      // ترتيب طلاب كل مرشد تصاعديًا حسب المعدل التراكمي (الأقل معدلاً أولاً -
      // بطلب سليمان صراحةً 2026-08-26، الأولوية لمن يحتاج متابعة المرشد
      // أكثر) - هذا الترتيب الافتراضي فقط، يبقى قابلاً لإعادة الفرز يدويًا
      // بالضغط على أي رأس عمود (انظر `_sortKey`/`DashTable`). عند تساوي
      // المعدل (أو غيابه لدى الطرفين): الأقدم أولاً حسب الرقم الجامعي
      // **الأصغر رقميًا** (مثال: 43005957 قبل 44005957) - الأرقام الجامعية
      // الأقدم تبدأ بسنة قبول أصغر فتصبح قيمتها الرقمية أصغر.
      int compareStudents(AdvisingCaseRecord a, AdvisingCaseRecord b) {
        final ga = a.gpa;
        final gb = b.gpa;
        if (ga != null && gb != null) {
          final c = ga.compareTo(gb);
          if (c != 0) return c;
        } else if (ga != null || gb != null) {
          return ga != null ? -1 : 1;
        }
        final ia = int.tryParse(a.studentId);
        final ib = int.tryParse(b.studentId);
        if (ia != null && ib != null) return ia.compareTo(ib);
        return a.studentId.compareTo(b.studentId);
      }

      final groups = byAdvisor.entries.map((e) {
        final first = e.value.first;
        return _AdvisorGroup(
          name: displayName(first.advisorNameRaw),
          advisorId: first.advisorId,
          shatr: first.shatr,
          students: e.value..sort(compareStudents),
        );
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _allGroups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل بيانات المرشدين: $e';
        _loading = false;
      });
    }
  }

  static String _normalize(String s) => s
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .toLowerCase();

  List<_AdvisorGroup> get _filteredGroups {
    if (_query.trim().isEmpty) return const [];
    final q = _normalize(_query);
    // البحث برقم المرشد أيضًا (لا الاسم فقط) - البيانات متاحة أصلًا
    // (AdvisingCaseRecord.advisorId من تقرير "طلاب تابعين لمرشد").
    return _allGroups.where((g) => _normalize(g.name).contains(q) || (g.advisorId.isNotEmpty && g.advisorId.contains(q))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'بحث عن مرشد وقائمة طلابه',
      navItems: buildAdminNavItems(context, current: 'advising-hub'),
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.lookup, isSuperAdmin: isSuperAdmin),
          Expanded(
            child: Container(
              color: DashTokens.pageBg,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AdvisingPageHeader(
                          breadcrumbTrail: 'بحث عن مرشد وقائمة طلبته',
                          title: 'بحث عن مرشد وقائمة طلبته',
                          description: 'ابحث باسم المرشد أو رقمه لعرض بياناته وقائمة الطلبة المرتبطين به.',
                          icon: Icons.person_search_outlined,
                        ),
                        const SizedBox(height: 18),
                        if (_loading)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
                        else if (_error != null)
                          AdvisingEmptyState(icon: Icons.error_outline, title: 'تعذّر تحميل البيانات', description: _error!)
                        else
                          _buildBody(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_allGroups.isEmpty) {
      return const AdvisingEmptyState(
        icon: Icons.person_search_outlined,
        title: 'لا توجد بيانات مرشدين بعد',
        description: 'ارفع ملف "كل الكليات" أولًا من شاشة "متابعة حالات الإرشاد" لتصبح بيانات المرشدين متاحة هنا.',
      );
    }

    final results = _filteredGroups;
    _AdvisorGroup? selected;
    if (_selectedKey != null) {
      for (final g in results) {
        if ('${g.name}|${g.shatr}' == _selectedKey) {
          selected = g;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              const Icon(Icons.search, size: 20, color: DashTokens.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'ابحث باسم المرشد أو رقمه...',
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _selectedKey = null;
                  }),
                ),
              ),
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _selectedKey = null;
                    });
                  },
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 4),
          child: Text('إجمالي المرشدين المتاحين للبحث', style: TextStyle(fontSize: 10.5, color: DashTokens.textMuted)),
        ),
        const SizedBox(height: 16),
        if (_query.trim().isEmpty)
          AdvisingEmptyState(
            icon: Icons.search,
            title: 'ابدأ بالبحث عن مرشد',
            description: 'اكتب اسم المرشد أو رقمه لعرض بياناته وقائمة الطلبة المرتبطين به.\nإجمالي المرشدين المتاحين للبحث: ${_allGroups.length}',
          )
        else if (results.isEmpty)
          AdvisingEmptyState(icon: Icons.search_off, title: 'لا يوجد مرشد مطابق', description: 'لم يُعثر على مرشد بالاسم أو الرقم "$_query" - جرّب تدقيق البحث.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in results)
                ChoiceChip(
                  label: Text('${g.name} (${g.students.length})'),
                  selected: '${g.name}|${g.shatr}' == _selectedKey,
                  onSelected: (_) => setState(() => _selectedKey = '${g.name}|${g.shatr}'),
                  selectedColor: AppColors.greenDark,
                  labelStyle: TextStyle(color: '${g.name}|${g.shatr}' == _selectedKey ? Colors.white : Colors.grey.shade700),
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
            ],
          ),
        if (selected != null) ...[const SizedBox(height: 16), _buildAdvisorPanel(selected)],
      ],
    );
  }

  static String _gpaText(AdvisingCaseRecord s) => s.gpa != null ? s.gpa!.toStringAsFixed(2) : '—';
  static String _rangeText(AdvisingCaseRecord s) => gpaStatusOf(s.gpa).label;

  /// نسخة مرتَّبة من طلاب المرشد وفق العمود المختار بالضغط على رأس عمود
  /// (`_sortKey`) - ترتيب افتراضي (بلا اختيار) يبقى تصاعديًا حسب المعدل كما
  /// حُمِّل أصلاً بـ[_load]. نفس القائمة تُستخدَم للعرض والتصدير معًا حتى
  /// يطابق الملف المصدَّر ما يظهر على الشاشة بالضبط.
  List<AdvisingCaseRecord> _sortedStudents(_AdvisorGroup group) {
    if (_sortKey == null) return group.students;
    int cmp(AdvisingCaseRecord a, AdvisingCaseRecord b) {
      switch (_sortKey) {
        case 'studentId':
          return a.studentId.compareTo(b.studentId);
        case 'gpa':
        case 'range':
          final ga = a.gpa;
          final gb = b.gpa;
          if (ga == null && gb == null) return 0;
          if (ga == null || gb == null) return ga == null ? 1 : -1;
          return ga.compareTo(gb);
        case 'completedHours':
          final ca = a.completedHours;
          final cb = b.completedHours;
          if (ca == null && cb == null) return 0;
          if (ca == null || cb == null) return ca == null ? 1 : -1;
          return ca.compareTo(cb);
        case 'remainingHours':
          final ra = a.remainingHours;
          final rb = b.remainingHours;
          if (ra == null && rb == null) return 0;
          if (ra == null || rb == null) return ra == null ? 1 : -1;
          return ra.compareTo(rb);
        case 'studentName':
        default:
          return a.studentName.compareTo(b.studentName);
      }
    }

    final sorted = [...group.students]..sort(cmp);
    if (!_sortAscending) return sorted.reversed.toList();
    return sorted;
  }

  Widget _buildAdvisorPanel(_AdvisorGroup group) {
    // عمود "التخصص" غير مفيد هنا (كل الطلاب أصلاً لنفس المرشد، غالبًا نفس
    // القسم) - أُزيل بطلب سليمان الصريح (2026-08-15). أُضيفت أعمدة "المعدل"/
    // "النطاق"/"الساعات المجتازة"/"الساعات المتبقية" بدلاً منه (2026-08-25/26)
    // بعد ربط رفع "بيانات الطلبة الأكاديمية". الجدول بهوية `DashTable`
    // الموحَّدة لكل جداول الموقع (فرز بالضغط على أي رأس عمود) - بطلب سليمان
    // صراحةً (2026-08-26)، بدل `DataTable` القياسي السابق.
    final title = '${group.name} - ${group.shatr}${group.advisorId.isNotEmpty ? ' (رقم المرشد: ${group.advisorId})' : ''}';
    final students = _sortedStudents(group);
    final headers = ['الرقم الجامعي', 'اسم الطالب', 'المعدل', 'النطاق', 'الساعات المجتازة', 'الساعات المتبقية'];
    final rows = [
      for (final s in students)
        [
          s.studentId,
          s.studentName,
          _gpaText(s),
          _rangeText(s),
          s.completedHours?.toString() ?? '—',
          s.remainingHours?.toString() ?? '—',
        ],
    ];
    final columns = <DashTableColumn>[
      const DashTableColumn(key: 'studentId', label: 'الرقم الجامعي', flex: 14, sortable: true),
      const DashTableColumn(key: 'studentName', label: 'اسم الطالب', flex: 26, sortable: true, align: TextAlign.right),
      const DashTableColumn(key: 'gpa', label: 'المعدل', flex: 10, sortable: true),
      const DashTableColumn(key: 'range', label: 'النطاق', flex: 12, sortable: true),
      const DashTableColumn(key: 'completedHours', label: 'الساعات المجتازة', flex: 14, sortable: true),
      const DashTableColumn(key: 'remainingHours', label: 'الساعات المتبقية', flex: 14, sortable: true),
    ];

    Widget cell(BuildContext context, int i, String key) {
      final s = students[i];
      switch (key) {
        case 'studentId':
          return Text(s.studentId, style: const TextStyle(fontSize: 12.5));
        case 'studentName':
          return Text(s.studentName, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600));
        case 'gpa':
          return Text(_gpaText(s), style: const TextStyle(fontSize: 12.5));
        case 'range':
          return Text(_rangeText(s), style: const TextStyle(fontSize: 12.5));
        case 'completedHours':
          return Text(s.completedHours?.toString() ?? '—', style: const TextStyle(fontSize: 12.5));
        case 'remainingHours':
          return Text(s.remainingHours?.toString() ?? '—', style: const TextStyle(fontSize: 12.5));
        default:
          return const SizedBox.shrink();
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('$title (${group.students.length})', style: AppTextStyles.h3(color: AppColors.greenDark))),
              TextButton.icon(
                onPressed: () {
                  final bytes = AdvisingCaseExcelService.build(title: group.name, headers: headers, rows: rows);
                  downloadBytes(bytes, '${group.name}.xlsx');
                },
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Excel'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final bytes = await AdvisingCasePdfService.build(title: title, headers: headers, rows: rows);
                  await Printing.sharePdf(bytes: bytes, filename: '${group.name}.pdf');
                },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF/طباعة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DashTableCard(
            table: DashTable(
              columns: columns,
              rowCount: students.length,
              sortKey: _sortKey,
              sortAscending: _sortAscending,
              onSort: _onSort,
              cellBuilder: cell,
            ),
          ),
        ],
      ),
    );
  }
}
