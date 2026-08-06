import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';

import 'package:sulaiman/data/position_catalog.dart';
import 'package:sulaiman/services/excel_protection_service.dart';

/// يرفع ملف منسوبي الكلية الحالي (بعد دمج أرقام المكاتب) إلى البنية الجديدة:
/// كل عمود "منصب" يصير عمودين (منصب معياري بقائمة منسدلة + توضيح حر بجانبه)،
/// مع الحفاظ على كل الصفوف والقيم الحالية كما هي (بما فيها ورقة "الإداريين"
/// بلا أي تعديل). أداة تشغيل لمرة واحدة، وليست جزءًا من التطبيق.
void main() {
  const dir = 'المرفقات/أعضاء هيئة التدريس';
  const sourcePath = '$dir/قالب_بيانات_منسوبي_الكلية_محدث_نهائي_بأرقام_المكاتب.xlsx';
  // اسم مختلف صراحةً عن "قالب_بيانات_منسوبي_الكلية_الرسمي.xlsx" (الاسم الذي
  // تعتمده العمادة) حتى يسهل التفريق بين نسخة الويب (هذا الملف، بأعمدة
  // توضيح المنصب الجديدة) وأي نسخة أخرى.
  const outputPath = '$dir/أعضاء_هيئة_التدريس_للويب.xlsx';

  const departmentOptions = [
    'قسم الادارة',
    'قسم المحاسبة',
    'قسم التسويق',
    'قسم الاقتصاد و التمويل',
    'قسم نظم المعلومات الادارية',
    'عمادة الكلية / جهة إدارية عامة',
  ];
  const shatrOptions = ['طلاب', 'طالبات', 'لا ينطبق'];
  const quotaReductionOptions = ['3 ساعات', '50%'];

  final sourceBytes = File(sourcePath).readAsBytesSync();
  final source = Excel.decodeBytes(sourceBytes);

  final facultySheet = source.tables['منسوبو الكلية']!;
  final oldHeader = facultySheet.row(0);
  final oldIndex = <String, int>{};
  for (var i = 0; i < oldHeader.length; i++) {
    final h = oldHeader[i]?.value?.toString().trim();
    if (h != null && h.isNotEmpty) oldIndex[h] = i;
  }
  String cell(List<Data?> row, String header) {
    final i = oldIndex[header];
    if (i == null || i >= row.length) return '';
    return row[i]?.value?.toString().trim() ?? '';
  }

  const newHeaders = [
    'م',
    'رقم المنسوب',
    'الاسم الكامل',
    'البريد الجامعي',
    'رقم الجوال',
    'القسم / الجهة',
    'الشطر',
    'الدرجة العلمية',
    'المنصب',
    'توضيح المنصب',
    'منصب آخر (إن وجد)',
    'توضيح المنصب الآخر',
    'منصب ثالث (احتياطي - إن وجد)',
    'توضيح المنصب الثالث',
    'ملاحظات تخفيض النصاب',
    'رقم المكتب',
    'ملاحظات',
  ];
  const positionColIndexes = [8, 10, 12];
  const quotaReductionColIndex = 14;

  final output = Excel.createExcel();
  output.rename('Sheet1', 'منسوبو الكلية');
  final outSheet = output['منسوبو الكلية'];

  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
  );
  const wideHeaders = {
    'ملاحظات',
    'المنصب',
    'توضيح المنصب',
    'منصب آخر (إن وجد)',
    'توضيح المنصب الآخر',
    'منصب ثالث (احتياطي - إن وجد)',
    'توضيح المنصب الثالث',
  };
  for (var c = 0; c < newHeaders.length; c++) {
    final hc = outSheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    hc.value = TextCellValue(newHeaders[c]);
    hc.cellStyle = headerStyle;
    outSheet.setColumnWidth(c, wideHeaders.contains(newHeaders[c]) ? 36 : 22);
  }

  var dataRowCount = 0;
  for (var r = 1; r < facultySheet.maxRows; r++) {
    final row = facultySheet.row(r);
    final name = cell(row, 'الاسم الكامل');
    if (name.isEmpty) continue;
    dataRowCount++;
    final rowIndex = dataRowCount;
    final values = [
      '$dataRowCount',
      cell(row, 'رقم المنسوب'),
      name,
      cell(row, 'البريد الجامعي'),
      cell(row, 'رقم الجوال'),
      cell(row, 'القسم / الجهة'),
      cell(row, 'الشطر'),
      cell(row, 'الدرجة العلمية'),
      cell(row, 'المنصب'),
      '', // توضيح المنصب - تُكمله العمادة
      cell(row, 'منصب آخر (إن وجد)'),
      '', // توضيح المنصب الآخر
      cell(row, 'منصب ثالث (احتياطي - إن وجد)'),
      '', // توضيح المنصب الثالث
      cell(row, 'ملاحظات تخفيض النصاب'),
      cell(row, 'رقم المكتب'),
      cell(row, 'ملاحظات'),
    ];
    for (var c = 0; c < values.length; c++) {
      if (values[c].isEmpty) continue;
      outSheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).value =
          TextCellValue(values[c]);
    }
  }

  // ورقة "الإداريين" تُنسَخ كما هي بلا أي تعديل - لا تدخل في تصنيف
  // الإرشاد/النصاب أصلاً فلا حاجة لتقسيم أعمدتها.
  final adminSource = source.tables['الإداريين'];
  if (adminSource != null) {
    final adminOut = output['الإداريين'];
    for (var r = 0; r < adminSource.maxRows; r++) {
      final row = adminSource.row(r);
      for (var c = 0; c < row.length; c++) {
        final v = row[c]?.value?.toString();
        if (v == null || v.isEmpty) continue;
        final target = adminOut.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        target.value = TextCellValue(v);
        if (r == 0) target.cellStyle = headerStyle;
      }
    }
  }

  final bytesNoProtection = output.encode()!;

  final protected = ExcelProtectionService.protect(
    Uint8List.fromList(bytesNoProtection),
    dataRowCount: dataRowCount + 50, // هامش لإضافة أعضاء جدد
    unlockedColumnIndexes: List.generate(newHeaders.length, (i) => i),
    dropdowns: [
      DropdownColumn(columnIndex: 5, options: departmentOptions),
      DropdownColumn(columnIndex: 6, options: shatrOptions),
      for (final c in positionColIndexes)
        DropdownColumn(columnIndex: c, options: PositionCatalog.standardPositions, strict: false),
      DropdownColumn(columnIndex: quotaReductionColIndex, options: quotaReductionOptions, strict: false),
    ],
  );

  File(outputPath).writeAsBytesSync(protected);
  stdout.writeln('تم إنشاء الملف: $outputPath ($dataRowCount عضو هيئة تدريس)');
}
