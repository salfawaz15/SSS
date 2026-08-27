import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/advising_schedule.dart';
import '../services/advising_schedule_excel_service.dart';
import '../services/college_roster_lookup_service.dart';
import '../services/college_roster_repository.dart';
import 'pdf_brand_kit.dart';

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

  /// نسخة "مقصوصة" (بلا الهامش الشفاف الضخم المحيط بالشعار الفعلي بملف
  /// unit_logo_transparent.png الأصلي) - سليمان 2026-08-13/14: الشعار يبدو
  /// صغيرًا جدًا مهما زدت `height`، لأن أغلب الصورة الأصلية فراغ شفاف فوق
  /// الشعار الحقيقي، فيتقلَّص الجزء المرئي فعليًا بنفس نسبة الفراغ عند أي
  /// تحجيم. **تحديث 2026-08-14**: `unit_logo_cropped.png` (الحل السابق) كانت
  /// حدودها ضيقة فعلًا لكن بخلفية بيضاء صريحة (بلا شفافية إطلاقًا) - سبّبت
  /// مربعًا أبيض قبيحًا حول الشعار فوق الشريط الأخضر، وهذا "المشكلة الكبيرة"
  /// التي لاحظها سليمان. استُبدلت بـunit_logo_final.png: مقصوصة يدويًا من
  /// شعار سليمان الجديد (شفاف حقيقي 100% بالحواف الأربع) بأداة سكربت مخصَّصة
  /// تحسب صندوق الحدود المرئي فعليًا بدل الاعتماد على ملف مُجهَّز مسبقًا.
  static Future<pw.MemoryImage> _logo() async {
    final bytes = await rootBundle.load('assets/images/unit_logo_final.png');
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
        footer: (context) => pw.Stack(
          children: [
            pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'صفحة ${context.pageNumber} من ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ),
            pw.Positioned(left: 0, bottom: 0, child: PdfBrandKit.watermark()),
          ],
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
        final coordinatorMatch = CollegeRosterLookupService.coordinatorFor(roster, department, shatr);
        final coordinatorLabel = coordinatorMatch == null
            ? null
            : '${coordinatorMatch.male ? 'منسّق القسم' : 'منسّقة القسم'}: ${coordinatorMatch.name}';
        if (signage) {
          // كل فترة = صفحة مستقلة تمامًا (طلب سليمان صراحةً 2026-08-24: "كل
          // فترة في صفحة مستقلة") - بدل محاولة حشر فترتين بنفس الصفحة
          // (جنبًا لجنب أو مكدّستين)، التي كانت تُنتج أحيانًا محتوى مفقودًا
          // تمامًا (بطاقة فارغة، أو فترة ثانية مختفية بالكامل) حين يتجاوز
          // مجموعهما ارتفاع الصفحة الثابتة - تحقَّق فعليًا من ملفات اختبار
          // حقيقية رفعها سليمان.
          for (final slot in daySlots) {
            if (sections.isNotEmpty) sections.add(pw.NewPage());
            sections.addAll(_periodCardWidgets(department, shatr, coordinatorLabel, slot));
          }
        } else {
          // كل قسم/شطر يبدأ صفحة جديدة دائمًا (بلا هذا كان جدول قسم قد ينتهي
          // قرب أسفل الصفحة فيظهر عنوان القسم التالي ملتصقًا به مباشرة بشكل
          // غير احترافي - سليمان 2026-08-13، "قسم الإدارة مع المحاسبة بشكل
          // غير احترافي"). نفس مبدأ [_daysWithPageBreaks] لكن على مستوى القسم
          // داخل صفحات اليوم الواحد.
          if (sections.isNotEmpty) sections.add(pw.NewPage());
          // مسطَّحة (بلا Column يجمعها) - السبب الجذري الحقيقي للتجمّد اللانهائي
          // (تحقَّق فعليًا 2026-08-10 عبر متصفح حقيقي: ScriptDuration/JSHeap
          // يتصاعدان بلا توقّف بلا نهاية): pw.Column **لا يدعم التقسيم بين
          // الصفحات** بمكتبة pdf (بخلاف pw.Table المصمَّم لذلك)، فأي Column
          // يجمع قسمًا كبيرًا يتجاوز ارتفاعه أي صفحة منفردة، فتدخل المكتبة
          // حلقة إضافة صفحات فارغة بلا نهاية محاولةً وضعه. الإصلاح: تُضاف
          // عناصر كل قسم منفصلة مباشرة لقائمة محتوى الصفحة (لا داخل Column
          // واحد)، فيبقى pw.Table وحده الكتلة الكبيرة، وهو قابل للتقسيم
          // فعليًا بين الصفحات.
          sections.addAll(_deptShatrWidgets(department, shatr, coordinatorLabel, daySlots, signage: false));
        }
      }
      if (sections.isEmpty) continue;
      anyDataAtAll = true;

      doc.addPage(
        pw.MultiPage(
          pageFormat: signage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(signage ? 28 : 24),
          textDirection: pw.TextDirection.rtl,
          header: (context) => _genericHeader(logo: logo, scale: signage ? 1.6 : 1),
          footer: signage
              ? (context) => pw.Align(alignment: pw.Alignment.bottomLeft, child: PdfBrandKit.watermark())
              : (context) => pw.Stack(
                    children: [
                      pw.Container(
                        alignment: pw.Alignment.center,
                        margin: const pw.EdgeInsets.only(top: 8),
                        child: pw.Text(
                          'صفحة ${context.pageNumber} من ${context.pagesCount}',
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                        ),
                      ),
                      pw.Positioned(left: 0, bottom: 0, child: PdfBrandKit.watermark()),
                    ],
                  ),
          build: (context) => [
            pw.SizedBox(height: signage ? 14 : 10),
            if (!signage) ...[
              // اسم اليوم انتقل هنا (كان داخل الشريط الأخضر أعلاه) - سليمان
              // 2026-08-14: الشريط صار يعرض عنوان الجدول الثابت بدلًا منه.
              pw.Center(
                child: pw.Text(
                  'يوم $day',
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

  /// يبني ملفًا مضغوطًا (ZIP) منظَّمًا لإدارة الكلية: مجلد لكل شطر (طلاب/
  /// طالبات)، وداخله مجلد فرعي لكل قسم يحوي ملف PDF واحد فقط يجمع كل أيام
  /// ذلك القسم - بنفس تصميم/مقاس [build] تمامًا (لا تصميم مختلف) - حتى يسهل
  /// على إدارة الكلية تعميم ملف قسم واحد بعينه على مرشديه دون البحث بين كل
  /// الأقسام (طلب سليمان صراحةً 2026-08-27).
  static Future<Uint8List> buildDepartmentFolderZip({
    required Map<(String, String), List<AdvisingScheduleSlot>> byDeptShatr,
  }) async {
    final archive = Archive();
    for (final entry in byDeptShatr.entries) {
      final (department, shatr) = entry.key;
      final slots = entry.value;
      if (slots.isEmpty) continue;
      final pdfBytes = await build(department: department, shatr: shatr, slots: slots);
      final path = '$shatr/${_sanitizeFileName(department)}.pdf';
      archive.addFile(ArchiveFile(path, pdfBytes.length, pdfBytes));
    }
    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  static String _sanitizeFileName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// نسخة "بطاقات" منفصلة لوضع شاشات العرض: كل بطاقة = يوم × قسم × شطر ×
  /// **فترة واحدة فقط** في ملف PDF مستقل تمامًا (طلب سليمان صراحةً
  /// 2026-08-24: "كل فترة في صفحة مستقلة" - لا فترتان بنفس البطاقة بأي
  /// تخطيط، مهما كان). تحويلها لاحقًا لصور PNG (راجع
  /// AdvisingScheduleSignageImageService) تُرسَل لسكرتارية الكلية لعرضها
  /// كشرائح على شاشات الإسياب. تُستخدَم `pw.MultiPage` (لا `pw.Page`
  /// الثابتة) حتى لو تجاوز محتوى فترة واحدة (نادر جدًا) ارتفاع صفحة واحدة -
  /// `pw.Page` كانت تُنتج بطاقات فارغة تمامًا بصمت عند أي تجاوز طفيف
  /// (تحقَّق فعليًا من ملفات اختبار حقيقية). تعيد نفس ترتيب البطاقات
  /// المستخدَم فعليًا بـ[buildAll] (اليوم أولًا، ثم الشطر، ثم القسم، ثم
  /// الفترة).
  static Future<List<({String label, String department, String shatr, Uint8List pdfBytes})>> buildSignageCards({
    required Map<(String, String), List<AdvisingScheduleSlot>> byDeptShatr,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();
    final roster = await CollegeRosterRepository.load();

    final pairs = [
      for (final s in AdvisingScheduleExcelService.shatrOptions)
        for (final d in AdvisingScheduleExcelService.departmentOptions) (d, s),
    ];

    final cards = <({String label, String department, String shatr, Uint8List pdfBytes})>[];

    for (final day in AdvisingScheduleExcelService.dayColumnLabels) {
      for (final (department, shatr) in pairs) {
        final daySlots = (byDeptShatr[(department, shatr)] ?? const [])
            .where((s) => s.dayLabel == day)
            .toList()
          ..sort((a, b) => _periodOrder(a.periodLabel).compareTo(_periodOrder(b.periodLabel)));
        if (daySlots.isEmpty) continue;

        final coordinatorMatch = CollegeRosterLookupService.coordinatorFor(roster, department, shatr);
        final coordinatorLabel = coordinatorMatch == null
            ? null
            : '${coordinatorMatch.male ? 'منسّق القسم' : 'منسّقة القسم'}: ${coordinatorMatch.name}';

        for (final slot in daySlots) {
          final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
          doc.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.all(28),
              textDirection: pw.TextDirection.rtl,
              build: (context) => [
                _genericHeader(logo: logo, scale: 1.6),
                pw.SizedBox(height: 14),
                pw.Center(
                  child: pw.Text('يوم $day', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _green)),
                ),
                pw.SizedBox(height: 4),
                pw.Center(child: pw.Container(height: 2, width: 160, color: _gold)),
                pw.SizedBox(height: 16),
                ..._periodCardWidgets(department, shatr, coordinatorLabel, slot),
              ],
            ),
          );

          cards.add((
            label:
                '$day - ${department.replaceFirst(RegExp(r'^قسم\s+'), '')} - $shatr - ${AdvisingScheduleExcelService.periodDisplayLabel(slot.periodLabel)}',
            department: department,
            shatr: shatr,
            pdfBytes: await doc.save(),
          ));
        }
      }
    }

    return cards;
  }

  /// عناصر بطاقة فترة واحدة مستقلة: عنوان القسم/الشطر (+ المنسّق إن وُجد)
  /// ثم جدول تلك الفترة فقط (يُقسَّم أعمدته داخليًا عند الحاجة عبر
  /// [_periodTableSignage]). قائمة مسطَّحة (لا Column يجمعها) لنفس سبب
  /// [_deptShatrWidgets] - راجع تعليقها.
  static List<pw.Widget> _periodCardWidgets(
    String department,
    String shatr,
    String? coordinatorLabel,
    AdvisingScheduleSlot slot,
  ) {
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('${department.replaceFirst(RegExp(r'^قسم\s+'), '')} - $shatr',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 16)),
            if (coordinatorLabel != null)
              pw.Text(coordinatorLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 14)),
          ],
        ),
      ),
      ..._periodTableSignage(slot),
    ];
  }

  /// عنوان عام لصفحة يوم كامل (بلا قسم/شطر مفرد، لأن الصفحة تجمع عدة أقسام) -
  /// الشعار واسم الوحدة فقط، واسم اليوم كعنوان رئيسي بدل بيانات قسم واحد.
  /// حجم مصغَّر (سليمان 2026-08-13: "صغّر الشعار") - هذا العنوان يتكرر أعلى
  /// **كل صفحة** بتقرير "كل الأقسام" (قد يصل عشرات الصفحات)، فحجمه الكبير
  /// السابق كان يهدر مساحة فعلية تمنع أقسامًا كثيرة من الاكتمال بصفحة واحدة.
  static pw.Widget _genericHeader({required pw.MemoryImage logo, double scale = 1}) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 7 * scale),
      decoration: pw.BoxDecoration(color: _green, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // يمين الصفحة (RTL: أول عنصر بالقائمة): الشعار - أكبر قليلاً بطلب
          // سليمان. السبب الحقيقي لصغره سابقًا مهما زاد `height` كان هامشًا
          // شفافًا ضخمًا بالصورة الأصلية (أُصلح باستخدام unit_logo_cropped.png
          // بدلًا منها في _logo()) لا قيمة الحجم نفسها.
          pw.Image(logo, height: 36 * scale),
          pw.SizedBox(width: 8 * scale),
          pw.Expanded(
            flex: 5,
            child: pw.Center(
              child: pw.Text(
                'جدول توزيع فترات الإرشاد الأكاديمي للفصل الدراسي الأول 1448هـ',
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12 * scale),
              ),
            ),
          ),
          pw.SizedBox(width: 8 * scale),
          // يسار الصفحة (آخر عنصر بالقائمة): اسم الوحدة.
          pw.Expanded(
            flex: 3,
            child: pw.Text('وحدة الإرشاد الأكاديمي والخريجين',
                textAlign: pw.TextAlign.right,
                maxLines: 2,
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10 * scale)),
          ),
        ],
      ),
    );
  }

  /// قسم فرعي واحد (قسم أكاديمي × شطر) ضمن صفحة يوم كامل بوضع الطباعة
  /// الرسمي (غير شاشات العرض - راجع [_periodCardWidgets] لبطاقة فترة
  /// مستقلة بوضع شاشات العرض) - عنوان مصغَّر (القسم + الشطر + المنسّق إن
  /// وُجد) ثم جداول الفترات لنفس اليوم. **قائمة مسطَّحة من العناصر، لا
  /// Column واحد يجمعها** - Column لا يدعم التقسيم بين صفحات PDF (بخلاف
  /// pw.Table)، فتجميع قسم كبير بداخله يسبّب تجمّدًا لانهائيًا إن تجاوز
  /// ارتفاعه صفحة واحدة (راجع التعليق بموقع الاستدعاء بـ[buildAll]
  /// للتفاصيل الكاملة - تحقَّق فعليًا 2026-08-10).
  static List<pw.Widget> _deptShatrWidgets(
    String department,
    String shatr,
    String? coordinatorLabel,
    List<AdvisingScheduleSlot> daySlots, {
    required bool signage,
  }) {
    assert(!signage, 'وضع شاشات العرض يستخدم _periodCardWidgets (فترة واحدة لكل بطاقة) لا هذه الدالة');
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('${department.replaceFirst(RegExp(r'^قسم\s+'), '')} - $shatr',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)),
            if (coordinatorLabel != null)
              pw.Text(coordinatorLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 9)),
          ],
        ),
      ),
      // جدولا الفترتين جنبًا إلى جنب (عمودان) بدل تحت بعض - سليمان
      // 2026-08-13: "قسم الاقتصاد شطر الطالبات أعدادهم كبيرة، يجب أن يستوعب
      // الجميع بصفحة واحدة، شرط يوم واحد فيه جدولان". يقلّل الارتفاع
      // المطلوب للقسم للنصف تقريبًا (بدل تراكم الجدولين رأسيًا)، فيتّسع عدد
      // أكبر من الأعضاء بصفحة واحدة. **حد أمان**: لا يُطبَّق إلا حين يكون
      // إجمالي الأعضاء بكلا الفترتين معقولاً (≤70) وعدد الفترات فترتان
      // بالضبط - وإلا يُستخدَم التكديس الرأسي القابل للتقسيم بين الصفحات
      // (الأصلي) تفاديًا لخطر تجمّد pw.Column اللانهائي الموثَّق أعلى
      // [buildAll] لو تجاوز المحتوى ارتفاع صفحة واحدة فعليًا.
      if (daySlots.length == 2 &&
          daySlots.fold<int>(0, (sum, s) => sum + s.entries.length) <= 70)
        _periodTablesSideBySide(daySlots)
      else
        for (final slot in daySlots) ..._periodTable(slot),
    ];
  }

  /// الحد الأقصى لعدد الصفوف بعمود واحد بوضع شاشات العرض (خط ضخم) قبل تقسيم
  /// نفس الفترة لعمودين/ثلاثة أعمدة جنبًا إلى جنب بدل ترك `pw.Table` يقسمها
  /// تلقائيًا بين صفحتين - كان هذا الانقسام التلقائي هو سبب الصفوف اليتيمة
  /// والصفحات شبه الفارغة التي لاحظها سليمان (2026-08-24) بملف "شاشات_العرض"
  /// (69 صفحة، جداول قسم تنقسم منتصف القائمة).
  static const int _kSignageMaxRowsPerColumn = 10;

  static pw.Widget _periodTablesSideBySide(List<AdvisingScheduleSlot> slots) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: _periodTable(slots[i]),
            ),
          ),
        ],
      ],
    );
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
              // نفس ملاحظة _genericHeader: بعد التحويل لـunit_logo_cropped.png
              // (بلا الهامش الشفاف الضخم) صار 72 كبيرًا جدًا فعليًا - خُفِّض لـ36.
              pw.Image(logo, height: 36 * scale),
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
        // كل فترة صفحة مستقلة (راجع تعليق [_periodCardWidgets]) - بلا هذا
        // فإن فترتين على نفس الصفحة قد يتجاوز مجموعهما ارتفاعها.
        for (var i = 0; i < periods.length; i++) ...[
          if (i > 0) pw.NewPage(),
          ..._periodTableSignage(periods[i]),
        ],
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
    final entries = slot.entries;
    // عدد الأعمدة يُحسب من عدد الصفوف الفعلي (لا يتجاوز 3 أعمدة كي يبقى كل
    // عمود مقروءًا من مسافة على شاشة الإسياب) - بدل عمود واحد قد يتجاوز
    // ارتفاعه صفحة واحدة فيقسمه pw.Table تلقائيًا بشكل عشوائي.
    final columnCount = (entries.length / _kSignageMaxRowsPerColumn).ceil().clamp(1, 3);
    final perColumn = (entries.length / columnCount).ceil();
    final columns = <List<AdvisingScheduleEntry>>[
      for (var i = 0; i < entries.length; i += perColumn)
        entries.sublist(i, (i + perColumn > entries.length) ? entries.length : i + perColumn),
    ];

    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: _lightGray,
        child: pw.Text('الفترة: ${AdvisingScheduleExcelService.periodDisplayLabel(slot.periodLabel)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: _green)),
      ),
      if (columns.length <= 1)
        _signageColumnTable(entries)
      else
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 12),
              pw.Expanded(child: _signageColumnTable(columns[i])),
            ],
          ],
        ),
    ];
  }

  static pw.Widget _signageColumnTable(List<AdvisingScheduleEntry> entries) {
    return pw.Table(
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
        for (var i = 0; i < entries.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _lightGray),
            children: [
              _cell(entries[i].office, fontSize: 14),
              _cell(entries[i].advisorName, fontSize: 14),
            ],
          ),
      ],
    );
  }

  /// حشو رأسي مصغَّر (3 بدل 5) بين كل اسم والتالي - سليمان 2026-08-13:
  /// "قلل الفرق بين الأسماء"، لتقليل هدر المساحة العمودية فيسع أعضاء أكثر
  /// بنفس الصفحة (يقلّل احتمال انقسام جدول قسم بين صفحتين).
  static List<pw.Widget> _periodTable(AdvisingScheduleSlot slot) {
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        color: _lightGray,
        child: pw.Text('الفترة: ${AdvisingScheduleExcelService.periodDisplayLabel(slot.periodLabel)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _green)),
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
              _cell('رقم المكتب', bold: true, color: PdfColors.white, verticalPadding: 3),
              _cell('اسم المرشد الأكاديمي', bold: true, color: PdfColors.white, verticalPadding: 3),
            ],
          ),
          for (var i = 0; i < slot.entries.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _lightGray),
              children: [
                _cell(slot.entries[i].office, verticalPadding: 3),
                _cell(slot.entries[i].advisorName, verticalPadding: 3),
              ],
            ),
        ],
      ),
    ];
  }

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color, double fontSize = 10, double verticalPadding = 5}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: verticalPadding),
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
