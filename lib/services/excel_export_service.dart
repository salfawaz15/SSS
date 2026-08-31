import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'advising_report_repository.dart';
import 'course_schedule_repository.dart' show Shatr;

class ExcelExportService {
  // أسماء عناوين الأعمدة المرجعية - تُستخدم أيضًا عند إعادة قراءة الملفات
  // المعالَجة العائدة من المرشدين (ProcessedFileParserService) للبحث عن
  // العمود المطلوب بالاسم بدل الفهرس الثابت.
  static const String studentNameHeader = 'اسم الطالب';
  static const String shatrHeader = 'الشطر';
  static const String departmentHeader = 'القسم';
  static const String advisorNameHeader = 'المرشد الأكاديمي';
  static const String universityIdHeader = 'الرقم الجامعي';
  static const String remainingHoursHeader = 'الساعات المتبقية';
  static const String gpaHeader = 'المعدل';
  static const String actionTypeHeader = 'نوع الإجراء';
  static const String reasonHeader = 'سبب الطلب';
  static const String courseNameHeader = 'اسم المقرر';
  static const String courseCodeHeader = 'رمز المقرر';
  static const String addSectionHeader = 'رقم الشعبة المراد إضافتها';
  static const String deleteSectionHeader = 'رقم الشعبة المراد حذفها';
  static const String currentSectionHeader = 'رقم الشعبة الحالية (المطلوب تعديلها)';
  static const String requestedSectionHeader = 'رقم الشعبة المطلوبة (بعد التعديل)';
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
    studentNameHeader,
    universityIdHeader,
    remainingHoursHeader,
    gpaHeader,
    shatrHeader,
    departmentHeader,
    advisorNameHeader,
    'رقم الجوال',
    'تصنيف أولوية التخرج',
    'ذوي إعاقة',
    actionTypeHeader,
    courseNameHeader,
    courseCodeHeader,
    addSectionHeader,
    deleteSectionHeader,
    currentSectionHeader,
    requestedSectionHeader,
    reasonHeader,
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
    14,
    10,
    12,
    22,
    20,
    14,
    10,
    10,
    16,
    30,
    14,
    16,
    16,
    16,
    16,
    42,
    16,
    24,
    28,
    16,
    24,
    16,
    24,
  ];

  /// فهرس عمود "الساعات المتبقية" (صفر-فهرسة) - قيمته تُكتَب رقمًا صحيحًا
  /// فعليًا (`IntCellValue`) لا نصًا، حتى يصح الفرز الرقمي لاحقًا لو فرزه
  /// المرشد يدويًا داخل إكسل (سليمان صراحةً 2026-08-27).
  /// عدد أعمدة ملف المرشد الكلي - يُستخدم خارجيًا (AdvisorZipService) لبناء
  /// مراجع خلايا صريحة تغطي كل الأعمدة بلا تكرار رقم 25 حرفيًا في مكانين.
  static int get columnCount => _headers.length;

  static const int remainingHoursColumnIndex = 2;

  /// فهرس عمود "المعدل" (صفر-فهرسة) - يُكتَب رقمًا عشريًا فعليًا
  /// (`DoubleCellValue`) لنفس سبب [remainingHoursColumnIndex].
  static const int gpaColumnIndex = 3;

  /// فهارس أعمدة موحَّدة القيمة عبر كل صفوف ملف مرشد واحد (كل ملف يخص مرشدًا
  /// بقسم/شطر واحد أصلاً عبر AdvisorZipService) - تكرارها بكل صف لا يفيد،
  /// تُخفى بملف المرشد تحديدًا (سليمان صراحةً 2026-08-25)، بخلاف الرقم
  /// الجامعي/اسم الطالب المختلفَين فعليًا بكل صف.
  static const int shatrColumnIndex = 4;
  static const int departmentColumnIndex = 5;
  static const int advisorNameColumnIndex = 6;

  /// فهرس عمود "رقم الجوال" - يُخفى بملف المرشد (سليمان صراحةً 2026-08-25:
  /// التواصل مع الطالب يكون عبر القنوات الرسمية فقط، لا هاتفيًا مباشرة).
  static const int phoneColumnIndex = 7;

  /// فهرس عمود "تصنيف أولوية التخرج" (صفر-فهرسة) - يُحسَب تلقائيًا للصفوف
  /// العادية من بيانات الطلبة الأكاديمية، لكن صفوف النموذج الورقي (بلا بيانات
  /// أكاديمية معروفة) يُختار له قائمة منسدلة يدويًا (نعم/لا)، انظر
  /// [AdvisorZipService.buildAdvisorFiles].
  static const int expectedGraduateColumnIndex = 8;

  /// فهرس عمود "ذوي إعاقة" (صفر-فهرسة) - قائمة منسدلة يدوية بصفوف النموذج
  /// الورقي تحديدًا (نعم/لا).
  static const int disabilityColumnIndex = 9;

  /// فهرس عمود "نوع الإجراء" (صفر-فهرسة) - قائمة منسدلة يدوية بصفوف النموذج
  /// الورقي تحديدًا (إضافة/حذف/تعديل) لمنع أخطاء إملائية حرة بكتابته يدويًا.
  static const int actionTypeColumnIndex = 10;

  /// فهرس عمود "رمز المقرر" - اسم المقرر وحده كافٍ عمليًا للمرشد.
  static const int courseCodeColumnIndex = 12;

  /// فهرس عمود "حالة الإنجاز من قبل المرشد الأكاديمي" (صفر-فهرسة)
  static const int advisorStatusColumnIndex = 18;

  /// فهرس عمود "ملاحظات المرشد الأكاديمي" (قائمة أسباب جاهزة - صفر-فهرسة)
  static const int advisorNotesColumnIndex = 19;

  /// فهرس عمود "يرجى كتابة السبب الآخر" (نص حر، يُستخدم فقط عند اختيار
  /// "سبب آخر" بعمود الملاحظات - صفر-فهرسة)
  static const int advisorOtherReasonColumnIndex = 20;

  /// فهرس عمود "حالة الإنجاز من قبل منسق القسم" (صفر-فهرسة)
  static const int coordinatorStatusColumnIndex = 21;

  /// فهرس عمود "ملاحظات منسق القسم" (صفر-فهرسة)
  static const int coordinatorNotesColumnIndex = 22;

  /// فهرس عمود "حالة الإنجاز من قبل منسق الكلية" (صفر-فهرسة)
  static const int collegeStatusColumnIndex = 23;

  /// فهرس عمود "ملاحظات منسق الكلية" (صفر-فهرسة)
  static const int collegeNotesColumnIndex = 24;

  static final _thinGrayBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('FFB9C4BF'),
  );

  static CellStyle _headerStyle({int? fontSize, Border? border}) => CellStyle(
    bold: true,
    fontSize: fontSize,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: border ?? _thinGrayBorder,
    rightBorder: border ?? _thinGrayBorder,
    topBorder: border ?? _thinGrayBorder,
    bottomBorder: border ?? _thinGrayBorder,
  );

  /// حدّ أثقل (أسمك وأغمق) من الحدّ الرفيع المعتاد - يُستخدم لإبراز صف
  /// العناوين المكرَّر بقسم النموذج الورقي بصريًا أكثر عن صف العناوين
  /// الأصلي، بطلب سليمان صراحةً (2026-09-02).
  static final _thickGoldBorder = Border(
    borderStyle: BorderStyle.Medium,
    borderColorHex: ExcelColor.fromHexString('FFFCE8B2'),
  );

  static CellStyle _rowStyle({required bool alternate, bool wrapText = false, String? backgroundColorHex}) => CellStyle(
    backgroundColorHex: backgroundColorHex != null
        ? ExcelColor.fromHexString(backgroundColorHex)
        : (alternate ? ExcelColor.fromHexString('FFEFF5F2') : ExcelColor.white),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: wrapText ? TextWrapping.WrapText : null,
    leftBorder: _thinGrayBorder,
    rightBorder: _thinGrayBorder,
    topBorder: _thinGrayBorder,
    bottomBorder: _thinGrayBorder,
  );

  /// فهرس عمود "سبب الطلب" (صفر-فهرسة) - قد يحوي عدة أسباب مفصولة بـ";"
  /// فيطول النص، يُفعَّل التفاف السطر له تحديدًا بدل قصّه بصريًا.
  static const int _reasonColumnIndex = 17;

  /// نص شريط التعليمات الموجز أعلى ملف المرشد - يشرح خياري القائمة المنسدلة
  /// بكلمات بسيطة بدل ترك المرشد يخمّن معناها.
  static const String advisorInstructionsText =
      'تعليمات: 1) اختر من القائمة المنسدلة في عمود "حالة الإنجاز من قبل المرشد الأكاديمي" '
      'إمّا "تم التنفيذ" أو "لم يتم التنفيذ". 2) إن اخترت "لم يتم التنفيذ" اختر السبب من '
      'القائمة المنسدلة في عمود "ملاحظات المرشد الأكاديمي" - وفقط إن لم ينطبق أي سبب اختر '
      '"سبب آخر" واكتب التفصيل في العمود الأخير "يرجى كتابة السبب الآخر". '
      '3) رُتبت الطلبات بحسب أولوية التخرّج وعدد الساعات المتبقية - يبدأ المرشد بمعالجة '
      'الطلبة المتوقع تخرجهم (صفوف وردية، 30 ساعة متبقية فأقل)، ثم القريبين من التخرج '
      '(صفوف صفراء، 31 أو 32 ساعة)، ثم بقية الطلبة، مع الالتزام بالترتيب الظاهر '
      'بالملف ومعالجة جميع طلبات الطالب قبل الانتقال للطالب التالي.';

  /// يحمّل خريطة (رقم جامعي ← الساعات المتبقية/المعدل) من "بيانات الطلبة
  /// الأكاديمية" لكلا الشطرين - تُستخدم لترتيب صفوف ملف المرشد حسب أولوية
  /// التخرّج (سليمان صراحةً 2026-08-27): طالب قليل الساعات المتبقية أولى
  /// بتسكينه بشعبته المطلوبة قبل أن تمتلئ، لأنه على الأرجح يتخرّج قريبًا.
  /// لا تُفشِل بناء الملف كاملاً لو تعذّر تحميل بيانات الطلبة الأكاديمية
  /// (Firestore غير مهيَّأ باختبار، أو خطأ شبكي عابر) - يُكمَل البناء ببيانات
  /// ساعات/معدل مجهولة للجميع (تنزل تلقائيًا لأسفل قائمة الأولوية) بدل توقّف
  /// العملية بالكامل.
  static Future<Map<String, ({int? remainingHours, double? gpa})>> _loadAcademicLookup() async {
    final lookup = <String, ({int? remainingHours, double? gpa})>{};
    try {
      final results = await Future.wait([
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.base),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.base),
      ]);
      for (final list in results) {
        for (final r in list) {
          lookup[r.studentId] = (remainingHours: r.remainingHours, gpa: r.gpa);
        }
      }
    } catch (_) {
      // يُكمَل ببيانات فارغة - انظر توثيق الدالة أعلاه.
    }
    return lookup;
  }

  /// ألوان دورية لصفوف عنوان اليوم (فاتحة، تسمح بقراءة نص أسود عليها) -
  /// تتكرر لو تجاوزت الدورة 3 أيام (سليمان صراحةً 2026-08-28).
  static const List<String> _dayHeaderColors = ['FFFDEBD3', 'FFD6EAF8', 'FFD5F5E3'];

  static CellStyle _dayTitleStyle(String colorHex) => CellStyle(
    bold: true,
    fontSize: 13,
    backgroundColorHex: ExcelColor.fromHexString(colorHex),
    horizontalAlign: HorizontalAlign.Right,
    verticalAlign: VerticalAlign.Center,
  );

  /// عدد الصفوف الفارغة المفتوحة للتحرير الكامل المضافة بنهاية ملف المرشد
  /// لتسجيل حالات النموذج الورقي يدويًا (توجيه إداري استثنائي خلال أيام
  /// الحذف والإضافة الثلاثة - سليمان صراحةً 2026-09-01/2026-09-02: بعض
  /// الطلبة واجهوا صعوبة بالتقديم عبر Microsoft Forms فسُمح لهم بنموذج ورقي
  /// بديل، وتبيّن أن بعض المرشدين استخدموه فعليًا منذ اليوم الأول (الأحد)
  /// لا اليوم الأخير فقط - تُدخَل بياناته يدويًا هنا من قبل المرشد، بصرف
  /// النظر عن اليوم الذي استُلمت فيه). راجع [ExcelProtectionService.protect]
  /// حيث تُفتَح كل أعمدة هذه الصفوف تحديدًا (بخلاف بقية الملف المقفل إلا
  /// ثلاثة أعمدة).
  static const int paperFormExtraRowCount = 20;

  /// عنوان صف الفاصل الذي يسبق صفوف النموذج الورقي الفارغة - نفس أسلوب عنوان
  /// اليوم لكن بنص توضيحي صريح ولون مميّز ثابت (لا يدور مع ألوان الأيام).
  static const String paperFormSectionTitle =
      'حالات النموذج الورقي (تُكتب هنا يدويًا) - أي حالة عولجت ورقيًا بأي يوم من أيام الحذف والإضافة';
  static const String _paperFormColorHex = 'FFE8D5F5';

  /// نص التعليمات فوق صفوف النموذج الورقي - يشرح طريقة التعبئة اليدوية مع
  /// تحذير صريح بشأن الرقم الجامعي (سليمان صراحةً 2026-09-01: أي خطأ فيه
  /// يمنع مطابقة الحالة لاحقًا بالنظام).
  /// خيارات القائمة المنسدلة لعمود "نوع الإجراء" بصفوف النموذج الورقي فقط.
  static const List<String> paperFormActionTypeOptions = ['إضافة', 'حذف', 'تعديل'];

  /// خيارات القائمة المنسدلة لعمود "ذوي إعاقة" بصفوف النموذج الورقي فقط.
  static const List<String> paperFormYesNoOptions = ['نعم', 'لا'];

  /// خيارات القائمة المنسدلة لعمود "تصنيف أولوية التخرج" بصفوف النموذج
  /// الورقي - نفس التصنيفات الفعلية المستخدَمة تلقائيًا بالصفوف العادية
  /// (انظر منطق GraduationTier أعلاه: 30 ساعة فأقل = متوقع تخرجه، 31-32 =
  /// قريب من التخرج)، بدل نعم/لا فقط (سليمان صراحةً 2026-09-02).
  static const List<String> paperFormGraduationPriorityOptions = [
    'متوقع تخرجه',
    'قريب من التخرج',
    'نعم',
    'لا',
  ];

  static const String paperFormInstructionsText =
      'تعليمات تعبئة حالات النموذج الورقي: هذه الصفوف مفتوحة بالكامل للتحرير (خلافًا لبقية '
      'الملف)، وتُستخدَم لأي حالة وصلتك ورقيًا سواء اليوم أو بأي يوم سابق من أيام الحذف '
      'والإضافة (لا يشترط أن تكون من اليوم الأخير). اكتب بيانات كل حالة كما لو كانت صفًا عاديًا: اسم '
      'الطالب، الرقم الجامعي، المقرر، نوع الإجراء (إضافة/حذف/تعديل)، والشعبة المطلوبة. '
      '⚠️ تنبيه مهم: تأكد تمامًا من كتابة الرقم الجامعي بشكل صحيح ودقيق دون أي خطأ - أي '
      'خطأ فيه يمنع مطابقة الحالة بالنظام لاحقًا. اترك أي صف فارغًا لم تحتجه. لتحديد حالة '
      'الإنجاز والملاحظات استخدم نفس القوائم المنسدلة المستخدَمة ببقية الملف.';

  /// يبني ملف Excel حقيقي (.xlsx) لتذاكر قسم واحد ويرجّع بايتاته مع
  /// [DepartmentWorkbookResult.totalDataRowCount] (كل الصفوف الفعلية تحت
  /// العناوين، شاملةً صفوف عنوان اليوم والفواصل الفارغة - لازم لضبط نطاق
  /// القوائم المنسدلة بشكل صحيح عند حماية الملف لاحقًا، انظر
  /// [ExcelProtectionService.protect]).
  /// [includeInstructions] يضيف صفًا مدمَجًا أعلى العناوين بشرح موجز لكيفية
  /// استخدام قائمة "حالة الإنجاز" المنسدلة - يُستخدم فقط لملف المرشد نفسه
  /// (لا لملفات أخرى تُبنى بنفس الدالة كالتصعيد/ذوي الإعاقة).
  /// [includePaperFormRows] يضيف بنهاية الملف [paperFormExtraRowCount] صفًا
  /// فارغًا مخصَّصًا لحالات النموذج الورقي - يُستخدم فقط لملف المرشد نفسه.
  static Future<DepartmentWorkbookResult> buildDepartmentWorkbook(
    List<Map<String, dynamic>> tickets, {
    bool includeInstructions = false,
    bool includePaperFormRows = false,
  }) async {
    final academicLookup = await _loadAcademicLookup();
    final workbook = Excel.createExcel();
    final defaultSheetName = workbook.getDefaultSheet()!;
    // اسم ورقة مهني بدل "Sheet1" الافتراضي (سليمان صراحةً 2026-08-27).
    const sheetName = 'طلبات المرشد';
    workbook.rename(defaultSheetName, sheetName);
    final sheet = workbook[sheetName];
    sheet.isRTL = true;

    for (var c = 0; c < _columnWidths.length; c++) {
      sheet.setColumnWidth(c, _columnWidths[c]);
    }

    final headerRowIndex = includeInstructions ? 1 : 0;

    if (includeInstructions) {
      // العمود A يُترَك فارغًا عمدًا - نص التعليمات يبدأ من B ليطابق نطاق
      // الدمج B-O أدناه (سليمان صراحةً 2026-08-27، ضُيِّق من A-P لاحقًا بسبب
      // ضيق الصفحة).
      sheet.appendRow([TextCellValue(''), TextCellValue(advisorInstructionsText)]);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: 0),
      );
      // ارتفاع أكبر (كان 30، ثم 90) - بعد تضييق نطاق الدمج يلتف النص لعدد
      // أسطر أكبر بنفس الطول، فيحتاج ارتفاعًا أكبر ليظهر كاملاً (سليمان
      // صراحةً 2026-08-27، بلقطة شاشة فعلية للملف).
      sheet.setRowHeight(0, 130);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FF154B36'),
        backgroundColorHex: ExcelColor.fromHexString('FFFCE8B2'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );
    }

    sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
    // ارتفاع أكبر من الافتراضي + التفاف نص مُفعَّل بـ_headerStyle - بعض
    // العناوين الطويلة (مثال: "رقم الشعبة المطلوبة (بعد التعديل)") كانت
    // تظهر مضغوطة بصف عناوين رفيع بلا التفاف (سليمان صراحةً 2026-08-27).
    sheet.setRowHeight(headerRowIndex, 45);
    for (var c = 0; c < _headers.length; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIndex))
              .cellStyle =
          _headerStyle();
    }

    // نجمّع كل (تذكرة، إجراء) بصف مستقل أولاً بدل الكتابة المباشرة، لنرتّبها
    // بعدها بترتيب جديد (سليمان صراحةً 2026-08-27): **الساعات المتبقية
    // تصاعديًا أولًا** (طالب قليل الساعات = قرب تخرّج = أولوية تسكين بشعبته
    // قبل امتلائها؛ طالب مجهول الساعات (غير موجود بملف بيانات الطلبة) يوضع
    // **بأسفل** القائمة - الأولوية للمؤكَّد قرب تخرّجهم لا للمجهولين)، ثم
    // **الرقم الجامعي تصاعديًا** كفاصل تعادل، مع إبقاء كل طلبات نفس الطالب
    // متتابعة كحزمة واحدة (إضافة ثم حذف ثم تعديل) بدل تشتتها بين كتل منفصلة
    // حسب نوع الإجراء كما كان سابقًا - يعدّل المرشد لكل طالب مرة واحدة بدل
    // البحث عنه في كل كتلة نوع إجراء على حدة.
    const unknownHoursSortKey = 1 << 30; // أكبر من أي عدد ساعات حقيقي فيوضع أخيرًا
    final rowSpecs = <_RowSpec>[];
    for (final t in tickets) {
      final studentId = (t['university_id'] ?? '').toString();
      // فارغ (بلا هذا الحقل - تذاكر أُدخلت قبل 2026-08-28) يُعامَل كأقدم يوم
      // فيظهر أولًا تلقائيًا (المقارنة النصية تضع "" قبل أي تاريخ حقيقي).
      final uploadedDate = (t['uploaded_date'] ?? '').toString();
      final academic = academicLookup[studentId];
      final remainingHours = academic?.remainingHours;
      final gpa = academic?.gpa;
      final hoursSortKey = remainingHours ?? unknownHoursSortKey;
      // تصنيف قرب التخرّج - بطلب سليمان صراحةً (2026-08-27): 30 ساعة متبقية
      // فأقل = "متوقع تخرجه" (تمييز وردي فاتح)، 31 أو 32 ساعة = "قريب من
      // التخرج" (تمييز أصفر فاتح)، 33 فأكثر = الحالة المعتادة (بلا تمييز،
      // القيمة الأصلية المُبلَّغ عنها ذاتيًا بالطلب).
      final GraduationTier tier;
      final String expectedGraduateLabel;
      if (remainingHours != null && remainingHours <= 30) {
        tier = GraduationTier.expected;
        expectedGraduateLabel = 'متوقع تخرجه';
      } else if (remainingHours != null && remainingHours <= 32) {
        tier = GraduationTier.near;
        expectedGraduateLabel = 'قريب من التخرج';
      } else {
        tier = GraduationTier.normal;
        expectedGraduateLabel = (t['expected_graduate'] == true) ? 'نعم' : 'لا';
      }
      final baseInfo = [
        t['name'] ?? '',
        studentId,
        remainingHours, // int? - يُكتَب رقمًا صحيحًا فعليًا لا نصًا، انظر _appendStyledRow
        gpa, // double? - يُكتَب رقمًا عشريًا فعليًا لا نصًا
        t['shatr'] ?? '',
        t['department'] ?? '',
        t['advisor'] ?? '',
        t['phone'] ?? '',
        expectedGraduateLabel,
        (t['has_disability'] == true) ? 'نعم' : 'لا',
      ];
      final actions = (t['actions'] as List?) ?? [];

      if (actions.isEmpty) {
        rowSpecs.add(_RowSpec(
          day: uploadedDate,
          hoursSortKey: hoursSortKey,
          studentId: studentId,
          actionPriority: 99,
          tier: tier,
          values: [
            ...baseInfo,
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
        ));
        continue;
      }

      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final actionType = (action['action_type'] ?? '').toString();
        final advisorStatus = (action['advisor_status'] ?? '').toString();
        final advisorNotes = (action['advisor_notes'] ?? '').toString();
        final advisorOtherReason = (action['advisor_other_reason'] ?? '').toString();
        final coordinatorStatus = (action['coordinator_status'] ?? '').toString();
        final coordinatorNotes = (action['coordinator_notes'] ?? '').toString();
        final collegeStatus = (action['college_status'] ?? '').toString();
        final collegeNotes = (action['college_notes'] ?? '').toString();
        // .contains بدل == لتحمّل تسميات إجراء أوسع من الثلاث القياسية
        // (مثل 'إضافة شعبة' بدل 'إضافة' بمصادر بيانات أقدم/اختبارات).
        final isAdd = actionType.contains('إضافة');
        final isDelete = actionType.contains('حذف');
        final isChange = actionType.contains('تعديل');
        // توافق رجعي: تذاكر بلا course_name/course_code منفصلين (لم تمرّ
        // عبر ExcelParserService الحالي) - نستخدم حقل 'course' الخام كاسم.
        final courseName = action['course_name'] ?? action['course'] ?? '';
        final courseCode = action['course_code'] ?? '';
        // Microsoft Forms يُخرج إجابات الاختيار المتعدد مفصولة بـ";" مع فاصلة
        // زائدة بالنهاية (";;;" أحيانًا) - تُزال هنا قبل الكتابة (سليمان
        // صراحةً 2026-08-27، بلقطة شاشة فعلية للملف).
        final rawReason = (action['reason_detail'] ?? action['reason'] ?? '').toString();
        final reason = rawReason.replaceAll(RegExp(r'[;؛\s]+$'), '');
        final row = [
          ...baseInfo,
          actionType,
          courseName,
          courseCode,
          isAdd ? (action['required_section'] ?? '') : '',
          isDelete ? (action['current_section'] ?? '') : '',
          isChange ? (action['current_section'] ?? '') : '',
          isChange ? (action['required_section'] ?? '') : '',
          reason,
          advisorStatus,
          advisorNotes,
          advisorOtherReason,
          coordinatorStatus,
          coordinatorNotes,
          collegeStatus,
          collegeNotes,
        ];
        rowSpecs.add(_RowSpec(
          day: uploadedDate,
          hoursSortKey: hoursSortKey,
          studentId: studentId,
          actionPriority: isAdd ? 0 : (isDelete ? 1 : (isChange ? 2 : 98)),
          tier: tier,
          values: row,
        ));
      }
    }

    // اليوم أولًا (المتراكم الأقدم أعلى الملف)، ثم نفس الترتيب السابق داخل كل
    // يوم (سليمان صراحةً 2026-08-28: فاصل يومي واضح بدل التداخل الكامل).
    rowSpecs.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      final byHours = a.hoursSortKey.compareTo(b.hoursSortKey);
      if (byHours != 0) return byHours;
      final byId = a.studentId.compareTo(b.studentId);
      if (byId != 0) return byId;
      return a.actionPriority.compareTo(b.actionPriority);
    });

    var dataRowIndex = 0; // صفر-فهرسة بين صفوف البيانات (بدون العناوين/التعليمات)
    String? currentDay;
    var dayColorCursor = 0;
    for (final spec in rowSpecs) {
      if (spec.day != currentDay) {
        if (currentDay != null) {
          // صف فارغ كامل يفصل عن مجموعة اليوم السابق (بلا لون).
          sheet.appendRow([]);
          dataRowIndex++;
        }
        currentDay = spec.day;
        final colorHex = _dayHeaderColors[dayColorCursor % _dayHeaderColors.length];
        dayColorCursor++;
        final rowIndex = dataRowIndex + headerRowIndex + 1;
        final titleText = spec.day.isEmpty ? 'حالات سابقة (بلا تاريخ رفع مسجَّل)' : spec.day;
        sheet.appendRow([TextCellValue(titleText)]);
        // ارتفاع صف ثابت صراحةً - بدونه يعتمد الاحتواء التلقائي لإكسل الذي
        // يتصرّف بشكل غير متسق بين صفوف عناوين الأيام (يظهر بعضها بخط واضح
        // وبعضها مضغوطًا بخط صغير جدًا رغم تطابق التنسيق البرمجي، سليمان
        // صراحةً 2026-09-02، بلقطة شاشة فعلية توضح التفاوت).
        sheet.setRowHeight(rowIndex, 28);
        final titleStyle = _dayTitleStyle(colorHex);
        for (var c = 0; c < _headers.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = titleStyle;
        }
        dataRowIndex++;
      }
      _appendStyledRow(sheet, spec.values, dataRowIndex, headerRowIndex, tier: spec.tier);
      dataRowIndex++;
    }

    int? paperFormFirstRow;
    int? paperFormLastRow;
    if (includePaperFormRows) {
      if (currentDay != null) {
        sheet.appendRow([]); // فاصل فارغ عن آخر مجموعة يوم عادية
        dataRowIndex++;
      }

      // صف عنوان القسم - نفس أسلوب عنوان اليوم بلون ثابت مميّز (لا يدور مع
      // ألوان الأيام)، بخط أكبر (16) والتفاف نص مُفعَّل وارتفاع صف كافٍ حتى
      // يظهر النص كاملاً وواضحًا بعدة أسطر بدل الانحشار بسطر واحد مقصوص
      // (سليمان صراحةً 2026-09-02، بلقطة شاشة فعلية توضح القصّ).
      var rowIndex = dataRowIndex + headerRowIndex + 1;
      sheet.appendRow([TextCellValue(paperFormSectionTitle)]);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        CellIndex.indexByColumnRow(columnIndex: _headers.length - 1, rowIndex: rowIndex),
      );
      sheet.setRowHeight(rowIndex, 80);
      final sectionTitleStyle = CellStyle(
        bold: true,
        fontSize: 20,
        backgroundColorHex: ExcelColor.fromHexString(_paperFormColorHex),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );
      for (var c = 0; c < _headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = sectionTitleStyle;
      }
      dataRowIndex++;

      // شريط تعليمات مدمَج - نفس تنسيق شريط التعليمات أعلى الملف تمامًا
      // (نفس الألوان والخط الغامق) لكن بخط أكبر لإبرازه، بطلب سليمان صراحةً
      // (2026-09-02: "لازم تكون مثل التعليمات اللي فوق بالتنسيق بخط كبير").
      // يشرح طريقة التعبئة مع تحذير صريح بشأن الرقم الجامعي.
      // العمود 0 لا 1 - خلاف شريط التعليمات الأعلى (يبدأ فعليًا من B لأن ذلك
      // لا يمسّ صفوف بيانات حقيقية): لو بدأ من العمود 1 هنا فهو بالضبط عمود
      // "الرقم الجامعي"، فيقرأ ProcessedFileParserService النص الطويل خطأً
      // كأنه رقم جامعي طالب (خلل حقيقي مؤكَّد، سليمان صراحةً 2026-09-02).
      rowIndex = dataRowIndex + headerRowIndex + 1;
      sheet.appendRow([TextCellValue(paperFormInstructionsText)]);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIndex),
      );
      sheet.setRowHeight(rowIndex, 130);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).cellStyle = CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: ExcelColor.fromHexString('FF154B36'),
        backgroundColorHex: ExcelColor.fromHexString('FFFCE8B2'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );
      dataRowIndex++;

      // صف عناوين أعمدة مكرَّر - نفس صف العناوين الأصلي (صف 2 بالملف) يُعاد
      // وضعه هنا مباشرة قبل صفوف الإدخال اليدوي، حتى يرى المرشد اسم كل عمود
      // بلا حاجة للتمرير لأعلى الملف (سليمان صراحةً 2026-09-02).
      rowIndex = dataRowIndex + headerRowIndex + 1;
      sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
      sheet.setRowHeight(rowIndex, 60);
      final repeatedHeaderStyle = _headerStyle(fontSize: 13, border: _thickGoldBorder);
      for (var c = 0; c < _headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = repeatedHeaderStyle;
      }
      dataRowIndex++;

      // الشطر/القسم/المرشد موحَّدة أصلاً عبر كل صفوف ملف مرشد واحد (انظر
      // توثيق [shatrColumnIndex]) - تُعبَّأ تلقائيًا هنا من أول تذكرة بدل
      // تركها فارغة، فتبقى مقفلة كبقية الملف ولا يحتاج المرشد كتابتها يدويًا
      // (وهي أعمدة مخفية عنه أصلاً فلن يقدر على رؤيتها ليكتبها لو تُركت له).
      final firstTicket = tickets.isNotEmpty ? tickets.first : const <String, dynamic>{};
      final paperFormRowTemplate = List<dynamic>.filled(_headers.length, '');
      // null لا نص فارغ - عمودا الساعات/المعدل يُتوقَّعان رقمًا أو null فقط
      // بـ_cellValueFor (تحويل `'' as int` يرمي استثناءً، انظر تعريفها).
      paperFormRowTemplate[remainingHoursColumnIndex] = null;
      paperFormRowTemplate[gpaColumnIndex] = null;
      paperFormRowTemplate[shatrColumnIndex] = firstTicket['shatr'] ?? '';
      paperFormRowTemplate[departmentColumnIndex] = firstTicket['department'] ?? '';
      paperFormRowTemplate[advisorNameColumnIndex] = firstTicket['advisor'] ?? '';

      paperFormFirstRow = dataRowIndex + headerRowIndex + 1;
      for (var i = 0; i < paperFormExtraRowCount; i++) {
        _appendStyledRow(sheet, List.of(paperFormRowTemplate), dataRowIndex, headerRowIndex);
        final r = dataRowIndex + headerRowIndex + 1;
        final style = _rowStyle(alternate: false, backgroundColorHex: _paperFormColorHex);
        for (var c = 0; c < _headers.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = style;
        }
        dataRowIndex++;
      }
      paperFormLastRow = dataRowIndex + headerRowIndex;
    }

    return DepartmentWorkbookResult(
      bytes: Uint8List.fromList(workbook.encode()!),
      totalDataRowCount: dataRowIndex,
      paperFormFirstRow: paperFormFirstRow,
      paperFormLastRow: paperFormLastRow,
    );
  }

  /// يحوّل قيمة عمود واحد إلى نوع خلية Excel الصحيح - رقم صحيح/عشري فعلي
  /// لعمودَي الساعات المتبقية/المعدل (بدل نص، ليصح الفرز الرقمي لاحقًا لو
  /// فرزه المرشد يدويًا)، وإلا نص عادي كالسابق. قيمة null (ساعات/معدل غير
  /// معروفة) تُكتَب كنص "—" بدل رقم صفري مضلِّل.
  static CellValue? _cellValueFor(int columnIndex, dynamic value) {
    if (columnIndex == remainingHoursColumnIndex) {
      return value == null ? TextCellValue('—') : IntCellValue(value as int);
    }
    if (columnIndex == gpaColumnIndex) {
      return value == null ? TextCellValue('—') : DoubleCellValue(value as double);
    }
    // خلية فارغة فعليًا (لا قيمة إطلاقًا) بدل نص فارغ - سليمان صراحةً
    // (2026-08-27): نص فارغ يبدو فارغًا بصريًا لكنه يبقى "مستخدَمًا" تقنيًا
    // (قد تعتبره أدوات فحص خارجية خلية بها بيانات)، بينما الفراغ الحقيقي
    // ضروري ليصح اكتشاف حالات لم يعالجها المرشد بعد. مهم خصوصًا لأعمدة حالة/
    // ملاحظات المرشد ومنسق القسم/الكلية.
    final text = value.toString();
    return text.isEmpty ? null : TextCellValue(text);
  }

  static void _appendStyledRow(
    Sheet sheet,
    List<dynamic> values,
    int dataRowIndex,
    int headerRowIndex, {
    GraduationTier tier = GraduationTier.normal,
  }) {
    sheet.appendRow([
      for (var c = 0; c < values.length; c++) _cellValueFor(c, values[c]),
    ]);
    final rowIndex = dataRowIndex + headerRowIndex + 1; // بعد صف(وف) العناوين/التعليمات
    // تمييز قرب التخرّج بلون خلفية عبر كامل الصف - يطغى على التلوين المتناوب
    // العادي (سليمان صراحةً 2026-08-27)، فيبقى واضحًا بصريًا أينما وقع الصف.
    final tierColorHex = switch (tier) {
      GraduationTier.expected => 'FFF9D4DE', // وردي فاتح - متوقع تخرجه
      GraduationTier.near => 'FFFCEBC7', // أصفر فاتح - قريب من التخرج
      GraduationTier.normal => null,
    };
    final style = _rowStyle(alternate: dataRowIndex.isEven, backgroundColorHex: tierColorHex);
    final reasonStyle = _rowStyle(alternate: dataRowIndex.isEven, wrapText: true, backgroundColorHex: tierColorHex);
    for (var c = 0; c < values.length; c++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex),
              )
              .cellStyle =
          c == _reasonColumnIndex ? reasonStyle : style;
    }
  }
}

