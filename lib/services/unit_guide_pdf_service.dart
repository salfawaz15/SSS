import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_brand_kit.dart';

/// يبني نسختي "الدليل الإرشادي" بصيغة PDF:
///  - [buildOfficialStudentGuide]: نسخة "نظامية" موجّهة للطلبة، خالية تمامًا
///    من أي ذكر لبوابتنا الداخلية - مُعدّة لتُنشر على صفحة الوحدة الرسمية في
///    موقع الجامعة. صالحة لكل الفصول والسنوات الدراسية (بلا ذكر عام دراسي).
///  - [buildInternalOperationsGuide]: نسخة تشغيلية داخلية لفريق الوحدة تشرح
///    استخدام بوابتنا خطوة بخطوة - لا تُنشر خارج البوابة نفسها.
/// كلاهما بمحتوى متدفّق عبر pw.MultiPage (بدل صفحة منفصلة لكل قسم) لتفادي
/// الفراغات الكبيرة التي تظهر عندما لا يملأ محتوى قسم ما صفحة كاملة.
class UnitGuidePdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _greenDark = PdfColor.fromHex('0D3324');
  static final _gold = PdfColor.fromHex('C9A227');
  static final _lightGray = PdfColor.fromHex('F0F3F1');
  static final _grayText = PdfColor.fromHex('555555');

  /// ملاحظة ختامية مشتركة لنماذج الوحدة الورقية (توثيق الحالة والدعم النفسي)
  /// - بلا أي إشارة لأي موقع أو بوابة إلكترونية عمدًا.
  static const _custodyNote =
      'ملاحظة: تُحفظ النسخة الأصلية بعد اعتمادها لدى المرشد الأكاديمي أو '
      'منسّق القسم لمتابعة الحالة.';

  // مخزَّن مؤقتًا بعد أول تحميل - كان يُعاد تنزيله من الإنترنت في كل استدعاء.
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

  /// الشعار الرسمي المعتمد (نسخة الخلفية الفاتحة - يُعرض داخل بطاقة بيضاء
  /// على غلاف كل تقرير/دليل بصرف النظر عن لون خلفية الصفحة نفسها).
  static Future<pw.MemoryImage> _logo() async {
    final bytes = await rootBundle.load('assets/images/unit_logo_final.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  // ============================== النسخة الرسمية (الطلبة) ==============================

  static Future<Uint8List> buildOfficialStudentGuide() async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(_coverPage(
      logo: logo,
      title: 'الدليل الإرشادي لطلاب وطالبات كلية إدارة الأعمال',
      subtitle: 'نموذج الحذف والإضافة الإلكتروني',
      footer: 'إعداد: سليمان الفواز\nنائب رئيس وحدة الإرشاد الأكاديمي والخريجين',
    ));

    final sections = <pw.Widget>[
      _sectionHeading('المقدمة'),
      pw.SizedBox(height: 14),
      _paragraph(
        'يشرح هذا الدليل آلية تقديم طلب الحذف والإضافة عبر النموذج الإلكتروني '
        'المعتمد من وحدة الإرشاد الأكاديمي والخريجين، بديلاً عن التوجه الشخصي '
        'وتعبئة النماذج الورقية. اقرأ الخطوات التالية بعناية قبل تقديم طلبك '
        'لضمان إنجازه بأقل جهد ودون أي تأخير.',
      ),
      pw.SizedBox(height: 14),
      _infoBox(
        title: 'لماذا التحول الإلكتروني؟',
        color: _lightGray,
        children: [
          _bullet('القضاء على التكدس والحضور الشخصي خلال فترة الحذف والإضافة.'),
          _bullet('تتبّع لحظي لحالة طلبك بدل الانتظار دون معرفة نتيجة الإجراء.'),
          _bullet('حقول إلزامية تمنع أي طلب ناقص البيانات من الوصول للمعالجة.'),
          _bullet('أولوية معالجة فورية لطلبات الخريجين المتوقعين وذوي الإعاقة.'),
        ],
      ),
      pw.SizedBox(height: 22),

      _sectionHeading('تنبيه مهم قبل البدء'),
      pw.SizedBox(height: 14),
      _infoBox(
        title: 'يرجى الانتباه',
        color: PdfColor.fromHex('FDECEC'),
        children: [
          _bullet('في بداية النموذج إقرار وتعهد إلزامي بصحة بياناتك؛ عدم الموافقة عليه يوقف تقديم الطلب نهائيًا.'),
          _bullet('يُسمح لك بتقديم النموذج مرة واحدة فقط، لذا راجع وتأكد من جميع طلباتك (الإضافة/الحذف/التعديل) بعناية قبل الضغط على الإرسال النهائي.'),
        ],
      ),
      pw.SizedBox(height: 22),

      _sectionHeading('خطوات تقديم الطلب'),
      pw.SizedBox(height: 14),
      _stepRow('1', 'تسجيل الدخول', 'افتح النموذج وسجّل الدخول إلزاميًا بالبريد الجامعي الرسمي فقط لتوثيق هويتك.'),
      _stepRow('2', 'الإقرار والتعهد', 'يجب الموافقة على الإقرار الإلزامي للمتابعة؛ عدم الموافقة يوقف تقديم الطلب نهائيًا.'),
      _stepRow('3', 'البيانات الأساسية', 'رقم الجوال، حالة التخرج المتوقعة، من ذوي الإعاقة، الشطر والقسم العلمي، والمرشد الأكاديمي.'),
      _stepRow('4', 'نوع الإجراء', 'اختيار إضافة/حذف/تعديل شعبة، مع رقم الشعبة الحالية إلزاميًا للجميع (راجع "دليل الإجراءات" أدناه).'),
      _stepRow('5', 'المقرر وسبب الطلب', 'تحديد المقرر المرتبط بالإجراء وسبب الطلب من قائمة محددة.'),
      _stepRow('6', 'أكثر من إجراء في نفس النموذج', 'يمكنك إدراج أكثر من إجراء (إضافة وحذف وتعديل) ضمن نفس النموذج قبل الإرسال النهائي.'),
      _stepRow('7', 'الإرسال النهائي', 'الإرسال لا يُعدّ موافقة على التنفيذ؛ تُدرس طلباتك وفق اللوائح والضوابط الأكاديمية.'),
      pw.SizedBox(height: 22),

      _sectionHeading('دليل الإجراءات'),
      pw.SizedBox(height: 14),
      _paragraph('تعرّف على معنى كل إجراء لتختار المناسب لحالتك:'),
      pw.SizedBox(height: 10),
      _procedureCard('إضافة شعبة', 'تسجيل شعبة جديدة لمقرر لم يكن مسجّلاً في جدولك. يُطلب منك تحديد رقم الشعبة المطلوبة بدقة بعد التأكد من توفّرها وعدم تعارضها مع بقية جدولك.'),
      _procedureCard('حذف شعبة', 'إلغاء تسجيلك في شعبة موجودة حاليًا ضمن جدولك. يُطلب رقم الشعبة الحالية المراد حذفها.'),
      _procedureCard('تعديل', 'الانتقال من شعبة إلى أخرى لنفس المقرر (يجمع بين حذف الشعبة الحالية وإضافة الشعبة الجديدة في خطوة واحدة).'),
      pw.SizedBox(height: 22),

      _sectionHeading('تنبيهات إضافية'),
      pw.SizedBox(height: 14),
      _twoByTwoBoxes([
        _tipBox('الدخول بالبريد الجامعي', 'التوثيق الذكي يعتمد طلبك باسمك رسميًا، ويحمي سجلّك الأكاديمي.'),
        _tipBox('الحقول الإلزامية', 'لا يقبل النظام طلبًا ناقص البيانات — تأكد من اكتمال جميع الحقول قبل الإرسال.'),
        _tipBox('أكثر من إجراء في نموذج واحد', 'أدرج جميع احتياجاتك من إضافة وحذف وتعديل قبل الإرسال النهائي.'),
        _tipBox('الإرسال ليس موافقة على التنفيذ', 'تُدرس الطلبات وفق اللوائح الأكاديمية، وتصلك النتيجة عبر متابعتك بنفسك.'),
      ]),
      pw.SizedBox(height: 22),

      _sectionHeading('متابعة نتيجة طلبك'),
      pw.SizedBox(height: 14),
      _infoBox(
        title: 'من خلال المنظومة الجامعية',
        color: _lightGray,
        children: [
          _bullet('يمكنك متابعة حالة طلبك وما إذا تم تنفيذه من خلال المنظومة الجامعية.'),
        ],
      ),
      pw.SizedBox(height: 14),
      _stepRow('1', 'الدخول للمنظومة الجامعية', 'برقمك الجامعي وكلمة السر الخاصة بك (نفس بيانات النظام الأكاديمي).'),
      _stepRow('2', 'تبويب "أكاديمي"', 'من القائمة الرئيسية للمنظومة، اختر تبويب "أكاديمي".'),
      _stepRow('3', 'الجدول الدراسي / السجل الأكاديمي', 'تحقق من جدولك الدراسي الحالي للتأكد من تنفيذ الإضافة/الحذف/التعديل المطلوب.'),
      _stepRow('4', 'عند وجود استفسار', 'تواصل مع مرشدك الأكاديمي مباشرة عبر تبويب "التواصل مع المرشد الأكاديمي" داخل المنظومة، أو عبر بريده الجامعي الرسمي.'),
      pw.SizedBox(height: 22),

      _sectionHeading('المرشد الأكاديمي'),
      pw.SizedBox(height: 14),
      _paragraph(
        'المرشد الأكاديمي هو عضو هيئة التدريس المكلّف بإرشاد عدد من الطلاب في كل '
        'ما يتعلق بشؤونهم الأكاديمية منذ قبولهم بالكلية وحتى تخرجهم، بما في ذلك '
        'متابعة طلبات الحذف والإضافة الخاصة بك.',
      ),
      pw.SizedBox(height: 14),
      _infoBox(
        title: 'كيفية التواصل مع مرشدك الأكاديمي',
        color: _lightGray,
        children: [
          _bullet('من المنظومة الجامعية: أكاديمي ← التواصل مع المرشد الأكاديمي ← طلب تواصل جديد.'),
          _bullet('عبر البريد الإلكتروني الجامعي الرسمي الخاص بمرشدك.'),
          _bullet('عبر نظام Blackboard: منتديات المجموعة الخاصة بالإرشاد الأكاديمي باسم المرشد.'),
          _bullet('الساعات المكتبية المخصصة من المرشد لمقابلة الطلبة ومناقشة استفساراتهم.'),
        ],
      ),
      pw.SizedBox(height: 22),

      _sectionHeading('أسئلة شائعة'),
      pw.SizedBox(height: 14),
      _faqItem('هل إرسال النموذج يعني موافقة الكلية على طلبي؟',
          'لا، الإرسال هو تقديم للطلب فقط. تُدرس الطلبات وفق اللوائح والضوابط الأكاديمية، وتُنفَّذ إن كانت مستوفية الشروط.'),
      _faqItem('كم يستغرق تنفيذ طلبي؟',
          'تتم معالجة الطلبات ضمن فترة الحذف والإضافة المعلنة. تابع حالة طلبك بنفسك عبر المنظومة الجامعية.'),
      _faqItem('نسيت إضافة إجراء ضمن نموذجي، ماذا أفعل؟',
          'لا يُسمح بتقديم نموذج ثانٍ. تواصل مباشرة مع وحدة الإرشاد الأكاديمي عبر البريد الرسمي، أو من خلال مرشدك الأكاديمي.'),
      _faqItem('أنا من ذوي الإعاقة أو من الخريجين المتوقعين، هل هناك أولوية؟',
          'نعم، حدّد ذلك بدقة في الحقول المخصصة بالنموذج، ويمنحك هذا أولوية أعلى في سرعة المعالجة.'),
      pw.SizedBox(height: 30),
      _closingSignature('نتمنى لكم التوفيق والنجاح'),
    ];

    doc.addPage(_flowingMultiPage(sections));

    return doc.save();
  }

  // ============================== النسخة الداخلية (فريق الوحدة) ==============================

  static Future<Uint8List> buildInternalOperationsGuide() async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();
    final loginShot = await _screenshot('assets/images/guide/login_coordinator.png');
    final workspaceShot = await _screenshot('assets/images/guide/workspace_overview.png');
    final passwordShot = await _screenshot('assets/images/guide/change_password.png');

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(_coverPage(
      logo: logo,
      title: 'دليل استخدام البوابة لمنسّقي الأقسام',
      subtitle: 'وحدة الإرشاد الأكاديمي والخريجين',
      footer: 'إعداد: سليمان الفواز\nنائب رئيس وحدة الإرشاد الأكاديمي والخريجين',
    ));

    final sections = <pw.Widget>[
      _paragraph(
        'يشرح هذا الدليل خطوات عملك كمنسّق قسم على البوابة، من تسجيل الدخول '
        'وحتى رفع الملفات المعالجة ومتابعة الإنجاز، مع صور توضيحية من الواجهة '
        'الفعلية لكل خطوة.',
      ),
      pw.SizedBox(height: 22),

      _sectionHeading('١. تسجيل الدخول'),
      pw.SizedBox(height: 14),
      _paragraph('اختر تبويب "دخول منسّقي الوحدة"، ثم حدّد الشطر والقسم العلمي التابع لك، وأدخل كلمة المرور الخاصة بك.'),
      pw.SizedBox(height: 10),
      _screenshotImage(loginShot),
      pw.SizedBox(height: 22),

      _sectionHeading('٢. تنزيل ملف قسمك'),
      pw.SizedBox(height: 14),
      _paragraph('بعد الدخول تظهر لك لوحة قسمك مباشرة (كما بالصورة أدناه). اضغط "تنزيل ملف قسمي" للحصول على ملف مضغوط بداخله ملف Excel منفصل ومحمي لكل مرشد أكاديمي، ثم أرسل ملف كل مرشد له بطريقتك الخاصة (واتساب أو بريد شخصي).'),
      pw.SizedBox(height: 10),
      _screenshotImage(workspaceShot),
      pw.SizedBox(height: 22),

      _sectionHeading('٣. رفع الملف المعالج'),
      pw.SizedBox(height: 14),
      _paragraph('بعد استلام الملفات من المرشدين بعد تعبئتها، اضغط "رفع الملف المعالج" واختر ملفًا واحدًا أو أكثر دفعة واحدة. تُحدَّث حالة الطلبات تلقائيًا فور الرفع.'),
      pw.SizedBox(height: 22),

      _sectionHeading('٤. حالات ذوي الإعاقة'),
      pw.SizedBox(height: 14),
      _paragraph('يظهر لك قسم مستقل بعدد حالات ذوي الإعاقة في قسمك. اضغط "تنزيل ملف ذوي الإعاقة" للحصول على ملف واحد بكل هذه الحالات (بلا تجميع حسب المرشد)، وأرسله لأمين القسم لخبرته في اختيار القاعات المناسبة، ثم ارفع عودته بنفس زر "رفع الملف المعالج".'),
      pw.SizedBox(height: 22),

      _sectionHeading('٥. متابعة إنجاز قسمك'),
      pw.SizedBox(height: 14),
      _paragraph('قسم "متابعة إنجاز قسمي" يرتّب مرشدي قسمك حسب نسبة الإنجاز ويعرض لوحة رسم بياني تلقائية، مع خيارات طباعة وتنزيل Excel وPDF لهذا التقرير.'),
      pw.SizedBox(height: 22),

      _sectionHeading('٦. تفريغ حالة القسم (عند الحاجة)'),
      pw.SizedBox(height: 14),
      _paragraph('إذا رفعت ملفًا معالجًا بالخطأ، يمكنك الضغط على "تفريغ حالة القسم" للتراجع عن آخر عملية دمج - بيانات الطلاب الأصلية تبقى كما هي، فقط تُمسح حالة الإنجاز لتتمكن من إعادة الرفع الصحيح.'),
      pw.SizedBox(height: 22),

      _sectionHeading('٧. تغيير كلمة المرور'),
      pw.SizedBox(height: 14),
      _paragraph('اضغط أيقونة القفل 🔒 أعلى الشاشة بجانب زر تسجيل الخروج، أدخل كلمة المرور الحالية ثم الجديدة وتأكيدها، واضغط "حفظ".'),
      pw.SizedBox(height: 10),
      _screenshotImage(passwordShot),

      pw.SizedBox(height: 30),
      _closingSignature('نتمنى لكم تجربة عمل سلسة وموفّقة'),
    ];

    doc.addPage(_flowingMultiPage(sections));

    return doc.save();
  }

  // ==================== نموذج طلب الدعم النفسي والاجتماعي (ورقي) ====================

  /// نموذج ورقي فارغ يطبعه الطالب ويعبئه بخط اليد - بديل النموذج الإلكتروني
  /// المباشر، حتى تبقى بيانات الطلبة الحساسة بعيدة تمامًا عن أي نظام رقمي
  /// للوحدة. يُسلَّم الطالب النموذج المعبَّأ يدويًا للمرشد الأكاديمي أو منسّق
  /// القسم مباشرة (وليس أمين الوحدة حصرًا)، ويُعامَل بسرّية تامة. نفس هوية
  /// وتصميم وآلية اعتماد (بيانات شخصية + الشطر بمربعات اختيار + اعتماد
  /// مزدوج: المرشد/المنسّق ثم إدارة الوحدة) المستخدمة في نموذج توثيق حالة
  /// الطالب [buildHardshipCaseFormPdf]، لتوحيد شكل نماذج الوحدة الورقية.
  /// نموذج ورقي مضغوط في صفحة A4 واحدة فقط (بلا صفحة غلاف منفصلة).
  static Future<Uint8List> buildSupportRequestFormPdf() async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 18, 28, 18),
        footer: (context) => pw.Align(alignment: pw.Alignment.bottomLeft, child: PdfBrandKit.watermark()),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
            // ترويسة مضغوطة (بلا صفحة غلاف كاملة) تناسب الطباعة على ورقة واحدة.
            pw.Row(
              children: [
                pw.Container(
                  width: 90,
                  height: 40,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('نموذج طلب دعم نفسي واجتماعي',
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _greenDark)),
                      pw.SizedBox(height: 2),
                      pw.Text('وحدة الإرشاد الأكاديمي والخريجين — كلية إدارة الأعمال',
                          style: pw.TextStyle(fontSize: 9, color: _grayText)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 1.4, color: _gold),
            pw.SizedBox(height: 10),
            pw.Text(
              'نموذج سرّي يُعامَل بسرّية تامة - يمكن تعبئته يدويًا وتسليمه مباشرة للمرشد الأكاديمي أو منسّق القسم.',
              style: pw.TextStyle(fontSize: 8.5, color: _grayText, lineSpacing: 1.5),
            ),
            pw.SizedBox(height: 12),

            _compactHeading('البيانات الشخصية'),
            pw.SizedBox(height: 8),
            _compactFormLine('الاسم'),
            _compactFormLine('الرقم الجامعي'),
            _compactFormLine('القسم العلمي'),
            _compactFormLine('رقم الجوال (للتواصل معك)'),
            pw.SizedBox(height: 2),
            pw.Text('الشطر', style: pw.TextStyle(fontSize: 9, color: _grayText)),
            pw.SizedBox(height: 6),
            pw.Center(child: _checkboxRow(['شطر الطلاب', 'شطر الطالبات'])),
            pw.SizedBox(height: 12),

            _compactHeading('نوع الاستشارة'),
            pw.SizedBox(height: 6),
            pw.Center(child: _checkboxRow(['نفسي', 'اجتماعي', 'أكاديمي (ضغط دراسي)', 'أخرى'])),
            pw.SizedBox(height: 10),

            _compactHeading('أولوية الطلب'),
            pw.SizedBox(height: 6),
            pw.Center(child: _checkboxRow(['عادية', 'عاجلة'])),
            pw.SizedBox(height: 10),

            _compactHeading('تفاصيل الطلب'),
            pw.SizedBox(height: 6),
            ..._compactBlankLines(6),
            pw.SizedBox(height: 10),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: _compactFormLine('التاريخ')),
                pw.SizedBox(width: 24),
                pw.Expanded(child: _compactFormLine('توقيع الطالب/ة')),
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('FBF6E9'),
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _gold, width: 1.2),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'اعتماد المرشد الأكاديمي / منسّق القسم',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _greenDark),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(flex: 2, child: _compactFormLine('الاسم')),
                      pw.SizedBox(width: 16),
                      pw.Expanded(child: _compactFormLine('التاريخ')),
                    ],
                  ),
                  _compactFormLine('التوقيع'),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: _lightGray,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _green, width: 1.2),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'اعتماد إدارة الوحدة',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _greenDark),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(flex: 2, child: _compactFormLine('الاسم')),
                      pw.SizedBox(width: 16),
                      pw.Expanded(child: _compactFormLine('التاريخ')),
                    ],
                  ),
                  _compactFormLine('التوقيع'),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              _custodyNote,
              style: pw.TextStyle(fontSize: 8, color: _grayText, lineSpacing: 1.4),
            ),
          ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _compactFormLine(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _grayText)),
          pw.SizedBox(height: 3),
          pw.Container(height: 1, color: _lightGray),
        ],
      ),
    );
  }

  static List<pw.Widget> _compactBlankLines(int count) {
    return List.generate(
      count,
      (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 9),
        child: pw.Container(height: 1, color: _lightGray),
      ),
    );
  }

  static pw.Widget _compactHeading(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(colors: [_greenDark, _green]),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  static pw.Widget _checkboxRow(List<String> options) {
    return pw.Wrap(
      spacing: 26,
      runSpacing: 14,
      children: options.map((o) {
        return pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(o, style: const pw.TextStyle(fontSize: 11.5)),
            pw.SizedBox(width: 8),
            pw.Container(width: 16, height: 16, decoration: pw.BoxDecoration(border: pw.Border.all(color: _grayText, width: 1.2))),
          ],
        );
      }).toList(),
    );
  }

  // ==================== نموذج توثيق حالة الطالب (ظروف خاصة) ====================

  /// نموذج ورقي فارغ (A4) يطبعه الطالب أو يحصل على نسخة ورقية من المرشد
  /// الأكاديمي/منسّق القسم ويعبئه بخط اليد - الغرض منه فهم ظرف الطالب
  /// القهري/الأسري/الصحي غير الموثَّق رسميًا ومساعدته أكاديميًا، وليس تقديم
  /// دليل لأي لجنة خارجية (لا ذكر لأي لجنة أو تاريخ اختبار هنا عمدًا). تبقى
  /// النسخة الأصلية الموقَّعة لدى منسّق القسم بعد الاعتماد، ثم يوثّق المنسّق
  /// بياناتها إلكترونيًا في "حالات الظروف الخاصة" على البوابة.
  static Future<Uint8List> buildHardshipCaseFormPdf() async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 18, 28, 18),
        footer: (context) => pw.Align(alignment: pw.Alignment.bottomLeft, child: PdfBrandKit.watermark()),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
            // الشعار في منتصف الصفحة أعلاها، بلا أي إطار أو خلفية خلفه.
            pw.Center(
              child: pw.SizedBox(
                width: 130,
                height: 62,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'نموذج توثيق حالة الطالب',
                style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _greenDark),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'وحدة الإرشاد الأكاديمي والخريجين — كلية إدارة الأعمال',
                style: pw.TextStyle(fontSize: 9.5, color: _grayText),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 1.4, color: _gold),
            pw.SizedBox(height: 10),
            pw.Text(
              'يُعبَّأ هذا النموذج من قبل الطالب/ـة عند وجود ظرف قهري أو أسري أو صحي '
              'يرغب بإطلاع وحدة الإرشاد الأكاديمي عليه، لدراسة حالته ومساعدته في '
              'مسيرته التعليمية.',
              style: pw.TextStyle(fontSize: 8.5, color: _grayText, lineSpacing: 1.5),
            ),
            pw.SizedBox(height: 12),

            _compactHeading('البيانات الشخصية'),
            pw.SizedBox(height: 8),
            _compactFormLine('الاسم الرباعي'),
            pw.Row(
              children: [
                pw.Expanded(flex: 2, child: _compactFormLine('الرقم الجامعي')),
                pw.SizedBox(width: 16),
                pw.Expanded(flex: 2, child: _compactFormLine('التخصص')),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 2, child: _compactFormLine('البريد الجامعي')),
                pw.SizedBox(width: 16),
                pw.Expanded(child: _compactFormLine('رقم الجوال')),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text('الشطر', style: pw.TextStyle(fontSize: 9, color: _grayText)),
            pw.SizedBox(height: 6),
            pw.Center(child: _checkboxRow(['شطر الطلاب', 'شطر الطالبات'])),
            pw.SizedBox(height: 12),

            _compactHeading('شرح الحالة'),
            pw.SizedBox(height: 6),
            pw.Text(
              'يرجى شرح ظرفك بما تراه مناسبًا (لا يشترط إرفاق أي مستند إثبات)',
              style: pw.TextStyle(fontSize: 8.5, color: _grayText),
            ),
            pw.SizedBox(height: 6),
            ..._compactBlankLines(6),
            pw.SizedBox(height: 6),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: _compactFormLine('التاريخ')),
                pw.SizedBox(width: 24),
                pw.Expanded(child: _compactFormLine('توقيع الطالب/ـة')),
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('FBF6E9'),
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _gold, width: 1.2),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'اعتماد المرشد الأكاديمي / منسّق القسم',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _greenDark),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(flex: 2, child: _compactFormLine('الاسم')),
                      pw.SizedBox(width: 16),
                      pw.Expanded(child: _compactFormLine('التاريخ')),
                    ],
                  ),
                  _compactFormLine('التوقيع'),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: _lightGray,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _green, width: 1.2),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'اعتماد إدارة الوحدة',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _greenDark),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(flex: 2, child: _compactFormLine('الاسم')),
                      pw.SizedBox(width: 16),
                      pw.Expanded(child: _compactFormLine('التاريخ')),
                    ],
                  ),
                  _compactFormLine('التوقيع'),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              _custodyNote,
              style: pw.TextStyle(fontSize: 8, color: _grayText, lineSpacing: 1.4),
            ),
          ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ==================== نموذج الحذف والإضافة الورقي ====================

  /// نموذج ورقي بديل لطلب الحذف والإضافة الإلكتروني (Microsoft Forms) - يُعبَّأ
  /// يدويًا من الطالب/ـة فقط عند تعذّر استخدام النموذج الإلكتروني (مشكلة دخول
  /// بالبريد الجامعي، إعاقة تمنع الكتابة على الحاسب، إعاقة بصرية، أو أي سبب
  /// آخر). يستلمه المرشد الأكاديمي ويستخدمه لتعبئة ملف Excel المخصّص لهذه
  /// الحالات يدويًا. يتضمّن حقولاً غير موجودة بالنموذج الورقي القديم (اسم
  /// المرشد الأكاديمي، الشطر، سبب الطلب) لضمان توافقه الكامل مع بيانات نظامنا.
  static Future<Uint8List> buildAddDropManualFormPdf() async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
        build: (context) => pw.Stack(children: [
          pw.Container(
          width: double.infinity,
          height: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _green, width: 1.4)),
          child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 78,
                  height: 34,
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('نموذج الحذف والإضافة الورقي',
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _greenDark)),
                      pw.SizedBox(height: 1),
                      pw.Text('وحدة الإرشاد الأكاديمي والخريجين — كلية إدارة الأعمال',
                          style: pw.TextStyle(fontSize: 8.5, color: _grayText)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Container(height: 1.2, color: _gold),
            pw.SizedBox(height: 8),

            _infoGrid(),
            pw.SizedBox(height: 10),

            _compactHeading('المقررات المطلوب حذفها/إضافتها/تعديلها'),
            pw.SizedBox(height: 6),
            _addDropTable(),
            pw.SizedBox(height: 8),

            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('FBF6E9'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _gold, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'بتقديم هذا النموذج أقرّ بصحة البيانات المدوَّنة أعلاه وأتحمّل المسؤولية الكاملة عن '
                    'دقتها، مع العلم أنّ تعبئته لا تعني الموافقة على الطلب وإنما إحالته لدراسته واتخاذ '
                    'الإجراء اللازم بشأنه، وأنّ وجود أي بيانات غير صحيحة أو غير مكتملة قد يحول دون '
                    'إمكانية معالجة الطلب واستبعاده.',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.black, lineSpacing: 1.4),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'قد يستغرق تنفيذ الطلب عبر هذا النموذج الورقي وقتًا أطول من النموذج الإلكتروني - '
                    'يُفضَّل دائمًا استخدام النموذج الإلكتروني كلما أمكن ذلك.',
                    style: pw.TextStyle(fontSize: 8, color: _grayText, lineSpacing: 1.4),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: _compactFormLine('التاريخ')),
                pw.SizedBox(width: 24),
                pw.Expanded(child: _compactFormLine('توقيع الطالب/ـة')),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              _custodyNote,
              style: pw.TextStyle(fontSize: 7.5, color: _grayText, lineSpacing: 1.3),
            ),
          ],
          ),
        ),
          pw.Positioned(left: 14, bottom: 8, child: PdfBrandKit.watermark()),
        ]),
      ),
    );

    return doc.save();
  }

  /// شبكة بيانات الطالب/ـة الشخصية بجدول محدود الحدود (بدل أسطر متفرّقة بلا
  /// حدود) - أكثر انضباطًا واحترافية، ويوفّر مساحة رأسية لضمان صفحة واحدة.
  static pw.Widget _infoGrid() {
    final label = pw.TextStyle(fontSize: 8, color: PdfColors.black, fontWeight: pw.FontWeight.bold);
    final cellPad = const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8);
    final border = pw.TableBorder.all(color: PdfColor.fromHex('B9C4BF'), width: 0.6);

    pw.Widget field(String text) => pw.Padding(
          padding: cellPad,
          child: pw.Text(text, style: label),
        );

    pw.Widget checks(List<String> options, {double fontSize = 7.5}) => pw.Padding(
          padding: cellPad,
          child: pw.Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options.map((o) {
              return pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(o, style: pw.TextStyle(fontSize: fontSize)),
                  pw.SizedBox(width: 3),
                  pw.Container(
                    width: 8,
                    height: 8,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: _grayText, width: 0.9)),
                  ),
                ],
              );
            }).toList(),
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ملاحظة مهمة: pw.Table لا يعكس ترتيب الأعمدة تلقائيًا حسب اتجاه
        // RTL (بعكس pw.Row) - يرسم الأعمدة بترتيبها الحرفي في القائمة من
        // اليسار لليمين دائمًا. لذا يجب كتابة كل صف هنا بالترتيب المعكوس
        // (العمود الذي يجب أن يظهر أقصى اليمين يُكتب أخيرًا في القائمة).
        pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(2.7),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(2.7),
            3: pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: cellPad, child: pw.SizedBox()),
              field('الرقم الجامعي'),
              pw.Padding(padding: cellPad, child: pw.SizedBox()),
              field('الاسم الرباعي'),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: cellPad, child: pw.SizedBox()),
              field('رقم الجوال'),
              pw.Padding(padding: cellPad, child: pw.SizedBox()),
              field('البريد الجامعي'),
            ]),
            pw.TableRow(children: [
              checks(['طلاب', 'طالبات']),
              field('الشطر'),
              pw.Padding(padding: cellPad, child: pw.SizedBox()),
              field('اسم المرشد الأكاديمي'),
            ]),
            pw.TableRow(children: [
              checks(['نعم', 'لا']),
              field('من ذوي الإعاقة؟'),
              checks(['نعم', 'لا']),
              field('متوقع/ـة تخرجه/ـا؟'),
            ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: border,
          columnWidths: const {0: pw.FlexColumnWidth(6.7), 1: pw.FlexColumnWidth(1.3)},
          children: [
            pw.TableRow(children: [
              checks(
                ['إدارة الأعمال', 'المحاسبة', 'التسويق', 'الاقتصاد والتمويل', 'نظم المعلومات الإدارية'],
                fontSize: 7,
              ),
              field('القسم العلمي'),
            ]),
          ],
        ),
      ],
    );
  }

  /// أسباب الطلب كما تظهر بالضبط في القائمة المنسدلة لنموذج Microsoft Forms
  /// الإلكتروني (سؤال "سبب الطلب") - تُرقَّم هنا (١-٦) ليُشار إليها برقم مختصر
  /// داخل كل صف مقرر بدل تكرار النص الكامل في كل مرة.
  static const _requestReasons = [
    'توصية المرشد الأكاديمي',
    'زيادة عدد الساعات الدراسية',
    'تقليل عدد الساعات الدراسية',
    'الرغبة في التسجيل لدى عضو هيئة تدريس آخر',
    'الرغبة في تقليل عدد أيام الحضور',
    'غير ذلك (يُذكر في خانة "توضيح السبب" أدناه)',
  ];

  static pw.Widget _addDropTable() {
    final headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    // معكوسة عمدًا (بدل من اليمين لليسار كما تُقرأ) لأن pw.Table يرسم
    // الأعمدة بترتيب القائمة الحرفي من اليسار لليمين دائمًا، بلا أي عكس
    // تلقائي حسب اتجاه RTL.
    final headers = ['سبب الطلب (اختر رقمًا)', 'الإجراء المطلوب', 'رقم الشعبة', 'اسم المقرر'];
    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(2.4),
      1: const pw.FlexColumnWidth(1.8),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(2.0),
    };

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('FBF6E9'),
            border: pw.Border.all(color: _gold, width: 0.8),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('سبب الطلب (اختر الرقم المناسب في الجدول أدناه):',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _greenDark)),
              pw.SizedBox(height: 3),
              pw.Wrap(
                spacing: 10,
                runSpacing: 3,
                children: [
                  for (var i = 0; i < _requestReasons.length; i++)
                    pw.Text('${i + 1}) ${_requestReasons[i]}', style: pw.TextStyle(fontSize: 7, color: PdfColors.black)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromHex('B9C4BF'), width: 0.7),
          columnWidths: widths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(gradient: pw.LinearGradient(colors: [_greenDark, _green])),
              children: headers
                  .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Center(child: pw.Text(h, style: headerStyle, textAlign: pw.TextAlign.center)),
                      ))
                  .toList(),
            ),
            for (var i = 0; i < 5; i++)
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: pw.Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      children: List.generate(_requestReasons.length, (i) => i + 1).map((n) {
                        return pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text('$n', style: const pw.TextStyle(fontSize: 8)),
                            pw.SizedBox(width: 2),
                            pw.Container(
                              width: 9,
                              height: 9,
                              decoration: pw.BoxDecoration(border: pw.Border.all(color: _grayText, width: 1)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: pw.Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      children: ['حذف', 'إضافة', 'تعديل'].map((o) {
                        return pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(o, style: const pw.TextStyle(fontSize: 8)),
                            pw.SizedBox(width: 3),
                            pw.Container(
                              width: 9,
                              height: 9,
                              decoration: pw.BoxDecoration(border: pw.Border.all(color: _grayText, width: 1)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  pw.Container(height: 42, padding: const pw.EdgeInsets.all(4)),
                  pw.Container(height: 42, padding: const pw.EdgeInsets.all(4)),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text('توضيح السبب (فقط إن اخترت رقم ٦ "غير ذلك"):',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.black, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        ..._compactBlankLines(5),
      ],
    );
  }

  // ==================== دليل المنظومة الداخلية للمرشد الأكاديمي ====================

  /// دليل توضيحي لاستخدام المرشد الأكاديمي للمنظومة الداخلية الرسمية
  /// بالجامعة (نظام Oracle Forms الأكاديمي) لإجراء عمليات الحذف والإضافة
  /// ونقل الشعب مباشرة - بنفس الهوية البصرية لبقية تقارير وأدلة الوحدة.
  static Future<Uint8List> buildAdvisorInternalSystemGuide() async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(_coverPage(
      logo: logo,
      title: 'دليل استخدام المنظومة الداخلية للمرشد الأكاديمي',
      subtitle: 'الخصائص الإلكترونية التي تساعد المرشد الأكاديمي',
      footer: 'إعداد: سليمان الفواز\nنائب رئيس وحدة الإرشاد الأكاديمي والخريجين',
    ));

    final sections = <pw.Widget>[
      _sectionHeading('نظرة عامة'),
      pw.SizedBox(height: 14),
      _paragraph(
        'يستطيع المرشد الأكاديمي الدخول على المنظومة الداخلية للجامعة من خلال '
        'رقم المنسوب وكلمة السر الخاصة به، لإجراء كافة عمليات الإرشاد '
        'الأكاديمي مباشرة.',
      ),
      pw.SizedBox(height: 14),
      _infoBox(
        title: 'العمليات المتاحة للمرشد عبر المنظومة',
        color: _lightGray,
        children: [
          _bullet('نقل الطالب/ة من شعبة إلى شعبة.'),
          _bullet('عملية إضافة مقرر.'),
          _bullet('عملية حذف مقرر.'),
          _bullet('طباعة السجل الأكاديمي والإرشادي.'),
          _bullet('طباعة جدول الطالب.'),
        ],
      ),
      pw.SizedBox(height: 10),
      _paragraph('يمكن لرئيس القسم وعميد الكلية منح المرشد الصلاحيات التي يحتاجها عبر شاشة مجموعة الصلاحيات على المنظومة الداخلية.'),
      pw.SizedBox(height: 22),

      _sectionHeading('١. الوصول إلى النظام الأكاديمي'),
      pw.SizedBox(height: 14),
      _stepRow('1', 'الموقع الإلكتروني للجامعة', 'ادخل على الموقع الإلكتروني لجامعة الطائف، ثم انقر تبويب "الخدمات الإلكترونية".'),
      _stepRow('2', 'خدمات نظم أكاديمية', 'من القائمة المنسدلة، اختر "النظام الأكاديمي" ضمن خدمات نظم أكاديمية.'),
      _stepRow('3', 'تأكيد التشغيل', 'عند ظهور نافذة تحذير الأمان، اضغط "Run" للمتابعة.'),
      pw.SizedBox(height: 22),

      _sectionHeading('٢. تسجيل الدخول واستعراض بيانات الطالب'),
      pw.SizedBox(height: 14),
      _stepRow('4', 'تسجيل الدخول', 'اكتب رقم المنسوب في خانة اسم المستخدم، وكلمة السر الخاصة بك (تُنشأ وتُعطى من صاحب الصلاحية)، ثم اضغط دخول.'),
      _stepRow('5', 'معلومات الطلاب', 'انقر على "معلومات الطلاب" من الشاشة الرئيسية.'),
      _stepRow('6', 'التسجيل', 'اذهب إلى "التسجيل".'),
      _stepRow('7', 'التسجيل (مرة أخرى)', 'انقر على "التسجيل" مرة أخرى من القائمة التالية.'),
      _stepRow('8', 'الحذف والإضافة', 'اختر أيقونة "الحذف والإضافة".'),
      _stepRow('9', 'الرقم الجامعي', 'اكتب الرقم الجامعي للطالب ثم اضغط Enter؛ تظهر عندها شاشة الحذف والإضافة الخاصة بالطالب.'),
      pw.SizedBox(height: 22),

      _sectionHeading('دليل أيقونات شاشة التسجيل'),
      pw.SizedBox(height: 14),
      _paragraph('بعد كتابة الرقم الجامعي للطالب والضغط على Enter، تظهر شاشة التسجيل بعدة أيقونات وتبويبات، وظيفة كل منها:'),
      pw.SizedBox(height: 10),
      _procedureCard('خطة الطالب', 'استعراض خطة الطالب: المقررات المنجزة، المتبقية، المتطلبات، الإجبارية، والاختيارية.'),
      _procedureCard('بحث عن مقرر', 'البحث عن مقرر باسمه أو رقمه، واستعراض جميع الشعب المتاحة وغير المتاحة له.'),
      _procedureCard('التسجيل الآلي', 'يساعد على تسجيل جدول كامل للطالب من الجداول أو الشعب المتاحة وغير المتعارضة بما يتلاءم مع خطته.'),
      _procedureCard('تبديل الشعبة', 'استعراض جميع الشعب المتاحة وغير المتعارضة للمقرر المراد تبديل شعبته.'),
      _procedureCard('حذف التسجيل بأكمله', 'خاص بالطلبة المنتظمين الذين تُسجَّل جداولهم آليًا؛ يتيح تغيير المجموعة كاملة.'),
      _procedureCard('حذف مقرر محدد', 'يتيح حذف التسجيل بمقرر واحد فقط. يرجى التأكد قبل الحذف من توافر الشعب وإمكانية إعادة التسجيل.'),
      _procedureCard('إضافة مقرر', 'استعراض المقررات المعرّفة في خطة الطالب والمتاحة للإضافة (التي استوفى متطلباتها والمطروحة بالفصل الحالي)؛ بالنقر على المقرر ثم أيقونة الإضافة يتم تسجيله.'),
      _procedureCard('الحد الأدنى والأعلى للعبء', 'يظهر الحد الأدنى للعبء الدراسي والحد الأعلى المسموح به بناءً على معدل الطالب؛ يجب ألا يتجاوز التسجيل الحد الأعلى ولا يقل عن الحد الأدنى.'),
      _procedureCard('الساعات المسجَّلة حاليًا', 'تظهر إجمالي الساعات المسجَّلة حاليًا في جدول الطالب.'),
      _procedureCard('الوضع الأكاديمي', 'يظهر الوضع الأكاديمي للطالب وجميع المعلومات ذات الصلة.'),
      _procedureCard('الخروج', 'للخروج من النافذة والرجوع إلى القائمة الخاصة بالنظام الأكاديمي.'),

      pw.SizedBox(height: 30),
      _closingSignature('نتمنى لكم تجربة عمل سلسة وموفّقة'),
    ];

    doc.addPage(_flowingMultiPage(sections));

    return doc.save();
  }

  static Future<pw.MemoryImage> _screenshot(String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static pw.Widget _screenshotImage(pw.MemoryImage image) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _lightGray, width: 1.5), borderRadius: pw.BorderRadius.circular(10)),
      padding: const pw.EdgeInsets.all(4),
      child: pw.ClipRRect(
        horizontalRadius: 8,
        verticalRadius: 8,
        child: pw.Image(image, fit: pw.BoxFit.contain),
      ),
    );
  }

  // ============================== مكوّنات مشتركة ==============================

  static pw.Page _coverPage({
    required pw.MemoryImage logo,
    required String title,
    required String subtitle,
    required String footer,
  }) {
    final year = DateTime.now().year;
    return pw.Page(
      pageTheme: pw.PageTheme(
        textDirection: pw.TextDirection.rtl,
        // الطريقة الموثّقة الصحيحة لتلوين صفحة كاملة في مكتبة pdf: خلفية
        // منفصلة عبر buildBackground + FullPage، بدل تمديد Container يدويًا
        // بـ double.infinity (وهو ما كان يُنتج الشكل المشوَّه في كل محاولة
        // سابقة).
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _greenDark),
        ),
      ),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            // الشعار الرسمي المعتمد - بلا أي بطاقة أو إطار خلفه، يظهر مباشرة
            // بلونه الذهبي فوق خلفية الغلاف (نسخة شفافة مصمَّمة لهذا الغرض).
            pw.SizedBox(
              width: 240,
              height: 100,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'وحدة الإرشاد الأكاديمي والخريجين',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.white),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'كلية إدارة الأعمال — جامعة الطائف',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.white),
            ),
            pw.SizedBox(height: 36),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 46),
              child: pw.Text(
                title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: pw.BoxDecoration(color: _gold, borderRadius: pw.BorderRadius.circular(20)),
              child: pw.Text(subtitle, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _greenDark)),
            ),
            pw.SizedBox(height: 70),
            pw.Container(height: 1, width: 70, color: PdfColors.white),
            pw.SizedBox(height: 16),
            pw.Text(
              footer,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 11, color: PdfColors.white, lineSpacing: 4),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '$year',
              style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// صفحات المحتوى الفعلي - قسم واحد متدفق (MultiPage) بدل صفحة منفصلة لكل
  /// موضوع، حتى لا تظهر فراغات كبيرة أسفل الأقسام القصيرة. يستخدم التقسيم
  /// الطبيعي لصفحات A4 القياسية (بدل صفحة واحدة طويلة جدًا) حتى لا تتكوّن
  /// مساحات بيضاء ضخمة بعد نهاية المحتوى الفعلي.
  static pw.MultiPage _flowingMultiPage(List<pw.Widget> sections) {
    return pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(32, 26, 32, 26),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _gold, width: 1.4)),
        ),
        child: pw.Text(
          'وحدة الإرشاد الأكاديمي والخريجين — كلية إدارة الأعمال',
          style: pw.TextStyle(fontSize: 9, color: _grayText),
        ),
      ),
      footer: (context) => pw.Align(alignment: pw.Alignment.bottomLeft, child: PdfBrandKit.watermark()),
      build: (context) => sections,
    );
  }

  /// خاتمة موحّدة في نهاية كل تقرير/دليل - عبارة ختامية مع توقيع الوحدة.
  static pw.Widget _closingSignature(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _greenDark,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            message,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _gold),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'مع تحيات وحدة الإرشاد الأكاديمي والخريجين',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 11, color: _gold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionHeading(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(colors: [_greenDark, _green]),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  static pw.Widget _paragraph(String text) {
    return pw.Text(text, style: pw.TextStyle(fontSize: 11.5, color: _grayText, lineSpacing: 3));
  }

  static pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 5, height: 5, margin: const pw.EdgeInsets.only(top: 4, left: 6), decoration: pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle)),
          pw.Expanded(child: pw.Text(text, style: pw.TextStyle(fontSize: 10.5, lineSpacing: 2))),
        ],
      ),
    );
  }

  static pw.Widget _infoBox({required String title, required PdfColor color, required List<pw.Widget> children}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _greenDark)),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _stepRow(String number, String title, String description) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 26,
            height: 26,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle),
            child: pw.Text(number, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _greenDark)),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _greenDark)),
                pw.SizedBox(height: 3),
                pw.Text(description, style: pw.TextStyle(fontSize: 10, color: _grayText, lineSpacing: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _procedureCard(String title, String description) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _lightGray, width: 1.2), borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _greenDark)),
          pw.SizedBox(height: 5),
          pw.Text(description, style: pw.TextStyle(fontSize: 10, color: _grayText, lineSpacing: 2)),
        ],
      ),
    );
  }

  static pw.Widget _tipBox(String title, String description) {
    return pw.Container(
      width: 235,
      padding: const pw.EdgeInsets.all(12),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _lightGray, width: 1.2), borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _greenDark)),
          pw.SizedBox(height: 6),
          pw.Text(description, style: pw.TextStyle(fontSize: 9, color: _grayText, lineSpacing: 2)),
        ],
      ),
    );
  }

  static pw.Widget _twoByTwoBoxes(List<pw.Widget> boxes) {
    return pw.Wrap(spacing: 12, runSpacing: 0, children: boxes);
  }

  static pw.Widget _faqItem(String question, String answer) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('س: $question', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _greenDark)),
          pw.SizedBox(height: 4),
          pw.Text('ج: $answer', style: pw.TextStyle(fontSize: 10, color: _grayText, lineSpacing: 2)),
        ],
      ),
    );
  }
}
