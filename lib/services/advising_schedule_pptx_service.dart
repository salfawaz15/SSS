import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/advising_schedule.dart';
import 'advising_schedule_excel_service.dart';

/// يبني عروض PowerPoint (.pptx) حقيقية قابلة للتعديل - كل ملف = يوم × فترة ×
/// شطر، وكل شريحة داخله = قسم واحد - لتُعرَض كشرائح متتالية (slideshow) على
/// شاشات الإسياب بسكرتارية الكلية. طلب سليمان صراحةً (2026-08-25) بعد أن
/// أرسل ملف مرجعي بنفس هذا الشكل وطلب أن يبقى التنزيل متاحًا دومًا (كل فصل،
/// مع أي بيانات محدَّثة) لا ملفات ثابتة - ثم مواصفة تقنية كاملة (نفس اليوم)
/// حدَّدت عتبات الأعمدة وتشغيل العرض التلقائي.
///
/// **لماذا XML يدوي بدل مكتبة جاهزة**: لا توجد مكتبة Dart لتوليد ملفات
/// .pptx - يُبنى الملف مباشرة بصيغة Office Open XML (نفس أسلوب توليد ملفات
/// Excel/Word الأخرى بالمشروع)، ببنية مبسَّطة (تخطيط فارغ + أشكال نصية
/// بمواضع مطلَقة بدل عناصر نائبة موروثة) تحافظ على نفس الهوية البصرية
/// (الأخضر 154B36/0D3324، الذهبي C9A227، الشعار) بلا تعقيد قوالب PowerPoint
/// الحقيقية - **ليست** نسخة طبق الأصل بكسل واحد من أي ملف مرجعي (اتُّفق مع
/// سليمان صراحةً أن هذا غير واقعي تقنيًا باستنساخ XML حرفي).
///
/// **حجم الجدول موحَّد بكل شرائح نفس الملف**: يُحسَب أعلى عدد مرشدين بين كل
/// الأقسام لنفس (يوم × فترة × شطر) مرة واحدة، ويُحدِّد هذا الرقم عدد الأعمدة
/// وارتفاع الصف الموحَّد لكل شرائح الملف (حتى لو اختلف العدد الفعلي بين
/// الأقسام) - طلب سليمان صراحةً. عتبات الأعمدة (مواصفة تقنية 2026-08-25):
/// حتى 6 مرشدين = عمود واحد، 7-14 = عمودان، أكثر من 14 = ثلاثة أعمدة.
class AdvisingSchedulePptxService {
  static const _green = '154B36';
  static const _greenDark = '0D3324';
  static const _gold = 'C9A227';
  static const _lightGray = 'F7F5EF';
  static const _white = 'FFFFFF';
  static const _textDark = '1F2A24';

  static const int _slideW = 12192000; // 13.33in - عرض شاشة 16:9 قياسي
  static const int _slideH = 6858000; // 7.5in
  static const int _marginX = 450000;
  static const int _contentW = _slideW - 2 * _marginX;

  static Uint8List? _cachedLogoPng;
  static Future<Uint8List> _logoPng() async {
    if (_cachedLogoPng != null) return _cachedLogoPng!;
    final bytes = await rootBundle.load('assets/images/unit_logo_final.png');
    _cachedLogoPng = bytes.buffer.asUint8List();
    return _cachedLogoPng!;
  }

  static int _dayOrder(String label) {
    final i = AdvisingScheduleExcelService.dayColumnLabels.indexOf(label);
    return i == -1 ? AdvisingScheduleExcelService.dayColumnLabels.length : i;
  }

  static int _periodOrder(String label) {
    final i = AdvisingScheduleExcelService.periodOptions.indexWhere(label.startsWith);
    return i == -1 ? AdvisingScheduleExcelService.periodOptions.length : i;
  }

