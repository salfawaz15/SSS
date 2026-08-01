import 'dart:typed_data';

import 'package:excel/excel.dart';

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
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;

    if (sheet.maxRows < 2) return [];

    final headerRow = sheet.row(0);
    final columnIndex = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final header = headerRow[i]?.value?.toString().trim();
      if (header != null && header.isNotEmpty) {
        columnIndex[header] = i;
      }
    }

    final universityIdCol = columnIndex[ExcelExportService.universityIdHeader];
    final actionTypeCol = columnIndex[ExcelExportService.actionTypeHeader];
    final courseCol = columnIndex[ExcelExportService.courseHeader];
    final sectionCol = columnIndex[ExcelExportService.requiredSectionHeader];
    final statusCol = columnIndex[ExcelExportService.statusHeader];
    final notesCol = columnIndex[ExcelExportService.notesHeader];
    // عمود اختياري - قد لا يُعبَّأ دائمًا
    final completedByCol = columnIndex[ExcelExportService.completedByHeader];

    if (universityIdCol == null ||
        actionTypeCol == null ||
        courseCol == null ||
        sectionCol == null ||
        statusCol == null ||
        notesCol == null) {
      throw const FormatException(
        'الملف لا يحتوي على كل الأعمدة المتوقعة (الرقم الجامعي، نوع الإجراء، المقرر، رقم الشعبة، حالة الإنجاز، ملاحظات)',
      );
    }

    final rows = <Map<String, dynamic>>[];

    for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = sheet.row(rowIndex);
      if (row.isEmpty) continue;

      final universityId = _cellText(row, universityIdCol);
      if (universityId.isEmpty) continue;

      rows.add({
        'university_id': universityId,
        'action_type': _cellText(row, actionTypeCol),
        'course': _cellText(row, courseCol),
        'section': _cellText(row, sectionCol),
        'status': _cellText(row, statusCol),
        'notes': _cellText(row, notesCol),
        'completed_by': completedByCol != null
            ? _cellText(row, completedByCol)
            : '',
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
