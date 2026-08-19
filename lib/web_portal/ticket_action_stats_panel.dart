import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/excel_parser_service.dart';
import '../services/report_data_service.dart';
import '../services/ticket_action_stats_service.dart';
import '../theme/app_theme.dart';

/// لوحة إحصائيات طلبات الحذف/الإضافة/تعديل الشعب - "الإنجاز" الحقيقي الذي
/// نقيسه هنا هو معالجة المرشد (ثم منسّق القسم فمنسّق الكلية) لهذه الطلبات
/// نفسها، فهو عمل المرشد الإرشادي بحق. أما تسكين الطالب على مرشده الصحيح
/// (`advisor_corrected`) فهو شرط صحة بيانات أساسي لا مؤشر تقدّم - يُعرض هنا
/// كتنبيه منفصل بصريًا عن بطاقات الإنجاز، لا كرقم إنجاز. تصميم هذه اللوحة
/// معتمَد من سليمان بعد مراجعة Mockup مصمَّم بهوية التقارير الرسمية (رأس
/// متدرّج أخضر داكن + شارات ذهبية دائرية + عناوين أقسام بشريط أخضر متدرّج).
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
    'إضافة': Color(0xFF2E7D32),
    'حذف': Color(0xFFB3261E),
    'تعديل': Color(0xFF9C6D00),
  };

  static const _actionIcons = {
    'إضافة': Icons.add,
    'حذف': Icons.remove,
    'تعديل': Icons.swap_horiz,
  };

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
              const Expanded(
                child: Text(
                  'إحصائيات طلبات الحذف والإضافة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.greenDark),
                ),
              ),
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
            ],
          ),
          const SizedBox(height: 16),
          if (stats.totalActions == 0)
            Text('لا توجد حالات لهذا الاختيار', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
          else ...[

          // صف بطاقات KPI الدائرية
          LayoutBuilder(
            builder: (context, constraints) {
              final total = stats.totalActions == 0 ? 1 : stats.totalActions;
              final overallRate = reportData.overall.total == 0
                  ? 0.0
                  : reportData.overall.completed / reportData.overall.total;
              final cards = [
                _KpiCircleCard(
                  label: 'إجمالي الحالات',
                  value: '${stats.totalTickets}',
                  percent: 1,
                  ringColor: AppColors.greenDark,
                  trackColor: AppColors.greenDark.withValues(alpha: 0.1),
                  icon: Icons.folder_outlined,
                ),
                _KpiCircleCard(
                  label: 'نسبة الإنجاز العامة',
                  value: '${(overallRate * 100).round()}%',
                  percent: overallRate,
                  ringColor: overallRate >= 0.5 ? const Color(0xFF2E7D32) : AppColors.errorRed,
                  trackColor: Colors.grey.shade200,
                  icon: Icons.track_changes_outlined,
                ),
                for (final type in ['إضافة', 'حذف', 'تعديل'])
                  if (stats.byActionType.containsKey(type))
                    _KpiCircleCard(
                      label: 'طلبات $type',
                      value: '${stats.byActionType[type]!.total}',
                      percent: stats.byActionType[type]!.total / total,
                      ringColor: _actionColors[type]!,
                      trackColor: _actionColors[type]!.withValues(alpha: 0.1),
                      icon: _actionIcons[type]!,
                    ),
              ];
              final isNarrow = constraints.maxWidth < 700;
              if (isNarrow) {
                return Column(
                  children: [
                    for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
                  ],
                );
              }
              return Row(
                children: [
                  for (final c in cards) ...[
                    Expanded(child: c),
                    if (c != cards.last) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          _SectionTitle(icon: Icons.insights_outlined, text: 'حالة إنجاز معالجة الطلبات (لكل نوع إجراء)'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final gauges = [
                for (final type in ['إضافة', 'حذف', 'تعديل'])
                  if (stats.byActionType.containsKey(type))
                    _StatusGaugeCard(label: 'طلبات $type', stats: stats.byActionType[type]!),
              ];
              if (isNarrow) {
                return Column(
                  children: [
                    for (final g in gauges) Padding(padding: const EdgeInsets.only(bottom: 14), child: g),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in gauges) ...[
                    Expanded(child: g),
                    if (g != gauges.last) const SizedBox(width: 24),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              final bestList = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(icon: Icons.stars_outlined, text: 'أفضل 5 مرشدين إنجازًا'),
                  const SizedBox(height: 12),
                  _BestAdvisorsList(advisors: bestAdvisors.take(5).toList()),
                ],
              );
              final deptTable = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(icon: Icons.stacked_bar_chart_outlined, text: 'توزيع الحالات حسب القسم'),
                  const SizedBox(height: 12),
                  _DepartmentBreakdownTable(stats: stats),
                ],
              );
              if (isNarrow) {
                return Column(
                  children: [bestList, const SizedBox(height: 24), deptTable],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: bestList),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: deptTable),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          _SectionTitle(icon: Icons.groups_2_outlined, text: 'عدد الحالات لدى كل مرشد'),
          const SizedBox(height: 12),
          _AdvisorCaseCountTable(advisors: advisorStats),
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
        ],
      ),
    );
  }
}

/// عنوان قسم بشريط أخضر متدرّج - نفس هوية `_sectionHeading` بتقارير PDF
/// الرسمية (unit_guide_pdf_service.dart)، معتمَد من سليمان لتوحيد الهوية
/// بين التقارير المطبوعة ولوحة الإدارة.
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.goldLight),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

/// بطاقة KPI دائرية: الرقم داخل حلقة التقدّم، وشارة أيقونة ذهبية بزاويتها.
class _KpiCircleCard extends StatelessWidget {
  final String label;
  final String value;
  final double percent;
  final Color ringColor;
  final Color trackColor;
  final IconData icon;

  const _KpiCircleCard({
    required this.label,
    required this.value,
    required this.percent,
    required this.ringColor,
    required this.trackColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 66,
                  height: 66,
                  child: CircularProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: trackColor,
                    valueColor: AlwaysStoppedAnimation(ringColor),
                  ),
                ),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
                Positioned(
                  top: -2,
                  left: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 4)],
                    ),
                    child: Icon(icon, size: 11, color: AppColors.greenDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// عدّاد دائري ثلاثي الألوان (مكتمل/قيد التنفيذ/لم يبدأ) لنوع إجراء واحد.
class _StatusGaugeCard extends StatelessWidget {
  final String label;
  final ActionTypeStats stats;

  const _StatusGaugeCard({required this.label, required this.stats});

  static const _completeColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final counts = stats.statusCounts;
    final completed = counts.completed;
    final progress = counts.partial;
    final notStarted = counts.notDone + counts.blank;
    final total = counts.total == 0 ? 1 : counts.total;
    final completedPct = ((completed / total) * 100).round();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 42,
                  sections: [
                    if (completed > 0)
                      PieChartSectionData(value: completed.toDouble(), color: _completeColor, showTitle: false, radius: 18),
                    if (progress > 0)
                      PieChartSectionData(value: progress.toDouble(), color: AppColors.gold, showTitle: false, radius: 18),
                    if (notStarted > 0)
                      PieChartSectionData(value: notStarted.toDouble(), color: AppColors.errorRed, showTitle: false, radius: 18),
                    if (completed == 0 && progress == 0 && notStarted == 0)
                      PieChartSectionData(value: 1, color: Colors.grey.shade200, showTitle: false, radius: 18),
                  ],
                ),
              ),
              Text('$completedPct%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
              const SizedBox(height: 8),
              _legendDot(_completeColor, 'مكتمل: $completed'),
              const SizedBox(height: 6),
              _legendDot(AppColors.gold, 'قيد التنفيذ: $progress'),
              const SizedBox(height: 6),
              _legendDot(AppColors.errorRed, 'لم يبدأ: $notStarted'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String text) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}

