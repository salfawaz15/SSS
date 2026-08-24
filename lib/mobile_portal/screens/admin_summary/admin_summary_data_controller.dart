import '../../../services/firestore_ticket_service.dart';
import '../../../services/report_data_service.dart';
import '../../../services/ticket_action_stats_service.dart';
import '../../../services/ticket_workflow_stats_service.dart';

/// بيانات "لوحة الإدارة" المختصرة بتبويب "لوحة الإدارة" - نفس مصدر لوحة
/// الإدارة بالموقع (`FirestoreTicketService.watchAllTickets()` +
/// `ReportDataService`/`ticket_workflow_stats_service.dart`/
/// `ticket_action_stats_service.dart`) بلا أي حساب مستقل جديد (القسم 37:
/// عدم تكرار منطق الأعمال). تجمع كل تفاصيل قسم "الحذف والإضافة" التي كانت
/// موزَّعة سابقًا بين الرئيسية وهذا التبويب - نُقلت إلى هنا حصرًا (سليمان
/// 2026-08-23: الرئيسية لمحة سريعة فقط، لوحة الإدارة كل التفصيل).
class AdminSummaryData {
  final int totalCases;
  final ReportData report;
  // تقدّم المرشدين الأكاديميين تحديدًا (منجزة/لم يُعمَل عليها/محوَّلة لمنسّق
  // القسم) - أهم جزء بقسم "الحذف والإضافة" بلوحة الإدارة بحسب سليمان صراحةً
  // (2026-08-23).
  final TicketRoleProgress advisorProgress;
  final List<TicketRoleProgress> roleProgress;
  final Map<String, ActionTypeStats> actionTypeStats;
  final int exceededCount;

  const AdminSummaryData({
    required this.totalCases,
    required this.report,
    required this.advisorProgress,
    required this.roleProgress,
    required this.actionTypeStats,
    required this.exceededCount,
  });

  int get activeDepartmentsCount => report.departments.where((d) => d.counts.total > 0).length;
}

class AdminSummaryDataController {
  static Stream<AdminSummaryData> watch() {
    return FirestoreTicketService.watchAllTickets().map((tickets) {
      final roleProgress = computeTicketRoleProgress(tickets);
      return AdminSummaryData(
        totalCases: tickets.length,
        report: ReportDataService.build(tickets),
        advisorProgress: roleProgress.first,
        roleProgress: roleProgress,
        actionTypeStats: TicketActionStatsService.build(tickets).byActionType,
        exceededCount: computeExceededWorkflowCount(tickets),
      );
    });
  }
}
