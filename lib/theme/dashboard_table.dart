import 'package:flutter/material.dart';

import 'dashboard_tokens.dart';

/// وصف عمود بجدول [DashTable] - `flex` يحدّد عرضه النسبي (نفس منطق
/// `Expanded.flex`)، و`sortable` يفعّل النقر على رأس العمود لفرزه.
class DashTableColumn {
  final String key;
  final String label;
  final int flex;
  final bool sortable;
  final TextAlign align;

  const DashTableColumn({
    required this.key,
    required this.label,
    this.flex = 10,
    this.sortable = false,
    this.align = TextAlign.center,
  });
}

Alignment _alignmentFor(TextAlign align) => switch (align) {
      TextAlign.left || TextAlign.start => Alignment.centerLeft,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => Alignment.center,
    };

/// جدول بهوية بصرية موحَّدة - مأخوذ حرفيًا من بطاقة "أفضل 5 مرشدين إنجازًا"
/// (`ticket_action_stats_panel.dart`: `_BestAdvisorsTable`/`_AdvisorRow`)
/// وعُمِّم هنا كمكوّن عام قابل لإعادة الاستخدام بأي جدول آخر بالموقع، بديلاً
/// عن `DataTable` القياسي الذي لا يدعم شرائط تقدّم/بطاقات مصمَّمة داخل
/// الخلايا. يحافظ على واجهة استدعاء مشابهة لـDataTable (أعمدة قابلة للفرز
/// عبر `onSort`)، لكن الرسم يدوي بالكامل (Row/Container لكل صف) بدل
/// الاعتماد على Flutter DataTable.
///
/// الصف الأول يُميَّز بنجمة ذهبية تلقائيًا (نفس هوية "أفضل 5 مرشدين")؛
/// عطّل هذا عبر `showFirstRowStar: false` للجداول التي لا تمثّل ترتيبًا
/// تنازليًا (كجدول منسوبي الكلية غير المرتَّب حسب إنجاز).
class DashTable extends StatelessWidget {
  final List<DashTableColumn> columns;
  final int rowCount;
  final Widget Function(BuildContext context, int rowIndex, String columnKey) cellBuilder;
  final String? sortKey;
  final bool sortAscending;
  final ValueChanged<String>? onSort;
  final bool showFirstRowStar;
  final Color? Function(int rowIndex)? rowBackground;

  const DashTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.cellBuilder,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.showFirstRowStar = false,
    this.rowBackground,
  });

  Widget _headerCell(DashTableColumn c) {
    final active = sortKey == c.key;
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            c.label,
            textAlign: c.align,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? DashTokens.green900 : DashTokens.textMuted,
            ),
          ),
        ),
        if (c.sortable) ...[
          const SizedBox(width: 2),
          Icon(
            active ? (sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
            size: 13,
            color: active ? DashTokens.green900 : DashTokens.textMuted,
          ),
        ],
      ],
    );
    if (c.sortable && onSort != null) {
      content = InkWell(
        onTap: () => onSort!(c.key),
        borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: content),
      );
    }
    return Expanded(flex: c.flex, child: Align(alignment: _alignmentFor(c.align), child: content));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [for (final c in columns) _headerCell(c)]),
        const Divider(height: 14, color: DashTokens.border),
        for (var i = 0; i < rowCount; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: rowBackground?.call(i),
              border: i == rowCount - 1
                  ? null
                  : Border(bottom: BorderSide(color: DashTokens.border.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                for (var ci = 0; ci < columns.length; ci++)
                  Expanded(
                    flex: columns[ci].flex,
                    child: ci == 0 && showFirstRowStar && i == 0
                        ? Row(
                            mainAxisAlignment: columns[ci].align == TextAlign.center
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.star_rounded, size: 14, color: DashTokens.gold500),
                              const SizedBox(width: 4),
                              Flexible(child: cellBuilder(context, i, columns[ci].key)),
                            ],
                          )
                        : Align(
                            alignment: _alignmentFor(columns[ci].align),
                            child: cellBuilder(context, i, columns[ci].key),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// بطاقة بيضاء بحدود خفيفة وظل لطيف تحيط بـ[DashTable] - نفس حاوية
/// `_CardShell`/`DashCardShell` المعتمَدة بكل البوابة، بعرض أفقي عند الحاجة
/// (جداول بأعمدة كثيرة على شاشات ضيقة) بدل تكسّر التخطيط.
class DashTableCard extends StatelessWidget {
  final Widget table;
  final double? minWidth;

  const DashTableCard({super.key, required this.table, this.minWidth});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        boxShadow: DashTokens.cardShadow,
      ),
      child: table,
    );
    if (minWidth == null) return content;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: minWidth, child: content),
    );
  }
}

/// خلية شريط تقدّم برتقالي/ملوَّن بنسبة مئوية - نفس هوية عمود "نسبة الإنجاز"
/// بجدول "أفضل 5 مرشدين إنجازًا" (نسبة مئوية على اليسار + شريط تقدّم رفيع).
class DashProgressCell extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final String? label;

  const DashProgressCell({super.key, required this.value, required this.color, this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label ?? '${(value * 100).round()}%',
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: DashTokens.track,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// شارة ملوَّنة صغيرة (خلفية شفافة + حدّ بنفس اللون) - نفس هوية شارات
/// "عبء الإرشاد"/"العبء الدراسي" الحالية بجدول منسوبي الكلية، عُمِّمت هنا
/// ليُعاد استخدامها بأي جدول آخر بلا تكرار.
class DashBadgeCell extends StatelessWidget {
  final String label;
  final Color color;
  final String? tooltip;

  const DashBadgeCell({super.key, required this.label, required this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
    if (tooltip == null || tooltip!.isEmpty) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
