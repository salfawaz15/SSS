import 'package:flutter/material.dart';

import '../models/advisor_roster_entry.dart';
import '../services/advisor_roster_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/ticket_action_stats_service.dart';
import '../theme/app_theme.dart';
import 'academic_services_hub_screen.dart';
import 'admin_nav.dart';
import 'admin_workspace_screen.dart';
import 'advising_hub_screen.dart';
import 'college_roster_admin_screen.dart';
import 'portal_header.dart';
import 'reports_hub_screen.dart';
import 'upload_hub_screen.dart';

/// لوحة الإدارة الرئيسية (Executive Dashboard) - أول ما يراه المدير بعد
/// الدخول، تلخّص وضع البوابة **كاملة** لا الحذف/الإضافة فقط (تلك انتقلت
/// لتبويب "الحذف والإضافة" المستقل) - بطلب سليمان صراحةً 2026-08-19 وفق
/// مواصفات إعادة التصميم الشامل (design_references/portal_redesign_spec_ar.md
/// القسم 11). تعرض فقط مؤشرات لها مصدر بيانات حقيقي فعليًا بالنظام - بلا
/// أي رقم وهمي (مثل "إجمالي الطلبة" غير المتوفر أصلاً بهذا النظام).
class AdminExecutiveDashboardScreen extends StatelessWidget {
  const AdminExecutiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'لوحة الإدارة',
      showBackButton: false,
      navItems: buildAdminNavItems(context, current: 'dashboard'),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchAllTickets(),
        builder: (context, ticketsSnap) {
          final tickets = ticketsSnap.data ?? [];
          return FutureBuilder<List<AdvisorRosterEntry>>(
            future: AdvisorRosterService.loadAll(),
            builder: (context, rosterSnap) {
              final roster = rosterSnap.data ?? [];
              final stats = TicketActionStatsService.build(tickets);
              final activeAdvisors = roster.where((a) => !a.isOnLeave).length;
              final needsAttention = stats.advisorMismatchCount + stats.priorityPendingCount;
              final overallRate =
                  stats.totalActions == 0 ? 0.0 : _overallCompletionRate(tickets);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final cards = [
                      _KpiCard(
                        label: 'طلبات الحذف والإضافة',
                        value: '${stats.totalTickets}',
                        icon: Icons.assignment_outlined,
                        accent: AppColors.greenDark,
                      ),
                      _KpiCard(
                        label: 'نسبة إنجاز الحذف والإضافة',
                        value: '${(overallRate * 100).round()}%',
                        icon: Icons.track_changes_outlined,
                        accent: overallRate >= 0.5 ? const Color(0xFF2E7D32) : AppColors.errorRed,
                      ),
                      _KpiCard(
                        label: 'مرشدون أكاديميون نشطون',
                        value: '$activeAdvisors',
                        icon: Icons.groups_outlined,
                        accent: AppColors.gold,
                      ),
                      _KpiCard(
                        label: 'حالات تحتاج متابعة',
                        value: '$needsAttention',
                        icon: Icons.flag_outlined,
                        accent: AppColors.errorRed,
                      ),
                    ];
                    final columns = constraints.maxWidth < 700
                        ? 1
                        : constraints.maxWidth < 1100
                            ? 2
                            : 4;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in cards)
                          SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns, child: c),
                      ],
                    );
                  }),
                  const SizedBox(height: 22),
                  const Text(
                    'روابط سريعة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.greenDark),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final links = [
                      _QuickLink(
                        label: 'الحذف والإضافة',
                        icon: Icons.assignment_outlined,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const AdminWorkspaceScreen())),
                      ),
                      _QuickLink(
                        label: 'لوحة الإرشاد',
                        icon: Icons.fact_check_outlined,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const AdvisingHubScreen())),
                      ),
                      _QuickLink(
                        label: 'خدمات أكاديمية',
                        icon: Icons.school_outlined,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const AcademicServicesHubScreen())),
                      ),
                      _QuickLink(
                        label: 'المنسوبين',
                        icon: Icons.badge_outlined,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const CollegeRosterAdminScreen())),
                      ),
                      _QuickLink(
                        label: 'رفع ملفات',
                        icon: Icons.cloud_upload_outlined,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const UploadHubScreen())),
                      ),
                      _QuickLink(
                        label: 'تقارير',
                        icon: Icons.assessment_outlined,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const ReportsHubScreen())),
                      ),
                    ];
                    final columns = constraints.maxWidth < 500
                        ? 2
                        : constraints.maxWidth < 900
                            ? 3
                            : 6;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final l in links)
                          SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns, child: l),
                      ],
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  double _overallCompletionRate(List<Map<String, dynamic>> tickets) {
    var total = 0, completed = 0;
    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final action in actions) {
        total++;
        final advisorStatus = (action['advisor_status'] ?? '').toString().trim();
        final coordinatorStatus = (action['coordinator_status'] ?? '').toString().trim();
        final collegeStatus = (action['college_status'] ?? '').toString().trim();
        if (collegeStatus == 'تم الإنجاز' || coordinatorStatus == 'تم الإنجاز' || advisorStatus == 'تم الإنجاز') {
          completed++;
        }
      }
    }
    return total == 0 ? 0.0 : completed / total;
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 2),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: accent),
          ),
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickLink({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.goldLight),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.greenDark, size: 26),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
