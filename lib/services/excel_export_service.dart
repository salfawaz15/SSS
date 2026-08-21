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
  static const String advisorStatusHeader = 'حالة الإنجاز من قبل المرشد الأكاديمي';
  static const String advisorNotesHeader = 'ملاحظات المرشد الأكاديمي';
  static const String advisorOtherReasonHeader = 'يرجى كتابة السبب الآخر (فقط إن اخترت "سبب آخر")';
  static const String coordinatorStatusHeader = 'حالة الإنجاز من قبل منسق القسم';
  static const String coordinatorNotesHeader = 'ملاحظات منسق القسم';
  static const String collegeStatusHeader = 'حالة الإنجاز من قبل منسق الكلية';
  static const String collegeNotesHeader = 'ملاحظات منسق الكلية';

  /// خيارات "من أنجز فعليًا" - لم تعد عمودًا يدويًا، بل تُستنتَج تلقائيًا من
  /// أي عمود حالة (مرشد/منسق قسم/منسق كلية) يحمل "تم الإنجاز" أولاً حسب
  /// ترتيب التصعيد؛ هذه القائمة تُستخدم فقط لتهيئة عدّاد تفصيل التقرير الشامل
  static const List<String> completionSourceOptions = [
    'المرشد الأكاديمي',
    'منسق القسم',
    'منسق الكلية',
  ];

  /// قائمة أسباب عدم التنفيذ الجاهزة لعمود "ملاحظات المرشد الأكاديمي" -
  /// إلزامية (Strict) بلا كتابة حرة؛ لو لم ينطبق أي سبب مما تبقّى يختار
  /// المرشد "سبب آخر" ويكتب التفصيل في عمود [advisorOtherReasonHeader]
  /// المنفصل بدلاً من ذلك.
  static const List<String> advisorReasonOptions = [
    'الشعبة مكتملة (اكتملت طاقتها الاستيعابية)',
    'المادة لها متطلب سابق لم يُنهِه الطالب',
    'المادة متطلب لمادة أخرى مسجَّل بها الطالب حاليًا',
    'الطالب وصل الحد الأقصى المسموح من الساعات',
    'تعارض في الجدول مع مادة أخرى مسجَّلة',
    'الطالب سيهبط عن الحد الأدنى المسموح من الساعات',
    'المادة غير مطروحة (لا توجد أي شعبة لها هذا الفصل)',
    'الطالب مسجَّل بالفعل بشعبة أخرى لنفس المادة',
    'سبق للطالب اجتياز المادة بنجاح',
    'الطالب غير مسجَّل أصلًا بهذه الشعبة',
    'سبب آخر',
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
    advisorStatusHeader,
    advisorNotesHeader,
    advisorOtherReasonHeader,
    coordinatorStatusHeader,
    coordinatorNotesHeader,
    collegeStatusHeader,
    collegeNotesHeader,
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
    28,
    16,
    24,
    16,
    24,
  ];

  /// فهرس عمود "حالة الإنجاز من قبل المرشد الأكاديمي" (صفر-فهرسة)
  static const int advisorStatusColumnIndex = 12;

  /// فهرس عمود "ملاحظات المرشد الأكاديمي" (قائمة أسباب جاهزة - صفر-فهرسة)
  static const int advisorNotesColumnIndex = 13;

  /// فهرس عمود "يرجى كتابة السبب الآخر" (نص حر، يُستخدم فقط عند اختيار
  /// "سبب آخر" بعمود الملاحظات - صفر-فهرسة)
  static const int advisorOtherReasonColumnIndex = 14;

  /// فهرس عمود "حالة الإنجاز من قبل منسق القسم" (صفر-فهرسة)
  static const int coordinatorStatusColumnIndex = 15;

  /// فهرس عمود "ملاحظات منسق القسم" (صفر-فهرسة)
  static const int coordinatorNotesColumnIndex = 16;

  /// فهرس عمود "حالة الإنجاز من قبل منسق الكلية" (صفر-فهرسة)
  static const int collegeStatusColumnIndex = 17;

  /// فهرس عمود "ملاحظات منسق الكلية" (صفر-فهرسة)
  static const int collegeNotesColumnIndex = 18;

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

  /// نص شريط التعليمات الموجز أعلى ملف المرشد - يشرح خياري القائمة المنسدلة
  /// بكلمات بسيطة بدل ترك المرشد يخمّن معناها.
  static const String advisorInstructionsText =
      'تعليمات: 1) اختر من القائمة المنسدلة في عمود "حالة الإنجاز من قبل المرشد الأكاديمي" '
      'إمّا "تم التنفيذ" أو "لم يتم التنفيذ". 2) إن اخترت "لم يتم التنفيذ" اختر السبب من '
      'القائمة المنسدلة في عمود "ملاحظات المرشد الأكاديمي" - وفقط إن لم ينطبق أي سبب اختر '
      '"سبب آخر" واكتب التفصيل في العمود الأخير "يرجى كتابة السبب الآخر".';

  /// يبني ملف Excel حقيقي (.xlsx) لتذاكر قسم واحد ويرجّع بايتاته.
  /// [includeInstructions] يضيف صفًا مدمَجًا أعلى العناوين بشرح موجز لكيفية
  /// استخدام قائمة "حالة الإنجاز" المنسدلة - يُستخدم فقط لملف المرشد نفسه
  /// (لا لملفات أخرى تُبنى بنفس الدالة كالتصعيد/ذوي الإعاقة).
  static Uint8List buildDepartmentWorkbook(
    List<Map<String, dynamic>> tickets, {
    bool includeInstructions = false,
  }) {
    final workbook = Excel.createExcel();
    final sheetName = workbook.getDefaultSheet()!;
    final sheet = workbook[sheetName];

    for (var c = 0; c < _columnWidths.length; c++) {
      sheet.setColumnWidth(c, _columnWidths[c]);
    }

    final headerRowIndex = includeInstructions ? 1 : 0;

    if (includeInstructions) {
      sheet.appendRow([TextCellValue(advisorInstructionsText)]);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: _headers.length - 1, rowIndex: 0),
      );
      sheet.setRowHeight(0, 30);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FF154B36'),
        backgroundColorHex: ExcelColor.fromHexString('FFFCE8B2'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );
    }

    sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
    for (var c = 0; c < _headers.length; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIndex))
              .cellStyle =
          _headerStyle();
    }

    var dataRowIndex = 0; // صفر-فهرسة بين صفوف البيانات (بدون العناوين/التعليمات)

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
          ' ',
          ' ',
          ' ',
          ' ',
        ], dataRowIndex, headerRowIndex);
        dataRowIndex++;
        continue;
      }

      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final advisorStatus = (action['advisor_status'] ?? '').toString();
        final advisorNotes = (action['advisor_notes'] ?? '').toString();
        final advisorOtherReason = (action['advisor_other_reason'] ?? '').toString();
        final coordinatorStatus = (action['coordinator_status'] ?? '').toString();
        final coordinatorNotes = (action['coordinator_notes'] ?? '').toString();
        final collegeStatus = (action['college_status'] ?? '').toString();
        final collegeNotes = (action['college_notes'] ?? '').toString();
        final row = [
          ...baseInfo,
          action['action_type'] ?? '',
          action['course'] ?? '',
          action['required_section'] ?? action['current_section'] ?? '',
          action['reason_detail'] ?? action['reason'] ?? '',
          advisorStatus.isEmpty ? ' ' : advisorStatus,
          advisorNotes.isEmpty ? ' ' : advisorNotes,
          advisorOtherReason.isEmpty ? ' ' : advisorOtherReason,
          coordinatorStatus.isEmpty ? ' ' : coordinatorStatus,
          coordinatorNotes.isEmpty ? ' ' : coordinatorNotes,
          collegeStatus.isEmpty ? ' ' : collegeStatus,
          collegeNotes.isEmpty ? ' ' : collegeNotes,
        ];
        _appendStyledRow(sheet, row, dataRowIndex, headerRowIndex);
        dataRowIndex++;
      }
    }

    return Uint8List.fromList(workbook.encode()!);
  }

  static void _appendStyledRow(
    Sheet sheet,
    List<dynamic> values,
    int dataRowIndex,
    int headerRowIndex,
  ) {
    sheet.appendRow(values.map((v) => TextCellValue(v.toString())).toList());
    final rowIndex = dataRowIndex + headerRowIndex + 1; // بعد صف(وف) العناوين/التعليمات
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
