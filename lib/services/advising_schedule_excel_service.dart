import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import '../models/advising_schedule.dart';
import 'excel_protection_service.dart';

/// يبني ويقرأ نموذج Excel بسيط لتوزيع فترات الإرشاد - ملف واحد يصلح لأي
/// قسم: يختار مسؤول القسم شطره ثم قسمه أعلى النموذج، فتتحدَّث قائمة الأسماء
/// تلقائيًا لتعرض منسوبي هذا القسم/الشطر فقط (بلا أي استثناء لأصحاب
/// المناصب - قد يترك أحدهم منصبه لاحقًا). صف واحد لكل عضو (لا تكرار)،
/// وعمود لكل يوم يحدَّد فيه فترة العضو (إن وُجدت). رقم المكتب يظهر تلقائيًا
/// عند اختيار الاسم. لا صور/شعارات مضمَّنة (سبّبت تلف الملف)، ولا حماية
/// صارمة (يعبّئه مسؤول موثوق كرئيس القسم/الأمين/منسّق الوحدة).
class AdvisingScheduleExcelService {
  static const List<String> departmentOptions = [
    'قسم الإدارة',
    'قسم المحاسبة',
    'قسم التسويق',
    'قسم الاقتصاد والتمويل',
    'قسم نظم المعلومات الإدارية',
  ];
  static const List<String> shatrOptions = ['شطر الطلاب', 'شطر الطالبات'];
  static const List<String> dayColumnLabels = ['اليوم الأول', 'اليوم الثاني', 'اليوم الثالث'];
  static const List<String> periodOptions = ['الفترة الأولى', 'الفترة الثانية', 'الفترة الثالثة'];
  static const _headers = ['م', 'اسم المرشد الأكاديمي', 'رقم المكتب', ...dayColumnLabels];

  static const _mainSheetName = 'توزيع الإرشاد';
  static const _namesSheetName = 'قائمة الأسماء';

  static final _green = xls.ExcelColor.fromHexString('FF154B36');
  static final _greenDark = xls.ExcelColor.fromHexString('FF0D3324');

  /// اسم نطاق معرَّف صالح لكل (قسم، شطر) - أرقام بدل نص عربي لتفادي أي قيود
  /// على أسماء النطاقات المعرَّفة في بعض إصدارات إكسل.
  static String _rangeNameFor(int deptIndex, int shatrIndex) => 'قائمة_${deptIndex}_$shatrIndex';

  /// [membersByDeptShatr] كل الأعضاء مُصنَّفين حسب (القسم، الشطر) ← (اسم ←
  /// رقم مكتب معروف حاليًا، فارغ إن لم يُعرف بعد).
  static Uint8List buildTemplate({
    required Map<(String, String), Map<String, String>> membersByDeptShatr,
  }) {
    final excel = xls.Excel.createExcel();
    excel.rename('Sheet1', _mainSheetName);
    final sheet = excel[_mainSheetName];

    // صف الهوية البصرية: خلية واحدة مدموجة عبر كل الأعمدة - شريط متصل حقيقي
    // بلا أي فجوة. الدمج آمن الآن لأن ExcelProtectionService يُدرِج
    // dataValidations بعد mergeCells دائمًا (كان الترتيب الخاطئ سابقًا هو
    // سبب تلف الملف، وليس الدمج نفسه).
    final bannerStyle = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.white,
      backgroundColorHex: _green,
      fontSize: 14,
      horizontalAlign: xls.HorizontalAlign.Center,
    );
    sheet.merge(
      xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      xls.CellIndex.indexByColumnRow(columnIndex: _headers.length - 1, rowIndex: 0),
    );
    for (var c = 0; c < _headers.length; c++) {
      final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = bannerStyle;
      if (c == 0) {
        cell.value = xls.TextCellValue('وحدة الإرشاد الأكاديمي والخريجين - نموذج توزيع فترات الإرشاد');
      }
    }
    sheet.setRowHeight(0, 26);