/// تصنيف قرب التخرّج حسب الساعات المتبقية - انظر توثيق منطق الحساب داخل
/// [ExcelExportService.buildDepartmentWorkbook].
enum GraduationTier { expected, near, normal }

/// ناتج [ExcelExportService.buildDepartmentWorkbook] - [totalDataRowCount]
/// ضروري لضبط نطاق القوائم المنسدلة بشكل صحيح عند التمرير لـ
/// [ExcelProtectionService.protect] (يشمل صفوف عنوان اليوم والفواصل الفارغة،
/// لا صفوف بيانات التذاكر فقط).
class DepartmentWorkbookResult {
  final Uint8List bytes;
  final int totalDataRowCount;

  /// أول/آخر رقم صف (1-فهرسة، صيغة OOXML) لصفوف النموذج الورقي الفارغة -
  /// null إن لم تُطلَب ([ExcelExportService.buildDepartmentWorkbook] بمعامل
  /// includePaperFormRows: false). تُستخدم لفتح كل أعمدة هذا النطاق تحديدًا
  /// عند الحماية، انظر [ExcelProtectionService.protect].
  final int? paperFormFirstRow;
  final int? paperFormLastRow;

  const DepartmentWorkbookResult({
    required this.bytes,
    required this.totalDataRowCount,
    this.paperFormFirstRow,
    this.paperFormLastRow,
  });
}

/// صف مبنى مؤقتًا قبل الكتابة الفعلية بالشيت - يُرتَّب أولًا حسب [day] (يوم
/// رفع التذكرة، الأقدم أولًا - المجهول "" يُعامَل كأقدم فيوضع أولًا)، ثم
/// [hoursSortKey] (الساعات المتبقية تصاعديًا، المجهول يُعامَل كأكبر قيمة
/// فيوضع أخيرًا)، ثم [studentId] كفاصل تعادل، ثم [actionPriority] (0=إضافة،
/// 1=حذف، 2=تعديل، أكبر=غير مصنَّف/بلا إجراءات) لإبقاء حزمة كل طالب متتابعة.
/// [tier] يحدّد لون تمييز الصف (قرب التخرّج).
class _RowSpec {
  final String day;
  final int hoursSortKey;
  final String studentId;
  final int actionPriority;
  final GraduationTier tier;
  final List<dynamic> values;
  const _RowSpec({
    required this.day,
    required this.hoursSortKey,
    required this.studentId,
    required this.actionPriority,
    required this.tier,
    required this.values,
  });
}
