import 'dart:io';
import 'package:excel/excel.dart';

/// يضيف عمودًا جديدًا "قرار تخفيض النصاب" (3 قيم: الحد الأدنى / 50% / بدون
/// تخفيض نصاب) قبل عمود "نصاب عضو هيئة التدريس" مباشرة، ثم يستبدل قيمة ذلك
/// العمود الثابتة بمعادلة إكسل حية تحسب النصاب الفعلي من الدرجة العلمية
/// وقرار التخفيض معًا - أداة تشغيل لمرة واحدة.
void main() {
  const path =
      'المرفقات/أعضاء هيئة التدريس/قالب البيانات النهائي بعد تحديث المبتعثين 06-08-2026م.xlsx';

  final bytes = File(path).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['منسوبو الكلية'];
  if (sheet == null) {
    stderr.writeln('لم أجد ورقة "منسوبو الكلية"');
    exit(1);
  }

  const rankColIndex = 7; // الدرجة العلمية (H)
  const assignmentColIndex = 8; // نوع التكليف (I)
  const otherPositionColIndex = 10; // منصب آخر (K)
  const decisionColIndex = 12; // قرار تخفيض النصاب (جديد - يُدرَج هنا)
  const teachingColIndex = 13; // نصاب عضو هيئة التدريس (بعد الإزاحة)
  const statusColIndexOld = 15; // حالة الموظف (قبل الإزاحة، سيصبح 16)

  final maxCol = sheet.row(0).length;
  final maxRow = sheet.maxRows;

  // 1) إزاحة كل الأعمدة من decisionColIndex فصاعدًا خانة واحدة لليمين.
  for (var r = 0; r < maxRow; r++) {
    for (var c = maxCol - 1; c >= decisionColIndex; c--) {
      final srcCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      final destCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c + 1, rowIndex: r));
      destCell.value = srcCell.value;
      if (srcCell.cellStyle != null) destCell.cellStyle = srcCell.cellStyle;
    }
  }

  // 2) عنوان العمود الجديد.
  final headerStyle =
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: teachingColIndex, rowIndex: 0)).cellStyle;
  final decisionHeaderCell =
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: decisionColIndex, rowIndex: 0));
  decisionHeaderCell.value = TextCellValue('قرار تخفيض النصاب');
  if (headerStyle != null) decisionHeaderCell.cellStyle = headerStyle;
  sheet.setColumnWidth(decisionColIndex, 20);

  // 3) حالات معروفة صراحةً بالاسم (تعليمات المستخدم المباشرة).
  const minimumNames = {'فؤاد'}; // فؤاد جعماني
  const halfNames = {'خليل', 'قظيع'}; // خليل الرتيعي، سالم آل قظيع

  String colLetter(int i) => String.fromCharCode('A'.codeUnitAt(0) + i);

  var minCount = 0, halfCount = 0, noneCount = 0, excludedCount = 0;

  for (var r = 1; r < maxRow; r++) {
    final name = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
            .value
            ?.toString()
            .trim() ??
        '';
    if (name.isEmpty) continue;

    final position = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: assignmentColIndex, rowIndex: r))
            .value
            ?.toString()
            .trim() ??
        '';
    final otherPosition = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: otherPositionColIndex, rowIndex: r))
            .value
            ?.toString()
            .trim() ??
        '';
    final status = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: statusColIndexOld + 1, rowIndex: r))
            .value
            ?.toString()
            .trim() ??
        '';
    final combined = '$position $otherPosition $status';

    String decision;
    if (combined.contains('معار') || combined.contains('مجاز') || combined.contains('مبتعث')) {
      decision = ''; // لا يوجد نصاب - المعادلة تُرجع 0 بصرف النظر عن القرار
      excludedCount++;
    } else if (minimumNames.any((n) => name.contains(n))) {
      decision = 'الحد الأدنى';
      minCount++;
    } else if (halfNames.any((n) => name.contains(n))) {
      decision = '50%';
      halfCount++;
    } else if (position.contains('وكيل') ||
        position.contains('عميد') ||
        position.contains('رئيس قسم') ||
        position.contains('رئيسة قسم')) {
      decision = 'الحد الأدنى';
      minCount++;
    } else {
      decision = 'بدون تخفيض نصاب';
      noneCount++;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: decisionColIndex, rowIndex: r)).value =
        decision.isEmpty ? null : TextCellValue(decision);

    // 4) معادلة النصاب الفعلي في العمود التالي مباشرة.
    final excelRow = r + 1;
    final rankRef = '${colLetter(rankColIndex)}$excelRow';
    final posRef = '${colLetter(assignmentColIndex)}$excelRow';
    final otherRef = '${colLetter(otherPositionColIndex)}$excelRow';
    final decisionRef = '${colLetter(decisionColIndex)}$excelRow';
    final statusRef = '${colLetter(statusColIndexOld + 1)}$excelRow';

    final rankMax =
        'IF($rankRef="استاذ",10,IF($rankRef="استاذ مشارك",12,IF($rankRef="استاذ مساعد",14,16)))';
    final excludedExpr = 'OR(ISNUMBER(SEARCH("معار",$posRef&" "&$otherRef&" "&$statusRef))'
        ',ISNUMBER(SEARCH("مجاز",$posRef&" "&$otherRef&" "&$statusRef))'
        ',ISNUMBER(SEARCH("مبتعث",$posRef&" "&$otherRef&" "&$statusRef)))';
    final formula = '=IF($excludedExpr,0,'
        'IF($decisionRef="الحد الأدنى",3,'
        'IF($decisionRef="50%",ROUND($rankMax/2,0),'
        '$rankMax)))';

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: teachingColIndex, rowIndex: r))
        .setFormula(formula);
  }

  File(path).writeAsBytesSync(excel.encode()!);
  stdout.writeln(
      'تم: $minCount حد أدنى، $halfCount نسبة 50%، $noneCount بدون تخفيض، $excludedCount مستبعَد (معار/مجاز/مبتعث).');
}
