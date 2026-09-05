import 'package:flutter/material.dart';

import '../services/stage_snapshot_service.dart';
import '../theme/app_theme.dart';
import 'admin_executive_dashboard_screen.dart' show completionPercent;

/// قسم "سجل الدورات السابقة" بلوحة الإدارة التنفيذية - يعرض ملخّص كل دورة
/// حذف/إضافة مؤرشَفة تلقائيًا لحظة "تفريغ البيانات" (انظر
/// `StageSnapshotService.freezeCycleEnd`، يُستدعى من admin_workspace_screen،
/// upload_hub_screen، وportal_uploads_screen قبل `clearAll()` مباشرة).
/// بلا هذا القسم لا تبقى أي وسيلة لمقارنة أداء الدورات ببعضها بعد التفريغ
/// النهائي (سليمان صراحةً 2026-09-05).
class CycleHistorySection extends StatelessWidget {
  const CycleHistorySection({super.key});

  static const _green = AppColors.greenDark;
  static const _gold = AppColors.gold;
  static const _border = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CycleArchive>>(
      stream: StageSnapshotService.watchCycleArchives(),
      builder: (context, snapshot) {
        final archives = snapshot.data ?? const <CycleArchive>[];

        return Container(
          margin: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_edu_outlined, size: 19, color: _green),
                  SizedBox(width: 7),
                  Text(
                    'سجل الدورات السابقة',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _green),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'ملخّص كل دورة حذف وإضافة مؤرشَفة تلقائيًا لحظة تفريغ بياناتها - لمقارنة الأداء بين الفصول',
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              if (archives.isEmpty)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Colors.black45),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لا توجد دورات مؤرشَفة بعد - ستظهر هنا تلقائيًا كل دورة عند تفريغ بياناتها.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (var i = 0; i < archives.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _CycleArchiveCard(
                    archive: archives[i],
                    previous: i + 1 < archives.length ? archives[i + 1] : null,
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _CycleArchiveCard extends StatelessWidget {
  final CycleArchive archive;
  final CycleArchive? previous;
  const _CycleArchiveCard({required this.archive, required this.previous});

  static const _green = CycleHistorySection._green;
  static const _gold = CycleHistorySection._gold;
  static const _border = CycleHistorySection._border;

  @override
  Widget build(BuildContext context) {
    final rate = completionPercent(archive.completedCount, archive.totalActions == 0 ? 1 : archive.totalActions);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final endedAt = archive.endedAt;
    final dateLabel = endedAt == null
        ? 'تاريخ غير مسجَّل'
        : '${endedAt.year}-${twoDigits(endedAt.month)}-${twoDigits(endedAt.day)}';

    String? bestDepartment;
    var bestRate = -1.0;
    for (final d in archive.departmentBreakdown) {
      final total = (d['total'] as num?)?.toInt() ?? 0;
      if (total == 0) continue;
      final completed = (d['completed'] as num?)?.toInt() ?? 0;
      final deptRate = completed / total;
      if (deptRate > bestRate) {
        bestRate = deptRate;
        bestDepartment = (d['department'] ?? '').toString();
      }
    }

    final digital = archive.digitalTransformation;
    final digitalSharePercent = (digital['digital_share_percent'] as num?)?.round() ?? 0;

    int? previousRate;
    if (previous != null) {
      previousRate = completionPercent(
        previous!.completedCount,
        previous!.totalActions == 0 ? 1 : previous!.totalActions,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_outlined, size: 16, color: _gold),
              const SizedBox(width: 6),
              Text(dateLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
              const Spacer(),
              Text('$rate%', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _green)),
              if (previousRate != null) ...[
                const SizedBox(width: 4),
                Icon(
                  rate >= previousRate ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: rate >= previousRate ? _green : Colors.red.shade400,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text('${archive.totalTickets} طلب · ${archive.totalActions} إجراء', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
              Text('قناة Forms: $digitalSharePercent%', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
              if (bestDepartment != null && bestDepartment.isNotEmpty)
                Text('الأعلى إنجازًا: $bestDepartment', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }
}
