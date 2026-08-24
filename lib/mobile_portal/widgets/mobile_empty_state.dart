import 'package:flutter/material.dart';

import '../theme/portal_theme.dart';

/// حالة فراغ موحّدة (القسم 34) - بدل لوحة بيضاء فارغة بلا معنى.
class MobileEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const MobileEmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.body(color: Colors.black54)),
        ],
      ),
    );
  }
}
