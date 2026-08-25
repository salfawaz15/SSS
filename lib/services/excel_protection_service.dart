import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// يعالج ملف xlsx مُولَّد مسبقًا (كأرشيف ZIP/XML وفق مواصفة OOXML) لإضافة
/// قائمة منسدلة على عمود معيّن، وحماية الشيت بحيث تبقى أعمدة محدّدة قابلة
/// للتعديل فقط. مكتبة `excel` المستخدمة في المشروع لا تدعم أيًا من الاثنين
/// مباشرة، لذا تتم المعالجة يدويًا على مستوى XML.
/// قائمة منسدلة واحدة مطلوب إضافتها لعمود معيّن
class DropdownColumn {
  final int columnIndex;
  final List<String> options;

  /// true (الافتراضي) = يرفض إكسل أي قيمة خارج القائمة تمامًا. false = تظهر
  /// القائمة كاقتراح مع تحذير فقط، ويبقى بإمكان المستخدم كتابة نص حر (مثال:
  /// عمود ملاحظات فيه خيارات شائعة لكن تُسمح كتابة حالة غير متوقعة يدويًا).
  final bool strict;

  /// نطاق خلايا مخصَّص (مثال: "B2:B2" لخلية واحدة أعلى الجدول) بدل الحساب
  /// التلقائي لعمود كامل عبر كل صفوف البيانات - يُستخدم لقوائم لا تتكرر لكل
  /// صف (كاختيار القسم مرّة واحدة أعلى النموذج).
  final String? sqrefOverride;

  /// مرجع نطاق خام كصيغة (مثال: "قائمة_الأسماء!\$A\$2:\$A\$50") بدل قائمة
  /// نصية حرفية - يتفادى حد الطول (~255 حرفًا) الذي يرفضه إكسل للقوائم
  /// الطويلة المكتوبة كنص مباشر داخل الصيغة.
  final String? rangeFormula;

  const DropdownColumn({
    required this.columnIndex,
    this.options = const [],
    this.strict = true,
    this.sqrefOverride,
    this.rangeFormula,
  });
}

class ExcelProtectionService {
  static const String protectionPassword = 'Sulaiman';
  static const List<String> statusOptions = ['تم الإنجاز', 'جزئي', 'لم يتم'];

  /// خياران فقط لعمود "حالة الإنجاز من قبل المرشد الأكاديمي" تحديدًا (بخلاف
  /// [statusOptions] الثلاثي المستخدَم بمستويي مراجعة القسم/الكلية): المرشد
  /// يقرّر لكل إجراء منفرد هل نُفِّذ أو لا فقط، بينما "تنفيذ جزئي" تُحسب لاحقًا
  /// تلقائيًا على مستوى الطالب ككل من مجموع إجراءاته (وليست خيارًا يدويًا).
  static const List<String> advisorActionStatusOptions = ['تم التنفيذ', 'لم يتم التنفيذ'];

