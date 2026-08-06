import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';

import 'package:sulaiman/data/faculty_sort_order.dart';
import 'package:sulaiman/models/college_roster_member.dart';

/// يبني ملف Excel مستقل (اسم عضو هيئة التدريس، القسم، رقم المكتب) من
/// البيانات الحيّة الفعلية في collegeRoster (Firestore) - وليس من أي ملف
/// مصدر ثابت. يعتمد على المستخرَج بواسطة
/// tool/admin_cli/export_faculty_roster.js أولاً. أداة تشغيل لمرة واحدة،
/// وليست جزءًا من التطبيق.
void main() {
  const jsonPath = 'المرفقات/أعضاء هيئة التدريس/faculty_export_temp.json';
  const outputPath = 'المرفقات/أعضاء هيئة التدريس/أرقام مكاتب أعضاء هيئة التدريس.xlsx';

  final jsonList = jsonDecode(File(jsonPath).readAsStringSync()) as List<dynamic>;
  final members = jsonList.map((e) => CollegeRosterMember.fromJson(e as Map<String, dynamic>)).toList()
    ..sort((a, b) => FacultySortOrder.compareMembers(a, b, compareDepartment: true));

  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'أرقام المكاتب');
  final sheet = excel['أرقام المكاتب'];

  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
  );

  const headers = ['م', 'الاسم', 'القسم', 'رقم المكتب'];
  for (var c = 0; c < headers.length; c++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = TextCellValue(headers[c]);
    cell.cellStyle = headerStyle;
    sheet.setColumnWidth(c, c == 1 ? 32 : c == 2 ? 26 : 14);
  }

  for (var i = 0; i < members.length; i++) {
    final m = members[i];
    final rowIndex = i + 1;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = IntCellValue(i + 1);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = TextCellValue(m.name);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value =
        TextCellValue(FacultySortOrder.displayDepartment(m.department));
    if (m.office.isNotEmpty) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = TextCellValue(m.office);
    }
  }

  File(outputPath).writeAsBytesSync(excel.encode()!);
  File(jsonPath).deleteSync();
  stdout.writeln('تم إنشاء الملف: $outputPath (${members.length} عضو)');
}
