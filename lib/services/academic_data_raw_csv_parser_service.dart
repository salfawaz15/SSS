import 'dart:typed_data';

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;
import 'windows1256_decoder.dart';

/// يقرأ ملف "بيانات الطلبة الأكاديمية" الخام - تصدير مباشر من المنظومة
/// الجامعية بلا أي تحويل وسيط (بخلاف كل المصادر السابقة: ملفات CSV الستة
/// المستنتِجة الحالة من اسم الملف، xlsx القديم، وHTML التفصيلي - استُبدلت
/// هذه الثلاثة بالكامل بهذا المصدر الوحيد، بتأكيد سليمان الصريح 2026-09-30).
/// **مصدر شامل تاريخي**: يضم كل من مرّ بالكلية (منتظم/مفصول/منقطع/متخرج/
/// مطوي قيد...)، ملف مستقل لكل شطر يُعرَف من عمود "المقر" لكل صف (لا حاجة
/// لاسم الملف).
///
/// ترميز Windows-1256، فاصل `;`، الأعمدة: الفصل، المقر، الدرجة، الكلية،
/// القسم، رمزالتخصص، اسم التخصص، الرقم الجامعي، اسم الطالب، الوضع في الفصل،
/// الساعات المسجلة، المعدل التراكمي، ساعات الخطة، الساعات المتبقية.
///
/// **منطق حالة القيد** (عمود "الوضع في الفصل" فارغ لغالبية الصفوف تاريخيًا -
/// تأكيد سليمان المباشر 2026-09-30):
/// - غير فارغ (منتظم/مطوي قيده/موقوف تأديبي - مفصول مؤقت/مؤجل/معتذر/منسحب/
///   متوفى) → يُستخدَم كما هو حرفيًا.
/// - فارغ + الساعات المتبقية > 0 → "مطوي قيده" (تندمج مع نفس التسمية الصريحة
///   أعلاه - لا تصنيف منفصل).
/// - فارغ وإلا (صفر أو غير قابلة للتحويل) → "متخرج".
class AcademicDataRawCsvParserService {
  static String _normalize(String s) => s.trim();

  static Map<String, int> _headerIndex(List<String> headerRow) {
    final map = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final h = headerRow[i];
      if (h.trim().isNotEmpty) map[_normalize(h)] = i;
    }
    return map;
  }

  static String _cell(List<String> row, Map<String, int> index, String header) {
    final i = index[header];
    if (i == null || i >= row.length) return '';
    return row[i].trim();
  }

  static List<AdvisingCaseRecord> parse(Uint8List bytes) {
    final text = Windows1256Decoder.decode(bytes);
    final lines = text.split(RegExp(r'\r\n|\r|\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) return const [];

    final index = _headerIndex(lines.first.split(';'));
    final records = <AdvisingCaseRecord>[];

    for (var r = 1; r < lines.length; r++) {
      final row = lines[r].split(';');
      final id = _cell(row, index, 'الرقم الجامعي');
      final name = _cell(row, index, 'اسم الطالب');
      final college = _cell(row, index, 'الكلية');
      if (id.isEmpty || name.isEmpty || college.isEmpty) continue;

      final mawqi3 = _cell(row, index, 'المقر');
      final shatr = mawqi3.contains('طالبات') ? Shatr.female : Shatr.male;

      final gpaText = _cell(row, index, 'المعدل التراكمي').replaceAll('٫', '.');
      final planText = _cell(row, index, 'ساعات الخطة');
      final remainingText = _cell(row, index, 'الساعات المتبقية');
      final remainingHours = int.tryParse(remainingText);

      final specialization = _cell(row, index, 'اسم التخصص');
      final rawStatus = _cell(row, index, 'الوضع في الفصل');
      final String enrollmentStatus;
      if (rawStatus.isNotEmpty) {
        enrollmentStatus = rawStatus;
      } else if ((remainingHours ?? 0) > 0) {
        enrollmentStatus = 'مطوي قيده';
      } else {
        enrollmentStatus = 'متخرج';
      }

      records.add(AdvisingCaseRecord(
        studentId: id,
        studentName: name,
        department: normalizeDepartmentName(_cell(row, index, 'القسم')),
        shatr: shatr.label,
        advisorNameRaw: '',
        gpa: double.tryParse(gpaText),
        planHours: int.tryParse(planText),
        remainingHours: remainingHours,
        enrollmentStatus: enrollmentStatus,
        specialization: specialization,
      ));
    }

    return records;
  }
}
