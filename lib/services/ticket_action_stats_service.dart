import 'report_data_service.dart' show StatusCounts, effectiveStatus;

/// عدّادات نوع إجراء واحد (إضافة/حذف/تعديل): العدد الكلي + توزيع حالة
/// الإنجاز (تصعيديًا مرشد ← منسق قسم ← منسق كلية، عبر effectiveStatus
/// الموجودة أصلاً بـreport_data_service.dart).
class ActionTypeStats {
  int total = 0;
  final StatusCounts statusCounts = StatusCounts();
}

/// إحصائيات طلبات الحذف/الإضافة/تعديل الشعب (مختلفة تمامًا عن
/// [ReportDataService] المخصَّص لتقارير متابعة إنجاز الإرشاد) - يُبنى مرة
/// واحدة من قائمة التذاكر الخام (FirestoreTicketService.watchAllTickets)
/// ويُستهلَك من TicketActionStatsPanel بلوحة الإدارة.
class TicketActionStats {
  final int totalTickets;
  final int totalActions;
  final Map<String, ActionTypeStats> byActionType;
  // مفتاح: 'شطر|قسم' - القيمة: عدد كل نوع إجراء ضمن تلك التوليفة
  final Map<String, Map<String, int>> byDepartmentShatr;
  final int advisorMismatchCount;
  final int advisorUnverifiedCount;
  final int priorityPendingCount;

  const TicketActionStats({
    required this.totalTickets,
    required this.totalActions,
    required this.byActionType,
    required this.byDepartmentShatr,
    required this.advisorMismatchCount,
    required this.advisorUnverifiedCount,
    required this.priorityPendingCount,
  });
}

class TicketActionStatsService {
  static TicketActionStats build(List<Map<String, dynamic>> tickets) {
    final byActionType = <String, ActionTypeStats>{};
    final byDepartmentShatr = <String, Map<String, int>>{};
    var totalActions = 0;
    var advisorMismatchCount = 0;
    var advisorUnverifiedCount = 0;
    var priorityPendingCount = 0;

    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final department = (ticket['department'] ?? '').toString();
      final shatr = (ticket['shatr'] ?? '').toString();
      final key = '$shatr|$department';

      var ticketHasPending = false;
      for (final action in actions) {
        totalActions++;
        final type = (action['action_type'] ?? '').toString();
        if (type.isEmpty) continue;

        final stats = byActionType.putIfAbsent(type, () => ActionTypeStats());
        stats.total++;
        stats.statusCounts.addStatus(effectiveStatus(action));

        final deptCounts = byDepartmentShatr.putIfAbsent(key, () => {});
        deptCounts[type] = (deptCounts[type] ?? 0) + 1;

        if (effectiveStatus(action) != 'تم الإنجاز') ticketHasPending = true;
      }

      final advisorCorrected = ticket['advisor_corrected'];
      if (advisorCorrected == true) {
        advisorMismatchCount++;
      } else if (advisorCorrected == null) {
        advisorUnverifiedCount++;
      }

      final isPriority = ticket['expected_graduate'] == true || ticket['has_disability'] == true;
      if (isPriority && ticketHasPending) priorityPendingCount++;
    }

    return TicketActionStats(
      totalTickets: tickets.length,
      totalActions: totalActions,
      byActionType: byActionType,
      byDepartmentShatr: byDepartmentShatr,
      advisorMismatchCount: advisorMismatchCount,
      advisorUnverifiedCount: advisorUnverifiedCount,
      priorityPendingCount: priorityPendingCount,
    );
  }
}
