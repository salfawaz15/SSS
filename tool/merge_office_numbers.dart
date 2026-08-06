import 'dart:io';
import 'package:excel/excel.dart';

/// يدمج أرقام المكاتب من ملف "أرقام مكاتب أعضاء هيئة التدريس.xlsx" (عمود
/// الاسم + عمود رقم المكتب) داخل عمود "رقم المكتب" في ورقة "منسوبو الكلية"
/// بملف V1 المحدَّث، بالمطابقة على الاسم الكامل الحرفي. أداة تشغيل لمرة
/// واحدة، وليست جزءًا من التطبيق.
void main() {
  const dir = 'المرفقات/أعضاء هيئة التدريس';
  const v1Path = '$dir/V1قالب_بيانات_منسوبي_الكلية_محدث_نهائي.xlsx';
  const officePath = '$dir/أرقام مكاتب أعضاء هيئة التدريس.xlsx';
  const outPath = '$dir/قالب_بيانات_منسوبي_الكلية_محدث_نهائي_بأرقام_المكاتب.xlsx';

  final officeBytes = File(officePath).readAsBytesSync();
  final officeExcel = Excel.decodeBytes(officeBytes);
  final officeSheet = officeExcel.tables[officeExcel.tables.keys.first]!;

  final officeByName = <String, String>{};
  for (var r = 1; r < officeSheet.maxRows; r++) {
    final row = officeSheet.row(r);
    final name = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
    final office = row.length > 3 ? (row[3]?.value?.toString().trim() ?? '') : '';
    if (name.isEmpty || office.isEmpty) continue;
    officeByName[name] = office;
  }
  stdout.writeln('عدد أرقام المكاتب المتوفرة في ملف المصدر: ${officeByName.length}');

  final v1Bytes = File(v1Path).readAsBytesSync();
  final v1Excel = Excel.decodeBytes(v1Bytes);
  final facultySheet = v1Excel.tables['منسوبو الكلية']!;

  const nameCol = 2; // C: الاسم الكامل
  const officeCol = 12; // M: رقم المكتب

  var filled = 0;
  var alreadyHad = 0;
  var noMatch = 0;
  final unmatchedNames = <String>[];

  for (var r = 1; r < facultySheet.maxRows; r++) {
    final row = facultySheet.row(r);
    if (row.isEmpty) continue;
    final name = row.length > nameCol ? (row[nameCol]?.value?.toString().trim() ?? '') : '';
    if (name.isEmpty) continue;

    final existingOffice = row.length > officeCol ? (row[officeCol]?.value?.toString().trim() ?? '') : '';
    if (existingOffice.isNotEmpty) {
      alreadyHad++;
      continue;
    }

    final office = officeByName[name];
    if (office == null || office.isEmpty) {
      noMatch++;
      unmatchedNames.add(name);
      continue;
    }

    facultySheet.cell(CellIndex.indexByColumnRow(columnIndex: officeCol, rowIndex: r)).value =
        TextCellValue(office);
    filled++;
  }

  stdout.writeln('تم ملء رقم المكتب لـ $filled عضوًا.');
  stdout.writeln('كان لديهم رقم مكتب مسبقًا (لم يُلمَس): $alreadyHad');
  stdout.writeln('بلا رقم مكتب متوفر بعد (تبقى فارغة): $noMatch');
  if (unmatchedNames.isNotEmpty) {
    stdout.writeln('الأسماء التي لا يزال رقم مكتبها فارغًا:');
    for (final n in unmatchedNames) {
      stdout.writeln('  - $n');
    }
  }

  final outBytes = v1Excel.encode()!;
  File(outPath).writeAsBytesSync(outBytes);
  stdout.writeln('تم إنشاء الملف: $outPath');
}
