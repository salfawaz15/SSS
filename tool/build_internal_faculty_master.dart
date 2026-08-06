import 'dart:io';
import 'package:excel/excel.dart';

/// النسخة الداخلية (لنا فقط) من ملف بيانات منسوبي الكلية - تطابق نفس ترتيب
/// أعمدة الملف الخارجي (tool/build_faculty_master_template.dart) بالضبط
/// حتى يسهل النسخ عمودًا بعمود من نسخة العمادة المحدَّثة إلى هنا (الاسم،
/// المنصب، الدرجة العلمية، رقم المكتب...)، مع عمود إضافي واحد فقط: تصنيف
/// عبء الإرشاد، كصيغة إكسل حيّة تُعيد الحساب تلقائيًا فور لصق بيانات جديدة -
/// نفس منطق lib/data/advising_load_rules.dart لكن مكتوب كصيغة Excel بدل
/// Dart، لأن هذا الملف يُحدَّث يدويًا داخل إكسل مباشرة وليس عبر استيراد
/// برمجي. هذا العمود لا يوجد ولن يوجد أبدًا في الملف الخارجي المُرسَل
/// للعمادة. أداة تشغيل لمرة واحدة، وليست جزءًا من التطبيق.
void main() {
  const sourcePath = 'المرفقات/أعضاء هيئة التدريس/أعضاء_هيئة_التدريس_كلية_إدارة_الأعمال.xlsx';
  const outputPath = 'المرفقات/أعضاء هيئة التدريس/بيانات_منسوبي_الكلية_الداخلي.xlsx';

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
    'تصنيف عبء الإرشاد (تلقائي - داخلي فقط)',
  ];

  const deptNormalize = {
    'الإدارة': 'قسم الادارة',
    'المحاسبة': 'قسم المحاسبة',
    'التسويق': 'قسم التسويق',
    'الاقتصاد والتمويل': 'قسم الاقتصاد و التمويل',
    'نظم المعلومات الإدارية': 'قسم نظم المعلومات الادارية',
  };

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

    rows.add([staffNumber, name, '', '', dept, shatr, rank, position, position2, '', '', '', '']);
  }

  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'منسوبو الكلية (داخلي)');
  final sheet = excel['منسوبو الكلية (داخلي)'];

  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
  );
  // تمييز عمود التصنيف الذكي بلون مختلف - تذكير بصري أنه محسوب وليس بيانات مُدخَلة
  final smartHeaderStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF8A5A00'),
  );

  for (var c = 0; c < headers.length; c++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = TextCellValue(headers[c]);
    cell.cellStyle = c == headers.length - 1 ? smartHeaderStyle : headerStyle;
    sheet.setColumnWidth(
      c,
      c == headers.length - 1
          ? 40
          : ['ملاحظات', 'المنصب', 'منصب آخر (إن وجد)', 'منصب ثالث (احتياطي - إن وجد)']
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

  // نفس صيغة تصنيف عبء الإرشاد لكل صف بيانات + هامش صفوف إضافية فارغة (لأي
  // عضو يُضاف يدويًا لاحقًا) - مع حارس فراغ على عمود الاسم (B) حتى لا تظهر
  // "كامل" لصفوف فارغة بالكامل.
  for (var excelRow = 2; excelRow <= rows.length + 51; excelRow++) {
    final rowIndex = excelRow - 1;
    final combined = 'I$excelRow&J$excelRow&K$excelRow';

    final formula = '=IF(C$excelRow="","",IF(OR('
        'ISNUMBER(SEARCH("عميد",$combined)),'
        'ISNUMBER(SEARCH("وكيل",$combined)),'
        'ISNUMBER(SEARCH("معار",$combined)),'
        'ISNUMBER(SEARCH("مبتعث",$combined)),'
        'ISNUMBER(SEARCH("رئيس وحدة الإرشاد",$combined)),'
        'ISNUMBER(SEARCH("نائب رئيس وحدة الإرشاد",$combined)),'
        'ISNUMBER(SEARCH("رئيس قسم",$combined)),'
        'ISNUMBER(SEARCH("رئيسة قسم",$combined)),'
        'AND(ISNUMBER(SEARCH("تكليف",$combined)),NOT(ISNUMBER(SEARCH("%",$combined))))'
        '),"معفى بالكامل",'
        'IF(ISNUMBER(SEARCH("أمين",$combined)),"حالات خاصة فقط (كذوي الإعاقة)",'
        'IF(ISNUMBER(SEARCH("%",$combined)),"مخفّض (راجع النسبة المذكورة في المنصب)",'
        'IF(OR('
        'ISNUMBER(SEARCH("منسق قسم",$combined)),'
        'ISNUMBER(SEARCH("منسق الكلية",$combined)),'
        'ISNUMBER(SEARCH("منسقة قسم",$combined)),'
        'ISNUMBER(SEARCH("منسقة الكلية",$combined))'
        '),"مخفّض 50%",'
        '"كامل")))))';

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: rowIndex))
        .setFormula(formula);
  }

  // ورقة الإداريين الداخلية - نفس ترتيب أعمدة نسخة الإداريين الخارجية
  // بالضبط (للنسخ عمودًا بعمود)، مع نفس عمود التصنيف الذكي كصيغة حيّة، لأن
  // الموظف الإداري قد يحمل أكثر من مسمى وظيفي في نفس الوقت أيضًا.
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
    'تصنيف عبء الإرشاد (تلقائي - داخلي فقط)',
  ];
  final adminSheet = excel['الإداريين (داخلي)'];
  for (var c = 0; c < adminHeaders.length; c++) {
    final cell = adminSheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = TextCellValue(adminHeaders[c]);
    cell.cellStyle = c == adminHeaders.length - 1 ? smartHeaderStyle : headerStyle;
    adminSheet.setColumnWidth(
      c,
      c == adminHeaders.length - 1
          ? 40
          : ['ملاحظات', 'المسمى الوظيفي', 'مسمى آخر (إن وجد)', 'مسمى ثالث (احتياطي - إن وجد)']
                  .contains(adminHeaders[c])
              ? 42
              : 22,
    );
  }
  // أعمدة المسمى الثلاثة هنا هي G، H، I (فهرسة صفر: 6، 7، 8) بعد إضافة عمود
  // "رقم المنسوب"
  for (var r = 2; r <= 300; r++) {
    final combined = 'G$r&H$r&I$r';
    final formula = '=IF(G$r="","",IF(OR('
        'ISNUMBER(SEARCH("عميد",$combined)),'
        'ISNUMBER(SEARCH("وكيل",$combined)),'
        'ISNUMBER(SEARCH("معار",$combined)),'
        'ISNUMBER(SEARCH("مبتعث",$combined)),'
        'ISNUMBER(SEARCH("رئيس وحدة الإرشاد",$combined)),'
        'ISNUMBER(SEARCH("نائب رئيس وحدة الإرشاد",$combined)),'
        'ISNUMBER(SEARCH("رئيس قسم",$combined)),'
        'ISNUMBER(SEARCH("رئيسة قسم",$combined)),'
        'AND(ISNUMBER(SEARCH("تكليف",$combined)),NOT(ISNUMBER(SEARCH("%",$combined))))'
        '),"معفى بالكامل",'
        'IF(ISNUMBER(SEARCH("أمين",$combined)),"حالات خاصة فقط (كذوي الإعاقة)",'
        'IF(ISNUMBER(SEARCH("%",$combined)),"مخفّض (راجع النسبة المذكورة في المنصب)",'
        'IF(OR('
        'ISNUMBER(SEARCH("منسق قسم",$combined)),'
        'ISNUMBER(SEARCH("منسق الكلية",$combined)),'
        'ISNUMBER(SEARCH("منسقة قسم",$combined)),'
        'ISNUMBER(SEARCH("منسقة الكلية",$combined))'
        '),"مخفّض 50%",'
        '"كامل")))))';
    adminSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: adminHeaders.length - 1, rowIndex: r - 1))
        .setFormula(formula);
  }

  // ورقة تعليمات داخلية
  final instructions = excel['تعليمات (داخلي)'];
  final lines = [
    'هذا الملف داخلي فقط - لا يُرسل أبدًا لعمادة الكلية.',
    '',
    'الأعمدة من "م" حتى "ملاحظات" مطابقة تمامًا لترتيب أعمدة الملف الخارجي '
        '(قالب_بيانات_منسوبي_الكلية_الرسمي.xlsx) - عند وصول نسخة العمادة '
        'المحدَّثة، انسخ كل عمود من ملفهم والصقه في نفس عمود هذا الملف '
        '(الاسم فوق الاسم، المنصب فوق المنصب...) - لا تلصق الملف كاملاً '
        'دفعة واحدة حتى لا يُستبدَل عمود التصنيف بالخطأ.',
    'آخر عمود "تصنيف عبء الإرشاد" صيغة إكسل حيّة، تُعيد حسابها تلقائيًا فور '
        'تغيّر أي من أعمدة المنصب الثلاثة - لا تكتب فيه شيء يدويًا.',
    'هذا العمود يطبّق نفس منطق lib/data/advising_load_rules.dart المستخدَم '
        'داخل التطبيق، لكن كصيغة إكسل بدل كود Dart.',
  ];
  for (var i = 0; i < lines.length; i++) {
    instructions.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i)).value =
        TextCellValue(lines[i]);
  }
  instructions.setColumnWidth(0, 110);

  final bytes = excel.encode()!;
  File(outputPath).writeAsBytesSync(bytes);
  stdout.writeln('تم إنشاء الملف: $outputPath (${rows.length} عضو)');
}
