import 'package:flutter/material.dart';

import '../models/advisor_roster_entry.dart';
import '../services/advisor_roster_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/report_data_service.dart';
import '../theme/app_theme.dart';
import 'follow_up_chart.dart';
import 'portal_cards.dart';

/// محتوى "لوحة الإدارة" الجوّالة لحساب المدير العام (`salfawaz`) - **مطابقة
/// كاملة لمحتوى الصفحة الفعلي بالموقع** (`admin_workspace_screen.dart`):
/// نفس بطاقات الإحصاء الثلاث (إجمالي الحالات/الأقسام النشطة/نسبة الإنجاز)
/// من نفس `ReportDataService`، ثم نفس `FollowUpChart` (رسم متابعة الإنجاز
/// الدائري + فلاتر شطر/قسم + ترتيب المرشدين) - **بلا Scaffold/AppBar خاص
/// بها** (2026-08-16): تُضمَّن داخل `IndexedStack` بـ`mobile_home_screen.dart`
/// حتى يبقى الشريطان العلوي والسفلي ثابتين عند التبديل بين التبويبات.
///
/// بطلب سليمان صراحةً (2026-08-16): "أبغى أشاهد صفحة الأدمن كاملة متكاملة
/// مثل الموقع تمامًا". `FollowUpChart` نفسه (لا نسخة مختصرة) لأنه مبني
/// أصلًا بتخطيط متجاوب (`LayoutBuilder`/`Wrap`) يتكيّف مع عرض جوال ضيق -
/// خلافًا لشاشات أخرى دُفعت سابقًا هذه الجلسة بلا أي تكيّف فسبَّبت صفحات
/// مكسورة.
class MobileAdminDashboardBody extends StatefulWidget {
  const MobileAdminDashboardBody({super.key});

  @override
  State<MobileAdminDashboardBody> createState() => _MobileAdminDashboardBodyState();
}

class _MobileAdminDashboardBodyState extends State<MobileAdminDashboardBody> {
  List<AdvisorRosterEntry> _roster = [];

  @override
  void initState() {
    super.initState();
    AdvisorRosterService.loadAll().then((r) {
      if (mounted) setState(() => _roster = r);
    });
  }

  Widget _buildDashboardCards(ReportData data, int totalCases, int activeDepartments) {
    final rate = (data.overall.completionRate * 100).toStringAsFixed(0);
    final tiles = [
      (label: 'إجمالي الحالات', value: '$totalCases', icon: Icons.folder_copy_outlined, color: AppColors.greenDark),
      (label: 'الأقسام النشطة', value: '$activeDepartments', icon: Icons.apartment_rounded, color: AppColors.gold),
      (label: 'نسبة الإنجاز', value: '$rate%', icon: Icons.trending_up_rounded, color: AppColors.green),
    ];
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          PortalStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accentColor: tiles[i].color),
          if (i < tiles.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreTicketService.watchAllTickets(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذّر تحميل بيانات لوحة الإدارة: ${snapshot.error}', textAlign: TextAlign.center),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tickets = snapshot.data!;
        final data = ReportDataService.build(tickets, roster: _roster);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildDashboardCards(data, tickets.length, tickets.map((t) => t['department']).toSet().length),
            FollowUpChart(
              data: data,
              tickets: tickets,
              roster: _roster,
              showShatrFilter: true,
              showDepartmentFilter: true,
            ),
          ],
        );
      },
    );
  }
}
