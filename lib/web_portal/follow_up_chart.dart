import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/advisor_roster_entry.dart';
import '../services/excel_parser_service.dart';
import '../services/report_data_service.dart';
import '../theme/app_theme.dart';

/// رسم بياني تفاعلي لتقرير متابعة الإنجاز - يظهر تلقائيًا (لا يحتاج ضغط أي
/// زر) مثل لوحة تحكم Power BI: مخطط دائري لتوزيع حالة كل المرشدين (إحصائية
/// إجمالية تشمل كل الأقسام، تبقى ثابتة بصرف النظر عن الفلترة)، ثم عند توفر
/// [tickets] (لوحة الإدارة/منسّق الكلية التي تغطي أكثر من قسم) قائمتا تصفية
/// (الشطر/القسم) يجب اختيار إحداهما على الأقل قبل ظهور ترتيب المرشدين -
/// بدل عرض قائمة طويلة مختلطة من كل الأقسام دفعة واحدة.
class FollowUpChart extends StatefulWidget {
  final ReportData data;
  final List<Map<String, dynamic>>? tickets;
  final List<AdvisorRosterEntry>? roster;
  final bool showShatrFilter;
  final bool showDepartmentFilter;
  // منسّق القسم لا يرى أداء منسّقي الكلية (مستوى أعلى منه) - يُعطَّل فقط في
  // شاشة منسّق القسم؛ الإدارة ومنسّق الكلية يريان كل المستويات كالمعتاد.
  final bool showCollegePerformance;

  const FollowUpChart({
    super.key,
    required this.data,
    this.tickets,
    this.roster,
    this.showShatrFilter = false,
    this.showDepartmentFilter = false,
    this.showCollegePerformance = true,
  });

  @override
  State<FollowUpChart> createState() => _FollowUpChartState();
}

class _FollowUpChartState extends State<FollowUpChart> {
  String? _shatr;
  String? _department;

  bool get _hasFilters => widget.showShatrFilter || widget.showDepartmentFilter;

