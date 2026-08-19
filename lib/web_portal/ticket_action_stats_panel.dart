import 'package:flutter/material.dart';

import '../services/excel_parser_service.dart';
import '../services/report_data_service.dart';
import '../services/ticket_action_stats_service.dart';
import '../theme/app_theme.dart';
import 'portal_cards.dart';

/// لوحة إحصائيات طلبات الحذف/الإضافة/تعديل الشعب - "الإنجاز" الحقيقي الذي
/// نقيسه هنا هو معالجة المرشد (ثم منسّق القسم فمنسّق الكلية) لهذه الطلبات
/// نفسها، فهو عمل المرشد الإرشادي بحق. أما تسكين الطالب على مرشده الصحيح
/// (`advisor_corrected`) فهو شرط صحة بيانات أساسي لا مؤشر تقدّم - يُعرض هنا
/// كتنبيه منفصل بصريًا عن بطاقات الإنجاز، لا كرقم إنجاز. تظهر تلقائيًا أسفل
/// لوحة متابعة الإنجاز بلوحة الإدارة.
class TicketActionStatsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> tickets;
  final ReportData reportData;

  const TicketActionStatsPanel({super.key, required this.tickets, required this.reportData});

  static const _actionColors = {
    'إضافة': Color(0xFF2E7D32),
    'حذف': Color(0xFFB3261E),
    'تعديل': Color(0xFF9C6D00),
  };

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return const SizedBox.shrink();

    final stats = TicketActionStatsService.build(tickets);
    if (stats.totalActions == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.greenDark),
              const SizedBox(width: 8),
              const Text(
                'إحصائيات طلبات الحذف والإضافة وتعديل الشعب',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.greenDark),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final cards = [
                for (final type in ['إضافة', 'حذف', 'تعديل'])
                  if (stats.byActionType.containsKey(type))
                    PortalStatCard(
                      icon: type == 'إضافة'
                          ? Icons.add_circle_outline
                          : type == 'حذف'
                              ? Icons.remove_circle_outline
                              : Icons.swap_horiz,
                      value: '${stats.byActionType[type]!.total}',
                      label: 'طلبات $type',
                      accentColor: _actionColors[type]!,
                    ),
                PortalStatCard(
                  icon: Icons.priority_high_rounded,
                  value: '${stats.priorityPendingCount}',
                  label: 'خريجون/ذوو إعاقة لهم طلبات معلَّقة',
                  accentColor: AppColors.gold,
                ),
              ];
              if (isNarrow) {
                return Column(
                  children: [
                    for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in cards) SizedBox(width: (constraints.maxWidth - 24) / 3, child: c),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'حالة إنجاز معالجة الطلبات (لكل نوع إجراء)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.greenDark),
          ),
          const SizedBox(height: 10),
          for (final type in ['إضافة', 'حذف', 'تعديل'])
            if (stats.byActionType.containsKey(type))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ActionProgressBar(
                  label: type,
                  color: _actionColors[type]!,
                  stats: stats.byActionType[type]!,
                ),
              ),
          const SizedBox(height: 16),
          const Text(
            'توزيع الطلبات حسب القسم والشطر',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.greenDark),
          ),
          const SizedBox(height: 10),
          _DepartmentBreakdownTable(stats: stats),
          const SizedBox(height: 24),
          const Text(
            'عدد الحالات لدى كل مرشد',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.greenDark),
          ),
          const SizedBox(height: 10),
          _AdvisorCaseCountTable(advisors: TicketActionStatsService.buildAdvisorCaseStats(tickets)),
          const SizedBox(height: 24),
          _TeamPerformanceSection(reportData: reportData),
          if (stats.advisorMismatchCount > 0) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'تنبيه صحة بيانات (ليس مؤشر إنجاز): ${stats.advisorMismatchCount} '
                      'حالة اختار فيها الطالب مرشدًا غير مرشده الفعلي بالنموذج - '
                      'صُحِّحت تلقائيًا واعتُمد المرشد الصحيح لتوجيه الطلب.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.errorRed),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// شريط تقدّم واحد لنوع إجراء واحد: نسبة (لم يبدأ/قيد التنفيذ/مكتمل) - هذا
