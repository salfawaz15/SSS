import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/digital_transformation_stats_service.dart';
import '../services/excel_parser_service.dart';
import '../services/report_data_service.dart';
import '../theme/app_theme.dart';

/// قسم "مؤشرات التحول الرقمي" بلوحة الإدارة التنفيذية - دليل حي بالأرقام
/// والرسوم البيانية يدعم توجه التحول الإلكتروني في عمليات الحذف والإضافة،
/// مبنيّ حصرًا على بيانات Firestore الحقيقية (`DigitalTransformationStatsService`)
/// بلا أي رقم وهمي. أبرز عنصر فيه (بطلب سليمان صراحةً) هو تطور الطلبات
/// واستجابة المرشدين عبر أيام فترة الحذف والإضافة الثلاثة - يظهر أولاً
/// وبأكبر حجم بصري.
class DigitalTransformationSection extends StatelessWidget {
  final List<Map<String, dynamic>> tickets;

  const DigitalTransformationSection({super.key, required this.tickets});

  static const _green = AppColors.greenDark;
  static const _gold = AppColors.gold;
  static const _border = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return const SizedBox.shrink();
    final stats = DigitalTransformationStatsService.build(tickets);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_outlined, size: 19, color: _green),
              SizedBox(width: 7),
              Text(
                'مؤشرات التحول الرقمي',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _green),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'دليل حي يدعم توجه التحول الإلكتروني في عمليات الحذف والإضافة - مبنيّ على بيانات فعلية محدَّثة لحظيًا',
            style: TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          if (stats.dailyCohorts.isEmpty)
            _InfoBanner(text: 'لا تتوفر بيانات تواريخ رفع كافية بعد لعرض تطور الأيام الثلاثة.')
          else
            _DailyTrendCard(stats: stats),
          const SizedBox(height: 10),
          _ChannelSection(stats: stats),
          const SizedBox(height: 10),
          _TopPerformersSection(tickets: tickets),
          const SizedBox(height: 10),
          const _SatisfactionSurveyNotice(),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        border: Border.all(color: DigitalTransformationSection._border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54))),
        ],
      ),
    );
  }
}

/// أهم عنصر بالقسم بأكمله (بطلب سليمان صراحةً) - تطور عدد الطلبات المُقدَّمة
/// واستجابة المرشدين عبر أيام فترة الحذف والإضافة الثلاثة، بلا أي تجميل أو
/// إخفاء للاتجاه الحقيقي بالبيانات (حتى لو كان اتجاهًا غير متوقَّع كتزايد
/// الطلبات يوميًا بدل تناقصها).
class _DailyTrendCard extends StatelessWidget {
  final DigitalTransformationStats stats;
  const _DailyTrendCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cohorts = stats.dailyCohorts;
    final maxTickets = cohorts.map((c) => c.ticketCount).fold(0, (a, b) => a > b ? a : b).toDouble();
    final chartMax = maxTickets <= 0 ? 1.0 : maxTickets * 1.25;

    final increasing = cohorts.length > 1 && cohorts.last.ticketCount > cohorts.first.ticketCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: DigitalTransformationSection._border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.stacked_line_chart_outlined, size: 17, color: DigitalTransformationSection._gold),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'تطور الطلبات واستجابة المرشدين عبر أيام فترة الحذف والإضافة',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DigitalTransformationSection._green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'عدد الطلبات حسب يوم تقديمها فعليًا، ونسبة استجابة المرشدين الحالية لكل فوج يوم',
            style: TextStyle(fontSize: 10.5, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: chartMax,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= cohorts.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('يوم ${i + 1}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < cohorts.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: cohorts[i].ticketCount.toDouble(),
                          color: DigitalTransformationSection._green,
                          width: 26,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final c in cohorts)
                _CohortChip(cohort: c),
            ],
          ),
          if (increasing) ...[
            const SizedBox(height: 10),
            const _TrendNote(
              icon: Icons.trending_up,
              color: DigitalTransformationSection._gold,
              text: 'نمو مطّرد في عدد الطلبات المُقدَّمة يومًا بعد يوم عبر فترة الحذف والإضافة - مؤشر متزايد على إقبال الطلبة على النظام الإلكتروني.',
            ),
          ],
        ],
      ),
    );
  }
}

