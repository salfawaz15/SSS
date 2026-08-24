import 'report_data_service.dart' show isCompletedStatus;

/// حسابات مسار سير عمل التذاكر (تذاكر `tickets` بمعالجاتها الثلاث: مرشد
/// أكاديمي ← منسّق قسم ← منسّق كلية) - مصدر واحد مشترك بين لوحة الإدارة
/// بالموقع (`admin_executive_dashboard_screen.dart`) وتطبيق "بوابة الإرشاد"
/// الجوّالة الجديد، حتى لا يختلف رقم بين الاثنين (القسم 37 من مواصفات
/// التطبيق الجديد: عدم تكرار منطق الأعمال). استُخرجت من المنطق الخاص
/// الموجود أصلًا داخل شاشة لوحة الإدارة (كان بدوال/أصناف مسبوقة بـ`_` لا
/// يمكن استيرادها من ملف آخر) بلا أي تغيير في نتيجة الحساب نفسها.

/// أين إجراء واحد الآن بمسار سير العمل - راجع نفس المنطق بلوحة الإدارة.
enum TicketActionStage { advisor, deptReview, collegeReview, closed }

/// أعلى أعمدة حالة (`advisor_status`/`coordinator_status`/`college_status`)
/// عن "تم الإنجاز فعليًا" - نفس القيمة المعتمدة بـ`FirestoreTicketService`
/// و`excel_export_service.dart`.
const kTicketCompletedMarker = 'تم الإنجاز';

/// قيمة "تم" الخاصة بعمود المرشد الأكاديمي تحديدًا (قائمته المنسدلة ثنائية:
/// تم التنفيذ/لم يتم التنفيذ، بخلاف عمودي منسق القسم/الكلية اللذين ما زالا
/// يستخدمان [kTicketCompletedMarker]).
const kTicketAdvisorCompletedMarker = 'تم التنفيذ';

TicketActionStage ticketActionStageOf(Map<String, dynamic> action) {
  final advisorStatus = (action['advisor_status'] ?? '').toString();
  final coordinatorStatus = (action['coordinator_status'] ?? '').toString();
  final collegeStatus = (action['college_status'] ?? '').toString();

  if (collegeStatus == kTicketCompletedMarker) return TicketActionStage.closed;
  if (coordinatorStatus == kTicketCompletedMarker) return TicketActionStage.collegeReview;
  if (advisorStatus == kTicketAdvisorCompletedMarker || advisorStatus == kTicketCompletedMarker) {
    return TicketActionStage.deptReview;
  }
  return TicketActionStage.advisor;
}

/// نتيجة إجراء واحد مستقل لعمود حالة معيّن - ثلاث حالات فقط بلا "تنفيذ
/// جزئي" (كل صف بملف Excel = حالة/إجراء مستقل كامل). `escalated` تعني "لم
/// يُنفَّذ بهذا المستوى فانتقلت للمستوى التالي" - ليست بالضرورة رفضًا.
enum TicketActionOutcome { complete, escalated, notStarted }

TicketActionOutcome ticketActionOutcomeForField(Map<String, dynamic> action, String statusField) {
  final status = (action[statusField] ?? '').toString().trim();
  if (status.isEmpty) return TicketActionOutcome.notStarted;
  if (isCompletedStatus(status)) return TicketActionOutcome.complete;
  return TicketActionOutcome.escalated;
}

/// نتيجة إجراءات دور واحد (مرشد/منسّق قسم/منسّق كلية) على مستوى كل
/// إجراء/صف مستقل بمفرده.
class TicketRoleProgress {
  final String role;
  final Map<TicketActionOutcome, int> breakdown;
  const TicketRoleProgress({required this.role, required this.breakdown});

  int get total => breakdown.values.fold(0, (a, b) => a + b);
  int get complete => breakdown[TicketActionOutcome.complete] ?? 0;
  int get escalated => breakdown[TicketActionOutcome.escalated] ?? 0;
  int get notStarted => breakdown[TicketActionOutcome.notStarted] ?? 0;
}

