import 'package:flutter/material.dart';

import '../theme/portal_theme.dart';

/// حالة تحميل موحّدة (القسم 33) - لا شاشة بيضاء فارغة أثناء الانتظار.
class MobileLoadingState extends StatelessWidget {
  final String label;

  const MobileLoadingState({super.key, this.label = 'جارٍ تحديث البيانات...'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.green),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(label, style: AppTextStyles.caption(color: Colors.black54)),
        ],
      ),
    );
  }
}
