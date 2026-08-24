import 'package:flutter/material.dart';

import '../theme/portal_theme.dart';

/// بطاقة "حالات تجاوزت مستوى المعالجة دون إجراء" بالرئيسية (القسم 9) - تبدّل
/// شكلها تلقائيًا بين تحذير (عدد > 0) وحالة اطمئنان (عدد = 0).
class MobileAlertBanner extends StatelessWidget {
  final int exceededCount;
  final VoidCallback? onViewPressed;

  const MobileAlertBanner({super.key, required this.exceededCount, this.onViewPressed});

  @override
  Widget build(BuildContext context) {
    final hasIssues = exceededCount > 0;
    final color = hasIssues ? AppColors.gold : AppColors.green;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(hasIssues ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              hasIssues ? '$exceededCount حالة تحتاج المتابعة' : 'لا توجد حالات متجاوزة حاليًا',
              style: AppTextStyles.body(color: AppColors.greenDark).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (hasIssues && onViewPressed != null)
            TextButton(
              onPressed: onViewPressed,
              child: Text('عرض الحالات', style: AppTextStyles.caption(color: color).copyWith(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
