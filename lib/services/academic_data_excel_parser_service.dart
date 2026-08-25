import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import '../utils/xlsx_sanitizer.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

/// يقرأ ملف "بيانات الطلبة الأكاديمية" (قوائم اكسل 481 - طلاب/طالبات - منتظم)
/// - ملف منفصل تمامًا لكل شطر (لا عمود جنس يفرزهما) - أعمدته: الرقم الجامعي،
/// اسم الطالب، القسم، المعدل التراكمي، ساعات الخطة، الساعات المتبقية. يعتمد
/// أسماء الأعمدة لا فهرستها الثابتة، ويقرأ أول ورقة بالملف (اسمها متغيّر بين
/// رفعة وأخرى، مثل "طلاب 481 منتظمww20260825").
class AcademicDataExcelParserService {
  static String _normalize(String s) => s.trim();

  static Map<String, int> _headerIndex(List<Data?> headerRow) {
    final map = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final h = headerRow[i]?.value?.toString();
      if (h != null && h.trim().isNotEmpty) map[_normalize(h)] = i;
    }
    return map;
  }

  static String _cell(List<Data?> row, Map<String, int> index, String header) {
    final i = index[header];
    if (i == null || i >= row.length) return '';
    return row[i]?.value?.toString().trim() ?? '';
  }

  static List<AdvisingCaseRecord> parse(Uint8List bytes, Shatr shatr) {
    final excel = Excel.decodeBytes(sanitizeXlsxBytes(bytes));
    if (excel.tables.isEmpty) return const [];
    final sheet = excel.tables.values.first;
    if (sheet.maxRows <= 1) return const [];

    final index = _headerIndex(sheet.row(0));
    final records = <AdvisingCaseRecord>[];

    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
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
        enrollmentStatus: _cell(row, index, 'الوضع في الفصل'),
      ));
    }

    return records;
  }
}