  /// عدد الأعمدة حسب المواصفة المعتمَدة: حتى 6 = عمود واحد، 7-14 = عمودان،
  /// أكثر من 14 = ثلاثة أعمدة.
  static int _columnsFor(int count) {
    if (count <= 6) return 1;
    if (count <= 14) return 2;
    return 3;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// إزالة مرشدين مكرّرين حرفيًا (نفس الاسم ونفس المكتب معًا) ضمن نفس
  /// (يوم/فترة/شطر/قسم) - لا تمسّ حالات تشارك مكتب واحد بين مرشدات مختلفات
  /// (بيانات مصدر حقيقية، ليست تكرارًا).
  static List<AdvisingScheduleEntry> _dedupe(List<AdvisingScheduleEntry> entries) {
    final seen = <String>{};
    final result = <AdvisingScheduleEntry>[];
    for (final e in entries) {
      final key = '${e.advisorName.trim()}|${e.office.trim()}';
      if (seen.add(key)) result.add(e);
    }
    return result;
  }

  /// يبني ملف ZIP خارجي واحد (`عروض_فترات_الإرشاد_الأكاديمي.zip`) يحوي
  /// مجلدين (شطر الطلاب/شطر الطالبات)، كل منهما ملفات .pptx (يوم × فترة)
  /// بداخل كل منها شريحة لكل قسم فعليًا فيه بيانات (أو كل الأقسام مع رسالة
  /// "لا توجد فترة إرشادية..." إن [showEmptyDepartments] = true).
  static Future<Uint8List> buildZip({
    required Map<(String, String), List<AdvisingScheduleSlot>> byDeptShatr,
    String term = 'الفصل الدراسي الأول 1448هـ',
    bool showEmptyDepartments = false,
  }) async {
    final logoPng = await _logoPng();
    final outer = Archive();

    for (final shatr in AdvisingScheduleExcelService.shatrOptions) {
      // كل مجموعات (يوم × فترة) الظاهرة فعليًا لهذا الشطر بأي قسم - تُقرأ
      // ديناميكيًا من البيانات الفعلية بدل افتراض أيام/فترات ثابتة مسبقًا.
      final dayPeriodKeys = <(String, String)>{};
      for (final department in AdvisingScheduleExcelService.departmentOptions) {
        final slots = byDeptShatr[(department, shatr)] ?? const [];
        for (final s in slots) {
          if (s.entries.isNotEmpty) dayPeriodKeys.add((s.dayLabel, s.periodLabel));
        }
      }
      final sortedKeys = dayPeriodKeys.toList()
        ..sort((a, b) {
          final d = _dayOrder(a.$1).compareTo(_dayOrder(b.$1));
          return d != 0 ? d : _periodOrder(a.$2).compareTo(_periodOrder(b.$2));
        });

      for (final (day, periodLabel) in sortedKeys) {
        final deptEntries = <(String department, List<AdvisingScheduleEntry> entries)>[];
        for (final department in AdvisingScheduleExcelService.departmentOptions) {
          final slots = byDeptShatr[(department, shatr)] ?? const [];
          final slot = slots.where((s) => s.dayLabel == day && s.periodLabel == periodLabel).firstOrNull;
          final entries = _dedupe(slot?.entries ?? const []);
          if (entries.isNotEmpty || showEmptyDepartments) {
            deptEntries.add((department, entries));
          }
        }
        if (deptEntries.isEmpty) continue;

        final maxEntries = deptEntries.map((d) => d.$2.length).fold(0, (a, b) => a > b ? a : b);
        final columnCount = _columnsFor(maxEntries == 0 ? 1 : maxEntries);
        final rowsPerColumnCapacity = maxEntries == 0 ? 1 : (maxEntries / columnCount).ceil();

        final pptxBytes = await _buildPresentation(
          day: day,
          periodLabel: periodLabel,
          shatr: shatr,
          term: term,
          deptEntries: deptEntries,
          columnCount: columnCount,
          rowsPerColumnCapacity: rowsPerColumnCapacity,
          logoPng: logoPng,
        );

        final fileName = '${day}_${periodLabel.replaceAll(' ', '_')}_${shatr.replaceAll(' ', '_')}.pptx';
        outer.addFile(ArchiveFile('$shatr/$fileName', pptxBytes.length, pptxBytes));
      }
    }

    // ملف ZIP فارغ بصمت (بلا أي عرض) يعني أن النطاق المُختار حاليًا (قسم/شطر
    // معيّن، أو حتى "الكل") لا يملك بيانات فترات إرشاد مرفوعة أصلاً - يُبلَّغ
    // المستخدم صراحةً بدل تنزيل ملف مربك بلا محتوى - دليل فعلي من سليمان
    // (2026-08-25): WinRAR أظهر "No files to extract" بلا أي تفسير.
    if (outer.files.isEmpty) {
      throw Exception('لا توجد بيانات فترات إرشاد مرفوعة للنطاق الحالي (تحقّق من اختيار "الكل" بالفلتر، أو ارفع ملف فترات الإرشاد أولاً).');
    }

    final zipBytes = ZipEncoder().encode(outer) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  // ------------------------------------------------------------------
  // بناء ملف .pptx واحد (أرشيف ZIP داخلي بصيغة Office Open XML)
  // ------------------------------------------------------------------

  static Future<Uint8List> _buildPresentation({
    required String day,
    required String periodLabel,
    required String shatr,
    required String term,
    required List<(String department, List<AdvisingScheduleEntry> entries)> deptEntries,
    required int columnCount,
    required int rowsPerColumnCapacity,
    required Uint8List logoPng,
  }) async {
    final n = deptEntries.length;
    final archive = Archive();

    void addText(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addText('[Content_Types].xml', _contentTypesXml(n));
    addText('_rels/.rels', _rootRelsXml());
    addText('docProps/core.xml', _corePropsXml('$day - ${AdvisingScheduleExcelService.periodDisplayLabel(periodLabel)} - $shatr'));
    addText('docProps/app.xml', _appPropsXml(n));
    addText('ppt/presentation.xml', _presentationXml(n));
    addText('ppt/_rels/presentation.xml.rels', _presentationRelsXml(n));
    addText('ppt/slideMasters/slideMaster1.xml', _slideMasterXml());
    addText('ppt/slideMasters/_rels/slideMaster1.xml.rels', _slideMasterRelsXml());
    addText('ppt/slideLayouts/slideLayout1.xml', _slideLayoutXml());
    addText('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _slideLayoutRelsXml());
    addText('ppt/theme/theme1.xml', _themeXml());

    archive.addFile(ArchiveFile('ppt/media/logo.png', logoPng.length, logoPng));

    for (var i = 0; i < n; i++) {
      final (department, entries) = deptEntries[i];
      final slideXml = _slideXml(
        day: day,
        periodLabel: periodLabel,
        shatr: shatr,
        term: term,
        department: department,
        entries: entries,
        columnCount: columnCount,
        rowsPerColumnCapacity: rowsPerColumnCapacity,
        pageIndex: i + 1,
        pageCount: n,
      );
      addText('ppt/slides/slide${i + 1}.xml', slideXml);
      addText('ppt/slides/_rels/slide${i + 1}.xml.rels', _slideRelsXml());
    }

    final bytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(bytes);
  }

  // ---------------- أجزاء الحزمة الثابتة (لا تتغيّر إلا بعدد الشرائح) ----------------

  static String _contentTypesXml(int n) {
    final slideOverrides = List.generate(
      n,
      (i) =>
          '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '$slideOverrides'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>';
  }

  static String _rootRelsXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  static String _corePropsXml(String title) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(title)}</dc:title>'
      '<dc:creator>وحدة الإرشاد الأكاديمي والخريجين</dc:creator>'
      '<cp:lastModifiedBy>وحدة الإرشاد الأكاديمي والخريجين</cp:lastModifiedBy>'
      '</cp:coreProperties>';

  static String _appPropsXml(int n) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>Microsoft Office PowerPoint</Application>'
      '<PresentationFormat>Widescreen</PresentationFormat>'
      '<Slides>$n</Slides>'
      '<Company>جامعة الطائف - كلية إدارة الأعمال</Company>'
      '</Properties>';

  static String _presentationXml(int n) {
    final sldIds = List.generate(n, (i) => '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>').join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$sldIds</p:sldIdLst>'
        '<p:sldSz cx="$_slideW" cy="$_slideH" type="screen16x9"/>'
        '<p:notesSz cx="6858000" cy="9144000"/>'
        // loop="1": يُعيد العرض التلقائي الدوران من الشريحة الأولى بلا توقف
        // عند آخر قسم - طلب صريح بالمواصفة (بند 6: "Repeat continuously").
        '<p:showPr loop="1" showNarration="0"/>'
        '</p:presentation>';
  }

  static String _presentationRelsXml(int n) {
    final slideRels = List.generate(
      n,
      (i) =>
          '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '$slideRels'
        '</Relationships>';
  }

  static String _slideMasterXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld>'
      '<p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '</p:spTree>'
      '</p:cSld>'
      '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
      '<p:txStyles>'
      '<p:titleStyle><a:lvl1pPr><a:defRPr sz="4400"/></a:lvl1pPr></p:titleStyle>'
      '<p:bodyStyle><a:lvl1pPr><a:defRPr sz="3200"/></a:lvl1pPr></p:bodyStyle>'
      '<p:otherStyle><a:lvl1pPr><a:defRPr sz="3200"/></a:lvl1pPr></p:otherStyle>'
      '</p:txStyles>'
      '</p:sldMaster>';

  static String _slideMasterRelsXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
      '</Relationships>';

  static String _slideLayoutXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">'
      '<p:cSld name="فارغ">'
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '</p:spTree>'
      '</p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sldLayout>';

  static String _slideLayoutRelsXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
      '</Relationships>';

  static String _themeXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="الإرشاد الأكاديمي">'
      '<a:themeElements>'
      '<a:clrScheme name="الإرشاد">'
      '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
      '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
      '<a:dk2><a:srgbClr val="$_greenDark"/></a:dk2>'
      '<a:lt2><a:srgbClr val="$_lightGray"/></a:lt2>'
      '<a:accent1><a:srgbClr val="$_green"/></a:accent1>'
      '<a:accent2><a:srgbClr val="$_gold"/></a:accent2>'
      '<a:accent3><a:srgbClr val="$_greenDark"/></a:accent3>'
      '<a:accent4><a:srgbClr val="$_lightGray"/></a:accent4>'
      '<a:accent5><a:srgbClr val="$_green"/></a:accent5>'
      '<a:accent6><a:srgbClr val="$_gold"/></a:accent6>'
      '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
      '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
      '</a:clrScheme>'
      '<a:fontScheme name="الإرشاد">'
      // خط Arial - متوفر دومًا بأجهزة العرض الجامعية القياسية (بند تقني صريح:
      // تفادي أي خط قد لا يتوفر على شاشات الإسياب بالممرات).
      '<a:majorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface="Arial"/></a:majorFont>'
      '<a:minorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface="Arial"/></a:minorFont>'
      '</a:fontScheme>'
      '<a:fmtScheme name="الإرشاد">'
      '<a:fillStyleLst>'
      '<a:solidFill><a:schemeClr val="accent1"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="accent1"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="accent1"/></a:solidFill>'
      '</a:fillStyleLst>'
      '<a:lnStyleLst>'
      '<a:ln w="6350"><a:solidFill><a:schemeClr val="accent1"/></a:solidFill></a:ln>'
      '<a:ln w="12700"><a:solidFill><a:schemeClr val="accent1"/></a:solidFill></a:ln>'
      '<a:ln w="19050"><a:solidFill><a:schemeClr val="accent1"/></a:solidFill></a:ln>'
      '</a:lnStyleLst>'
      '<a:effectStyleLst>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '</a:effectStyleLst>'
      '<a:bgFillStyleLst>'
      '<a:solidFill><a:schemeClr val="lt1"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="lt1"/></a:solidFill>'
      '<a:solidFill><a:schemeClr val="lt1"/></a:solidFill>'
      '</a:bgFillStyleLst>'
      '</a:fmtScheme>'
      '</a:themeElements>'
      '</a:theme>';

  static String _slideRelsXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/logo.png"/>'
      '</Relationships>';

  // ---------------- بناء شريحة قسم واحد ----------------

  static int _shapeIdCounter = 1;
  static int _nextId() => ++_shapeIdCounter;

  static String _textBox({
    required int x,
    required int y,
    required int cx,
    required int cy,
    required String text,
    required int sz,
    bool bold = false,
    String color = _textDark,
    String? fillHex,
    String align = 'ctr',
  }) {
    final id = _nextId();
    final fill = fillHex == null ? '' : '<a:solidFill><a:srgbClr val="$fillHex"/></a:solidFill>';
    return '<p:sp>'
        '<p:nvSpPr><p:cNvPr id="$id" name="TextBox $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr>'
        '<a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '$fill'
        '</p:spPr>'
        '<p:txBody>'
        '<a:bodyPr wrap="square" anchor="ctr" rtlCol="1"><a:noAutofit/></a:bodyPr>'
        '<a:lstStyle/>'
        '<a:p><a:pPr algn="$align"/><a:r>'
        '<a:rPr lang="ar-SA" sz="$sz" b="${bold ? 1 : 0}"><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
        '<a:latin typeface="Arial"/><a:cs typeface="Arial"/></a:rPr>'
        '<a:t>${_esc(text)}</a:t>'
        '</a:r></a:p>'
        '</p:txBody>'
        '</p:sp>';
  }

  static String _pictureLogo({required int x, required int y, required int cx, required int cy}) {
    final id = _nextId();
    return '<p:pic>'
        '<p:nvPicPr><p:cNvPr id="$id" name="الشعار"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
        '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '</p:pic>';
  }

  // حدود أفقية رفيعة فاتحة بين الصفوف فقط (لا حدود رأسية) - نفس أسلوب جداول
  // PDF/Word بالمشروع - بدل الشبكة السوداء الغليظة الافتراضية بـPowerPoint
  // (نمط الجدول المدمَج `{5940675A-...}` "بلا نمط/بلا شبكة" بـ[_columnTable]
  // يُسكِت النمط الافتراضي، وهذه الحدود الصريحة هنا تحل محله) - دليل فعلي من
  // سليمان (2026-08-25): "الحدود الموضوعة غريبة كأنه تصميم شخص مبتدئ".
  static const String _cellBorders = '<a:lnL><a:noFill/></a:lnL>'
      '<a:lnR><a:noFill/></a:lnR>'
      '<a:lnT><a:noFill/></a:lnT>'
      '<a:lnB w="9525"><a:solidFill><a:srgbClr val="E3E0D6"/></a:solidFill></a:lnB>';

  static String _cellXml(String text, {bool bold = false, int sz = 1200, String color = _textDark, String? fillHex}) {
    final fill = fillHex == null ? '<a:noFill/>' : '<a:solidFill><a:srgbClr val="$fillHex"/></a:solidFill>';
    return '<a:tc>'
        '<a:txBody><a:bodyPr anchor="ctr" rtlCol="1"/><a:lstStyle/>'
        '<a:p><a:pPr algn="ctr"/><a:r>'
        '<a:rPr lang="ar-SA" sz="$sz" b="${bold ? 1 : 0}"><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
        '<a:latin typeface="Arial"/><a:cs typeface="Arial"/></a:rPr>'
        '<a:t>${_esc(text)}</a:t>'
        '</a:r></a:p>'
        '</a:txBody>'
        '<a:tcPr anchor="ctr">$_cellBorders$fill</a:tcPr>'
        '</a:tc>';
  }

  /// جدول DrawingML حقيقي (رقم المكتب + اسم المرشد) بـ[rowCount] صف بيانات
  /// ثابت (المُشتَق من أعلى عدد بكل الملف) - عمود المكتب أولًا ثم الاسم (رغم
  /// أن الاسم يظهر أولاً بالقراءة العربية) لأن جداول DrawingML تُرتَّب فعليًا
  /// من يسار الشريحة بصريًا لا حسب اتجاه النص، فيبقى الاسم بالجهة اليمنى
  /// المتوقَّعة فعليًا رغم فهرسته ثانيًا - نفس الحيلة المستخدَمة بمولّد PDF.
  static String _columnTable({
    required int x,
    required int y,
    required int cx,
    required int rowHeight,
    required int rowCount,
    required List<AdvisingScheduleEntry> rows,
  }) {
    final id = _nextId();
    final officeW = (cx * 0.28).round();
    final nameW = cx - officeW;
    final headerRow = '<a:tr h="$rowHeight">'
        '${_cellXml('رقم المكتب', bold: true, sz: 1300, color: _white, fillHex: _green)}'
        '${_cellXml('اسم المرشد الأكاديمي', bold: true, sz: 1300, color: _white, fillHex: _green)}'
        '</a:tr>';
    final dataRows = List.generate(rowCount, (i) {
      final zebra = i.isEven ? _white : _lightGray;
      if (i < rows.length) {
        return '<a:tr h="$rowHeight">'
            '${_cellXml(rows[i].office, sz: 1200, fillHex: zebra)}'
            '${_cellXml(rows[i].advisorName, sz: 1200, fillHex: zebra)}'
            '</a:tr>';
      }
      return '<a:tr h="$rowHeight">${_cellXml('', fillHex: zebra)}${_cellXml('', fillHex: zebra)}</a:tr>';
    }).join();
    final totalH = rowHeight * (rowCount + 1);
    return '<p:graphicFrame>'
        '<p:nvGraphicFramePr><p:cNvPr id="$id" name="جدول $id"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
        '<p:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$totalH"/></p:xfrm>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
        // نمط الجدول المدمَج "بلا نمط، بلا شبكة" - يُسكِت الشبكة السوداء
        // الافتراضية بـPowerPoint فتتحكم حدود كل خلية الصريحة ([_cellXml])
        // وحدها بالمظهر النهائي.
        '<a:tbl><a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{5940675A-B579-460E-94D1-54222C63F5DA}</a:tableStyleId></a:tblPr>'
        '<a:tblGrid><a:gridCol w="$officeW"/><a:gridCol w="$nameW"/></a:tblGrid>'
        '$headerRow$dataRows'
        '</a:tbl>'
        '</a:graphicData></a:graphic>'
        '</p:graphicFrame>';
  }

  static String _slideXml({
    required String day,
    required String periodLabel,
    required String shatr,
    required String term,
    required String department,
    required List<AdvisingScheduleEntry> entries,
    required int columnCount,
    required int rowsPerColumnCapacity,
    required int pageIndex,
    required int pageCount,
  }) {
    final shapes = StringBuffer();

    // شريط علوي أخضر غامق: الخلفية أولاً ثم الشعار والنصوص فوقها - كل شكل
    // لاحق يُرسَم فوق السابق بصيغة PowerPoint، فرسم الخلفية أخيرًا (كما كان)
    // كان يُخفي الشعار والعنوان كليًا خلفها بلا أي أثر ظاهر - دليل فعلي من
    // سليمان (2026-08-25): الشريط العلوي ظهر أخضر فارغًا تمامًا بلا شعار ولا
    // نص. شريط ذهبي رفيع أسفل الترويسة يفصلها عن بقية الشريحة (هوية بصرية).
    const headerH = 750000;
    shapes.write('<p:sp><p:nvSpPr><p:cNvPr id="${_nextId()}" name="خلفية الترويسة"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$_slideW" cy="$headerH"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="$_greenDark"/></a:solidFill></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>');
    shapes.write('<p:sp><p:nvSpPr><p:cNvPr id="${_nextId()}" name="فاصل ذهبي"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="0" y="$headerH"/><a:ext cx="$_slideW" cy="30000"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="$_gold"/></a:solidFill></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>');
    shapes.write(_pictureLogo(x: _marginX, y: 90000, cx: 570000, cy: 570000));
    shapes.write(_textBox(
      x: _marginX + 700000,
      y: 90000,
      cx: _contentW - 700000,
      cy: 340000,
      text: 'فترات الإرشاد الأكاديمي',
      sz: 2200,
      bold: true,
      color: _white,
      align: 'r',
    ));
    shapes.write(_textBox(
      x: _marginX + 700000,
      y: 420000,
      cx: _contentW - 700000,
      cy: 260000,
      text: term,
      sz: 1400,
      color: _gold,
      align: 'r',
    ));

    // شريط معلومات (اليوم | الفترة والوقت | الشطر) - خلفية فاتحة، نص أخضر بارز.
    const infoY = headerH + 40000;
    const infoH = 420000;
    shapes.write(_textBox(
      x: _marginX,
      y: infoY,
      cx: _contentW,
      cy: infoH,
      text: '$day  |  ${AdvisingScheduleExcelService.periodDisplayLabel(periodLabel)}  |  $shatr',
      sz: 1800,
      bold: true,
      color: _green,
      fillHex: _lightGray,
    ));

    // شريط اسم القسم - أخضر غامق بارز.
    const deptY = infoY + infoH + 40000;
    const deptH = 480000;
    shapes.write(_textBox(
      x: _marginX,
      y: deptY,
      cx: _contentW,
      cy: deptH,
      text: department,
      sz: 2000,
      bold: true,
      color: _white,
      fillHex: _greenDark,
    ));

    // تسمية "المرشدون المتاحون خلال هذه الفترة".
    const labelY = deptY + deptH + 30000;
    const labelH = 320000;
    shapes.write(_textBox(
      x: _marginX,
      y: labelY,
      cx: _contentW,
      cy: labelH,
      text: 'المرشدون المتاحون خلال هذه الفترة',
      sz: 1400,
      bold: true,
      color: _green,
    ));

    // منطقة الجدول (أو رسالة "لا توجد فترة إرشادية..." حين لا يوجد مرشدون).
    const footerH = 340000;
    const counterH = 260000;
    const bottomReserve = footerH + counterH + 100000;
    final tableY = labelY + labelH + 30000;
    final tableAreaH = _slideH - bottomReserve - tableY;

    if (entries.isEmpty) {
      shapes.write(_textBox(
        x: _marginX,
        y: tableY,
        cx: _contentW,
        cy: tableAreaH,
        text: 'لا توجد فترة إرشادية مسجلة لهذا القسم خلال الفترة المحددة',
        sz: 1600,
        bold: true,
        color: _greenDark,
      ));
    } else {
      final rowHeight = (tableAreaH / (rowsPerColumnCapacity + 1)).floor().clamp(220000, 480000);
      final perColumn = (entries.length / columnCount).ceil();
      final gap = 150000;
      final colW = ((_contentW - gap * (columnCount - 1)) / columnCount).floor();
      for (var c = 0; c < columnCount; c++) {
        final start = c * perColumn;
        if (start >= entries.length) break;
        final end = (start + perColumn > entries.length) ? entries.length : start + perColumn;
        final chunk = entries.sublist(start, end);
        final x = _marginX + c * (colW + gap);
        shapes.write(_columnTable(
          x: x,
          y: tableY,
          cx: colW,
          rowHeight: rowHeight,
          rowCount: chunk.length,
          rows: chunk,
        ));
      }
    }

    // رسالة أسفل الشريحة + عداد الصفحات.
    final footerY = _slideH - footerH - counterH - 60000;
    shapes.write(_textBox(
      x: _marginX,
      y: footerY,
      cx: _contentW,
      cy: footerH,
      text: 'يرجى التوجه إلى مكتب المرشد الأكاديمي الموضح أمام الاسم',
      sz: 1300,
      bold: true,
      color: _gold,
    ));
    shapes.write(_textBox(
      x: _marginX,
      y: footerY + footerH + 20000,
      cx: _contentW,
      cy: counterH,
      text: '$pageIndex / $pageCount',
      sz: 1100,
      color: _textDark,
    ));

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '$shapes'
        '</p:spTree></p:cSld>'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        // انتقال تلاشٍ (Fade) + تقدُّم تلقائي كل 12 ثانية - طلب صريح بالمواصفة
        // التقنية (بند 6)، مع `loop="1"` بـ`presentation.xml` للتكرار المستمر.
        '<p:transition spd="slow" advClick="1" advTm="12000"><p:fade/></p:transition>'
        '</p:sld>';
  }
}