class _CohortChip extends StatelessWidget {
  final DailyCohortStats cohort;
  const _CohortChip({required this.cohort});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        border: Border.all(color: DigitalTransformationSection._border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(cohort.dayLabel, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: DigitalTransformationSection._green)),
          const SizedBox(height: 2),
          Text('${cohort.ticketCount} طلبًا · ${cohort.actionCount} إجراء', style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          Text(
            'استجابة المرشد الآن: ${(cohort.advisorResponseRateNow * 100).round()}% · إنجاز الآن: ${(cohort.completionRateNow * 100).round()}%',
            style: const TextStyle(fontSize: 10, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

class _TrendNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _TrendNote({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _ChannelSection extends StatelessWidget {
  final DigitalTransformationStats stats;
  const _ChannelSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: DigitalTransformationSection._border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final chart = SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 46,
                  sections: [
                    if (stats.formsTicketCount > 0)
                      PieChartSectionData(value: stats.formsTicketCount.toDouble(), color: AppColors.green, showTitle: false, radius: 24),
                    if (stats.paperTicketCount > 0)
                      PieChartSectionData(value: stats.paperTicketCount.toDouble(), color: AppColors.gold, showTitle: false, radius: 24),
                    if (stats.formsTicketCount == 0 && stats.paperTicketCount == 0)
                      PieChartSectionData(value: 1, color: const Color(0xFFEDF0EE), showTitle: false, radius: 24),
                  ],
                ),
              ),
              Text('${stats.digitalSharePercent.round()}%', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: DigitalTransformationSection._green)),
            ],
          ),
        );

        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart_outline, size: 15, color: DigitalTransformationSection._gold),
                SizedBox(width: 6),
                Text('توزيع الطلبات حسب قناة التقديم', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DigitalTransformationSection._green)),
              ],
            ),
            const SizedBox(height: 10),
            _ChannelRow(channel: stats.forms, color: AppColors.green, total: stats.totalTickets),
            const SizedBox(height: 8),
            _ChannelRow(channel: stats.paperForm, color: AppColors.gold, total: stats.totalTickets),
          ],
        );

        if (isNarrow) {
          return Column(children: [Center(child: chart), const SizedBox(height: 12), legend]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [chart, const SizedBox(width: 18), Expanded(child: legend)],
        );
      }),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final ChannelCount channel;
  final Color color;
  final int total;
  const _ChannelRow({required this.channel, required this.color, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (channel.ticketCount / total * 100).round();
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(channel.label, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis),
        ),
        Text('${channel.ticketCount} ($pct%)', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        if (channel.totalActions > 0) ...[
          const SizedBox(width: 10),
          Text('نسبة الإنجاز: ${(channel.completionRate * 100).round()}%', style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
        ],
      ],
    );
  }
}

String _shatrDisplayLabel(String shatrRaw) => shatrRaw == ExcelParserService.shatrMale ? 'شطر الطلاب' : 'شطر الطالبات';
String _deptShortLabel(String value) => value.replaceFirst('قسم ', '');

/// بطاقات تكريمية إيجابية بحتة تُبرز الأقسام/الأفراد الأعلى إنجازًا -
/// بلا أي ترتيب سلبي أو ذكر لمن لم يحقق نفس المستوى (بطلب سليمان صراحةً).
/// مبنيّة كليًا على `ReportDataService`/`DepartmentReport`/`AdvisorReport`
/// الموجودة أصلاً (لا حسابات موازية جديدة):
/// - "منسّق القسم" هنا يعني أداءه الفعلي المسجَّل بعمود `coordinator_status`
///   بتذاكر الحذف والإضافة (`DepartmentReport.coordinatorCounts`) - هو الدور
///   الوحيد المميَّز فعليًا عن المرشد بهذا السياق تحديدًا (لا يوجد حقل اسم
///   شخصي لمنسّق القسم بالتذكرة، فقط أداء القسم ككل).
class _TopPerformersSection extends StatelessWidget {
  final List<Map<String, dynamic>> tickets;
  const _TopPerformersSection({required this.tickets});

