import 'firestore_ticket_service.dart';
import 'report_data_service.dart' show effectiveStatus, isCompletedStatus;

/// إحصائيات "التحول الرقمي" لطلبات الحذف والإضافة - تعتمد حصرًا على الحقول
/// الفعلية المتاحة بالبيانات (`uploaded_date` بكل تذكرة، وحقول الحالة
/// الثلاثة بكل إجراء) بلا أي بيانات وهمية أو مُخترَعة:
///
/// **تصنيف القناة** (نموذج Microsoft Forms مقابل النموذج الورقي):
/// - `uploaded_date` تاريخ حقيقي بصيغة yyyy-MM-dd = دخلت عبر رفع ملف
///   Microsoft Forms (راجع `FirestoreTicketService.replaceAllTickets`/
///   `addNewTickets` - يُكتَب لحظة الرفع، ولا يُعاد كتابته لاحقًا).
/// - `uploaded_date` تساوي `FirestoreTicketService.paperFormUploadedDateLabel`
///   = تذكرة أُنشئت تلقائيًا من صف معالجة غير مطابَق لأي طلب Forms (طالب لم
///   يُقدّم عبر النموذج الإلكتروني أصلاً - حالة نموذج ورقي).
/// لا يوجد أي حقل "منظومة داخلية"/"الموقع نفسه" بالبيانات الفعلية حاليًا.
///
/// **التطور اليومي عبر أيام فترة الحذف والإضافة**: نفس حقل `uploaded_date`
/// (تاريخ فعلي، لا منطق تقسيم أيام مُخترَع) يحدّد يوم تقديم كل طلب. كل قيمة
/// تاريخ مميّزة ظهرت فعليًا بالبيانات = "يوم" فترة حقيقي (اليوم الأول هو أول
/// تاريخ رفع ظهر، وهكذا) - **هذا حقل تخزين أصلي موجود مسبقًا في كل تذكرة،
/// وليس إعادة استخدام لمنطق "تقسيم الأيام" الذي أُزيل من ملفات المرشد
/// (commit 13b936e) - ذاك كان عرضًا تصعيديًا للمرشد نفسه أُزيل لتفادي
/// تضليله، لا حذفًا للحقل من البيانات**.
///
/// **لا يوجد أي حقل توقيت اعتماد/إنجاز** (فقط تاريخ الرفع الأول لكل تذكرة،
/// لا لكل إجراء، ولا يُسجَّل تاريخ تغيّر حالة). لذلك:
/// - لا يمكن حساب "متوسط زمن الإنجاز" بمصداقية - لم يُحسَب هنا إطلاقًا.
/// - "نسبة إنجاز/استجابة يوم X" أدناه تعني **الحالة الآنية الحالية** لكل
///   الإجراءات التي *قُدِّمت* في ذلك اليوم (لا الحالة وقت ذلك اليوم نفسه -
///   غير متاحة) - مؤشر مُقارَنة بين أفواج الأيام الثلاثة صادق لكنه ليس "زمن
///   إنجاز" حقيقيًا، ويُعرَض بعنوان واضح لا يوحي بغير ذلك.
class ChannelCount {
  final String label;
  int ticketCount = 0;
  int completedActions = 0;
  int totalActions = 0;

  ChannelCount(this.label);

  double get completionRate => totalActions == 0 ? 0 : completedActions / totalActions;
}

/// إحصائيات فوج طلبات يوم واحد من أيام فترة الحذف والإضافة - مبنيّة على
/// `uploaded_date` الفعلي لكل تذكرة، بلا أي تقسيم مُفترَض.
class DailyCohortStats {
  final String date;
  final String dayLabel;
  int ticketCount = 0;
  int actionCount = 0;
  // حالة الإنجاز *الآن* لإجراءات هذا الفوج (وليست حالتها في نفس يوم التقديم
  // - غير متاحة لعدم وجود توقيت اعتماد مخزَّن).
  int completedActionsNow = 0;
  // عدد الإجراءات التي كتب المرشد لها حالة *الآن* (بصرف النظر عن مضمونها) -
  // مؤشّر استجابة المرشد لهذا الفوج.
  int advisorRespondedActionsNow = 0;

