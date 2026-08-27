import 'dart:typed_data';

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;
import 'windows1256_decoder.dart';

/// يقرأ أحد ملفات "بيانات الطلبة الأكاديمية" الستة (CSV مصدرها تنزيل مباشر
/// من المنظومة الداخلية - منتظم/مفصول أكاديمي/منقطع عن الدراسة × طلاب/
/// طالبات) - ترميز Windows-1256، فاصل الحقول `;`، بلا اقتباس/تهريب (تحقّق
/// فعلي من الملفات الحقيقية). نفس أعمدة [AcademicDataExcelParserService]
/// بالضبط (يعتمد أسماء الأعمدة لا فهرستها الثابتة)، لكن عمود "الوضع في
/// الفصل" بالملف فارغ دومًا - الحالة تُمرَّر من الاستدعاء (مستنتَجة من اسم
/// الملف، انظر upload_flows.dart) لا من عمود الملف.
class AcademicDataCsvParserService {
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

  static List<AdvisingCaseRecord> parse(Uint8List bytes, Shatr shatr, String enrollmentStatus) {
    final text = Windows1256Decoder.decode(bytes);
    final lines = text.split(RegExp(r'\r\n|\r|\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) return const [];

    final index = _headerIndex(lines.first.split(';'));
    final records = <AdvisingCaseRecord>[];

    for (var r = 1; r < lines.length; r++) {
      final row = lines[r].split(';');
      final id = _cell(row, index, 'الرقم الجامعي');
      final name = _cell(row, index, 'اسم الطالب');
      if (id.isEmpty || name.isEmpty) continue;

      final gpaText = _cell(row, index, 'المعدل التراكمي').replaceAll('٫', '.');
      final planText = _cell(row, index, 'ساعات الخطة');
      final remainingText = _cell(row, index, 'الساعات المتبقية');

      records.add(AdvisingCaseRecord(
        studentId: id,
        studentName: name,
        department: normalizeDepartmentName(_cell(row, index, 'القسم')),
        shatr: shatr.label,
        advisorNameRaw: '',
        gpa: double.tryParse(gpaText),
        planHours: int.tryParse(planText),
        remainingHours: int.tryParse(remainingText),
        enrollmentStatus: enrollmentStatus,
      ));
    }

    return records;
  }
}