    // صف اختيار الشطر ثم القسم (مرّة واحدة لكل الملف) - الشطر يسبق القسم
    final selectorLabelStyle = xls.CellStyle(bold: true, backgroundColorHex: xls.ExcelColor.fromHexString('FFF7F5EF'));
    final selectorValueStyle = xls.CellStyle(
      backgroundColorHex: xls.ExcelColor.fromHexString('FFFFF8E1'),
      fontColorHex: xls.ExcelColor.fromHexString('FF7A5C00'),
      bold: true,
    );
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = xls.TextCellValue('الشطر:');
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).cellStyle = selectorLabelStyle;
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).cellStyle = selectorValueStyle;
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = xls.TextCellValue('القسم:');
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).cellStyle = selectorLabelStyle;
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).cellStyle = selectorValueStyle;
    for (var c = 4; c < _headers.length; c++) {
      sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1)).cellStyle = selectorLabelStyle;
    }
    sheet.setRowHeight(1, 22);

    // صف عناوين الأعمدة
    final headerStyle = xls.CellStyle(bold: true, fontColorHex: xls.ExcelColor.white, backgroundColorHex: _greenDark);
    for (var c = 0; c < _headers.length; c++) {
      final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2));
      cell.value = xls.TextCellValue(_headers[c]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(c, c == 1 ? 30 : 18);
    }

    // ورقة مرجعية مخفية: كل الأعضاء مرتَّبين حسب (القسم، الشطر) في كتل
    // متجاورة، ونطاق معرَّف لكل كتلة (قائمة_<فهرس القسم>_<فهرس الشطر>)
    // يُستخدم عبر INDIRECT في القائمة المنسدلة الرئيسية - بذلك تتغيّر قائمة
    // الأسماء المعروضة تلقائيًا حسب اختيار الشطر/القسم أعلى النموذج.
    final namesSheet = excel[_namesSheetName];
    namesSheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = xls.TextCellValue('الاسم');
    namesSheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = xls.TextCellValue('رقم المكتب');

    final definedNames = <String, String>{};
    var namesRow = 1; // صفر-فهرسة، أول صف بيانات
    for (var di = 0; di < departmentOptions.length; di++) {
      for (var si = 0; si < shatrOptions.length; si++) {
        final members = membersByDeptShatr[(departmentOptions[di], shatrOptions[si])] ?? const {};
        final names = members.keys.toList()..sort();
        final startRow = namesRow + 1; // رقم صف إكسل (1-فهرسة)
        for (final name in names) {
          namesSheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: namesRow)).value =
              xls.TextCellValue(name);
          final office = members[name] ?? '';
          if (office.isNotEmpty) {
            namesSheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: namesRow)).value =
                xls.TextCellValue(office);
          }
          namesRow++;
        }
        final endRow = namesRow; // آخر صف مُستخدَم (1-فهرسة) لهذه الكتلة
        // نطاق بخلية واحدة فارغة إذا لا يوجد أعضاء بعد - يمنع مرجعًا فارغًا غير صالح
        final rangeStart = names.isEmpty ? startRow : startRow;
        final rangeEnd = names.isEmpty ? startRow : endRow;
        definedNames[_rangeNameFor(di, si)] = "'$_namesSheetName'!\$A\$$rangeStart:\$A\$$rangeEnd";
      }
    }

    // صفوف بيانات فارغة (حتى 90 عضوًا) - العضو يُختار من القائمة المتغيّرة
    const maxRows = 90;
    for (var i = 0; i < maxRows; i++) {
      final rowIndex = i + 3;
      sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = xls.IntCellValue(i + 1);
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .setFormula('IFERROR(VLOOKUP(B${rowIndex + 1},\'$_namesSheetName\'!A:B,2,FALSE),"")');
    }

    final bytesNoProtection = excel.encode()!;

    // صيغة القائمة المنسدلة لاسم المرشد: تبني اسم النطاق المعرَّف من قيمتي
    // الشطر/القسم المختارتين أعلى النموذج (B2, D2) عبر INDIRECT.
    final nameListFormula = 'INDIRECT("قائمة_"&(MATCH(\$D\$2,{"${departmentOptions.join('","')}"},0)-1)'
        '&"_"&(MATCH(\$B\$2,{"${shatrOptions.join('","')}"},0)-1))';

    final dropdowns = <DropdownColumn>[
      DropdownColumn(columnIndex: 1, options: shatrOptions, sqrefOverride: 'B2:B2'),
      DropdownColumn(columnIndex: 3, options: departmentOptions, sqrefOverride: 'D2:D2'),
      DropdownColumn(columnIndex: 1, strict: false, rangeFormula: nameListFormula),
      for (var c = 3; c <= 5; c++) DropdownColumn(columnIndex: c, options: periodOptions, strict: false),
    ];

    final protected = ExcelProtectionService.protect(
      Uint8List.fromList(bytesNoProtection),
      headerRowCount: 3,
      dataRowCount: maxRows,
      unlockedColumnIndexes: const [0, 1, 3, 4, 5],
      unlockedCellRefs: const ['B2', 'D2'],
      dropdowns: dropdowns,
      // بلا قفل/كلمة مرور - يعبّئه مسؤول موثوق، والقوائم المنسدلة إرشادية كافية
      addProtection: false,
    );

    return ExcelProtectionService.finalizeWorkbook(
      protected,
      hiddenSheetNames: [_namesSheetName],
      definedNames: definedNames,
    );
  }

  /// يقرأ نموذجًا مُعبَّأً: الشطر/القسم من أعلى النموذج (قيمة واحدة تنطبق
  /// على الملف كله)، ثم صف لكل عضو وحتى 3 فترات (عمود لكل يوم) لهذا العضو.
  static ({String department, String shatr, List<AdvisingScheduleSlot> slots}) parseTemplate(Uint8List bytes) {
    final excel = xls.Excel.decodeBytes(bytes);
    final sheet = excel.tables[_mainSheetName] ?? excel.tables[excel.tables.keys.first]!;

    String cellAt(List<xls.Data?> row, int c) => c < row.length ? (row[c]?.value?.toString() ?? '').trim() : '';

    final selectorRow = sheet.row(1);
    final shatr = cellAt(selectorRow, 1);
    final department = cellAt(selectorRow, 3);

    final grouped = <String, List<AdvisingScheduleEntry>>{};
    final order = <String>[];
    for (var r = 3; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final name = cellAt(row, 1);
      final office = cellAt(row, 2);
      if (name.isEmpty) continue;
      for (var d = 0; d < dayColumnLabels.length; d++) {
        final period = cellAt(row, 3 + d);
        if (period.isEmpty) continue;
        final key = '${dayColumnLabels[d]}|$period';
        if (!grouped.containsKey(key)) order.add(key);
        grouped.putIfAbsent(key, () => []).add(AdvisingScheduleEntry.clean(advisorName: name, office: office));
      }
    }

    final slots = order.map((key) {
      final parts = key.split('|');
      return AdvisingScheduleSlot(dayLabel: parts[0], periodLabel: parts[1], entries: grouped[key]!);
    }).toList();

    return (department: department, shatr: shatr, slots: slots);
  }
}
