import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';

import 'package:sulaiman/services/excel_protection_service.dart';

/// يبني القالب الرسمي لبيانات منسوبي الكلية (أعضاء هيئة التدريس والإداريين
/// معًا) الذي تعتمده عمادة الكلية، **مُعبَّأً مسبقًا** بكل ما هو متوفر حاليًا
/// في قاعدة بياناتنا المتفرقة (ملف أعضاء هيئة التدريس الرسمي + دليل
/// الإيميلات + أرقام المكاتب المعروفة)، لتسهيل مهمة العمادة: تراجع وتعدّل
/// وتضيف بدل ما تبدأ من صفر. يبقى عمدًا خاليًا من أي عمود استنتاج ذكي
/// (انظر lib/data/advising_load_rules.dart لذلك المنطق الداخلي البحت).
/// صف العناوين ثابت ومحمي، وباقي الصفوف (حتى الفارغة) مفتوحة للتعديل/الإضافة.
/// أداة تشغيل لمرة واحدة تُعاد عند الحاجة لإعادة التوليد - وليست جزءًا من التطبيق.
void main() {
  const sourcePath = 'المرفقات/أعضاء هيئة التدريس/أعضاء_هيئة_التدريس_كلية_إدارة_الأعمال.xlsx';
  const outputPath = 'المرفقات/أعضاء هيئة التدريس/قالب_بيانات_منسوبي_الكلية_الرسمي.xlsx';

  const headers = [
    'م',
    'رقم المنسوب',
    'الاسم الكامل',
    'البريد الجامعي',
    'رقم الجوال',
    'القسم / الجهة',
    'الشطر',
    'الدرجة العلمية',
    'المنصب',
    'منصب آخر (إن وجد)',
    'منصب ثالث (احتياطي - إن وجد)',
    'ملاحظات تخفيض النصاب',
    'رقم المكتب',
    'ملاحظات',
  ];

  const quotaReductionOptions = ['3 ساعات', '50%'];

  const departmentOptions = [
    'قسم الادارة',
    'قسم المحاسبة',
    'قسم التسويق',
    'قسم الاقتصاد و التمويل',
    'قسم نظم المعلومات الادارية',
    'عمادة الكلية / جهة إدارية عامة',
  ];
  const shatrOptions = ['طلاب', 'طالبات', 'لا ينطبق'];

  const deptNormalize = {
    'الإدارة': 'قسم الادارة',
    'المحاسبة': 'قسم المحاسبة',
    'التسويق': 'قسم التسويق',
    'الاقتصاد والتمويل': 'قسم الاقتصاد و التمويل',
    'نظم المعلومات الإدارية': 'قسم نظم المعلومات الادارية',
  };

  // مناصب إضافية معروفة لدينا من مصادر أخرى (كود التطبيق أو ملف المكلفين)
  // ولا تظهر في ملف أعضاء هيئة التدريس المصدر - يدويًا حتى تُعتمَد رسميًا
  // ويُستغنى عن هذا التصحيح اليدوي مستقبلاً.
  const knownSecondPositions = {
    'هبه الله عبدالصبور أمين حسن': 'أمينة قسم التسويق',
    'وائل احمد رضوان عبدالجليل تمبوسي': 'مشرف على إدارة ريادة الأعمال',
  };

  final sourceBytes = File(sourcePath).readAsBytesSync();
  final source = Excel.decodeBytes(sourceBytes);
  final sourceSheet = source.tables[source.tables.keys.first]!;

  final rows = <List<String>>[]; // الاسم، البريد، الجوال، القسم، الشطر، الدرجة العلمية، المنصب، منصب آخر، منصب ثالث، المكتب، ملاحظات
  for (var r = 1; r < sourceSheet.maxRows; r++) {
    final row = sourceSheet.row(r);
    if (row.length < 6) continue;
    final name = (row[1]?.value?.toString() ?? '').trim();
    if (name.isEmpty) continue;
    final staffNumber = (row[2]?.value?.toString() ?? '').trim();
    final shatr = (row[3]?.value?.toString() ?? '').trim();
    final deptRaw = (row[4]?.value?.toString() ?? '').trim();
    final rank = (row[5]?.value?.toString() ?? '').trim();
    final leadershipRole = row.length > 6 ? (row[6]?.value?.toString() ?? '').trim() : '';

    final dept = deptNormalize[deptRaw] ?? deptRaw;
    final position = leadershipRole.isNotEmpty ? leadershipRole : '';
    final position2 = knownSecondPositions[name] ?? '';

    // البريد ورقم المكتب يُتركان فارغين عمدًا - لا مصدر مرفوع عبر الموقع
    // لهما بعد؛ تُكملهما عمادة الكلية يدويًا (بدل الاعتماد على قوائم ثابتة
    // قديمة بالكود مصدرها ملفات من مجلد المرفقات).
    rows.add([staffNumber, name, '', '', dept, shatr, rank, position, position2, '', '', '', '']);
  }

  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'منسوبو الكلية');
  final sheet = excel['منسوبو الكلية'];

  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
  );

  for (var c = 0; c < headers.length; c++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = TextCellValue(headers[c]);
    cell.cellStyle = headerStyle;
    sheet.setColumnWidth(
      c,
      ['ملاحظات', 'المنصب', 'منصب آخر (إن وجد)', 'منصب ثالث (احتياطي - إن وجد)']
              .contains(headers[c])
          ? 42
          : 22,
    );
  }

  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final rowIndex = i + 1;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        IntCellValue(i + 1);
    for (var c = 0; c < r.length; c++) {
      if (r[c].isEmpty) continue;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c + 1, rowIndex: rowIndex)).value =
          TextCellValue(r[c]);
    }
  }

  // ورقة عمل منفصلة للإداريين - حقول مختلفة عن أعضاء هيئة التدريس (لا درجة
  // علمية ولا شطر إلزامي)؛ لا يوجد لدينا مصدر بيانات لهم حاليًا فتبقى فارغة
  // بالكامل لتعبئة عمادة الكلية مباشرة. لا تخضع لحماية صف العناوين لأن
  // ExcelProtectionService يستهدف الورقة الأولى فقط حاليًا.
  const adminHeaders = [
    'م',
    'رقم المنسوب',
    'الاسم الكامل',
    'البريد الجامعي',
    'رقم الجوال',
    'الجهة / القسم التابع له',
    'المسمى الوظيفي',
    'مسمى آخر (إن وجد)',
    'مسمى ثالث (احتياطي - إن وجد)',
    'رقم المكتب',
    'ملاحظات',
  ];
  final adminSheet = excel['الإداريين'];
  for (var c = 0; c < adminHeaders.length; c++) {
    final cell = adminSheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = TextCellValue(adminHeaders[c]);
    cell.cellStyle = headerStyle;
    adminSheet.setColumnWidth(
      c,
      ['ملاحظات', 'المسمى الوظيفي', 'مسمى آخر (إن وجد)', 'مسمى ثالث (احتياطي - إن وجد)']
              .contains(adminHeaders[c])
          ? 42
          : 22,
    );
  }

  final bytesNoProtection = excel.encode()!;

  final protected = ExcelProtectionService.protect(
    Uint8List.fromList(bytesNoProtection),
    dataRowCount: rows.length + 50, // هامش لإضافة أعضاء جدد
    unlockedColumnIndexes: List.generate(headers.length, (i) => i),
    dropdowns: [
      DropdownColumn(columnIndex: 5, options: departmentOptions),
      DropdownColumn(columnIndex: 6, options: shatrOptions),
      DropdownColumn(columnIndex: 11, options: quotaReductionOptions, strict: false),
    ],
  );

  File(outputPath).writeAsBytesSync(protected);
  stdout.writeln('تم إنشاء الملف: $outputPath (${rows.length} عضو مُعبَّأ مسبقًا)');
}
