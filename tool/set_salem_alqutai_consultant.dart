import 'dart:io';
import 'package:excel/excel.dart';

/// يضبط منصب "سالم علي محمد ال قظيع" إلى "مستشار" في ملف منسوبي الكلية
/// المدمج (بعد دمج أرقام المكاتب) - أداة تشغيل لمرة واحدة.
void main() {
  const path = 'المرفقات/أعضاء هيئة التدريس/قالب_بيانات_منسوبي_الكلية_محدث_نهائي_بأرقام_المكاتب.xlsx';
  final bytes = File(path).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['منسوبو الكلية']!;

  var found = false;
  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.row(r);
    final name = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
    if (name.contains('قظيع')) {
      // "مستشار" (إعفاء كامل) كانت تصنيفًا خاطئًا لحالته: نصابه الفعلي
      // المعروف مسبقًا 50% (وليس إعفاءً كاملاً) - "مكلف بتخفيض 50%" تعكس ذلك
      // بدقة في كل من الإرشاد والنصاب معًا.
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value =
          TextCellValue('مكلف بتخفيض 50%');
      found = true;
      stdout.writeln('تم ضبط منصب: $name -> مكلف بتخفيض 50%');
    }
  }
  if (!found) {
    stdout.writeln('لم يُعثر على "قظيع" في الملف.');
    return;
  }

  File(path).writeAsBytesSync(excel.encode()!);
  stdout.writeln('تم حفظ الملف.');
}
