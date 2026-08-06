import 'dart:io';
import 'package:excel/excel.dart';

/// يبني ملف Excel جاهز لنسخ خيارات أسئلة "المرشد الأكاديمي" في مايكروسوفت
/// فورمز (سؤال منفصل لكل قسم × شطر، بنفس تسمية الأسئلة في النموذج الحالي)،
/// بالاعتماد على ملف أعضاء هيئة التدريس الرسمي - نفس المصدر المستخدم في
/// tool/admin_cli/seed_advisor_roster.js لتعبئة advisor_roster في Firestore.
/// أداة تشغيل لمرة واحدة، وليست جزءًا من التطبيق - يُعاد تشغيلها كلما
/// تحدّث ملف أعضاء هيئة التدريس.
void main() {
  const sourcePath = 'المرفقات/أعضاء هيئة التدريس/أعضاء_هيئة_التدريس_كلية_إدارة_الأعمال.xlsx';
  const outputPath = 'المرفقات/المرشدين/أسئلة_مايكروسوفت_فورمز_المرشدين.xlsx';

  final bytes = File(sourcePath).readAsBytesSync();
  final source = Excel.decodeBytes(bytes);
  final sheet = source.tables[source.tables.keys.first]!;

  const deptLabels = {
    'الإدارة': 'قسم الادارة',
    'المحاسبة': 'قسم المحاسبة',
    'التسويق': 'قسم التسويق',
    'الاقتصاد والتمويل': 'قسم الاقتصاد و التمويل',
    'نظم المعلومات الإدارية': 'قسم نظم المعلومات الادارية',
  };

  // shatr -> department -> [(name, title)]
  final grouped = <String, Map<String, List<List<String>>>>{
    'طلاب': {for (final d in deptLabels.keys) d: []},
    'طالبات': {for (final d in deptLabels.keys) d: []},
  };

  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.row(r);
    if (row.length < 6) continue;
    final name = (row[1]?.value?.toString() ?? '').trim();
    final shatr = (row[3]?.value?.toString() ?? '').trim();
    final dept = (row[4]?.value?.toString() ?? '').trim();
    final title = (row[5]?.value?.toString() ?? '').trim();
    // العمود السابع "الحالة" الثاني (منصب قيادي إن وُجد) - عمود إضافي رقم 6
    final leadershipRole = row.length > 6 ? (row[6]?.value?.toString() ?? '').trim() : '';
    if (name.isEmpty || shatr.isEmpty || !grouped.containsKey(shatr)) continue;
    if (!grouped[shatr]!.containsKey(dept)) continue;
    grouped[shatr]![dept]!.add([name, title, leadershipRole]);
  }

  final output = Excel.createExcel();
  output.rename('Sheet1', 'تعليمات');
  final instructions = output.sheets['تعليمات']!;
  final lines = <String>[
    'كيفية استخدام هذا الملف لأسئلة "المرشد الأكاديمي" في مايكروسوفت فورمز',
    '',
    '1. هذه أسماء الأسئلة كما هي بالضبط في النموذج الحالي: '
        '"المرشد الأكاديمي - <اسم القسم> - <الشطر>" (اختيار من متعدد).',
    '2. كل ورقة هنا تمثل قسمًا وشطرًا واحدًا، وفيها عمودان: اسم المرشد، ومنصبه إن وُجد '
        '(عميد/وكيل/رئيس قسم...) - راجع عمود المنصب واحذف يدويًا من لا يُفترض أن يكون '
        'مرشدًا أكاديميًا فعليًا قبل النسخ، فهذا القرار يحتاج مراجعة بشرية.',
    '3. انسخ عمود "الاسم" فقط (العمود A بعد حذف من لا ينطبق) والصقه في خيارات السؤال المطابق.',
    '4. يبقى التفريع بحسب "القسم العلمي" و"مقر الدراسة (الشطر)" كما هو معمول به حاليًا في النموذج.',
    '',
    'المصدر: أعضاء_هيئة_التدريس_كلية_إدارة_الأعمال.xlsx (نفس ملف تعبئة advisor_roster).',
    'أعد تشغيل tool/build_ms_forms_advisor_questions.dart كلما تحدّث ملف أعضاء هيئة التدريس.',
  ];
  for (var i = 0; i < lines.length; i++) {
    instructions.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i)).value =
        TextCellValue(lines[i]);
  }
  instructions.setColumnWidth(0, 110);

  for (final shatr in ['طلاب', 'طالبات']) {
    for (final entry in deptLabels.entries) {
      final deptKey = entry.key;
      final deptLabel = entry.value;
      final people = grouped[shatr]![deptKey]!;
      final sheetName = '$shatr - $deptLabel';
      final sheet = output[sheetName];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          TextCellValue('الاسم');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
          TextCellValue('المنصب (راجع قبل الحذف)');
      for (var i = 0; i < people.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value =
            TextCellValue(people[i][0]);
        final role = people[i][2].isNotEmpty ? people[i][2] : people[i][1];
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value =
            TextCellValue(role);
      }
      sheet.setColumnWidth(0, 45);
      sheet.setColumnWidth(1, 35);
    }
  }

  final outBytes = output.encode()!;
  File(outputPath).writeAsBytesSync(outBytes);
  stdout.writeln('تم إنشاء الملف: $outputPath');
}