List<TicketRoleProgress> computeTicketRoleProgress(List<Map<String, dynamic>> tickets) {
  final advisor = {for (final o in TicketActionOutcome.values) o: 0};
  final coordinator = {for (final o in TicketActionOutcome.values) o: 0};
  final college = {for (final o in TicketActionOutcome.values) o: 0};

  for (final ticket in tickets) {
    final actions = (ticket['actions'] as List?) ?? const [];
    for (final raw in actions) {
      final action = Map<String, dynamic>.from(raw as Map);
      final advisorOutcome = ticketActionOutcomeForField(action, 'advisor_status');
      advisor[advisorOutcome] = (advisor[advisorOutcome] ?? 0) + 1;
      final coordinatorOutcome = ticketActionOutcomeForField(action, 'coordinator_status');
      coordinator[coordinatorOutcome] = (coordinator[coordinatorOutcome] ?? 0) + 1;
      final collegeOutcome = ticketActionOutcomeForField(action, 'college_status');
      college[collegeOutcome] = (college[collegeOutcome] ?? 0) + 1;
    }
  }

  return [
    TicketRoleProgress(role: 'المرشدون الأكاديميون', breakdown: advisor),
    TicketRoleProgress(role: 'منسّقو الأقسام العلمية', breakdown: coordinator),
    TicketRoleProgress(role: 'منسّقو الكلية', breakdown: college),
  ];
}

class TicketKpiStats {
  final int totalRequests;
  final int totalCompleted;
  // عدد الطلاب الذين تخطّى المرشد حالتهم كليًا (لم يعمل على أي إجراء لها) لكن
  // أُنجز لاحقًا عند منسّق القسم أو منسّق الكلية.
  final int advisorSkippedCount;
  const TicketKpiStats({required this.totalRequests, required this.totalCompleted, required this.advisorSkippedCount});

  double get completionRate => totalRequests == 0 ? 0 : totalCompleted / totalRequests;
}

TicketKpiStats computeTicketKpiStats(List<Map<String, dynamic>> tickets) {
  var total = 0, completed = 0;
  var advisorSkipped = 0;
  for (final ticket in tickets) {
    final actions = (ticket['actions'] as List?) ?? const [];
    for (final raw in actions) {
      final action = Map<String, dynamic>.from(raw as Map);
      total++;
      if (ticketActionStageOf(action) == TicketActionStage.closed) completed++;
      if (isTicketActionSkippedByAdvisor(action)) advisorSkipped++;
    }
  }
  return TicketKpiStats(totalRequests: total, totalCompleted: completed, advisorSkippedCount: advisorSkipped);
}

/// هل تجاوز هذا الإجراء المستقل مستوى المرشد دون أن يعمل عليه؟ - المرشد لم
/// يعمل عليه إطلاقًا (حالته فارغة)، لكن منسّق القسم أو منسّق الكلية أنجزا/
/// عالجا شيئًا فيه.
bool isTicketActionSkippedByAdvisor(Map<String, dynamic> action) {
  if (ticketActionOutcomeForField(action, 'advisor_status') != TicketActionOutcome.notStarted) return false;
  return ticketActionOutcomeForField(action, 'coordinator_status') != TicketActionOutcome.notStarted ||
      ticketActionOutcomeForField(action, 'college_status') != TicketActionOutcome.notStarted;
}

/// نفس فكرة [isTicketActionSkippedByAdvisor] لمنسّق القسم - لم يعمل على هذا
/// الإجراء إطلاقًا، لكن منسّق الكلية عالج شيئًا فيه بدلًا عنه.
bool isTicketActionSkippedByCoordinator(Map<String, dynamic> action) {
  if (ticketActionOutcomeForField(action, 'coordinator_status') != TicketActionOutcome.notStarted) return false;
  return ticketActionOutcomeForField(action, 'college_status') != TicketActionOutcome.notStarted;
}

/// إجمالي "حالات تجاوزت مستوى المعالجة دون إجراء" - إجراءات تخطّاها المرشد
/// أو منسّق القسم كليًا لكن أُنجزت/عولجت بمستوى تالٍ بدلًا عنهما. نفس مصدر
/// بطاقة "حالات تجاوزت مستوى المعالجة" بلوحة الإدارة (منسّق الكلية غير
/// مُتابَع هنا - جهة تنفيذية بلا مهلة زمنية).
int computeExceededWorkflowCount(List<Map<String, dynamic>> tickets) {
  var count = 0;
  for (final ticket in tickets) {
    final actions = (ticket['actions'] as List?) ?? const [];
    for (final raw in actions) {
      final action = Map<String, dynamic>.from(raw as Map);
      if (isTicketActionSkippedByAdvisor(action) || isTicketActionSkippedByCoordinator(action)) count++;
    }
  }
  return count;
}

/// نسبة إنجاز صحيحة - تقريب عادي (round) لكن بسقف صارم: لا تظهر 100% إلا
/// عند اكتمال حقيقي تام (completed == total). نفس منطق
/// `admin_executive_dashboard_screen.completionPercent` - مصدر واحد مشترك.
int ticketCompletionPercent(int completed, int total) {
  if (total == 0) return 0;
  if (completed == total) return 100;
  final pct = (completed / total * 100).round();
  return pct >= 100 ? 99 : pct;
}
