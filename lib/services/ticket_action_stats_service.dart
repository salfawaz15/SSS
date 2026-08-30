import '../data/academic_department_names.dart';
import 'report_data_service.dart' show StatusCounts, effectiveStatus, isCompletedStatus;

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

/// عدّادات مرشد واحد (بطلب سليمان: عدد الحالات، المنجزة، المحوَّلة لمنسّق
/// القسم، ولم يُعمَل عليها إطلاقًا) - أدق من [AdvisorReport] بـ
/// report_data_service.dart (الذي يقيس فقط "اشتغل/لم يشتغل" على عمود حالة
/// المرشد وحده)، لأن هذا يميّز أيضًا هل صُعِّدت الحالة لمنسّق القسم أم لا.
class AdvisorCaseStats {
  final String advisorName;
  final String department;
  final String shatr;
  int total = 0;
  int completed = 0;
  int escalatedToCoordinator = 0;
  int notStarted = 0;

  AdvisorCaseStats({required this.advisorName, required this.department, required this.shatr});
}

/// أداء قسم/شطر واحد مجمَّعًا من كل مرشديه - أساس "تقرير الأداء اليومي"
/// المُرسَل لعمادة الكلية (سليمان صراحةً 2026-08-30): يقارن الأقسام ببعضها
/// لتحفيزها، بنفس تعريف "الإنجاز" المعتمَد (باشر الحالة، لا "تم التنفيذ" فقط).
class DeptShatrPerformance {
  final String department;
  final String shatr;
  int total = 0;
  int completed = 0;
  int escalatedToCoordinator = 0;
  int notStarted = 0;

  DeptShatrPerformance({required this.department, required this.shatr});

  double get completionRate => total == 0 ? 0 : completed / total;
}

/// عدّادات نوع إجراء واحد (إضافة/حذف/تعديل) بنفس تصنيف [AdvisorCaseStats]
/// الثلاثي (منجز/مصعَّد لمنسّق/لم يُعمل عليه إطلاقًا) - أساس صف "عدد الحالات
/// الكاملة" بتقرير الأداء اليومي (بطلب سليمان صراحةً 2026-08-30).
class ActionTypeCaseCounts {
  int total = 0;
  int completed = 0;
  int escalatedToCoordinator = 0;
  int notStarted = 0;
}

class TicketActionStatsService {
  /// يجمّع أداء كل مرشدي نفس القسم/الشطر معًا بصف واحد - يُستخدم لترتيب
  /// الأقسام ببعضها بتقرير الأداء اليومي (لا لعرض كل مرشد منفردًا).
  static List<DeptShatrPerformance> aggregateByDepartmentShatr(List<AdvisorCaseStats> advisors) {
    final byKey = <String, DeptShatrPerformance>{};
    for (final a in advisors) {
      final key = '${a.shatr}|${a.department}';
      final perf = byKey.putIfAbsent(key, () => DeptShatrPerformance(department: a.department, shatr: a.shatr));
      perf.total += a.total;
      perf.completed += a.completed;
      perf.escalatedToCoordinator += a.escalatedToCoordinator;
      perf.notStarted += a.notStarted;
    }
    return byKey.values.toList()..sort((a, b) => b.completionRate.compareTo(a.completionRate));
  }


  static List<AdvisorCaseStats> buildAdvisorCaseStats(List<Map<String, dynamic>> tickets) {
    final byAdvisor = <String, AdvisorCaseStats>{};

    for (final ticket in tickets) {
      final advisorName = (ticket['advisor'] ?? '').toString().trim();
      if (advisorName.isEmpty) continue;
      final department = normalizeDepartmentName((ticket['department'] ?? '').toString());
      final shatr = (ticket['shatr'] ?? '').toString();
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

      final stats = byAdvisor.putIfAbsent(
        advisorName,
        () => AdvisorCaseStats(advisorName: advisorName, department: department, shatr: shatr),
      );

      for (final action in actions) {
        stats.total++;
        final advisorStatus = (action['advisor_status'] ?? '').toString().trim();
        final coordinatorStatus = (action['coordinator_status'] ?? '').toString().trim();
        final collegeStatus = (action['college_status'] ?? '').toString().trim();

        // "إنجاز" المرشد = باشر الحالة بأي قيمة (تم التنفيذ أو لم يتم
        // التنفيذ فصُعِّدت) - لا يعني "تم التنفيذ" فقط. "عدم الإنجاز" =
        // لم يباشرها إطلاقًا (حالته فارغة)، بصرف النظر عمّن عالجها لاحقًا
        // (سليمان صراحةً 2026-08-30، بعد أن ظهرت نسبة إنجاز 0% لمرشدين
        // باشروا فعليًا حالاتهم بـ"لم يتم التنفيذ").
        if (advisorStatus.isNotEmpty) {
          stats.completed++;
        } else if (coordinatorStatus.isNotEmpty || collegeStatus.isNotEmpty) {
          stats.escalatedToCoordinator++;
        } else {
          stats.notStarted++;
        }
      }
    }

    return byAdvisor.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  /// نفس تصنيف [buildAdvisorCaseStats] الثلاثي لكن مجمَّعًا حسب نوع الإجراء
  /// (إضافة/حذف/تعديل) بدل المرشد - "عدد الحالات الكاملة" = مجموع الثلاثة.
  static Map<String, ActionTypeCaseCounts> buildActionTypeCaseStats(List<Map<String, dynamic>> tickets) {
    final byType = <String, ActionTypeCaseCounts>{};

    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final action in actions) {
        final actionType = (action['action_type'] ?? '').toString().trim();
        if (actionType.isEmpty) continue;
        final counts = byType.putIfAbsent(actionType, () => ActionTypeCaseCounts());
        counts.total++;

        final advisorStatus = (action['advisor_status'] ?? '').toString().trim();
        final coordinatorStatus = (action['coordinator_status'] ?? '').toString().trim();
        final collegeStatus = (action['college_status'] ?? '').toString().trim();
        if (advisorStatus.isNotEmpty) {
          counts.completed++;
        } else if (coordinatorStatus.isNotEmpty || collegeStatus.isNotEmpty) {
          counts.escalatedToCoordinator++;
        } else {
          counts.notStarted++;
        }
      }
    }

    return byType;
  }

  static TicketActionStats build(List<Map<String, dynamic>> tickets) {
    final byActionType = <String, ActionTypeStats>{};
    final byDepartmentShatr = <String, Map<String, int>>{};
    var totalActions = 0;
    var advisorMismatchCount = 0;
    var advisorUnverifiedCount = 0;
    var priorityPendingCount = 0;

    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final department = normalizeDepartmentName((ticket['department'] ?? '').toString());
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

        if (!isCompletedStatus(effectiveStatus(action))) ticketHasPending = true;
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
