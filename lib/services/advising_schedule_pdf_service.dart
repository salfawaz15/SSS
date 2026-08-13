import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/advising_schedule.dart';
import '../services/advising_schedule_excel_service.dart';
import '../services/college_roster_lookup_service.dart';
import '../services/college_roster_repository.dart';

/// يبني نسخة PDF موحّدة الهوية البصرية لجدول توزيع فترات الإرشاد الأكاديمي
/// لقسم وشطر معيّنين - بديل عن التصاميم المتفرّقة التي كان كل قسم يبنيها
/// بطريقته الخاصة.
class AdvisingSchedulePdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _greenDark = PdfColor.fromHex('0D3324');
  static final _gold = PdfColor.fromHex('C9A227');
  static final _lightGray = PdfColor.fromHex('F7F5EF');

  static Future<pw.Font>? _cachedRegularFont;
  static Future<pw.Font>? _cachedBoldFont;

  static Future<pw.Font> _regularFont() => _cachedRegularFont ??= () async {
        final bytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
        return pw.Font.ttf(bytes);
      }();
  static Future<pw.Font> _boldFont() => _cachedBoldFont ??= () async {
        final bytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
        return pw.Font.ttf(bytes);
      }();

  static Future<pw.MemoryImage> _logo() async {
    final bytes = await rootBundle.load('assets/images/unit_logo_transparent.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static Future<Uint8List> build({
    required String department,
    required String shatr,
    required List<AdvisingScheduleSlot> slots,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    // المصدر الوحيد لاسم إدارة الوحدة ومنسّق القسم هو ملف أعضاء هيئة
    // التدريس المعتمد المرفوع عبر الموقع - لا قوائم ثابتة بالكود. لا يُكتب
    // أي مسمى وظيفي (نائب رئيس/رئيسة) بناءً على طلب صريح، فقط الاسم كاملاً.
    final roster = await CollegeRosterRepository.load();
    final unitManagerName = CollegeRosterLookupService.unitManagerFor(roster, shatr);
    final coordinatorMatch = CollegeRosterLookupService.coordinatorFor(roster, department, shatr);
    final coordinator = coordinatorMatch == null
        ? null
        : (name: coordinatorMatch.name, label: coordinatorMatch.male ? 'منسّق القسم' : 'منسّقة القسم');

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        header: (context) => _header(
          logo: logo,
          department: department,
          shatr: shatr,
          coordinator: coordinator,
          unitManagerName: unitManagerName,
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'جدول توزيع فترات الإرشاد الأكاديمي',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _green),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Container(height: 2, width: 160, color: _gold),
          ),
          pw.SizedBox(height: 16),
          if (slots.isEmpty)
            pw.Center(child: pw.Text('لا توجد بيانات لهذا القسم/الشطر بعد.'))
          else
            ..._daysWithPageBreaks(slots, signage: false),
        ],
      ),
    );

    return doc.save();
  }

  /// كل يوم يبدأ في صفحة مستقلة دائمًا (مهما كان عدد الأعضاء) بدل ترك
  /// المحتوى يتدفّق بحرية - كان يُنتج أحيانًا صفحات شبه فارغة وأيامًا
  /// متداخلة في نفس الصفحة بشكل غير منظّم.
  static List<pw.Widget> _daysWithPageBreaks(List<AdvisingScheduleSlot> slots, {required bool signage}) {
    final days = _groupedByDay(slots).entries.toList();
    final widgets = <pw.Widget>[];
    for (var i = 0; i < days.length; i++) {
      if (i > 0) widgets.add(pw.NewPage());
      widgets.add(signage ? _daySectionSignage(days[i].key, days[i].value) : _daySection(days[i].key, days[i].value));
    }
    return widgets;
  }

  /// نسخة تجمع كل الأقسام/الأشطر معًا في ملف PDF واحد - **مرتَّبة باليوم
  /// أولًا** (الأحد بكل أقسامه، ثم الاثنين، ثم الثلاثاء)، وداخل كل يوم كل
  /// قسم × شطر بترتيب ثابت (نفس ترتيب [AdvisingScheduleExcelService]) -
  /// بدل الترتيب السابق (قسم كامل بكل أيامه، ثم القسم التالي) الذي طلب
  /// سليمان صراحةً استبداله (2026-08-10): "يوم الأحد الأقسام حسب الشطر
  /// وبعدها الاثنين وهكذا". كل يوم يبدأ صفحة جديدة دائمًا.
  static Future<Uint8List> buildAll({
    required Map<(String, String), List<AdvisingScheduleSlot>> byDeptShatr,
    bool signage = false,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();
    final roster = await CollegeRosterRepository.load();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    // ترتيب ثابت: الشطر أولاً (كل الأقسام لشطر الطلاب من الإدارة إلى نظم
    // المعلومات، ثم كل الأقسام لشطر الطالبات) لا القسم أولاً - بطلب سليمان
    // صراحةً (2026-08-10) بعد أن ظهر الترتيب معكوسًا بالنشر الأول.
    final pairs = [
      for (final s in AdvisingScheduleExcelService.shatrOptions)
        for (final d in AdvisingScheduleExcelService.departmentOptions) (d, s),
    ];

    var anyDataAtAll = false;
    for (final day in AdvisingScheduleExcelService.dayColumnLabels) {
      final sections = <pw.Widget>[];
      for (final (department, shatr) in pairs) {
        final daySlots = (byDeptShatr[(department, shatr)] ?? const [])
            .where((s) => s.dayLabel == day)
            .toList()
          ..sort((a, b) => _periodOrder(a.periodLabel).compareTo(_periodOrder(b.periodLabel)));
        if (daySlots.isEmpty) continue;
        // كل قسم/شطر يبدأ صفحة جديدة دائمًا (بلا هذا كان جدول قسم قد ينتهي
        // قرب أسفل الصفحة فيظهر عنوان القسم التالي ملتصقًا به مباشرة بشكل
        // غير احترافي - سليمان 2026-08-13، "قسم الإدارة مع المحاسبة بشكل
        // غير احترافي"). نفس مبدأ [_daysWithPageBreaks] لكن على مستوى القسم
        // داخل صفحات اليوم الواحد.
        if (sections.isNotEmpty) sections.add(pw.NewPage());
        final coordinatorMatch = CollegeRosterLookupService.coordinatorFor(roster, department, shatr);
        final coordinatorLabel = coordinatorMatch == null
            ? null
            : '${coordinatorMatch.male ? 'منسّق القسم' : 'منسّقة القسم'}: ${coordinatorMatch.name}';
        // مسطَّحة (بلا Column يجمعها) - السبب الجذري الحقيقي للتجمّد اللانهائي
        // (تحقَّق فعليًا 2026-08-10 عبر متصفح حقيقي: ScriptDuration/JSHeap
        // يتصاعدان بلا توقّف بلا نهاية): pw.Column **لا يدعم التقسيم بين
        // الصفحات** بمكتبة pdf (بخلاف pw.Table المصمَّم لذلك)، فأي Column
        // يجمع قسمًا كبيرًا (بفترتين حتى 26 مرشدًا بخط شاشات العرض الضخم)
        // يتجاوز ارتفاعه أي صفحة منفردة، فتدخل المكتبة حلقة إضافة صفحات
        // فارغة بلا نهاية محاولةً وضعه. الإصلاح: تُضاف عناصر كل قسم منفصلة
        // مباشرة لقائمة محتوى الصفحة (لا داخل Column واحد)، فيبقى pw.Table
        // وحده الكتلة الكبيرة، وهو قابل للتقسيم فعليًا بين الصفحات.
        sections.addAll(_deptShatrWidgets(department, shatr, coordinatorLabel, daySlots, signage: signage));
      }
      if (sections.isEmpty) continue;
      anyDataAtAll = true;

      doc.addPage(
        pw.MultiPage(
          pageFormat: signage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(signage ? 28 : 24),
          textDirection: pw.TextDirection.rtl,
          header: (context) => _genericHeader(logo: logo, title: day, scale: signage ? 1.6 : 1),
          footer: signage
              ? null
              : (context) => pw.Container(
                    alignment: pw.Alignment.center,
                    margin: const pw.EdgeInsets.only(top: 8),
                    child: pw.Text(
                      'صفحة ${context.pageNumber} من ${context.pagesCount}',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ),
          build: (context) => [
            pw.SizedBox(height: signage ? 14 : 10),
            if (!signage) ...[
              pw.Center(
                child: pw.Text(
                  'جدول توزيع فترات الإرشاد الأكاديمي',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _green),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Container(height: 2, width: 160, color: _gold)),
              pw.SizedBox(height: 16),
            ],
            ...sections,
          ],
        ),
      );
    }

    if (!anyDataAtAll) {
      doc.addPage(
        pw.Page(
          pageFormat: signage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          build: (context) => pw.Center(child: pw.Text('لا توجد بيانات لهذا النطاق بعد.')),
        ),
      );
    }

    return doc.save();
  }

  /// عنوان عام لصفحة يوم كامل (بلا قسم/شطر مفرد، لأن الصفحة تجمع عدة أقسام) -
  /// الشعار واسم الوحدة فقط، واسم اليوم كعنوان رئيسي بدل بيانات قسم واحد.
  static pw.Widget _genericHeader({required pw.MemoryImage logo, required String title, double scale = 1}) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
      decoration: pw.BoxDecoration(color: _green, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text('يوم $title',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 13 * scale)),
          ),
          pw.SizedBox(width: 10 * scale),
          pw.Image(logo, height: 72 * scale),
          pw.SizedBox(width: 10 * scale),
          pw.Expanded(
            flex: 4,
            child: pw.Text('وحدة الإرشاد الأكاديمي والخريجين',
                textAlign: pw.TextAlign.right,
                maxLines: 2,
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11 * scale)),
          ),
        ],
      ),
    );
  }

  /// قسم فرعي واحد (قسم أكاديمي × شطر) ضمن صفحة يوم كامل - عنوان مصغَّر
  /// (القسم + الشطر + المنسّق إن وُجد) ثم جداول الفترات لنفس اليوم فقط.
  /// **قائمة مسطَّحة من العناصر، لا Column واحد يجمعها** - Column لا يدعم
  /// التقسيم بين صفحات PDF (بخلاف pw.Table)، فتجميع قسم كبير بداخله يسبّب
  /// تجمّدًا لانهائيًا إن تجاوز ارتفاعه صفحة واحدة (راجع التعليق بموقع
  /// الاستدعاء بـ[buildAll] للتفاصيل الكاملة - تحقَّق فعليًا 2026-08-10).
  static List<pw.Widget> _deptShatrWidgets(
    String department,
    String shatr,
    String? coordinatorLabel,
    List<AdvisingScheduleSlot> daySlots, {
    required bool signage,
  }) {
    final titleFontSize = signage ? 16.0 : 11.0;
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: pw.EdgeInsets.symmetric(horizontal: signage ? 14 : 10, vertical: signage ? 8 : 6),
        decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('${department.replaceFirst(RegExp(r'^قسم\s+'), '')} - $shatr',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: titleFontSize)),
            if (coordinatorLabel != null)
              pw.Text(coordinatorLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: titleFontSize - 2)),
          ],
        ),
      ),
      for (final slot in daySlots) ...(signage ? _periodTableSignage(slot) : _periodTable(slot)),
    ];
  }

  /// نسخة مخصّصة لعرض الجدول على شاشات الإسياب داخل الكلية: اتجاه أفقي
  /// (Landscape) وخطوط أكبر بكثير لتكون مقروءة من مسافة، وتخطيط أبسط
  /// (بلا حدود جداول كثيفة) - بنفس الشعار والهوية البصرية للنسخة الرسمية،
  /// لكنها ليست مخصَّصة للطباعة الورقية أو الأرشفة.
  static Future<Uint8List> buildSignage({
    required String department,
    required String shatr,
    required List<AdvisingScheduleSlot> slots,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final roster = await CollegeRosterRepository.load();
    final unitManagerName = CollegeRosterLookupService.unitManagerFor(roster, shatr);
    final coordinatorMatch = CollegeRosterLookupService.coordinatorFor(roster, department, shatr);
    final coordinator = coordinatorMatch == null
        ? null
        : (name: coordinatorMatch.name, label: coordinatorMatch.male ? 'منسّق القسم' : 'منسّقة القسم');

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        header: (context) => _header(
          logo: logo,
          department: department,
          shatr: shatr,
          coordinator: coordinator,
          unitManagerName: unitManagerName,
          scale: 1.6,
        ),
        build: (context) => [
          pw.SizedBox(height: 14),
          if (slots.isEmpty)
            pw.Center(child: pw.Text('لا توجد بيانات لهذا القسم/الشطر بعد.', style: const pw.TextStyle(fontSize: 20)))
          else
            ..._daysWithPageBreaks(slots, signage: true),
        ],
      ),
    );

    return doc.save();
  }

  /// يرتّب الأيام بترتيب الأسبوع الفعلي والفترات داخل كل يوم بترتيب الوقت -
  /// بدونه كانت تظهر بترتيب ورودها العشوائي بالبيانات المرفوعة (سليمان
  /// 2026-08-10)، وهي نفس مشكلة `advising_schedule_admin_screen.dart`.
  static int _dayOrder(String label) {
    final i = AdvisingScheduleExcelService.dayColumnLabels.indexOf(label);
    return i == -1 ? AdvisingScheduleExcelService.dayColumnLabels.length : i;
  }

  static int _periodOrder(String label) {
    final i = AdvisingScheduleExcelService.periodOptions.indexWhere(label.startsWith);
    return i == -1 ? AdvisingScheduleExcelService.periodOptions.length : i;
  }

  static Map<String, List<AdvisingScheduleSlot>> _groupedByDay(List<AdvisingScheduleSlot> slots) {
    final sorted = [...slots]
      ..sort((a, b) {
        final dayCompare = _dayOrder(a.dayLabel).compareTo(_dayOrder(b.dayLabel));
        if (dayCompare != 0) return dayCompare;
        return _periodOrder(a.periodLabel).compareTo(_periodOrder(b.periodLabel));
      });
    final map = <String, List<AdvisingScheduleSlot>>{};
    for (final s in sorted) {
      map.putIfAbsent(s.dayLabel, () => []).add(s);
    }
    return map;
  }

  static pw.Widget _header({
    required pw.MemoryImage logo,
    required String department,
    required String shatr,
    required ({String name, String label})? coordinator,
    required String? unitManagerName,
    double scale = 1,
  }) {
    return pw.Column(
      children: [
        pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
          decoration: pw.BoxDecoration(
            color: _green,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // يمين الصفحة (RTL): القسم والمنسّق
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(department.replaceFirst(RegExp(r'^قسم\s+'), ''),
                        maxLines: 2,
                        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11 * scale)),
                    if (coordinator != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('${coordinator.label}: ${coordinator.name}',
                          maxLines: 2, style: pw.TextStyle(color: PdfColors.white, fontSize: 8.5 * scale)),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 10 * scale),
              pw.Image(logo, height: 72 * scale),
              pw.SizedBox(width: 10 * scale),
              // يسار الصفحة: إدارة الوحدة
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('وحدة الإرشاد الأكاديمي والخريجين',
                        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11 * scale),
                        maxLines: 2,
                        textAlign: pw.TextAlign.right),
                    if (unitManagerName != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(unitManagerName,
                          maxLines: 2,
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 8.5 * scale),
                          textAlign: pw.TextAlign.right),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(shatr, style: pw.TextStyle(fontSize: 10 * scale, color: PdfColors.grey700)),
      ],
    );
  }

  static pw.Widget _daySection(String dayLabel, List<AdvisingScheduleSlot> periods) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text(dayLabel, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ),
        pw.SizedBox(height: 6),
        for (final p in periods) ..._periodTable(p),
        pw.SizedBox(height: 14),
      ],
    );
  }

  /// نسخة شاشات العرض من قسم اليوم: خطوط أكبر بكثير وصفوف أوسع كي تُقرأ من
  /// مسافة على شاشة إسياب، وجدول واحد بلا تقسيم فترات متعدد الحدود الدقيقة.
  static pw.Widget _daySectionSignage(String dayLabel, List<AdvisingScheduleSlot> periods) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Text(dayLabel, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 20)),
        ),
        pw.SizedBox(height: 10),
        for (final p in periods) ..._periodTableSignage(p),
        pw.SizedBox(height: 22),
      ],
    );
  }

  // كل فترة = عنصران مستقلّان في القائمة المسطَّحة (عنوان صغير ثابت الطول +
  // pw.Table وحده) لا Column يجمعهما - راجع تعليق [_deptShatrWidgets] و
  // [buildAll] بخصوص خطر التجمّد اللانهائي (Column لا يدعم التقسيم بين
  // صفحات PDF بمكتبة pdf، بخلاف pw.Table المصمَّم لذلك خصيصًا - تحقَّق
  // فعليًا بمتصفح حقيقي 2026-08-10: الحل السابق بإزالة pw.Container فقط لم
  // يكفِ لأن pw.Column يحمل نفس القيد بالضبط).
  static List<pw.Widget> _periodTableSignage(AdvisingScheduleSlot slot) {
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: _lightGray,
        child: pw.Text('الفترة: ${slot.periodLabel}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: _green)),
      ),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300)),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(3)},
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _green),
            children: [
              _cell('رقم المكتب', bold: true, color: PdfColors.white, fontSize: 15),
              _cell('اسم المرشد الأكاديمي', bold: true, color: PdfColors.white, fontSize: 15),
            ],
          ),
          for (var i = 0; i < slot.entries.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _lightGray),
              children: [
                _cell(slot.entries[i].office, fontSize: 14),
                _cell(slot.entries[i].advisorName, fontSize: 14),
              ],
            ),
        ],
      ),
    ];
  }

  static List<pw.Widget> _periodTable(AdvisingScheduleSlot slot) {
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: _lightGray,
        child: pw.Text('الفترة: ${slot.periodLabel}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _green)),
      ),
      // ترتيب الأعمدة معكوس عمدًا (رقم المكتب أولاً..الاسم أخيرًا) لأن
      // pw.Table يرتّب أعمدته فعليًا من يسار الصفحة لا حسب اتجاه النص.
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300)),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(3)},
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _green),
            children: [
              _cell('رقم المكتب', bold: true, color: PdfColors.white),
              _cell('اسم المرشد الأكاديمي', bold: true, color: PdfColors.white),
            ],
          ),
          for (var i = 0; i < slot.entries.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _lightGray),
              children: [
                _cell(slot.entries[i].office),
                _cell(slot.entries[i].advisorName),
              ],
            ),
        ],
      ),
    ];
  }

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color, double fontSize = 10}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Center(
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      ),
    );
  }
}
