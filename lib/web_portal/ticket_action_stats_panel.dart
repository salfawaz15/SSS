import 'package:flutter/material.dart';

import '../services/excel_parser_service.dart';
import '../services/ticket_action_stats_service.dart';
import '../theme/app_theme.dart';
import 'portal_cards.dart';

/// لوحة إحصائيات طلبات الحذف/الإضافة/تعديل الشعب - مختلفة تمامًا عن
/// [FollowUpChart] (المخصَّص لمتابعة إنجاز الإرشاد): هذه تُجيب عن "كم طلب من
/// كل نوع؟ في أي قسم؟ وكم حالة كان المرشد المختار فيها خطأً؟" لا عن حالة
/// إنجاز المرشدين. تظهر تلقائيًا أسفل لوحة متابعة الإنجاز بلوحة الإدارة.
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
                  icon: Icons.warning_amber_rounded,
                  value: '${stats.advisorMismatchCount}',
                  label: 'مرشد مختار خطأً (صُحِّح تلقائيًا)',
                  accentColor: AppColors.errorRed,
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
            'توزيع الطلبات حسب القسم والشطر',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.greenDark),
          ),
          const SizedBox(height: 10),
          _DepartmentBreakdownTable(stats: stats),
        ],
      ),
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
