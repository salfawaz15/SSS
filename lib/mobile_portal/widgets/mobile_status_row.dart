import 'package:flutter/material.dart';

import '../theme/portal_theme.dart';

/// صف تقدّم مضغوط واحد لعملية (الإضافة/الحذف/تعديل الشعبة، أو قسم علمي) -
/// نسبة مئوية + شريط تقدّم رفيع، طبقًا للقسم 9 ("لا تُنشئ بطاقات ضخمة منفصلة").
/// لون الشريط متدرّج تلقائيًا حسب النسبة (أحمر عند القليل ← أخضر داكن عند
/// 100%) ما لم يُمرَّر `color` صريح (سليمان 2026-08-23).
class MobileStatusRow extends StatelessWidget {
  final String label;
  final double progress; // 0..1
  final Color? color;
  final int labelFlex;

  const MobileStatusRow({
    super.key,
    required this.label,
    required this.progress,
    this.color,
    this.labelFlex = 2,
  });

  /// تدرّج لوني من أحمر (0%) إلى أخضر داكن (100%) - يمر بالذهبي عند المنتصف
  /// تقريبًا، بنفس ألوان الهوية الثلاثة الموجودة أصلًا (بلا لون جديد).
  static Color _gradientColor(double progress) {
    final p = progress.clamp(0, 1);
    if (p <= 0.5) {
      return Color.lerp(AppColors.errorRed, AppColors.gold, p / 0.5)!;
    }
    return Color.lerp(AppColors.gold, AppColors.greenDark, (p - 0.5) / 0.5)!;
  }

  @override
  Widget build(BuildContext context) {
    final percentText = '${(progress * 100).round()}%';
    final barColor = color ?? _gradientColor(progress);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: labelFlex,
            child: Text(label, style: AppTextStyles.body(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 40,
            child: Text(
              percentText,
              textAlign: TextAlign.left,
              style: AppTextStyles.caption(color: Colors.black87).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