  /// يقفل كل الأعمدة في الشيت الأول عدا [unlockedColumnIndexes] (صفر-فهرسة)،
  /// ويضيف قائمة منسدلة لكل عنصر في [dropdowns]، لعدد صفوف بيانات
  /// [dataRowCount] (بدون احتساب صف العناوين).
  static Uint8List protect(
    Uint8List xlsxBytes, {
    required List<DropdownColumn> dropdowns,
    required List<int> unlockedColumnIndexes,
    required int dataRowCount,
    int headerRowCount = 1,
    List<String> unlockedCellRefs = const [],
    // false = لا قفل/كلمة مرور إطلاقًا (قوائم منسدلة إرشادية فقط) - يُستخدم
    // للنماذج التي يعبّئها مسؤول موثوق (رئيس قسم/أمين/منسّق) لا يحتاج قيدًا
    // صارمًا، بعكس نماذج أخرى في الموقع تتطلب حماية فعلية.
    bool addProtection = true,
    // أعمدة تُخفى بصريًا عن المستخدم (لا تُحذَف) - تبقى قيمها بالملف فعليًا
    // لأغراض أخرى (كالمطابقة عند إعادة القراءة) لكن لا داعي لعرضها له لو لم
    // يكن هو من يعبّئها (مثال: أعمدة منسّق القسم/الكلية بملف المرشد).
    List<int> hiddenColumnIndexes = const [],
  }) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);

    final stylesFile = archive.findFile('xl/styles.xml')!;
    final stylesXml = XmlDocument.parse(
      utf8.decode(stylesFile.content as List<int>),
    );
    final unlockedStyleIndex = _addUnlockedStyle(stylesXml);

    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final sheetXml = XmlDocument.parse(
      utf8.decode(sheetFile.content as List<int>),
    );
    // حزمة `excel` قد تُصدر عنصر <drawing r:id="rId1"/> داخل sheet1.xml نفسه
    // (لوحظ هذا لأول مرة هنا رغم أن ملاحظة سابقة افترضت أنه لا يحدث أبدًا) -
    // بينما أجزاء الرسم الفعلية (drawing1.xml وعلاقاته) تُحذَف أدناه دومًا لأن
    // [addLogoImage] غير مستخدَم بالمشروع. إبقاء هذا العنصر بلا حذف حالة
    // الرابط اليتيم (Relationship مفقود) بالضبط ما يجعل إكسل يعرض "وجدنا
    // مشكلة في المحتوى" ويطلب الإصلاح - فيجب حذفه دومًا هنا أيضًا.
    sheetXml.rootElement.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'drawing')
        .toList()
        .forEach((e) => e.parent?.children.remove(e));
    if (addProtection) {
      _unlockColumns(sheetXml, unlockedColumnIndexes, unlockedStyleIndex, headerRowCount);
      _unlockCells(sheetXml, unlockedCellRefs, unlockedStyleIndex);
      _addSheetProtection(sheetXml);
    }
    _addDropdowns(sheetXml, dropdowns, dataRowCount, headerRowCount);
    if (hiddenColumnIndexes.isNotEmpty) {
      _hideColumns(sheetXml, hiddenColumnIndexes);
    }

    // إزالة "شبح الرسم" الفارغ - حزمة `excel` تُصدر دومًا (لكل ملف تولّده،
    // حتى بلا أي صورة/رسم فعلي): xl/drawings/drawing1.xml فارغ +
    // xl/worksheets/_rels/sheet1.xml.rels يربطه بـsheet1.xml برقم rId1 +
    // إدخال Content_Types لذلك الجزء - لكن sheet1.xml نفسه **لا يحتوي أبدًا**
    // على عنصر `<drawing r:id="rId1"/>` الفعلي يستخدم تلك العلاقة. هذا تناقض
    // حقيقي بين ملف العلاقات والمحتوى الفعلي يرفضه محلِّل إكسل الصارم لسطح
    // المكتب (يظهر "وجدنا مشكلة في محتوى..." ويُصلِح الملف تلقائيًا، حاذفًا
    // معه أحيانًا القوائم المنسدلة المُدرَجة يدويًا) بينما يتجاهله إكسل أونلاين/
    // المتصفح بتساهل فيفتح الملف بلا مشكلة - بالضبط ما لاحظه سليمان صراحةً
    // (2026-08-15) بنموذج توزيع فترات الإرشاد. تحقَّقتُ بتوليد ملف فعلي
    // وفحص محتوى الأرشيف مباشرة قبل هذا الإصلاح لتأكيد التشخيص. الحذف هنا
    // آمن دومًا حاليًا لأن [addLogoImage] (المسار الوحيد الذي يضيف رسمًا
    // حقيقيًا) غير مستخدَم فعليًا بأي مكان بالمشروع.
    const drawingStubPaths = {
      'xl/drawings/drawing1.xml',
      'xl/drawings/_rels/drawing1.xml.rels',
      'xl/worksheets/_rels/sheet1.xml.rels',
    };
    final ctFile = archive.findFile('[Content_Types].xml');
    XmlDocument? ctXml;
    if (ctFile != null) {
      ctXml = XmlDocument.parse(utf8.decode(ctFile.content as List<int>));
      ctXml.rootElement.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'Override' && e.getAttribute('PartName') == '/xl/drawings/drawing1.xml')
          .toList()
          .forEach((e) => e.parent?.children.remove(e));
    }

    final newArchive = Archive();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (drawingStubPaths.contains(file.name)) continue;

      if (file.name == 'xl/styles.xml') {
        final bytes = utf8.encode(stylesXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (file.name == 'xl/worksheets/sheet1.xml') {
        final bytes = utf8.encode(sheetXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (file.name == '[Content_Types].xml' && ctXml != null) {
        final bytes = utf8.encode(ctXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        final content = file.content as List<int>;
        newArchive.addFile(ArchiveFile(file.name, content.length, content));
      }
    }

    return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
  }

  /// يضيف نمط خلية جديد بخاصية "غير مقفل" في نهاية cellXfs، ويرجّع فهرسه
  static int _addUnlockedStyle(XmlDocument stylesXml) {
    final cellXfs = stylesXml.findAllElements('cellXfs').first;
    final existingXfs = cellXfs.findElements('xf').toList();
    final template = existingXfs.last;

    final newXf = template.copy();
    newXf.children.add(
      XmlElement(XmlName('protection'), [XmlAttribute(XmlName('locked'), '0')]),
    );
    cellXfs.children.add(newXf);

    final newIndex = existingXfs.length;
    cellXfs.setAttribute('count', (newIndex + 1).toString());
    return newIndex;
  }

  static void _unlockColumns(
    XmlDocument sheetXml,
    List<int> unlockedColumnIndexes,
    int unlockedStyleIndex,
    int headerRowCount,
  ) {
    final unlockedLetters = unlockedColumnIndexes.map(_columnLetter).toSet();

    final rows = sheetXml.findAllElements('row');
    for (final row in rows) {
      final rowNumber = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
      if (rowNumber <= headerRowCount) continue; // تخطّي صفوف العناوين/الرأس

      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final letters = ref.replaceAll(RegExp(r'\d'), '');
        if (unlockedLetters.contains(letters)) {
          cell.setAttribute('s', unlockedStyleIndex.toString());
        }
      }
    }
  }

  /// يفتح خلايا محدَّدة بعناوينها الصريحة (مثال: "B1") بصرف النظر عن كونها
  /// ضمن صفوف الرأس المحمية أصلاً - يُستخدم لخلايا اختيار مفردة أعلى النموذج
  /// (كخلية اختيار القسم) لا تتبع نمط "عمود بيانات متكرر لكل صف".
  static void _unlockCells(XmlDocument sheetXml, List<String> refs, int unlockedStyleIndex) {
    if (refs.isEmpty) return;
    final refSet = refs.toSet();
    for (final row in sheetXml.findAllElements('row')) {
      for (final cell in row.findElements('c')) {
        if (refSet.contains(cell.getAttribute('r') ?? '')) {
          cell.setAttribute('s', unlockedStyleIndex.toString());
        }
      }
    }
  }

  /// يُخفي أعمدة بصريًا (`<cols><col .../></cols>`) - يجب أن يسبق `<sheetData>`
  /// مباشرة حسب ترتيب مخطط OOXML الرسمي، وإلا يعتبر إكسل الملف تالفًا.
  static void _hideColumns(XmlDocument sheetXml, List<int> columnIndexes) {
    final worksheet = sheetXml.rootElement;
    final sheetData = worksheet.findElements('sheetData').first;

    final colElements = columnIndexes.map((index) {
      final colNumber = index + 1; // 1-فهرسة بمخطط OOXML بخلاف صفر-فهرسة الخلايا
      return XmlElement(XmlName('col'), [
        XmlAttribute(XmlName('min'), colNumber.toString()),
        XmlAttribute(XmlName('max'), colNumber.toString()),
        XmlAttribute(XmlName('width'), '9'),
        XmlAttribute(XmlName('hidden'), '1'),
        XmlAttribute(XmlName('customWidth'), '1'),
      ]);
    }).toList();

    final colsElement = XmlElement(XmlName('cols'), [], colElements);
    sheetData.parent!.children.insert(
      sheetData.parent!.children.indexOf(sheetData),
      colsElement,
    );
  }

  static void _addSheetProtection(XmlDocument sheetXml) {
    final worksheet = sheetXml.rootElement;
    final sheetData = worksheet.findElements('sheetData').first;

    final protectionElement = XmlElement(XmlName('sheetProtection'), [
      XmlAttribute(XmlName('sheet'), '1'),
      XmlAttribute(XmlName('objects'), '1'),
      XmlAttribute(XmlName('scenarios'), '1'),
      // بلا هذين تُمنع تلقائيًا (القيمة الافتراضية "محمي" حسب مواصفة OOXML
      // لو غابا) - فلا يقدر أي عضو على توسيع عمود ليقرأ محتوى طويلاً حتى لو
      // كانت خلاياه نفسها مقفلة أصلاً (سليمان لاحظ هذا فعليًا 2026-08-25:
      // النص يظهر مبتورًا ولا يمكن تكبير العمود لقراءته).
      XmlAttribute(XmlName('formatColumns'), '0'),
      XmlAttribute(XmlName('formatRows'), '0'),
      XmlAttribute(XmlName('password'), _hashPassword(protectionPassword)),
    ]);

    sheetData.parent!.children.insert(
      sheetData.parent!.children.indexOf(sheetData) + 1,
      protectionElement,
    );
  }

  static void _addDropdowns(
    XmlDocument sheetXml,
    List<DropdownColumn> dropdowns,
    int dataRowCount,
    int headerRowCount,
  ) {
    if (dropdowns.isEmpty) return;

    final worksheet = sheetXml.rootElement;
    // dataValidations يجب أن يأتي بعد mergeCells (إن وُجد) وبعد sheetProtection
    // (إن وُجد) حسب ترتيب مخطط OOXML الرسمي (sheetData < sheetProtection <
    // ... < mergeCells < ... < dataValidations) - وإلا يعتبر إكسل الملف تالفًا
    // أو يتجاهل القوائم المنسدلة بصمت عند "الإصلاح التلقائي" للملف.
    final anchorEl = worksheet.findElements('mergeCells').firstOrNull ??
        worksheet.findElements('sheetProtection').firstOrNull ??
        worksheet.findElements('sheetData').first;
    final firstRow = headerRowCount + 1;
    final lastRow = headerRowCount + dataRowCount;

    final validationElements = dropdowns.map((dropdown) {
      final letter = _columnLetter(dropdown.columnIndex);
      final sqref = dropdown.sqrefOverride ?? '$letter$firstRow:$letter$lastRow';

      final formula = XmlElement(XmlName('formula1'), [], [
        XmlText(dropdown.rangeFormula ?? '"${dropdown.options.join(',')}"'),
      ]);

      return XmlElement(
        XmlName('dataValidation'),
        [
          XmlAttribute(XmlName('type'), 'list'),
          XmlAttribute(XmlName('allowBlank'), '1'),
          XmlAttribute(XmlName('showInputMessage'), '1'),
          XmlAttribute(XmlName('showErrorMessage'), '1'),
          if (!dropdown.strict) XmlAttribute(XmlName('errorStyle'), 'information'),
          XmlAttribute(XmlName('sqref'), sqref),
        ],
        [formula],
      );
    }).toList();

    final validationsElement = XmlElement(XmlName('dataValidations'), [
      XmlAttribute(XmlName('count'), validationElements.length.toString()),
    ], validationElements);

    anchorEl.parent!.children.insert(
      anchorEl.parent!.children.indexOf(anchorEl) + 1,
      validationsElement,
    );
  }

  /// يضيف صورة (مثل شعار الوحدة) في الشيت الأول عند خلية معيّنة - مكتبة
  /// `excel` لا تدعم تضمين الصور، فتُبنى أجزاء OOXML (media/drawing/rels)
  /// يدويًا وتُدمج في أرشيف الملف.
  static Uint8List addLogoImage(
    Uint8List xlsxBytes, {
    required List<int> imageBytes,
    int colFrom = 0,
    int rowFrom = 0,
    int widthPx = 130,
    int heightPx = 50,
  }) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);

    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final sheetXml = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final drawingRef = XmlDocument.parse(
      '<drawing xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1"/>',
    ).rootElement.copy();
    sheetXml.rootElement.children.add(drawingRef);

    // إكسل حساس لترتيب [Content_Types].xml: كل عناصر Default يجب أن تسبق كل
    // عناصر Override (المخطط الرسمي يفرض ذلك)، ومكتبة excel نفسها تُصدر
    // بالفعل عنصر Override لـ drawing1.xml ضمن كل ملف تولّده (حتى بلا صور) -
    // فيجب إزالته أولاً بدل تكراره، وإلا يرفض إكسل الملف عند الفتح.
    final ctFile = archive.findFile('[Content_Types].xml')!;
    final ctXml = XmlDocument.parse(utf8.decode(ctFile.content as List<int>));
    final ctChildren = ctXml.rootElement.children.whereType<XmlElement>().toList();
    ctChildren
        .where((e) => e.name.local == 'Override' && e.getAttribute('PartName') == '/xl/drawings/drawing1.xml')
        .toList()
        .forEach((e) => e.parent?.children.remove(e));

    final hasPngDefault = ctXml.rootElement.children
        .whereType<XmlElement>()
        .any((e) => e.name.local == 'Default' && e.getAttribute('Extension') == 'png');
    final lastDefaultIndex = ctXml.rootElement.children.lastIndexWhere(
      (n) => n is XmlElement && n.name.local == 'Default',
    );
    if (!hasPngDefault) {
      ctXml.rootElement.children.insert(
        lastDefaultIndex + 1,
        XmlElement(XmlName('Default'), [
          XmlAttribute(XmlName('Extension'), 'png'),
          XmlAttribute(XmlName('ContentType'), 'image/png'),
        ]),
      );
    }
    ctXml.rootElement.children.add(XmlElement(XmlName('Override'), [
      XmlAttribute(XmlName('PartName'), '/xl/drawings/drawing1.xml'),
      XmlAttribute(XmlName('ContentType'), 'application/vnd.openxmlformats-officedocument.drawing+xml'),
    ]));

    const emuPerPx = 9525;
    final widthEmu = widthPx * emuPerPx;
    final heightEmu = heightPx * emuPerPx;
    final drawingXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <xdr:oneCellAnchor>
    <xdr:from><xdr:col>$colFrom</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>$rowFrom</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>
    <xdr:ext cx="$widthEmu" cy="$heightEmu"/>
    <xdr:pic>
      <xdr:nvPicPr><xdr:cNvPr id="1" name="Logo"/><xdr:cNvPicPr/></xdr:nvPicPr>
      <xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
      <xdr:spPr>
        <a:xfrm><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
      </xdr:spPr>
    </xdr:pic>
    <xdr:clientData/>
  </xdr:oneCellAnchor>
</xdr:wsDr>''';

    const drawingRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
</Relationships>''';

    const sheetRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
</Relationships>''';

    final newArchive = Archive();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == 'xl/worksheets/sheet1.xml') {
        final bytes = utf8.encode(sheetXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (file.name == '[Content_Types].xml') {
        final bytes = utf8.encode(ctXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (file.name == 'xl/worksheets/_rels/sheet1.xml.rels' ||
          file.name == 'xl/drawings/drawing1.xml' ||
          file.name == 'xl/drawings/_rels/drawing1.xml.rels') {
        // تُستبدل أدناه - مكتبة excel تُصدر نسخة فارغة (stub) من drawing1.xml
        // في كل ملف حتى بلا صور؛ نسخها هنا كما هي يُنتج ملفًا مكررًا بنفس
        // الاسم داخل الأرشيف (ملف ZIP غير صالح) عند إضافة نسختنا لاحقًا.
        continue;
      } else {
        final content = file.content as List<int>;
        newArchive.addFile(ArchiveFile(file.name, content.length, content));
      }
    }
    newArchive.addFile(ArchiveFile('xl/media/image1.png', imageBytes.length, imageBytes));
    final drawingBytes = utf8.encode(drawingXml);
    newArchive.addFile(ArchiveFile('xl/drawings/drawing1.xml', drawingBytes.length, drawingBytes));
    final drawingRelsBytes = utf8.encode(drawingRelsXml);
    newArchive.addFile(ArchiveFile('xl/drawings/_rels/drawing1.xml.rels', drawingRelsBytes.length, drawingRelsBytes));
    final sheetRelsBytes = utf8.encode(sheetRelsXml);
    newArchive.addFile(ArchiveFile('xl/worksheets/_rels/sheet1.xml.rels', sheetRelsBytes.length, sheetRelsBytes));

    return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
  }

  /// يُخفي أوراق عمل مرجعية (كقائمة أسماء يُبنى عليها بحث/قوائم منسدلة) عن
  /// المستخدم النهائي، ويضيف أسماء نطاقات معرَّفة (Defined Names) في
  /// workbook.xml يمكن الإشارة إليها بصيغ INDIRECT لاحقًا (مثال: قائمة
  /// منسدلة تتغيّر حسب قسم/شطر مُختار في خليتين أخريين).
  static Uint8List finalizeWorkbook(
    Uint8List xlsxBytes, {
    List<String> hiddenSheetNames = const [],
    Map<String, String> definedNames = const {},
  }) {
    if (hiddenSheetNames.isEmpty && definedNames.isEmpty) return xlsxBytes;
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final wbFile = archive.findFile('xl/workbook.xml')!;
    final wbXml = XmlDocument.parse(utf8.decode(wbFile.content as List<int>));

    if (hiddenSheetNames.isNotEmpty) {
      for (final sheetEl in wbXml.findAllElements('sheet')) {
        if (hiddenSheetNames.contains(sheetEl.getAttribute('name'))) {
          sheetEl.setAttribute('state', 'hidden');
        }
      }
    }

    if (definedNames.isNotEmpty) {
      final definedNamesEl = wbXml.findAllElements('definedNames').firstOrNull ??
          () {
            final el = XmlElement(XmlName('definedNames'));
            final sheetsEl = wbXml.findAllElements('sheets').first;
            sheetsEl.parent!.children.insert(sheetsEl.parent!.children.indexOf(sheetsEl) + 1, el);
            return el;
          }();
      for (final entry in definedNames.entries) {
        definedNamesEl.children.add(
          XmlElement(XmlName('definedName'), [XmlAttribute(XmlName('name'), entry.key)], [XmlText(entry.value)]),
        );
      }
    }

    final newArchive = Archive();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == 'xl/workbook.xml') {
        final bytes = utf8.encode(wbXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        final content = file.content as List<int>;
        newArchive.addFile(ArchiveFile(file.name, content.length, content));
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
  }

  /// يحوّل فهرس عمود صفر-فهرسة إلى حرف/أحرف عمود Excel (0 -> A, 25 -> Z, 26 -> AA)
  static String _columnLetter(int index) {
    var n = index;
    var result = '';
    do {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    } while (n >= 0);
    return result;
  }

  /// خوارزمية Excel القياسية القديمة لتجزئة كلمة مرور حماية الشيت
  static String _hashPassword(String password) {
    var hash = 0;
    for (var i = password.length - 1; i >= 0; i--) {
      hash ^= password.codeUnitAt(i);
      final highBit = (hash & 0x4000) == 0x4000 ? 1 : 0;
      hash = (hash << 1) & 0x7FFF;
      hash |= highBit;
    }
    hash ^= password.length;
    hash ^= 0xCE4B;
    return hash.toRadixString(16).toUpperCase();
  }
}