/// هو "الإنجاز" الفعلي (معالجة المرشد/منسّق القسم/منسّق الكلية للطلب).
class _ActionProgressBar extends StatelessWidget {
  final String label;
  final Color color;
  final ActionTypeStats stats;

  const _ActionProgressBar({required this.label, required this.color, required this.stats});

  @override
  Widget build(BuildContext context) {
    final counts = stats.statusCounts;
    final total = counts.total == 0 ? 1 : counts.total;
    final completed = counts.completed;
    final partial = counts.partial;
    final notStarted = counts.notDone + counts.blank;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              'مكتمل $completed / قيد التنفيذ $partial / لم يبدأ $notStarted',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            // نتجنّب Row+Expanded(flex: ...) عمدًا: قيمة flex صفر لأكثر من
            // شريحة معًا (شائعة هنا لأن أغلب الطلبات لم تُعالَج بعد) قد
            // تُنتج تخطيطًا فارغًا بصمت. نحسب العرض بالبكسل مباشرة بدل ذلك،
            // بنفس أسلوب _AdvisorBars المُجرَّب فعليًا بهذا المشروع.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final completedW = w * completed / total;
                final partialW = w * partial / total;
                final notStartedW = (w - completedW - partialW).clamp(0.0, w);
                return Row(
                  children: [
                    Container(width: completedW, color: const Color(0xFF2E7D32)),
                    Container(width: partialW, color: AppColors.gold),
                    Container(width: notStartedW, color: Colors.grey.shade300),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DepartmentBreakdownTable extends StatelessWidget {
  final TicketActionStats stats;

  const _DepartmentBreakdownTable({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, Map<String, int>>>[];
    for (final shatr in [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]) {
      for (final department in ExcelParserService.departments) {
        final key = '$shatr|$department';
        final counts = stats.byDepartmentShatr[key];
        if (counts != null && counts.isNotEmpty) rows.add(MapEntry(key, counts));
      }
    }
    if (rows.isEmpty) {
      return Text('لا توجد بيانات كافية', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.background),
        columns: const [
          DataColumn(label: Text('الشطر')),
          DataColumn(label: Text('القسم')),
          DataColumn(label: Text('إضافة')),
          DataColumn(label: Text('حذف')),
          DataColumn(label: Text('تعديل')),
          DataColumn(label: Text('الإجمالي')),
        ],
        rows: [
          for (final entry in rows)
            DataRow(
              cells: [
                DataCell(Text(entry.key.split('|').first)),
                DataCell(Text(entry.key.split('|').last)),
                DataCell(Text('${entry.value['إضافة'] ?? 0}')),
                DataCell(Text('${entry.value['حذف'] ?? 0}')),
                DataCell(Text('${entry.value['تعديل'] ?? 0}')),
                DataCell(Text('${entry.value.values.fold<int>(0, (a, b) => a + b)}')),
              ],
            ),
        ],
      ),
    );
  }
}

/// جدول "عدد الحالات لدى كل مرشد" مع فلترة بالشطر/القسم - مختلف عن
/// _TeamPerformanceSection (الذي يبرز نسبة الإنجاز والتقصير) بأنه يركّز على
/// **العدد الخام** بشكل جدولي قابل للفلترة، وهو ما طلبه سليمان تحديدًا.
class _AdvisorCaseCountTable extends StatefulWidget {
  final List<AdvisorCaseStats> advisors;

  const _AdvisorCaseCountTable({required this.advisors});

  @override
  State<_AdvisorCaseCountTable> createState() => _AdvisorCaseCountTableState();
}

class _AdvisorCaseCountTableState extends State<_AdvisorCaseCountTable> {
  String? _shatr;
  String? _department;

  @override
  Widget build(BuildContext context) {
    if (widget.advisors.isEmpty) {
      return Text('لا توجد بيانات كافية', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    }

    final filtered = widget.advisors.where((a) {
      if (_shatr != null && a.shatr != _shatr) return false;
      if (_department != null && a.department != _department) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            DropdownMenu<String?>(
              label: const Text('الشطر'),
              initialSelection: _shatr,
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'كل الشطور'),
                ...[ExcelParserService.shatrMale, ExcelParserService.shatrFemale]
                    .map((s) => DropdownMenuEntry(value: s, label: s)),
              ],
              onSelected: (v) => setState(() => _shatr = v),
            ),
            DropdownMenu<String?>(
              label: const Text('القسم'),
              initialSelection: _department,
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'كل الأقسام'),
                ...ExcelParserService.departments.map((d) => DropdownMenuEntry(value: d, label: d)),
              ],
              onSelected: (v) => setState(() => _department = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Text('لا توجد حالات لهذا الاختيار', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.background),
              columns: const [
                DataColumn(label: Text('المرشد')),
                DataColumn(label: Text('القسم')),
                DataColumn(label: Text('الشطر')),
                DataColumn(label: Text('عدد الحالات')),
                DataColumn(label: Text('المنجزة')),
                DataColumn(label: Text('محوَّلة لمنسّق القسم')),
                DataColumn(label: Text('لم يُعمَل عليها')),
              ],
              rows: [
                for (final a in filtered)
                  DataRow(
                    cells: [
                      DataCell(Text(a.advisorName)),
                      DataCell(Text(a.department)),
                      DataCell(Text(a.shatr)),
                      DataCell(Text('${a.total}')),
                      DataCell(Text(
                        '${a.completed}',
                        style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                      )),
                      DataCell(Text(
                        '${a.escalatedToCoordinator}',
                        style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                      )),
                      DataCell(Text(
                        '${a.notStarted}',
                        style: const TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold),
                      )),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// أداء الفريق كاملاً: كل مرشد (حسب قسمه وشطره)، كل منسّق قسم، ومنسّقو
/// الكلية - بلا سقف عدد ولا حاجة لاختيار فلتر مسبقًا (بخلاف _AdvisorBars
/// بـFollowUpChart المصمَّمة لعرض سريع مختصر). يعتمد على دوال الترتيب
/// الجاهزة أصلاً بـReportDataService (rankedAdvisors/rankedCoordinators/
/// rankedCollegeCoordinators) لتفادي إعادة حساب نفس المنطق.
class _TeamPerformanceSection extends StatelessWidget {
  final ReportData reportData;

  const _TeamPerformanceSection({required this.reportData});

  @override
  Widget build(BuildContext context) {
    final advisors = ReportDataService.rankedAdvisors(reportData);
    final coordinators = ReportDataService.rankedCoordinators(reportData);
    final college = ReportDataService.rankedCollegeCoordinators(reportData);

    if (advisors.isEmpty && coordinators.isEmpty && college.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_2_outlined, color: AppColors.greenDark),
            const SizedBox(width: 8),
            const Text(
              'أداء الفريق: المرشدون ومنسّقو الأقسام والكلية',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.greenDark),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'مرتَّب من الأقل إنجازًا للأعلى، ليظهر فورًا من يحتاج متابعة',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        if (advisors.isNotEmpty)
          _TeamGroup(title: 'المرشدون الأكاديميون', icon: Icons.person_outline, rows: advisors),
        if (coordinators.isNotEmpty) ...[
          const SizedBox(height: 18),
          _TeamGroup(title: 'منسّقو الأقسام', icon: Icons.supervisor_account_outlined, rows: coordinators),
        ],
        if (college.isNotEmpty) ...[
          const SizedBox(height: 18),
          _TeamGroup(title: 'منسّقو الكلية', icon: Icons.apartment_outlined, rows: college),
        ],
      ],
    );
  }
}

class _TeamGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<AdvisorProgress> rows;

  const _TeamGroup({required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              '$title (${rows.length})',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  color: i.isEven ? Colors.white : AppColors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: _TeamRow(row: rows[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  final AdvisorProgress row;

  const _TeamRow({required this.row});

  Color get _rateColor {
    if (row.status == AdvisorProgressStatus.complete) return const Color(0xFF2E7D32);
    if (row.status == AdvisorProgressStatus.inProgress) return AppColors.gold;
    return AppColors.errorRed;
  }

  @override
  Widget build(BuildContext context) {
    final rate = row.counts.completionRate;
    final label = row.department.isEmpty
        ? row.advisorName
        : '${row.advisorName} · ${row.department} · ${row.shatr}';

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: rate,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(_rateColor),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(
            '${row.counts.completed}/${row.counts.total} (${(rate * 100).round()}%)',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _rateColor),
            textAlign: TextAlign.left,
          ),
        ),
      ],
    );
  }
}
