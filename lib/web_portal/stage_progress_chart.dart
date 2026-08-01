import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/stage_snapshot_service.dart';
import '../theme/app_theme.dart';

/// عرض تقرير مرحلي مجمَّد واحد (StageSnapshot) - بنفس الطراز البصري لبطاقة
/// FollowUpChart (بطاقة بيضاء، حدود رمادية فاتحة، ألوان AppColors) لكن على
/// بيانات ثابتة محفوظة سابقًا بدل بيانات حيّة، حتى تبقى شاهدًا تاريخيًا لما
/// كان عليه الوضع لحظة "التجميد" بغض النظر عن أي تغيير لاحق في البيانات.
class StageProgressChart extends StatelessWidget {
  final String title;
  final StageSnapshot snapshot;
  final bool showDelta;

  const StageProgressChart({
    super.key,
    required this.title,
    required this.snapshot,
    this.showDelta = false,
  });

  static const _redColor = Color(0xFFD9534F);
  static const _greyColor = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    final counts = snapshot.statusCounts;
    final blank = (counts['blank'] as num?)?.toInt() ?? 0;
    final notDone = (counts['not_done'] as num?)?.toInt() ?? 0;
    final partial = (counts['partial'] as num?)?.toInt() ?? 0;
    final completed = (counts['completed'] as num?)?.toInt() ?? 0;
    final total = (counts['total'] as num?)?.toInt() ?? 0;

    final dateLabel = snapshot.generatedAt == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm').format(snapshot.generatedAt!);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.greenDark, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.greenDark),
                ),
              ),
              if (dateLabel.isNotEmpty)
                Text(dateLabel, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _statChip('فارغة', blank, _greyColor),
              _statChip('لم يتم', notDone, _redColor),
              _statChip('جزئي', partial, AppColors.gold),
              _statChip('تم الإنجاز', completed, AppColors.green),
              _statChip('الإجمالي', total, Colors.black87),
            ],
          ),
          if (showDelta && snapshot.delta != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _deltaSummary(snapshot.delta!),
          ],
          if (snapshot.breakdown.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...snapshot.breakdown.map(_breakdownRow),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _deltaSummary(Map<String, dynamic> delta) {
    final newlyCompleted = (delta['newly_completed'] as num?)?.toInt() ?? 0;
    final newlyPartial = (delta['newly_partial'] as num?)?.toInt() ?? 0;
    final moved = (delta['moved_count'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        const Icon(Icons.trending_up, color: AppColors.green, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'ما تم إنجازه في هذه المرحلة تحديدًا: $moved حالة '
            '($newlyCompleted أُنجزت بالكامل، $newlyPartial أُنجزت جزئيًا)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.greenDark),
          ),
        ),
      ],
    );
  }

  Widget _breakdownRow(Map<String, dynamic> row) {
    final key = (row['key'] ?? '').toString();
    final total = (row['total'] as num?)?.toInt() ?? 0;
    final completed = (row['completed'] as num?)?.toInt() ?? 0;
    final rate = total == 0 ? 0.0 : completed / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                children: [
                  Container(height: 12, color: Colors.grey.shade200),
                  FractionallySizedBox(
                    widthFactor: rate.clamp(0.0, 1.0),
                    child: Container(height: 12, color: AppColors.green),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text('$completed/$total', style: const TextStyle(fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}
