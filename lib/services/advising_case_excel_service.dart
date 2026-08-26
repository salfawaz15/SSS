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

  static final _groupHeaderStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF2E6F52'),
    horizontalAlign: HorizontalAlign.Right,
    verticalAlign: VerticalAlign.Center,
  );

  /// [groupColumnIndex] اختياري: فهرس عمود (مثال: "المرشد") تُجمَّع صفوفه في
  /// كتل متتالية (بترتيب أول ظهور لكل قيمة، بلا إعادة فرز) - قبل كل كتلة يُدرَج
  /// صف عنوان ممتد (merge) بلون مميّز يحمل اسم القيمة وعدد صفوفها، بنفس أسلوب
  /// تقارير المنظومة الجامعية الأصلية (سليمان صراحةً 2026-08-25: التصدير
  /// المسطَّح الحالي "تنظيم غير احترافي" مقارنة بتقرير المنظومة الذي يُظهر كل
  /// مرشد ككتلة مستقلة بعنوان واضح). null (الافتراضي) يُبقي السلوك القديم.
  /// [rowCellColors] اختياري: لون خلفية (hex بصيغة `FFRRGGBB`) لخلايا محدَّدة
  /// من كل صف - `rowCellColors[i]` خريطة (فهرس العمود ← لون) لصف `rows[i]`،
  /// بديل بصري عن شريط تقدّم حي (غير مدعوم بالخلية بهذه المكتبة) - بطلب
  /// سليمان صراحةً (2026-08-26) لعمودَي "النطاق" حتى يبقى نفس الإحساس اللوني
  /// بالملف المصدَّر لا نصًا مجردًا فقط.
  static Uint8List build({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    int? groupColumnIndex,
    List<Map<int, String>>? rowCellColors,
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

    if (groupColumnIndex == null || groupColumnIndex < 0 || groupColumnIndex >= headers.length) {
      for (var r = 0; r < rows.length; r++) {
        final rowIndex = sheet.maxRows;
        sheet.appendRow(rows[r].map((v) => TextCellValue(v)).toList());
        final colors = rowCellColors != null && r < rowCellColors.length ? rowCellColors[r] : null;
        if (colors != null) {
          for (final entry in colors.entries) {
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: entry.key, rowIndex: rowIndex)).cellStyle = CellStyle(
              backgroundColorHex: ExcelColor.fromHexString(entry.value),
              horizontalAlign: HorizontalAlign.Center,
              verticalAlign: VerticalAlign.Center,
            );
          }
        }
      }
      return Uint8List.fromList(workbook.encode()!);
    }

    final groups = <String, List<List<String>>>{};
    for (final row in rows) {
      final key = groupColumnIndex < row.length ? row[groupColumnIndex] : '';
      (groups[key] ??= []).add(row);
    }

    final groupColumnName = headers[groupColumnIndex];
    for (final entry in groups.entries) {
      final rowIndex = sheet.maxRows;
      sheet.appendRow([TextCellValue('$groupColumnName: ${entry.key.isEmpty ? "بلا قيمة" : entry.key}  -  العدد: ${entry.value.length}')]);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: rowIndex),
      );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).cellStyle = _groupHeaderStyle;
      for (final row in entry.value) {
        sheet.appendRow(row.map((v) => TextCellValue(v)).toList());
      }
    }

    return Uint8List.fromList(workbook.encode()!);
  }
}
