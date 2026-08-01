import 'dart:typed_data';

import 'package:excel/excel.dart';

class ExcelExportService {
  // أسماء عناوين الأعمدة المرجعية - تُستخدم أيضًا عند إعادة قراءة الملفات
  // المعالَجة العائدة من المرشدين (ProcessedFileParserService) للبحث عن
  // العمود المطلوب بالاسم بدل الفهرس الثابت.
  static const String universityIdHeader = 'الرقم الجامعي';
  static const String actionTypeHeader = 'نوع الإجراء';
  static const String courseHeader = 'المقرر';
  static const String requiredSectionHeader = 'رقم الشعبة';
  static const String statusHeader = 'حالة الإنجاز';
  static const String notesHeader = 'ملاحظات';
  static const String completedByHeader = 'أُنجز من قبل';

  /// خيارات قائمة "أُنجز من قبل" المنسدلة - عمود اختياري لتوضيح الجهة التي
  /// أنجزت الطلب فعليًا (يُستخدم لاحقًا في تفصيل التقرير الشامل)
  static const List<String> completedByOptions = [
    'المرشد الأكاديمي',
    'منسق القسم',
    'وحدة الإرشاد الأكاديمي',
    'منسق الكلية',
  ];

  static const List<String> _headers = [
    'اسم الطالب',
    universityIdHeader,
    'الشطر',
    'القسم',
    'المرشد الأكاديمي',
    'رقم الجوال',
    'خريج متوقع',
    'ذوي إعاقة',
    actionTypeHeader,
    courseHeader,
    requiredSectionHeader,
    'سبب الطلب',
    statusHeader,
    notesHeader,
    completedByHeader,
  ];

  static const List<double> _columnWidths = [
    36,
    14,
    12,
    22,
    20,
    14,
    10,
    10,
    16,
    18,
    12,
    22,
    16,
    24,
    20,
  ];

  /// فهرس عمود "حالة الإنجاز" (صفر-فهرسة) في الملف المُصدَّر
  static const int statusColumnIndex = 12;

  /// فهرس عمود "ملاحظات" (صفر-فهرسة) في الملف المُصدَّر
  static const int notesColumnIndex = 13;

  /// فهرس عمود "أُنجز من قبل" (صفر-فهرسة) في الملف المُصدَّر
  static const int completedByColumnIndex = 14;

  static final _thinGrayBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('FFB9C4BF'),
  );

  static CellStyle _headerStyle() => CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _thinGrayBorder,
    rightBorder: _thinGrayBorder,
    topBorder: _thinGrayBorder,
    bottomBorder: _thinGrayBorder,
  );

  static CellStyle _rowStyle({required bool alternate}) => CellStyle(
    backgroundColorHex: alternate
        ? ExcelColor.fromHexString('FFEFF5F2')
        : ExcelColor.white,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _thinGrayBorder,
    rightBorder: _thinGrayBorder,
    topBorder: _thinGrayBorder,
    bottomBorder: _thinGrayBorder,
  );

  /// يبني ملف Excel حقيقي (.xlsx) لتذاكر قسم واحد ويرجّع بايتاته
  static Uint8List buildDepartmentWorkbook(List<Map<String, dynamic>> tickets) {
    final workbook = Excel.createExcel();
    final sheetName = workbook.getDefaultSheet()!;
    final sheet = workbook[sheetName];

    for (var c = 0; c < _columnWidths.length; c++) {
      sheet.setColumnWidth(c, _columnWidths[c]);
    }

    sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
    for (var c = 0; c < _headers.length; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .cellStyle =
          _headerStyle();
    }

    var dataRowIndex = 0; // صفر-فهرسة بين صفوف البيانات (بدون العناوين)

    for (final t in tickets) {
      final baseInfo = [
        t['name'] ?? '',
        t['university_id'] ?? '',
        t['shatr'] ?? '',
        t['department'] ?? '',
        t['advisor'] ?? '',
        t['phone'] ?? '',
        (t['expected_graduate'] == true) ? 'نعم' : 'لا',
        (t['has_disability'] == true) ? 'نعم' : 'لا',
      ];
      final actions = (t['actions'] as List?) ?? [];

      if (actions.isEmpty) {
        _appendStyledRow(sheet, [
          ...baseInfo,
          '',
          '',
          '',
          '',
          ' ',
          ' ',
          ' ',
        ], dataRowIndex);
        dataRowIndex++;
        continue;
      }

      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final status = (action['status'] ?? '').toString();
        final notes = (action['notes'] ?? '').toString();
        final completedBy = (action['completed_by'] ?? '').toString();
        final row = [
          ...baseInfo,
          action['action_type'] ?? '',
          action['course'] ?? '',
          action['required_section'] ?? action['current_section'] ?? '',
          action['reason_detail'] ?? action['reason'] ?? '',
          status.isEmpty ? ' ' : status,
          notes.isEmpty ? ' ' : notes,
          completedBy.isEmpty ? ' ' : completedBy,
        ];
        _appendStyledRow(sheet, row, dataRowIndex);
        dataRowIndex++;
      }
    }

    return Uint8List.fromList(workbook.encode()!);
  }

  static void _appendStyledRow(
    Sheet sheet,
    List<dynamic> values,
    int dataRowIndex,
  ) {
    sheet.appendRow(values.map((v) => TextCellValue(v.toString())).toList());
    final rowIndex = dataRowIndex + 1; // +1 لصف العناوين
    final style = _rowStyle(alternate: dataRowIndex.isEven);
    for (var c = 0; c < values.length; c++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex),
              )
              .cellStyle =
          style;
    }
  }
}
