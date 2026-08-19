import '../models/advising_case_record.dart';
import 'advisor_name_matching.dart';

/// يصحّح حقل 'advisor' في تذاكر [ExcelParserService.parseTickets] ليعتمد
/// دائمًا على المرشد الفعلي المسجَّل بتقرير الإرشاد الرسمي (allColleges)
/// بدل ما اختاره الطالب يدويًا في Microsoft Forms - فالطالب قد يخطئ باختيار
/// مرشد غير مرشده الحقيقي، والقرار المتفق عليه مع سليمان هو ألا يُترك ذلك
/// للطالب: يُحفَظ اختياره فقط كمرجع تحت 'selected_advisor' بينما يُستخدَم
/// المرشد الفعلي في التوزيع والعرض تلقائيًا (بلا أي تعديل على الشاشات أو
/// خدمات التوزيع، لأنها كلها تقرأ 'advisor' كالمعتاد).
class AdvisorCorrectionService {
  /// [records] يجب أن تكون آخر نسخة من تقرير الإرشاد (allColleges) لكلا
  /// الشطرين مجتمعة - تُحمَّل مرة واحدة عبر
  /// AdvisingReportRepository.load(shatr, kind: AdvisingReportKind.allColleges)
  /// من نقطة الاستدعاء قبل تمرير التذاكر هنا.
  static List<Map<String, dynamic>> applyAdvisorCorrection(
    List<Map<String, dynamic>> tickets,
    List<AdvisingCaseRecord> records,
  ) {
    final byStudentId = <String, AdvisingCaseRecord>{
      for (final r in records)
        if (r.studentId.trim().isNotEmpty) r.studentId.trim(): r,
    };

    return tickets.map((ticket) {
      final universityId = (ticket['university_id'] ?? '').toString().trim();
      final selectedAdvisor = (ticket['advisor'] ?? '').toString().trim();
      final record = byStudentId[universityId];

      final result = Map<String, dynamic>.from(ticket);
      result['selected_advisor'] = selectedAdvisor;

      if (record == null || !record.hasAdvisor) {
        // لا يوجد سجل إرشاد لهذا الطالب بعد (لم يُرفَع التقرير لهذا الفصل،
        // أو الطالب غير موجود فيه) - يتعذّر التحقق، فيبقى اختيار الطالب كما
        // هو دون تصحيح.
        result['advisor_corrected'] = null;
        return result;
      }

      final actualAdvisor = record.advisorNameRaw.trim();
      final isMatch = normalizeAdvisorNameForMatch(selectedAdvisor) ==
          normalizeAdvisorNameForMatch(actualAdvisor);

      result['advisor'] = actualAdvisor;
      result['advisor_corrected'] = !isMatch;
      return result;
    }).toList();
  }
}