  DailyCohortStats(this.date, this.dayLabel);

  double get completionRateNow => actionCount == 0 ? 0 : completedActionsNow / actionCount;
  double get advisorResponseRateNow => actionCount == 0 ? 0 : advisorRespondedActionsNow / actionCount;
}

class DigitalTransformationStats {
  final int totalTickets;
  final ChannelCount forms = ChannelCount('نموذج Microsoft Forms الإلكتروني');
  final ChannelCount paperForm = ChannelCount('النموذج الورقي');
  final List<DailyCohortStats> dailyCohorts;

  DigitalTransformationStats({
    required this.totalTickets,
    required this.dailyCohorts,
  });

  int get formsTicketCount => forms.ticketCount;
  int get paperTicketCount => paperForm.ticketCount;

  double get digitalSharePercent =>
      totalTickets == 0 ? 0 : forms.ticketCount / totalTickets * 100;
}

class DigitalTransformationStatsService {
  static bool _isPaperForm(Map<String, dynamic> ticket) {
    return (ticket['uploaded_date'] ?? '').toString() == FirestoreTicketService.paperFormUploadedDateLabel;
  }

  static final RegExp _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static DigitalTransformationStats build(List<Map<String, dynamic>> tickets) {
    final forms = ChannelCount('نموذج Microsoft Forms الإلكتروني');
    final paperForm = ChannelCount('النموذج الورقي');
    final cohortsByDate = <String, DailyCohortStats>{};

    for (final ticket in tickets) {
      final isPaper = _isPaperForm(ticket);
      final channel = isPaper ? paperForm : forms;
      channel.ticketCount++;

      final uploadedDate = (ticket['uploaded_date'] ?? '').toString();
      final isRealDate = !isPaper && _isoDatePattern.hasMatch(uploadedDate);

      final actions = (ticket['actions'] as List?) ?? const [];
      DailyCohortStats? cohort;
      if (isRealDate) {
        cohort = cohortsByDate.putIfAbsent(uploadedDate, () => DailyCohortStats(uploadedDate, uploadedDate));
        cohort.ticketCount++;
      }

      for (final raw in actions) {
        final action = Map<String, dynamic>.from(raw as Map);
        channel.totalActions++;
        final completed = isCompletedStatus(effectiveStatus(action));
        if (completed) channel.completedActions++;

        if (cohort != null) {
          cohort.actionCount++;
          if (completed) cohort.completedActionsNow++;
          if ((action['advisor_status'] ?? '').toString().trim().isNotEmpty) {
            cohort.advisorRespondedActionsNow++;
          }
        }
      }
    }

    final sortedDates = cohortsByDate.keys.toList()..sort();
    final dailyCohorts = <DailyCohortStats>[];
    for (var i = 0; i < sortedDates.length; i++) {
      final raw = cohortsByDate[sortedDates[i]]!;
      dailyCohorts.add(DailyCohortStats(raw.date, 'اليوم ${i + 1} (${raw.date})')
        ..ticketCount = raw.ticketCount
        ..actionCount = raw.actionCount
        ..completedActionsNow = raw.completedActionsNow
        ..advisorRespondedActionsNow = raw.advisorRespondedActionsNow);
    }

    final stats = DigitalTransformationStats(totalTickets: tickets.length, dailyCohorts: dailyCohorts);
    stats.forms
      ..ticketCount = forms.ticketCount
      ..totalActions = forms.totalActions
      ..completedActions = forms.completedActions;
    stats.paperForm
      ..ticketCount = paperForm.ticketCount
      ..totalActions = paperForm.totalActions
      ..completedActions = paperForm.completedActions;
    return stats;
  }
}
