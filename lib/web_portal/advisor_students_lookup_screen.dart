import 'package:flutter/material.dart';

import '../models/advising_case_record.dart';
import '../services/advising_report_repository.dart';
import '../services/course_schedule_repository.dart' show Shatr;
import '../theme/app_theme.dart';
import 'admin_nav.dart';
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
/// جديد، فقط تجميع/فلترة على بيانات موجودة ومُختبَرة فعلاً.
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
  String? _expandedKey;

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
          name: first.advisorNameRaw,
          advisorId: first.advisorId,
          shatr: first.shatr,
          students: e.value,
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
    return PortalScaffold(
      title: 'بحث عن مرشد وقائمة طلابه',
      navItems: buildAdminNavItems(context, current: 'advising-hub'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
                    : _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_allGroups.isEmpty) {
      return Center(
        child: Text(
          'لا توجد بيانات مرشدين بعد - ارفع ملف "كل الكليات" أولًا '
          'من شاشة "متابعة حالات الإرشاد".',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final results = _filteredGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'اكتب اسم المرشد (كل أو جزء من الاسم)',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 16),
        if (_query.trim().isEmpty)
          Text(
            'إجمالي المرشدين المتاحين للبحث: ${_allGroups.length}',
            style: TextStyle(color: Colors.grey.shade600),
          )
        else if (results.isEmpty)
          Text('لا يوجد مرشد مطابق لـ"$_query"', style: TextStyle(color: Colors.grey.shade600))
        else
          Expanded(
            child: ListView.separated(
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _buildAdvisorCard(results[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildAdvisorCard(_AdvisorGroup group) {
    final key = '${group.name}|${group.shatr}';
    final expanded = _expandedKey == key;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: (v) => setState(() => _expandedKey = v ? key : null),
        leading: CircleAvatar(
          backgroundColor: AppColors.green.withValues(alpha: 0.12),
          child: const Icon(Icons.person_outline, color: AppColors.green),
        ),
        title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${group.shatr}${group.advisorId.isNotEmpty ? ' - رقم المرشد: ${group.advisorId}' : ''} - عدد الطلاب: ${group.students.length}',
        ),
        children: [
          if (expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('الرقم الجامعي')),
                    DataColumn(label: Text('اسم الطالب')),
                    DataColumn(label: Text('التخصص')),
                  ],
                  rows: group.students
                      .map((s) => DataRow(cells: [
                            DataCell(Text(s.studentId)),
                            DataCell(Text(s.studentName)),
                            DataCell(Text(s.department)),
                          ]))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
