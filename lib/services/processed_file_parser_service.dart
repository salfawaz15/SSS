import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../utils/xlsx_sanitizer.dart';
import 'excel_export_service.dart';

/// يقرأ ملف Excel عائد من مرشد (بعد تعبئة عمودي حالة الإنجاز والملاحظات)
/// ويحوّله لقائمة صفوف بسيطة جاهزة للدمج عبر TicketRepository.
///
/// بخلاف ExcelParserService (الذي يقرأ ملف Microsoft Forms بفهرسة أعمدة
/// ثابتة لأن صيغته خارج تحكمنا)، هذا الملف من إنتاجنا نحن، لذا نبحث عن كل
/// عمود بالاسم في صف العناوين لا برقمه - أكثر أمانًا لو أعاد المستخدم ترتيب
/// الأعمدة بالخطأ.
class ProcessedFileParserService {
  static List<Map<String, dynamic>> parseProcessedRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(sanitizeXlsxBytes(bytes));
    final sheet = excel.tables[excel.tables.keys.first]!;

    if (sheet.maxRows < 2) return [];

    // صف العناوين عادة أول صف، لكن ملف المرشد قد يحتوي صف تعليمات مدمَج
    // فوقه - نبحث عن الصف الذي يحمل فعليًا عمود "الرقم الجامعي" بدل افتراض
    // أنه الصف صفر دومًا.
    var headerRowIndex = 0;
    var columnIndex = <String, int>{};
    for (var r = 0; r < sheet.maxRows && r < 5; r++) {
      final candidate = sheet.row(r);
      final candidateIndex = <String, int>{};
      for (var i = 0; i < candidate.length; i++) {
        final header = candidate[i]?.value?.toString().trim();
        if (header != null && header.isNotEmpty) {
          candidateIndex[header] = i;
        }
      }
      if (candidateIndex.containsKey(ExcelExportService.universityIdHeader)) {
        headerRowIndex = r;
        columnIndex = candidateIndex;
        break;
      }
    }

    final universityIdCol = columnIndex[ExcelExportService.universityIdHeader];
    final actionTypeCol = columnIndex[ExcelExportService.actionTypeHeader];
    final courseNameCol = columnIndex[ExcelExportService.courseNameHeader];
    final courseCodeCol = columnIndex[ExcelExportService.courseCodeHeader];
    final addSectionCol = columnIndex[ExcelExportService.addSectionHeader];
    final deleteSectionCol = columnIndex[ExcelExportService.deleteSectionHeader];
    final currentSectionCol = columnIndex[ExcelExportService.currentSectionHeader];
    final requestedSectionCol = columnIndex[ExcelExportService.requestedSectionHeader];
    // أعمدة إضافية لا تلزم لمطابقة/تحديث تذكرة موجودة (المطابقة تعتمد فقط
    // على المفتاح: رقم جامعي+نوع+مقرر+شعبة) لكنها ضرورية لإنشاء تذكرة جديدة
    // فعليًا عند عدم وجود مطابقة - حالة صفوف النموذج الورقي تحديدًا (سليمان
    // صراحةً 2026-09-01)، انظر FirestoreTicketService._mergeProcessedRowsIntoDocs.
    final studentNameCol = columnIndex[ExcelExportService.studentNameHeader];
    final shatrCol = columnIndex[ExcelExportService.shatrHeader];
    final departmentCol = columnIndex[ExcelExportService.departmentHeader];
    final advisorNameCol = columnIndex[ExcelExportService.advisorNameHeader];
    final reasonCol = columnIndex[ExcelExportService.reasonHeader];
    final advisorStatusCol = columnIndex[ExcelExportService.advisorStatusHeader];
    final advisorNotesCol = columnIndex[ExcelExportService.advisorNotesHeader];
    final advisorOtherReasonCol = columnIndex[ExcelExportService.advisorOtherReasonHeader];
    final coordinatorStatusCol = columnIndex[ExcelExportService.coordinatorStatusHeader];
    final coordinatorNotesCol = columnIndex[ExcelExportService.coordinatorNotesHeader];
    final collegeStatusCol = columnIndex[ExcelExportService.collegeStatusHeader];
    final collegeNotesCol = columnIndex[ExcelExportService.collegeNotesHeader];