  @override
  Widget build(BuildContext context) {
    final reportData = ReportDataService.build(tickets);

    DepartmentReport? bestDeptFor(String shatr) {
      DepartmentReport? best;
      for (final d in reportData.departments) {
        if (d.shatr != shatr || d.counts.total == 0) continue;
        if (best == null || d.counts.completionRate > best.counts.completionRate) best = d;
      }
      return best;
    }

    final bestMaleDept = bestDeptFor(ExcelParserService.shatrMale);
    final bestFemaleDept = bestDeptFor(ExcelParserService.shatrFemale);

    final advisors = ReportDataService.rankedAdvisors(reportData);
    final bestAdvisor = advisors.isEmpty ? null : advisors.last;

    final coordinators = ReportDataService.rankedCoordinators(reportData);
    final bestCoordinator = coordinators.isEmpty ? null : coordinators.last;

    final cards = <Widget>[
      if (bestMaleDept != null && bestMaleDept.counts.completed > 0)
        _TopPerformerCard(
          icon: Icons.emoji_events_outlined,
          title: 'القسم الأعلى إنجازًا - شطر الطلاب',
          name: _deptShortLabel(bestMaleDept.department),
          detail: '${bestMaleDept.counts.completed} حالة مُنجزة من ${bestMaleDept.counts.total}',
        ),
      if (bestFemaleDept != null && bestFemaleDept.counts.completed > 0)
        _TopPerformerCard(
          icon: Icons.emoji_events_outlined,
          title: 'القسم الأعلى إنجازًا - شطر الطالبات',
          name: _deptShortLabel(bestFemaleDept.department),
          detail: '${bestFemaleDept.counts.completed} حالة مُنجزة من ${bestFemaleDept.counts.total}',
        ),
      if (bestAdvisor != null && bestAdvisor.counts.completed > 0)
        _TopPerformerCard(
          icon: Icons.star_rounded,
          title: 'المرشد الأكثر تفاعلًا',
          name: bestAdvisor.advisorName,
          detail: '${bestAdvisor.counts.completed} حالة مُنجزة · ${_deptShortLabel(bestAdvisor.department)} · ${_shatrDisplayLabel(bestAdvisor.shatr)}',
        ),
      if (bestCoordinator != null && bestCoordinator.counts.completed > 0)
        _TopPerformerCard(
          icon: Icons.verified_outlined,
          title: 'القسم الأنشط بمتابعة منسّق القسم',
          name: _deptShortLabel(bestCoordinator.department),
          detail: '${bestCoordinator.counts.completed} حالة تابعها المنسّق · ${_shatrDisplayLabel(bestCoordinator.shatr)}',
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: DigitalTransformationSection._border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.workspace_premium_outlined, size: 17, color: DigitalTransformationSection._gold),
              SizedBox(width: 6),
              Text('الأبرز إنجازًا', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DigitalTransformationSection._green)),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth < 500 ? 1 : (constraints.maxWidth < 900 ? 2 : 4);
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in cards) SizedBox(width: (constraints.maxWidth - (columns - 1) * 10) / columns, child: c),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _TopPerformerCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String name;
  final String detail;
  const _TopPerformerCard({required this.icon, required this.title, required this.name, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        border: Border.all(color: DigitalTransformationSection._border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.gold),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.black54))),
            ],
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DigitalTransformationSection._green), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
        ],
      ),
    );
  }
}

/// لا يحتوي نموذج Microsoft Forms الحالي أي سؤال يقيس رضا/رغبة الطالب
/// بالتحول الإلكتروني (تحقَّقنا من كل الأعمدة المعروفة بـ`ExcelParserService`
/// وملفات قراءة Forms الأخرى - لا وجود لعمود من هذا النوع) - إشعار توصية
/// بدل اختراع رقم رضا وهمي (بطلب سليمان صراحةً: لا تُخترَع بيانات).
class _SatisfactionSurveyNotice extends StatelessWidget {
  const _SatisfactionSurveyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3DE),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.emoji_objects_outlined, size: 17, color: AppColors.gold),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'استبيان رضا الطلبة: نموذج Microsoft Forms الحالي لا يحتوي سؤالًا يقيس رضا/رغبة الطالب بالتحول الإلكتروني، فلا تتوفر بيانات فعلية لعرضها هنا. '
              'يُقترَح إضافة سؤال تقييم بسيط (مثلًا من 1 إلى 5، أو نعم/لا) في نموذج Forms القادم حتى يمكن عرض نتائجه في هذا القسم مستقبلًا.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF6B5B12), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
