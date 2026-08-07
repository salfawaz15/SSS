import 'dart:typed_data';

import 'package:excel/excel.dart';

/// يبني ملف Excel عام (عنوان الورقة + جدول برأس مُنسَّق) - نظير
/// [AdvisingCasePdfService] لنفس تقارير "متابعة حالات الإرشاد" الفرعية، حتى
/// يسهل نسخ الأرقام/الأسماء مباشرة بدل تفريغها يدويًا من PDF.
class AdvisingCaseExcelService {
  static final _headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  static Uint8List build({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final workbook = Excel.createExcel();
    final sheetName = title.length > 31 ? title.substring(0, 31) : title;
    final sheet = workbook[sheetName];
    workbook.setDefaultSheet(sheetName);
    for (final legacyDefault in workbook.sheets.keys.where((n) => n != sheetName).toList()) {
      workbook.delete(legacyDefault);
    }

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = _headerStyle;
    }

    for (var r = 0; r < rows.length; r++) {
      sheet.appendRow(rows[r].map((v) => TextCellValue(v)).toList());
    }

    return Uint8List.fromList(workbook.encode()!);
  }
}
