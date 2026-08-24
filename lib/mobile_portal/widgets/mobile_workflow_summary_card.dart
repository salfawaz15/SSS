import 'package:flutter/material.dart';

import '../../services/ticket_workflow_stats_service.dart';
import '../theme/portal_theme.dart';

/// ملخص مستوى واحد من مستويات سير العمل (مرشدون/أقسام/كلية) بالرئيسية -
/// القسم 9: "تم التنفيذ / لم يعمل عليه بعد / تعذّر أو تم التصعيد" فقط.
class MobileWorkflowSummaryCard extends StatelessWidget {
  final TicketRoleProgress progress;

  const MobileWorkflowSummaryCard({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(progress.role, style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: _countChip('${progress.complete}', PortalStatusColors.completed),
          ),
          Expanded(
            child: _countChip('${progress.notStarted}', PortalStatusColors.notStarted),
          ),
          Expanded(
            child: _countChip('${progress.escalated}', PortalStatusColors.escalated),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String value, Color color) {
    return Align(
      alignment: Alignment.center,
      child: Text(value, style: AppTextStyles.body(color: color).copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// عناوين الأعمدة الثلاثة أعلى قائمة بطاقات المستويات - مرة واحدة فوق
/// القائمة بدل تكرارها بكل بطاقة.
class MobileWorkflowSummaryHeader extends StatelessWidget {
  const MobileWorkflowSummaryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.caption(color: Colors.black54);
    return Row(
      children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(child: Center(child: Text('تم التنفيذ', style: style))),
        Expanded(child: Center(child: Text('لم يُعمَل بعد', style: style))),
        Expanded(child: Center(child: Text('تعذّر / تصعيد', style: style))),
      ],
    );
  }
}
