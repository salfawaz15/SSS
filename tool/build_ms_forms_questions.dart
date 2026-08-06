import 'dart:io';
import 'package:excel/excel.dart';

/// يبني ملف Excel جاهز لنسخ أسئلة وخيارات مايكروسوفت فورمز منه، بناءً على
/// ملف "المواد المتاحة لكل قسم" الرسمي. كل ورقة تمثل سؤال "المقرر الدراسي"
/// لقسم وشطر معينين (مع مواد "مشترك بين الأقسام" مُضافة تلقائيًا للجميع)،
/// ويُنسخ عمود الخيارات كاملاً ويُلصق دفعة واحدة في خانة خيارات السؤال في
/// فورمز. أداة تشغيل لمرة واحدة، وليست جزءًا من التطبيق.
void main() {
  const sourcePath = 'المرفقات/الامتدادات/المواد_المتاحة_لكل_قسم.xlsx';
  const outputPath = 'المرفقات/الامتدادات/أسئلة_مايكروسوفت_فورمز_المقررات_للتسجيل.xlsx';

  final bytes = File(sourcePath).readAsBytesSync();
  final source = Excel.decodeBytes(bytes);

  // shatr -> department -> options (سطر واحد لكل خيار، بصيغة "رمز - اسم")
  final collegeCourses = <String, Map<String, List<String>>>{
    'طلاب': {},
    'طالبات': {},
  };

  void readCollegeSheet(String sheetName, String shatr) {
    final sheet = source.tables[sheetName]!;
    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final dept = row.isNotEmpty ? row[0]?.value?.toString().trim() ?? '' : '';
      if (dept.isEmpty) continue;
      final code = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
      final name = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
      if (code.isEmpty || name.isEmpty) continue;

      collegeCourses[shatr]!.putIfAbsent(dept, () => []).add('$code - $name');
    }
  }

  readCollegeSheet('مقررات الكلية - طلاب', 'طلاب');
  readCollegeSheet('مقررات الكلية - طالبات', 'طالبات');

  // مواد خارج الكلية (إجباري/اختياري) - عامة لكل الأقسام في نفس الشطر
  final outsideCourses = <String, List<String>>{'طلاب': [], 'طالبات': []};
  void readOutsideSheet(String sheetName, String shatr) {
    final sheet = source.tables[sheetName]!;
    for (var r = 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final type = row.isNotEmpty ? row[0]?.value?.toString().trim() ?? '' : '';
      final code = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
      final name = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
      if (code.isEmpty || name.isEmpty) continue;
      outsideCourses[shatr]!.add('$code - $name ($type)');
    }
  }

  readOutsideSheet('مواد خارج الكلية - طلاب', 'طلاب');
  readOutsideSheet('مواد خارج الكلية - طالبات', 'طالبات');

  const deptLabels = {
    'الإدارة': 'قسم الادارة',
    'المحاسبة': 'قسم المحاسبة',
    'التسويق': 'قسم التسويق',
    'الاقتصاد والتمويل': 'قسم الاقتصاد و التمويل',
    'نظم المعلومات الإدارية': 'قسم نظم المعلومات الادارية',
  };

  final output = Excel.createExcel();
  output.rename('Sheet1', 'تعليمات آلية التفريع');
  final instructions = output.sheets['تعليمات آلية التفريع']!;
  final lines = <String>[
    'كيفية بناء التفريع في مايكروسوفت فورمز لسؤال "المقرر الدراسي"',
    '',
    '1. أنشئ سؤال "القسم العلمي" (اختيار من متعدد) بخيارات: قسم الادارة، قسم المحاسبة، '
        'قسم التسويق، قسم الاقتصاد و التمويل، قسم نظم المعلومات الادارية.',
    '2. لكل قسم من الأقسام الخمسة، أنشئ سؤال "المقرر الدراسي - <اسم القسم>" (اختيار من متعدد).',
    '3. افتح خيارات نسخ ولصق للسؤال (النقاط الثلاث أعلى يمين السؤال ثم "عرض خيارات النسخ واللصق")،'
        ' وألصق فيه كامل عمود الخيارات من ورقة القسم المطابقة في هذا الملف دفعة واحدة.',
    '4. من إعدادات فورمز اضغط على أيقونة "التفرع" (Branching) أعلى الصفحة، وحدد أنه عند اختيار'
        ' كل قسم في سؤال "القسم العلمي" ينتقل المستخدم إلى سؤال "المقرر الدراسي" الخاص بذلك القسم فقط.',
    '5. بعد كل سؤال قسم، فرّع مباشرة إلى السؤال التالي المشترك (نوع الإجراء، سبب الطلب...) '
        'حتى لا يمر الطالب على أسئلة الأقسام الأخرى.',
    '6. مواد "مشترك بين الأقسام" مُدرجة تلقائيًا داخل قائمة كل قسم في هذا الملف (لا حاجة لتكرارها يدويًا).',
    '7. المواد الإجبارية والاختيارية خارج الكلية (لغة، ثقافة إسلامية...) عامة لكل الأقسام - '
        'ضعها في سؤال منفصل "مقرر خارج الكلية" يظهر لكل الطلاب بعد سؤال الشطر مباشرة (بلا حاجة لتفريع حسب القسم)،'
        ' وخياراته في ورقة "مواد خارج الكلية".',
    '8. كرر كل الخطوات السابقة مرتين: مرة لفرع "شطر الطلاب" ومرة لفرع "شطر الطالبات"،'
        ' فأول تفريع في النموذج يجب أن يكون حسب سؤال "مقر الدراسة (الشطر)".',
    '',
    'ورقات هذا الملف:',
    '- ورقة واحدة لكل (شطر × قسم): عمود الخيارات جاهز للنسخ.',
    '- ورقة "مواد خارج الكلية - طلاب/طالبات": خيارات سؤال المقرر خارج الكلية.',
  ];
  for (var i = 0; i < lines.length; i++) {
    instructions.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i)).value =
        TextCellValue(lines[i]);
  }
  instructions.setColumnWidth(0, 110);

  for (final shatr in ['طلاب', 'طالبات']) {
    final shared = collegeCourses[shatr]!['مشترك بين الأقسام'] ?? [];
    for (final entry in deptLabels.entries) {
      final deptKey = entry.key;
      final deptLabel = entry.value;
      final options = <String>[...(collegeCourses[shatr]![deptKey] ?? []), ...shared];
      final sheetName = '$shatr - $deptLabel';
      final sheet = output[sheetName];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          TextCellValue('خيارات سؤال "المقرر الدراسي - $deptLabel" ($shatr)');
      for (var i = 0; i < options.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value =
            TextCellValue(options[i]);
      }
      sheet.setColumnWidth(0, 60);
    }

    final outsideSheet = output['مواد خارج الكلية - $shatr'];
    outsideSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('خيارات سؤال "مقرر خارج الكلية" ($shatr)');
    final outside = outsideCourses[shatr]!;
    for (var i = 0; i < outside.length; i++) {
      outsideSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value =
          TextCellValue(outside[i]);
    }
    outsideSheet.setColumnWidth(0, 60);
  }

  final outBytes = output.encode()!;
  File(outputPath).writeAsBytesSync(outBytes);
  stdout.writeln('تم إنشاء الملف: $outputPath');
}
