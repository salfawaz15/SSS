import 'package:flutter/material.dart';

import '../services/excel_parser_service.dart';
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

  const TicketActionStatsPanel({super.key, required this.tickets});

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
            child: Row(
              children: [
                Expanded(flex: completed, child: Container(color: const Color(0xFF2E7D32))),
                Expanded(flex: partial, child: Container(color: AppColors.gold)),
                Expanded(flex: notStarted, child: Container(color: Colors.grey.shade300)),
                if (completed == 0 && partial == 0 && notStarted == 0)
                  Expanded(flex: total, child: Container(color: Colors.grey.shade200)),
              ],
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
