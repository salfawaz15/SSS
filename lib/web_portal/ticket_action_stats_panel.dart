import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/excel_parser_service.dart';
import '../services/report_data_service.dart';
import '../services/ticket_action_stats_service.dart';

/// نظام ألوان/مقاسات هذه اللوحة تحديدًا (Compact Executive Dashboard) -
/// معتمَد من سليمان بعد مراجعة تصميم كامل مُفصَّل: أخضر مؤسسي داكن كأساسي،
/// ذهبي كـAccent فقط (لا يُستخدم بمساحات كبيرة)، بلا دوائر ضخمة ولا ظلال
/// قوية. مختلف عمدًا عن AppColors العامة بالموقع (درجات أدق لهذه اللوحة).
class _Tokens {
  static const green950 = Color(0xFF0B3B2E);
  static const green900 = Color(0xFF104836);
  static const green800 = Color(0xFF175B43);

  static const gold600 = Color(0xFFC79A2B);
  static const gold500 = Color(0xFFD5AA3B);

  static const success = Color(0xFF378542);
  static const successSoft = Color(0xFFEDF7EF);
  static const danger = Color(0xFFC2392F);
  static const dangerSoft = Color(0xFFFBEDEC);
  static const warning = Color(0xFFC79A2B);
  static const warningSoft = Color(0xFFFBF5E5);

  static const pageBg = Color(0xFFF4F7F5);
  static const cardBg = Colors.white;

  static const textPrimary = Color(0xFF17352B);
  static const textSecondary = Color(0xFF66746F);
  static const textMuted = Color(0xFF8A9691);

  static const border = Color(0xFFE4EAE7);
  static const track = Color(0xFFEDF0EE);

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: green950.withValues(alpha: 0.03), blurRadius: 5, offset: const Offset(0, 2)),
        BoxShadow(color: green950.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8)),
      ];
}

/// عرض قصير لقيمة الشطر المخزَّنة (مطابقة لـExcelParserService.shatrMale/
/// Female حرفيًا للفلترة) - "شطر الطلاب" تُعرَض "الطلاب" فقط، لأن عنوان
/// الحقل نفسه "الشطر" يغني عن تكرار الكلمة (ملاحظة لغوية من سليمان).
String _shatrShortLabel(String value) {
  if (value == ExcelParserService.shatrMale) return 'الطلاب';
  if (value == ExcelParserService.shatrFemale) return 'الطالبات';
  return value;
}

/// عرض اسم القسم بلا بادئة "قسم" (القيمة المخزَّنة تبقى كما هي للفلترة
/// والمطابقة، هذا للعرض فقط) - عنوان العمود/الحقل "القسم" يغني عن التكرار.
String _deptShortLabel(String value) => value.replaceFirst('قسم ', '');

/// لوحة إحصائيات طلبات الحذف/الإضافة/تعديل الشعب - Compact Executive
/// Dashboard معتمَدة من سليمان بمواصفات UI/UX مفصَّلة (2026-08-19): بلا
/// دوائر ضخمة، كثافة معلومات عالية بصفحة واحدة بلا تمرير طويل، ألوان
/// مؤسسية هادئة. المنطق/البيانات كما هي تمامًا (TicketActionStatsService/
/// ReportDataService) - هذا تصميم واجهة فقط.
class TicketActionStatsPanel extends StatefulWidget {
  final List<Map<String, dynamic>> tickets;

  const TicketActionStatsPanel({super.key, required this.tickets});

  @override
  State<TicketActionStatsPanel> createState() => _TicketActionStatsPanelState();
}

class _TicketActionStatsPanelState extends State<TicketActionStatsPanel> {
  String? _shatr;
  String? _department;

  static const _actionColors = {
    'إضافة': _Tokens.success,
    'حذف': _Tokens.danger,
    'تعديل': _Tokens.warning,
  };

  static const _actionIcons = {
    'إضافة': Icons.add_circle_outline,
    'حذف': Icons.remove_circle_outline,
    'تعديل': Icons.sync_alt_outlined,
  };

  bool get _hasFilters => _shatr != null || _department != null;

