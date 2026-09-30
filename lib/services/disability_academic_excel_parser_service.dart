import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import '../utils/xlsx_sanitizer.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

/// يقرأ ملف "بيانات الطلبة الأكاديمية لذوي الإعاقة" (xlsx) - ملف واحد يضم
/// الشطرين معًا (لا عمود جنس يفرزهما)، أعمدته: م، الرقم الجامعي، الاسم،
/// التخصص، المعدل، الحالة الدراسية، المستوى، نوع الإعاقة، رقم الجوال، البريد
/// الالكتروني - يُعتمَد منها فقط ما يقابل حقول [AdvisingCaseRecord] (رقم
/// الجوال والبريد يُهمَلان بطلب سليمان 2026-09-28). يعتمد أسماء الأعمدة لا
/// فهرستها الثابتة.
///
/// شطر كل طالب يُستنتَج من [shatrByStudentId] (خريطة رقم جامعي ← تسمية شطر،
/// مبنية من بيانات "حالات الإرشاد" الأساسية الموثوقة المرفوعة مسبقًا - المصدر
/// الوحيد المتاح لمعرفة جنس الطالب هنا). طالب غير موجود بالخريطة (لم تُرفع
/// بياناته الأساسية بعد، أو رقمه غير مطابق) يُضاف لكلا الشطرين معًا بنفس
/// أسلوب [AdvisingReportParserService] - الدمج لاحقًا يربط برقم الطالب داخل
/// شطر واحد فقط فتُتجاهَل النسخة بالشطر الخطأ تلقائيًا بلا أثر.
class DisabilityAcademicExcelParserService {
  /// إزالة **كل** المسافات (لا trim فقط) - عناوين هذا الملف وصلت فعليًا
  /// بمسافات/محارف Unicode غير قياسية (مسافة غير منقطعة  ، أو علامات
  /// اتجاه RTL ‎/‏) لا يزيلها trim العادي، ففشلت المطابقة الحرفية
  /// رغم تطابق النص بصريًا تمامًا (تشخيص حي، سليمان 2026-09-30). نفس أسلوب
  /// [AdvisingReportParserService._normalize].
  static String _normalize(String s) => s.replaceAll(RegExp(r'\s+'), '').trim();

  static Map<String, int> _headerIndex(List<Data?> headerRow) {
    final map = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final h = headerRow[i]?.value?.toString();
      if (h != null && _normalize(h).isNotEmpty) map[_normalize(h)] = i;
    }
    return map;
  }

  static String _cell(List<Data?> row, Map<String, int> index, String header) {
    final i = index[_normalize(header)];
    if (i == null || i >= row.length) return '';
    return row[i]?.value?.toString().trim() ?? '';
  }

  static List<AdvisingCaseRecord> parse(
    Uint8List bytes, {
    required Map<String, String> shatrByStudentId,
    List<String>? unresolvedStudents,
  }) {
    final excel = Excel.decodeBytes(sanitizeXlsxBytes(bytes));
    if (excel.tables.isEmpty) return const [];
    final sheet = excel.tables.values.first;
    if (sheet.maxRows <= 1) return const [];

    final index = _headerIndex(sheet.row(0));
    final records = <AdvisingCaseRecord>[];

    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final id = _cell(row, index, 'الرقم الجامعي');
      final name = _cell(row, index, 'الاسم');
      if (id.isEmpty || name.isEmpty) continue;

      final gpaText = _cell(row, index, 'المعدل').replaceAll('٫', '.');
      final department = normalizeDepartmentName(_cell(row, index, 'التخصص'));
      final gpa = double.tryParse(gpaText);
      final healthCondition = _cell(row, index, 'نوع الإعاقة');
      final enrollmentStatus = _cell(row, index, 'الحالة الدراسية');

      AdvisingCaseRecord buildRecord(String shatrLabel) => AdvisingCaseRecord(
            studentId: id,
            studentName: name,
            department: department,
            shatr: shatrLabel,
            advisorNameRaw: '',
            gpa: gpa,
            healthCondition: healthCondition,
            enrollmentStatus: enrollmentStatus,
          );

      final resolvedShatr = shatrByStudentId[id];
      if (resolvedShatr == null) {
        unresolvedStudents?.add('$name ($id)');
        records.add(buildRecord(Shatr.male.label));
        records.add(buildRecord(Shatr.female.label));
        continue;
      }
      records.add(buildRecord(resolvedShatr));
    }

    return records;
  }
}
