import 'package:flutter/material.dart';

import '../theme/portal_theme.dart';

/// حالة خطأ موحّدة بنص عربي مفهوم (القسم 35) - لا استثناءات تقنية خام.
class MobileErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const MobileErrorState({
    super.key,
    this.message = 'تعذّر تحميل البيانات.\nيرجى المحاولة مرة أخرى.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.errorRed),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.body(color: Colors.black54)),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ],
      ),
    );
  }
}