  @override
  Widget build(BuildContext context) {
    if (widget.tickets.isEmpty) return const SizedBox.shrink();

    final tickets = widget.tickets.where((t) {
      if (_shatr != null && (t['shatr'] ?? '') != _shatr) return false;
      if (_department != null && (t['department'] ?? '') != _department) return false;
      return true;
    }).toList();

    final reportData = ReportDataService.build(tickets);
    final stats = TicketActionStatsService.build(tickets);
    final advisorStats = TicketActionStatsService.buildAdvisorCaseStats(tickets);
    final bestAdvisors = [...advisorStats]
      ..sort((a, b) {
        final rateA = a.total == 0 ? 0.0 : a.completed / a.total;
        final rateB = b.total == 0 ? 0.0 : b.completed / b.total;
        return rateB.compareTo(rateA);
      });

    return Container(
      margin: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          const SizedBox(height: 12),
          if (stats.totalActions == 0)
            _EmptyState(onReset: () => setState(() {
              _shatr = null;
              _department = null;
            }))
          else ...[
            _buildKpiRow(stats, reportData),
            const SizedBox(height: 12),
            _buildStatusCard(stats),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                final bestCard = _CardShell(
                  title: 'أفضل 5 مرشدين إنجازًا',
                  subtitle: 'حسب نسبة الطلبات المكتملة',
                  icon: Icons.emoji_events_outlined,
                  child: _BestAdvisorsTable(advisors: bestAdvisors.take(5).toList()),
                );
                final deptCard = _CardShell(
                  title: 'توزيع الحالات حسب القسم',
                  icon: Icons.donut_small_outlined,
                  child: _DepartmentTable(stats: stats),
                );
                if (isNarrow) {
                  return Column(children: [bestCard, const SizedBox(height: 12), deptCard]);
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 155, child: bestCard),
                      const SizedBox(width: 12),
                      Expanded(flex: 100, child: deptCard),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _TeamPerformanceSection(reportData: reportData),
            _AdvisorFullTable(advisors: advisorStats),
            if (stats.advisorMismatchCount > 0) ...[
              const SizedBox(height: 14),
              _MismatchAlert(count: stats.advisorMismatchCount),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            const Icon(Icons.query_stats_outlined, size: 19, color: _Tokens.green900),
            const SizedBox(width: 7),
            const Text(
              'إحصائيات طلبات الحذف والإضافة',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _Tokens.textPrimary),
            ),
          ],
        ),
        const Spacer(),
        _FilterField(
          label: 'الشطر',
          value: _shatr,
          items: [ExcelParserService.shatrMale, ExcelParserService.shatrFemale],
          itemLabel: _shatrShortLabel,
          onChanged: (v) => setState(() => _shatr = v),
        ),
        const SizedBox(width: 10),
        _FilterField(
          label: 'القسم',
          value: _department,
          items: ExcelParserService.departments,
          itemLabel: _deptShortLabel,
          onChanged: (v) => setState(() => _department = v),
        ),
        if (_hasFilters) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: TextButton.icon(
              onPressed: () => setState(() {
                _shatr = null;
                _department = null;
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة ضبط الفلاتر'),
              style: TextButton.styleFrom(foregroundColor: _Tokens.textSecondary, textStyle: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiRow(TicketActionStats stats, ReportData reportData) {
    final overallRate = reportData.overall.total == 0 ? 0.0 : reportData.overall.completed / reportData.overall.total;
    final cards = [
      _KpiCard(
        label: 'إجمالي الحالات',
        value: '${stats.totalTickets}',
        note: 'طلبًا مسجلًا',
        icon: Icons.folder_outlined,
        accent: _Tokens.green900,
      ),
      _KpiCard(
        label: 'نسبة الإنجاز العامة',
        value: '${(overallRate * 100).round()}%',
        note: 'من إجمالي الطلبات',
        icon: Icons.track_changes_outlined,
        accent: _Tokens.success,
      ),
      for (final type in ['إضافة', 'حذف', 'تعديل'])
        if (stats.byActionType.containsKey(type))
          _KpiCard(
            label: 'طلبات $type',
            value: '${stats.byActionType[type]!.total}',
            note: 'طلبًا',
            icon: _actionIcons[type]!,
            accent: _actionColors[type]!,
          ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 480
            ? 1
            : constraints.maxWidth < 768
                ? 2
                : constraints.maxWidth < 1200
                    ? 3
                    : 5;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in cards)
              SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns, child: c),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(TicketActionStats stats) {
    final types = ['إضافة', 'حذف', 'تعديل'].where(stats.byActionType.containsKey).toList();
    var totalCompleted = 0, totalProgress = 0, totalNotStarted = 0;
    for (final t in types) {
      final c = stats.byActionType[t]!.statusCounts;
      totalCompleted += c.completed;
      totalProgress += c.partial;
      totalNotStarted += c.notDone + c.blank;
    }

    return _CardShell(
      title: 'حالة إنجاز معالجة الطلبات',
      subtitle: 'متابعة حالة الطلبات حسب نوع الإجراء',
      icon: Icons.donut_large_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 640;
              if (isNarrow) {
                return Column(
                  children: [
                    for (var i = 0; i < types.length; i++) ...[
                      _StatusGauge(label: 'طلبات ${types[i]}', stats: stats.byActionType[types[i]]!),
                      if (i < types.length - 1) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < types.length; i++) ...[
                    Expanded(child: _StatusGauge(label: 'طلبات ${types[i]}', stats: stats.byActionType[types[i]]!)),
                    if (i < types.length - 1)
                      Container(width: 1, height: 78, color: _Tokens.border, margin: const EdgeInsets.symmetric(horizontal: 6)),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAF9),
              border: Border.all(color: _Tokens.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: 22,
              runSpacing: 6,
              children: [
                _summaryItem('مكتمل', totalCompleted, _Tokens.success),
                _summaryItem('قيد التنفيذ', totalProgress, _Tokens.warning),
                _summaryItem('لم يبدأ', totalNotStarted, _Tokens.danger),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: _Tokens.textSecondary)),
        const SizedBox(width: 6),
        Text('$value', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _FilterField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final String Function(String) itemLabel;
  final ValueChanged<String?> onChanged;

  const _FilterField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _Tokens.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _Tokens.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isDense: true,
              icon: const Icon(Icons.expand_more_rounded, size: 18, color: _Tokens.textSecondary),
              style: const TextStyle(fontSize: 12.5, color: _Tokens.textPrimary, fontWeight: FontWeight.w500),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(9),
              items: [
                const DropdownMenuItem(value: null, child: Padding(padding: EdgeInsets.only(right: 6), child: Text('الكل'))),
                for (final item in items)
                  DropdownMenuItem(value: item, child: Padding(padding: const EdgeInsets.only(right: 6), child: Text(itemLabel(item)))),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color accent;

  const _KpiCard({required this.label, required this.value, required this.note, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      decoration: BoxDecoration(
        color: _Tokens.cardBg,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(_Tokens.radiusLg),
        boxShadow: _Tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(top: 0, right: 16, left: 16, child: Container(height: 3, decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4))))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 11.5, color: _Tokens.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _Tokens.textPrimary, height: 1)),
                      const SizedBox(height: 4),
                      Text(note, style: const TextStyle(fontSize: 10, color: _Tokens.textMuted)),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  const _CardShell({required this.title, this.subtitle, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _Tokens.cardBg,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(_Tokens.radiusLg),
        boxShadow: _Tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: _Tokens.gold500),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _Tokens.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: const TextStyle(fontSize: 10, color: _Tokens.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusGauge extends StatelessWidget {
  final String label;
  final ActionTypeStats stats;

  const _StatusGauge({required this.label, required this.stats});

  @override
  Widget build(BuildContext context) {
    final c = stats.statusCounts;
    final completed = c.completed;
    final progress = c.partial;
    final notStarted = c.notDone + c.blank;
    final total = c.total == 0 ? 1 : c.total;
    final pct = ((completed / total) * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _Tokens.textPrimary)),
          const SizedBox(height: 8),
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 32,
                    sections: [
                      if (completed > 0) PieChartSectionData(value: completed.toDouble(), color: _Tokens.success, showTitle: false, radius: 14),
                      if (progress > 0) PieChartSectionData(value: progress.toDouble(), color: _Tokens.warning, showTitle: false, radius: 14),
                      if (notStarted > 0) PieChartSectionData(value: notStarted.toDouble(), color: _Tokens.danger, showTitle: false, radius: 14),
                      if (completed == 0 && progress == 0 && notStarted == 0)
                        PieChartSectionData(value: 1, color: _Tokens.track, showTitle: false, radius: 14),
                    ],
                  ),
                ),
                Text('$pct%', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _Tokens.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _legendLine('مكتمل', completed, _Tokens.success),
          const SizedBox(height: 3),
          _legendLine('قيد التنفيذ', progress, _Tokens.warning),
          const SizedBox(height: 3),
          _legendLine('لم يبدأ', notStarted, _Tokens.danger),
        ],
      ),
    );
  }

  Widget _legendLine(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ', style: const TextStyle(fontSize: 10.5, color: _Tokens.textSecondary)),
        Text('$value', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _BestAdvisorsTable extends StatelessWidget {
  final List<AdvisorCaseStats> advisors;

  const _BestAdvisorsTable({required this.advisors});

  static Color _rateColor(double rate) {
    if (rate <= 0.5) return Color.lerp(_Tokens.danger, _Tokens.warning, (rate / 0.5).clamp(0.0, 1.0))!;
    return Color.lerp(_Tokens.warning, _Tokens.success, ((rate - 0.5) / 0.5).clamp(0.0, 1.0))!;
  }

  @override
  Widget build(BuildContext context) {
    if (advisors.isEmpty) {
      return const Text('لا توجد بيانات كافية', style: TextStyle(fontSize: 12, color: _Tokens.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _th('الاسم', 24),
            _th('القسم', 15),
            _th('الشطر', 9),
            _th('عدد الحالات', 10),
            _th('نسبة الإنجاز', 18),
          ],
        ),
        const Divider(height: 14, color: _Tokens.border),
        for (var i = 0; i < advisors.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == advisors.length - 1 ? 0 : 9),
            child: _AdvisorRow(advisor: advisors[i], isFirst: i == 0, rateColorOf: _rateColor),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: null,
            style: TextButton.styleFrom(foregroundColor: _Tokens.gold600, padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            child: const Text('عرض جميع المرشدين ←'),
          ),
        ),
      ],
    );
  }

  Widget _th(String text, int flex) => Expanded(flex: flex, child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _Tokens.textMuted)));
}

class _AdvisorRow extends StatelessWidget {
  final AdvisorCaseStats advisor;
  final bool isFirst;
  final Color Function(double) rateColorOf;

  const _AdvisorRow({required this.advisor, required this.isFirst, required this.rateColorOf});

  @override
  Widget build(BuildContext context) {
    final rate = advisor.total == 0 ? 0.0 : advisor.completed / advisor.total;
    final color = rateColorOf(rate);
    return Row(
      children: [
        Expanded(
          flex: 24,
          child: Row(
            children: [
              if (isFirst) ...[const Icon(Icons.star_rounded, size: 14, color: _Tokens.gold500), const SizedBox(width: 4)],
              Flexible(child: Text(advisor.advisorName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Tokens.textPrimary), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        Expanded(flex: 15, child: Text(_deptShortLabel(advisor.department), style: const TextStyle(fontSize: 11.5, color: _Tokens.textSecondary), overflow: TextOverflow.ellipsis)),
        Expanded(flex: 9, child: Text(_shatrShortLabel(advisor.shatr), style: const TextStyle(fontSize: 11.5, color: _Tokens.textSecondary))),
        Expanded(flex: 10, child: Text('${advisor.total}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _Tokens.textPrimary))),
        Expanded(
          flex: 18,
          child: Row(
            children: [
              SizedBox(width: 30, child: Text('${(rate * 100).round()}%', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color))),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(height: 5, child: LinearProgressIndicator(value: rate, backgroundColor: _Tokens.track, valueColor: AlwaysStoppedAnimation(color))),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DepartmentTable extends StatelessWidget {
  final TicketActionStats stats;

  const _DepartmentTable({required this.stats});

  int _count(String dept, String shatr, String type) => stats.byDepartmentShatr['$shatr|$dept']?[type] ?? 0;

  @override
  Widget build(BuildContext context) {
    if (stats.byDepartmentShatr.isEmpty) {
      return const Text('لا توجد بيانات كافية', style: TextStyle(fontSize: 12, color: _Tokens.textMuted));
    }

    Widget group(String label, Color color) => Expanded(
          flex: 2,
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        );
    Widget sub(String label) => Expanded(flex: 1, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: _Tokens.textMuted)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [const Expanded(flex: 3, child: SizedBox()), group('إضافة', _Tokens.success), group('حذف', _Tokens.danger), group('تعديل', _Tokens.warning)]),
        Row(children: [const Expanded(flex: 3, child: SizedBox()), sub('طلاب'), sub('طالبات'), sub('طلاب'), sub('طالبات'), sub('طلاب'), sub('طالبات')]),
        const Divider(height: 12, color: _Tokens.border),
        for (final dept in ExcelParserService.departments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(_deptShortLabel(dept), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Tokens.textPrimary), maxLines: 2)),
                _cell(_count(dept, ExcelParserService.shatrMale, 'إضافة'), _Tokens.success),
                _cell(_count(dept, ExcelParserService.shatrFemale, 'إضافة'), _Tokens.success),
                _cell(_count(dept, ExcelParserService.shatrMale, 'حذف'), _Tokens.danger),
                _cell(_count(dept, ExcelParserService.shatrFemale, 'حذف'), _Tokens.danger),
                _cell(_count(dept, ExcelParserService.shatrMale, 'تعديل'), _Tokens.warning),
                _cell(_count(dept, ExcelParserService.shatrFemale, 'تعديل'), _Tokens.warning),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int value, Color color) => Expanded(flex: 1, child: Text('$value', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)));
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onReset;

  const _EmptyState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _Tokens.cardBg,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(_Tokens.radiusLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 30, color: _Tokens.textMuted),
          const SizedBox(height: 10),
          const Text('لا توجد بيانات مطابقة للفلاتر المحددة', style: TextStyle(fontSize: 13, color: _Tokens.textSecondary)),
          const SizedBox(height: 10),
          TextButton(onPressed: onReset, child: const Text('إعادة ضبط الفلاتر')),
        ],
      ),
    );
  }
}

class _MismatchAlert extends StatelessWidget {
  final int count;

  const _MismatchAlert({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: _Tokens.dangerSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: _Tokens.danger.withValues(alpha: 0.2))),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: _Tokens.danger, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'تنبيه بيانات (ليس مؤشر إنجاز): $count حالة اختار فيها الطالب مرشدًا غير مرشده الفعلي بالنموذج - صُحِّحت تلقائيًا واعتُمد المرشد الصحيح لتوجيه الطلب.',
              style: const TextStyle(fontSize: 12, color: _Tokens.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// جدول "عدد الحالات لدى كل مرشد" الكامل (منجزة/محوَّلة/لم يُعمل عليها) -
/// يبقى بلا فلترة خاصة به لأن فلترة اللوحة العلوية تنطبق عليه أصلاً.
class _AdvisorFullTable extends StatelessWidget {
  final List<AdvisorCaseStats> advisors;

  const _AdvisorFullTable({required this.advisors});

  @override
  Widget build(BuildContext context) {
    final sorted = [...advisors]..sort((a, b) => b.total.compareTo(a.total));
    if (sorted.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: _CardShell(
        title: 'عدد الحالات لدى كل مرشد',
        icon: Icons.groups_2_outlined,
        child: Center(
          child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 40,
            headingRowColor: WidgetStateProperty.all(_Tokens.pageBg),
            columns: const [
              DataColumn(label: Text('المرشد', style: TextStyle(fontSize: 11.5))),
              DataColumn(label: Text('القسم', style: TextStyle(fontSize: 11.5))),
              DataColumn(label: Text('الشطر', style: TextStyle(fontSize: 11.5))),
              DataColumn(label: Text('عدد الحالات', style: TextStyle(fontSize: 11.5))),
              DataColumn(label: Text('المنجزة', style: TextStyle(fontSize: 11.5))),
              DataColumn(label: Text('محوَّلة لمنسّق القسم', style: TextStyle(fontSize: 11.5))),
              DataColumn(label: Text('لم يُعمَل عليها', style: TextStyle(fontSize: 11.5))),
            ],
            rows: [
              for (final a in sorted)
                DataRow(cells: [
                  DataCell(Text(a.advisorName, style: const TextStyle(fontSize: 12))),
                  DataCell(Text(_deptShortLabel(a.department), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(_shatrShortLabel(a.shatr), style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${a.total}', style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${a.completed}', style: const TextStyle(color: _Tokens.success, fontWeight: FontWeight.w700, fontSize: 12))),
                  DataCell(Text('${a.escalatedToCoordinator}', style: const TextStyle(color: _Tokens.warning, fontWeight: FontWeight.w700, fontSize: 12))),
                  DataCell(Text('${a.notStarted}', style: const TextStyle(color: _Tokens.danger, fontWeight: FontWeight.w700, fontSize: 12))),
                ]),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// أداء الفريق كاملاً (مرشدون/منسّقو أقسام/منسّقو كلية) - يبقى أسفل الصفحة
/// (بعد الشاشة الأولى) بلا تغيير جوهري بالمنطق، مقاسات مضغوطة فقط.
class _TeamPerformanceSection extends StatelessWidget {
  final ReportData reportData;

  const _TeamPerformanceSection({required this.reportData});

  @override
  Widget build(BuildContext context) {
    final advisors = ReportDataService.rankedAdvisors(reportData);
    final coordinators = ReportDataService.rankedCoordinators(reportData);
    final college = ReportDataService.rankedCollegeCoordinators(reportData);
    if (advisors.isEmpty && coordinators.isEmpty && college.isEmpty) return const SizedBox.shrink();

    return _CardShell(
      title: 'أداء الفريق: المرشدون ومنسّقو الأقسام والكلية',
      subtitle: 'مرتَّب من الأقل إنجازًا للأعلى، ليظهر فورًا من يحتاج متابعة',
      icon: Icons.groups_2_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (advisors.isNotEmpty) _TeamGroup(title: 'المرشدون الأكاديميون', icon: Icons.person_outline, rows: advisors),
          if (coordinators.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TeamGroup(title: 'منسّقو الأقسام', icon: Icons.supervisor_account_outlined, rows: coordinators),
          ],
          if (college.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TeamGroup(title: 'منسّقو الكلية', icon: Icons.apartment_outlined, rows: college),
          ],
        ],
      ),
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
            Icon(icon, size: 14, color: _Tokens.textSecondary),
            const SizedBox(width: 6),
            Text('$title (${rows.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _Tokens.textSecondary)),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(border: Border.all(color: _Tokens.border), borderRadius: BorderRadius.circular(9)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  color: i.isEven ? Colors.white : _Tokens.pageBg,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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
    if (row.status == AdvisorProgressStatus.complete) return _Tokens.success;
    if (row.status == AdvisorProgressStatus.inProgress) return _Tokens.warning;
    return _Tokens.danger;
  }

  @override
  Widget build(BuildContext context) {
    final rate = row.counts.completionRate;
    final label = row.department.isEmpty ? row.advisorName : '${row.advisorName} · ${_deptShortLabel(row.department)} · ${_shatrShortLabel(row.shatr)}';

    return Row(
      children: [
        Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 11.5, color: _Tokens.textPrimary), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(height: 6, child: LinearProgressIndicator(value: rate, backgroundColor: _Tokens.track, valueColor: AlwaysStoppedAnimation(_rateColor))),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 84,
          child: Text('${row.counts.completed}/${row.counts.total} (${(rate * 100).round()}%)', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _rateColor)),
        ),
      ],
    );
  }
}
