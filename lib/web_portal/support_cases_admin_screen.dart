import 'package:flutter/material.dart';

import '../models/hardship_case.dart';
import '../services/support_case_service.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

/// شاشة "حالات الدعم النفسي والاجتماعي" لإدارة الوحدة - قسم منفصل تمامًا عن حالات الظروف الخاصة وعن تقارير
/// طلبات الإضافة/الحذف، يعرض كل الحالات من كل الأقسام مجتمعة، مع إمكانية
/// فتح مسار المتابعة الكامل لأي حالة لمعرفة ماذا تم بشأنها بمرور الوقت.
class SupportCasesAdminScreen extends StatelessWidget {
  const SupportCasesAdminScreen({super.key});

  Color _statusColor(HardshipStatus s) {
    switch (s) {
      case HardshipStatus.newCase:
        return Colors.blueGrey;
      case HardshipStatus.underReview:
        return AppColors.gold;
      case HardshipStatus.contactedStudent:
      case HardshipStatus.contactedFamily:
        return Colors.teal;
      case HardshipStatus.referred:
        return Colors.deepOrange;
      case HardshipStatus.improved:
        return AppColors.green;
      case HardshipStatus.needsOngoingFollowUp:
        return Colors.redAccent;
    }
  }

  void _showHistory(BuildContext context, HardshipCase c) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('مسار المتابعة: ${c.studentName}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: c.history.reversed.map((h) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.status.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (h.notes.isNotEmpty) Text(h.notes, style: const TextStyle(fontSize: 12.5)),
                      Text(
                        '${h.updatedBy} — ${h.updatedAt != null ? h.updatedAt.toString().substring(0, 16) : ''}',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'حالات الدعم النفسي والاجتماعي',
      navItems: buildAdminNavItems(context, current: 'support'),
      body: StreamBuilder<List<HardshipCase>>(
        stream: SupportCaseService.watchAllCases(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cases = List<HardshipCase>.from(snapshot.data!)
            ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

          if (cases.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'لا توجد حالات دعم مسجَّلة بعد من أي قسم.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'إجمالي الحالات: ${cases.length}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              ...cases.map((c) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.studentName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(c.status).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  c.status.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(c.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${c.department} — ${c.shatr} — الرقم الجامعي: ${c.universityId}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          if (c.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(c.description, style: const TextStyle(fontSize: 12.5)),
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _showHistory(context, c),
                              icon: const Icon(Icons.history, size: 16),
                              label: const Text('مسار المتابعة الكامل'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
