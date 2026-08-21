import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/advising_case_record.dart';
import '../utils/name_display.dart';
import '../services/advising_case_excel_service.dart';
import '../services/advising_case_pdf_service.dart';
import '../services/advising_report_repository.dart';
import '../services/course_schedule_repository.dart' show Shatr;
import '../services/web_download.dart';
import '../theme/app_theme.dart';
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
      ]);
      final all = [...results[0], ...results[1]];

      final byAdvisor = <String, List<AdvisingCaseRecord>>{};
      for (final r in all) {
        if (!r.hasAdvisor) continue;
        final key = '${r.advisorNameRaw}|${r.shatr}';
        byAdvisor.putIfAbsent(key, () => []).add(r);
      }

      final groups = byAdvisor.entries.map((e) {
        final first = e.value.first;
        return _AdvisorGroup(
          name: displayName(first.advisorNameRaw),
          advisorId: first.advisorId,
          shatr: first.shatr,
          students: e.value..sort((a, b) => a.studentName.compareTo(b.studentName)),
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
    return _allGroups.where((g) => _normalize(g.name).contains(q)).toList();
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
                    hintText: 'ابحث باسم المرشد أو جزء من الاسم...',
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
            description: 'اكتب اسم المرشد أو جزءًا من الاسم لعرض بياناته وقائمة الطلبة المرتبطين به.\nإجمالي المرشدين المتاحين للبحث: ${_allGroups.length}',
          )
        else if (results.isEmpty)
          AdvisingEmptyState(icon: Icons.search_off, title: 'لا يوجد مرشد مطابق', description: 'لم يُعثر على مرشد باسم "$_query" - جرّب تدقيق الاسم.')
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

  Widget _buildAdvisorPanel(_AdvisorGroup group) {
    // عمود "التخصص" غير مفيد هنا (كل الطلاب أصلاً لنفس المرشد، غالبًا نفس
    // القسم) - أُزيل بطلب سليمان الصريح (2026-08-15). مستقبلاً حين تكتمل
    // بيانات الطلبة الأكاديمية (المعدل/النطاق)، يُضاف عمودا "المعدل"/"النطاق"
    // بدلاً منه هنا.
    final title = '${group.name} - ${group.shatr}${group.advisorId.isNotEmpty ? ' (رقم المرشد: ${group.advisorId})' : ''}';
    final headers = ['الرقم الجامعي', 'اسم الطالب'];
    final rows = [for (final s in group.students) [s.studentId, s.studentName]];
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.green),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: [for (final h in headers) DataColumn(label: Expanded(child: Text(h, textAlign: TextAlign.center)))],
              rows: [
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                    cells: [for (final v in rows[i]) DataCell(Center(child: Text(v)))],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