    if (universityIdCol == null ||
        actionTypeCol == null ||
        courseNameCol == null ||
        courseCodeCol == null ||
        addSectionCol == null ||
        deleteSectionCol == null ||
        requestedSectionCol == null ||
        advisorStatusCol == null ||
        advisorNotesCol == null ||
        coordinatorStatusCol == null ||
        coordinatorNotesCol == null ||
        collegeStatusCol == null ||
        collegeNotesCol == null) {
      throw const FormatException(
        'الملف لا يحتوي على كل الأعمدة المتوقعة (الرقم الجامعي، نوع الإجراء، اسم/رمز المقرر، '
        'أعمدة أرقام الشعب الأربعة، وأعمدة حالة/ملاحظات المرشد ومنسق القسم ومنسق الكلية)',
      );
    }

    final rows = <Map<String, dynamic>>[];

    for (var rowIndex = headerRowIndex + 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = sheet.row(rowIndex);
      if (row.isEmpty) continue;

      final universityId = _cellText(row, universityIdCol);
      if (universityId.isEmpty) continue;
      // صف العناوين المكرَّر (يُضاف مباشرة قبل صفوف النموذج الورقي - انظر
      // ExcelExportService.buildDepartmentWorkbook) حقله بعمود الرقم الجامعي
      // يحمل نص العنوان نفسه حرفيًا - يُتجاهل صراحةً هنا حتى لا يُقرأ كأنه
      // رقم جامعي طالب فعلي (خلل حقيقي مؤكَّد، سليمان صراحةً 2026-09-02).
      if (universityId == ExcelExportService.universityIdHeader) continue;

      final actionType = _cellText(row, actionTypeCol);
      final courseName = _cellText(row, courseNameCol);
      final courseCode = _cellText(row, courseCodeCol);
      // نعيد بناء 'course' و'section' بنفس صيغة/منطق التذكرة الأصلية
      // (FirestoreTicketService._actionKey/_ticketActionSection) للمطابقة
      // معها عند الدمج - انظر التوثيق هناك.
      final course = courseCode.isEmpty
          ? courseName
          : (courseName.isEmpty ? courseCode : '$courseCode - $courseName');
      // .contains بدل == - يطابق نفس منطق التصنيف الأوسع بـExcelExportService
      // (يتحمّل تسميات إجراء أوسع من الثلاث القياسية).
      final section = actionType.contains('إضافة')
          ? _cellText(row, addSectionCol)
          : (actionType.contains('تعديل') ? _cellText(row, requestedSectionCol) : _cellText(row, deleteSectionCol));

      rows.add({
        'university_id': universityId,
        'action_type': actionType,
        'course': course,
        'section': section,
        // حقول خام إضافية - غير مستخدَمة بمطابقة تذكرة موجودة (مفتاح المطابقة
        // أعلاه فقط)، بل عند إنشاء تذكرة جديدة فعليًا لصف غير مطابَق (حالات
        // النموذج الورقي تحديدًا)، انظر FirestoreTicketService._buildNewTicketFromUnmatchedRows.
        'course_name': courseName,
        'course_code': courseCode,
        'required_section': actionType.contains('إضافة')
            ? _cellText(row, addSectionCol)
            : (actionType.contains('تعديل') ? _cellText(row, requestedSectionCol) : ''),
        'current_section': actionType.contains('حذف')
            ? _cellText(row, deleteSectionCol)
            : (actionType.contains('تعديل') && currentSectionCol != null ? _cellText(row, currentSectionCol) : ''),
        if (studentNameCol != null) 'name': _cellText(row, studentNameCol),
        if (shatrCol != null) 'shatr': _cellText(row, shatrCol),
        if (departmentCol != null) 'department': _cellText(row, departmentCol),
        if (advisorNameCol != null) 'advisor': _cellText(row, advisorNameCol),
        if (reasonCol != null) 'reason_detail': _cellText(row, reasonCol),
        'advisor_status': _cellText(row, advisorStatusCol),
        'advisor_notes': _cellText(row, advisorNotesCol),
        if (advisorOtherReasonCol != null) 'advisor_other_reason': _cellText(row, advisorOtherReasonCol),
        'coordinator_status': _cellText(row, coordinatorStatusCol),
        'coordinator_notes': _cellText(row, coordinatorNotesCol),
        'college_status': _cellText(row, collegeStatusCol),
        'college_notes': _cellText(row, collegeNotesCol),
      });
    }

    return rows;
  }

  static String _cellText(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final value = row[index]?.value;
    if (value == null) return '';
    return value.toString().trim();
  }
}