  @override
  Widget build(BuildContext context) {
    final overallRanked = ReportDataService.rankedAdvisors(widget.data);
    if (overallRanked.isEmpty) {
      return const SizedBox.shrink();
    }

    final notStarted = overallRanked.where((a) => a.status == AdvisorProgressStatus.notStarted).length;
    final inProgress = overallRanked.where((a) => a.status == AdvisorProgressStatus.inProgress).length;
    final complete = overallRanked.where((a) => a.status == AdvisorProgressStatus.complete).length;

    final filterSelected = (!widget.showShatrFilter || _shatr != null) &&
        (!widget.showDepartmentFilter || _department != null);

    final overallRankedCoordinators = ReportDataService.rankedCoordinators(widget.data);
    final overallRankedCollege = widget.showCollegePerformance
        ? ReportDataService.rankedCollegeCoordinators(widget.data)
        : <AdvisorProgress>[];

    Widget bars;
    Widget? filteredPie;
    List<AdvisorProgress> coordinatorRanked = overallRankedCoordinators;
    List<AdvisorProgress> collegeRanked = overallRankedCollege;
    if (!_hasFilters) {
      bars = _AdvisorBars(ranked: overallRanked, cap: 10);
    } else if (!filterSelected) {
      bars = _FilterPrompt(showShatr: widget.showShatrFilter, showDepartment: widget.showDepartmentFilter);
      coordinatorRanked = [];
      collegeRanked = [];
    } else {
      final filteredTickets = (widget.tickets ?? []).where((t) {
        if (_shatr != null && (t['shatr'] ?? '') != _shatr) return false;
        if (_department != null && (t['department'] ?? '') != _department) return false;
        return true;
      }).toList();
      final filteredData = ReportDataService.build(filteredTickets, roster: widget.roster);
      final filteredRanked = ReportDataService.rankedAdvisors(filteredData);
      bars = filteredRanked.isEmpty
          ? Text('لا توجد حالات لهذا الاختيار', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
          : _AdvisorBars(ranked: filteredRanked, cap: 20);
      coordinatorRanked = ReportDataService.rankedCoordinators(filteredData);
      collegeRanked = widget.showCollegePerformance
          ? ReportDataService.rankedCollegeCoordinators(filteredData)
          : [];

      final fNotStarted = filteredRanked.where((a) => a.status == AdvisorProgressStatus.notStarted).length;
      final fInProgress = filteredRanked.where((a) => a.status == AdvisorProgressStatus.inProgress).length;
      final fComplete = filteredRanked.where((a) => a.status == AdvisorProgressStatus.complete).length;
      filteredPie = _StatusPie(notStarted: fNotStarted, inProgress: fInProgress, complete: fComplete);
    }

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
              const Icon(Icons.insights_outlined, color: AppColors.greenDark),
              const SizedBox(width: 8),
              const Text(
                'لوحة متابعة الإنجاز',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark),
              ),
            ],
          ),
          if (_hasFilters) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (widget.showShatrFilter)
                  DropdownMenu<String>(
                    label: const Text('الشطر'),
                    initialSelection: _shatr,
                    dropdownMenuEntries: [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]
                        .map((s) => DropdownMenuEntry(value: s, label: s))
                        .toList(),
                    onSelected: (v) => setState(() => _shatr = v),
                  ),
                if (widget.showDepartmentFilter)
                  DropdownMenu<String>(
                    label: const Text('القسم'),
                    initialSelection: _department,
                    dropdownMenuEntries: ExcelParserService.departments
                        .map((d) => DropdownMenuEntry(value: d, label: d))
                        .toList(),
                    onSelected: (v) => setState(() => _department = v),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
          ],
          const SizedBox(height: 14),
          if (filteredPie == null)
            _StatusPie(notStarted: notStarted, inProgress: inProgress, complete: complete)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                final overallPie = Column(
                  children: [
                    const Text('الإجمالي (كل الأقسام)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 8),
                    _StatusPie(notStarted: notStarted, inProgress: inProgress, complete: complete),
                  ],
                );
                final selectedPie = Column(
                  children: [
                    Text(
                      'حسب الفلترة الحالية',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.greenDark),
                    ),
                    const SizedBox(height: 8),
                    filteredPie!,
                  ],
                );
                if (narrow) {
                  return Column(children: [overallPie, const SizedBox(height: 20), selectedPie]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: overallPie),
                    const SizedBox(width: 16),
                    Expanded(child: selectedPie),
                  ],
                );
              },
            ),
          const SizedBox(height: 18),
          bars,
          if (coordinatorRanked.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 18),
            _AdvisorBars(
              ranked: coordinatorRanked,
              cap: 10,
              title: 'نسبة إنجاز منسقي الأقسام (الأقل إنجازًا أولًا)',
              moreLabel: 'قسمًا آخر',
            ),
          ],
          if (collegeRanked.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 18),
            _AdvisorBars(
              ranked: collegeRanked,
              cap: 10,
              title: 'نسبة إنجاز منسقي الكلية (الأقل إنجازًا أولًا)',
              moreLabel: 'شطرًا آخر',
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterPrompt extends StatelessWidget {
  final bool showShatr;
  final bool showDepartment;

  const _FilterPrompt({required this.showShatr, required this.showDepartment});

  @override
  Widget build(BuildContext context) {
    final what = showShatr && showDepartment
        ? 'الشطر والقسم'
        : showShatr
            ? 'الشطر'
            : 'القسم';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'اختر $what أعلاه لعرض ترتيب إنجاز المرشدين',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPie extends StatelessWidget {
  final int notStarted;
  final int inProgress;
  final int complete;

  const _StatusPie({required this.notStarted, required this.inProgress, required this.complete});

  static const _redColor = Color(0xFFD9534F);
  static const _goldColor = AppColors.gold;
  static const _greenColor = AppColors.green;

  @override
  Widget build(BuildContext context) {
    final total = notStarted + inProgress + complete;
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              sections: [
                if (notStarted > 0)
                  PieChartSectionData(
                    value: notStarted.toDouble(),
                    color: _redColor,
                    title: '$notStarted',
                    radius: 46,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                if (inProgress > 0)
                  PieChartSectionData(
                    value: inProgress.toDouble(),
                    color: _goldColor,
                    title: '$inProgress',
                    radius: 46,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                if (complete > 0)
                  PieChartSectionData(
                    value: complete.toDouble(),
                    color: _greenColor,
                    title: '$complete',
                    radius: 46,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _legendDot(_redColor, 'لم يبدأ ($notStarted)'),
            _legendDot(_goldColor, 'قيد التنفيذ ($inProgress)'),
            _legendDot(_greenColor, 'مكتمل ($complete)'),
          ],
        ),
        const SizedBox(height: 8),
        Text('إجمالي المرشدين: $total', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _AdvisorBars extends StatelessWidget {
  final List<AdvisorProgress> ranked;
  final int cap;
  final String title;
  final String moreLabel;

  const _AdvisorBars({
    required this.ranked,
    required this.cap,
    this.title = 'نسبة إنجاز المرشدين (الأقل إنجازًا أولًا)',
    this.moreLabel = 'مرشدًا آخر',
  });

  Color _colorFor(AdvisorProgressStatus status) {
    switch (status) {
      case AdvisorProgressStatus.notStarted:
        return const Color(0xFFD9534F);
      case AdvisorProgressStatus.inProgress:
        return AppColors.gold;
      case AdvisorProgressStatus.complete:
        return AppColors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    // الأسوأ إنجازًا أولًا، محدودة بعدد [cap] لإبقاء الرسم واضحًا ومقروءًا؛
    // التفصيل الكامل متاح في التقرير المُصدَّر.
    final shown = ranked.take(cap).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ...shown.map((advisor) {
          final rate = advisor.counts.completionRate;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        advisor.advisorName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(rate * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Container(height: 18, color: Colors.grey.shade200),
                      FractionallySizedBox(
                        widthFactor: rate.clamp(0.0, 1.0),
                        child: Container(height: 18, color: _colorFor(advisor.status)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        if (ranked.length > cap)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'وأيضًا ${ranked.length - cap} $moreLabel - التفصيل الكامل في التقرير المُصدَّر',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
      ],
    );
  }
}