/// قائمة "أفضل 5 مرشدين إنجازًا" - انطباع إيجابي عند الدخول (بطلب سليمان)،
/// بشريط تقدّم بتدرّج لوني مستمر (أحمر→ذهبي→أخضر) حسب النسبة بالضبط، لا 3
/// عتبات ثابتة، حتى تتمايز القيم القريبة من بعضها بصريًا.
class _BestAdvisorsList extends StatelessWidget {
  final List<AdvisorCaseStats> advisors;

  const _BestAdvisorsList({required this.advisors});

  static Color _rateColor(double rate) {
    const red = Color(0xFFB3261E);
    const gold = AppColors.gold;
    const green = Color(0xFF2E7D32);
    if (rate <= 0.5) return Color.lerp(red, gold, (rate / 0.5).clamp(0.0, 1.0))!;
    return Color.lerp(gold, green, ((rate - 0.5) / 0.5).clamp(0.0, 1.0))!;
  }

  @override
  Widget build(BuildContext context) {
    if (advisors.isEmpty) {
      return Text('لا توجد بيانات كافية', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _headerCell('الاسم', flex: 22),
            _headerCell('القسم', flex: 13),
            _headerCell('الشطر', flex: 8),
            _headerCell('عدد الحالات', flex: 9),
            _headerCell('نسبة الإنجاز', flex: 16),
          ],
        ),
        const Divider(height: 16),
        for (final a in advisors)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 22,
                  child: Text(a.advisorName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
                Expanded(flex: 13, child: Text(a.department, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))),
                Expanded(flex: 8, child: Text(a.shatr, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))),
                Expanded(flex: 9, child: Text('${a.total}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                Expanded(
                  flex: 16,
                  child: Builder(builder: (context) {
                    final rate = a.total == 0 ? 0.0 : a.completed / a.total;
                    final color = _rateColor(rate);
                    return Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              height: 7,
                              child: LinearProgressIndicator(
                                value: rate,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 34,
                          child: Text('${(rate * 100).round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headerCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
    );
  }
}

/// جدول "توزيع الحالات حسب القسم" - 5 صفوف فقط (قسم واحد لكل سطر) بدل 10
/// (تكرار كل قسم لشطرين)، برأس مزدوج المستوى يفصل طلاب/طالبات تحت كل نوع
/// إجراء - بطلب سليمان صراحةً بعد أن رأى تكرار الصفوف غير منظَّم.
class _DepartmentBreakdownTable extends StatelessWidget {
  final TicketActionStats stats;

  const _DepartmentBreakdownTable({required this.stats});

  int _count(String dept, String shatr, String type) {
    return stats.byDepartmentShatr['$shatr|$dept']?[type] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final hasData = stats.byDepartmentShatr.isNotEmpty;
    if (!hasData) {
      return Text('لا توجد بيانات كافية', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    }

    Widget groupHeader(String label, Color color) => Expanded(
          flex: 2,
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        );
    Widget subHeader(String label) => Expanded(
          flex: 1,
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(flex: 3, child: SizedBox()),
            groupHeader('إضافة', const Color(0xFF2E7D32)),
            groupHeader('حذف', AppColors.errorRed),
            groupHeader('تعديل', const Color(0xFF9C6D00)),
          ],
        ),
        Row(
          children: [
            const Expanded(flex: 3, child: SizedBox()),
            subHeader('طلاب'),
            subHeader('طالبات'),
            subHeader('طلاب'),
            subHeader('طالبات'),
            subHeader('طلاب'),
            subHeader('طالبات'),
          ],
        ),
        const Divider(height: 14),
        for (final dept in ExcelParserService.departments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(dept, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 2),
                ),
                _valueCell(_count(dept, ExcelParserService.shatrMale, 'إضافة'), const Color(0xFF2E7D32)),
                _valueCell(_count(dept, ExcelParserService.shatrFemale, 'إضافة'), const Color(0xFF2E7D32)),
                _valueCell(_count(dept, ExcelParserService.shatrMale, 'حذف'), AppColors.errorRed),
                _valueCell(_count(dept, ExcelParserService.shatrFemale, 'حذف'), AppColors.errorRed),
                _valueCell(_count(dept, ExcelParserService.shatrMale, 'تعديل'), const Color(0xFF9C6D00)),
                _valueCell(_count(dept, ExcelParserService.shatrFemale, 'تعديل'), const Color(0xFF9C6D00)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _valueCell(int value, Color color) {
    return Expanded(
      flex: 1,
      child: Text('$value', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

/// جدول "عدد الحالات لدى كل مرشد" مع فلترة بالشطر/القسم - مختلف عن قائمة
/// "أفضل 5" بأعلى الصفحة بأنه جدول عدد خام كامل (منجزة/محوَّلة/لم يُعمل
/// عليها) قابل للفلترة، وهو ما طلبه سليمان تحديدًا.
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
        _SectionTitle(icon: Icons.groups_2_outlined, text: 'أداء الفريق: المرشدون ومنسّقو الأقسام والكلية'),
        const SizedBox(height: 6),
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
