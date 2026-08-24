import '../../../services/advising_overview_stats_service.dart';
import '../../../services/firestore_ticket_service.dart';
import '../../../services/ticket_action_stats_service.dart';
import '../../../services/ticket_workflow_stats_service.dart';

/// إحصائيات قسم "الحذف والإضافة" بالرئيسية - نفس صيغة بطاقات الموقع
/// ("إجمالي الحالات"/"نسبة الإنجاز العامة"/طلبات إضافة/حذف/تعديل) من نفس
/// مصادر `ticket_workflow_stats_service.dart`/`ticket_action_stats_service.dart`.
class DeleteAddOverview {
  final int totalCases;
  final int completionPercent;
  final int addCount;
  final int deleteCount;
  final int editCount;

  const DeleteAddOverview({
    required this.totalCases,
    required this.completionPercent,
    required this.addCount,
    required this.deleteCount,
    required this.editCount,
  });
}

class DeleteAddOverviewController {
  static Stream<DeleteAddOverview> watch() {
    return FirestoreTicketService.watchAllTickets().map((tickets) {
      final kpi = computeTicketKpiStats(tickets);
      final byType = TicketActionStatsService.build(tickets).byActionType;
      return DeleteAddOverview(
        totalCases: tickets.length,
        completionPercent: ticketCompletionPercent(kpi.totalCompleted, kpi.totalRequests),
        addCount: byType['إضافة']?.total ?? 0,
        deleteCount: byType['حذف']?.total ?? 0,
        editCount: byType['تعديل']?.total ?? 0,
      );
    });
  }
}

/// إحصائيات قسم "مؤشرات رئيسية لحالات الإرشاد" - `Future` لا `Stream` (مصدرها
/// تقارير مرفوعة تُقرأ مرة واحدة، لا تحديث لحظي كالتذاكر) عبر
/// `AdvisingOverviewStatsService` المُستخرَجة من نفس منطق الموقع.
class AdvisingOverviewController {
  static Future<AdvisingOverviewStats> load() => AdvisingOverviewStatsService.load();
}
