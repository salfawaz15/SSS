import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import 'advisor_name_matching.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

const String _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// يُرمى حين لا يحتوي الملف عمود "الجنس" (فلا يمكن فرز صفوفه تلقائيًا حسب
/// الشطر) ولم يُحدَّد شطر صراحةً عند الاستدعاء - تلتقطه الشاشة لتعرض على
/// المستخدم اختيار الشطر يدويًا ثم تعيد المحاولة به.
class ShatrRequiredException implements Exception {
  const ShatrRequiredException();
}

/// يقرأ تقارير المنظومة الداخلية المتعلقة بالإرشاد (كلها بعد تحويلها من PDF
/// إلى Word بنفس الآلية المعتمدة، وكلها بنفس أسلوب الجدول): "بيانات الطلبة
/// الأكاديمية حسب الكلية والقسم" (القاعدة + المعدل)، "طلاب تابعين لمرشد"،
/// و"طلاب غير تابعين لمرشد" (ربط المرشد). **لا يعتمد على ترتيب أعمدة ثابت**
/// بل يبحث عن صف العناوين ويطابق كل عمود مطلوب بالاسم - بعض الأعمدة تكون
/// غائبة حسب نوع التقرير (مثال: تقارير ربط المرشد لا تحوي عمود "التخصص"
/// لأن قسم الطالب فيها يظهر كعنوان صفحة لا كعمود، فيُستكمَل من تقرير القاعدة
/// عند الدمج، وليس هنا).
class AdvisingReportParserService {
  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

  static String _toWestern(String s) {
    final buffer = StringBuffer();
    for (final ch in s.runes) {
      final idx = _arabicDigits.indexOf(String.fromCharCode(ch));
      buffer.write(idx == -1 ? String.fromCharCode(ch) : idx.toString());
    }
    return buffer.toString();
  }

  static String _cellText(XmlElement tc) {
    final buffer = StringBuffer();
    for (final t in tc.findAllElements('t', namespace: _wNs)) {
      buffer.write(t.innerText);
    }
    return _toWestern(buffer.toString()).trim();
  }

  static String _normalize(String s) => s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه');

  /// يفضّل التطابق التام أولًا قبل الاحتواء الجزئي - وإلا فعمود "الجنسية"
  /// (سعودي/يمني...) يُلتقَط خطأً كعمود "الجنس" لأن "الجنسية" تبدأ بنفس حروف
  /// "الجنس"، وبالمثل قد تلتبس أعمدة أخرى ببعضها.
  static int _findColumn(List<String> normalizedHeaders, List<String> candidates) {
    for (final c in candidates) {
      final nc = _normalize(c);
      for (var i = 0; i < normalizedHeaders.length; i++) {
        if (normalizedHeaders[i] == nc) return i;
      }
    }
    for (final c in candidates) {
      final nc = _normalize(c);
      for (var i = 0; i < normalizedHeaders.length; i++) {
        if (normalizedHeaders[i].contains(nc)) return i;
      }
    }
    return -1;
  }

  static String _cell(List<String> row, int index) => (index < 0 || index >= row.length) ? '' : row[index];

  /// يحاول فصل نص خلية "الاسم+التخصص" المندمجة إلى (الاسم الفعلي، نص
  /// التخصص) - انظر التعليق عند نقطة الاستدعاء لسبب حدوث هذا الاندماج. يجرّب
  /// أطول لاحقة كلمات ممكنة أولًا (3 ثم 2 ثم 1) حتى لا يُقتطَع جزء من تخصص
  /// متعدد الكلمات ("نظم المعلومات الادارية") كأنه جزء من الاسم. null لو لم
  /// تُطابِق أي لاحقة تخصصًا معروفًا - الصف يبقى بلا إصلاح فيُستبعَد لاحقًا
  /// بفحص القسم المعتاد بدل عرض بيانات فاسدة.
  static (String, String)? _splitMergedNameAndDepartment(String mergedText) {
    final words = mergedText.trim().split(RegExp(r'\s+'));
    for (final wordCount in [3, 2, 1]) {
      if (words.length <= wordCount) continue;
      final suffix = words.sublist(words.length - wordCount).join(' ');
      if (isKnownBachelorDepartment(normalizeDepartmentName(suffix))) {
        return (words.sublist(0, words.length - wordCount).join(' '), suffix);
      }
    }
    return null;
  }

  static List<List<String>> _readTableRows(List<int> docxBytes) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    final xmlStr = utf8.decode(docFile.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);

    final rows = <List<String>>[];
    for (final tr in doc.findAllElements('tr', namespace: _wNs)) {
      final cells = tr.findAllElements('tc', namespace: _wNs).map(_cellText).toList();
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  static const List<String> _maleGenderWords = ['ذكر', 'طالب'];
  static const List<String> _femaleGenderWords = ['انثي', 'انثى', 'طالبه'];

  /// صف "بيانات المرشد" الذي يسبق جدول طلابه في تقارير ربط المرشد (اسم
  /// المرشد، رقمه، ثم خلية تسمية "رقم المرشد" - نفس الترتيب دائمًا في هذه
  /// التقارير المحوَّلة من PDF).
  static bool _isAdvisorHeaderRow(List<String> row) =>
      row.length == 3 && _normalize(row.last).contains(_normalize('رقم المرشد'));

  /// أسماء فروع جامعة الطائف خارج المقر الرئيسي - لها كليات بنفس مسمّيات
  /// كليتنا (مثال: "كلية إدارة الأعمال" موجودة بالخرمة وتربة ورنية أيضًا)
  /// بنفس أسماء الأقسام تمامًا، فيتعذّر تمييز طلابها عن طلابنا بالاسم وحده -
  /// سليمان حدَّد (2026-08-14) أن سطر "الكلية" يظهر أسفل كل كتلة مرشد مباشرة
  /// (تحت "رقم المرشد") ويذكر اسم الفرع صراحةً حين يكون الطالب من فرع، أو
  /// "كلية إدارة الأعمال" فقط حين يكون من المقر الرئيسي (الصحيح المطلوب قراءته،
  /// شاملاً حالات انتداب معروفة مثل طارق حلمي رغم كونه من كلية أخرى بالمقر
  /// الرئيسي - لا يُستبعَد، فقط فروع المحافظات تُستبعَد).
  static const List<String> _branchCampusNames = ['الخرمة', 'تربة', 'رنية'];

  /// سطر "الكلية" القصير الذي يظهر أسفل كل كتلة مرشد (لا صف بيانات طالب عادي
  /// - تلك صفوف عريضة بأعمدة كثيرة) - نتحقق من قصر الصف (≤3 خلايا) قبل
  /// البحث عن كلمة "كلية" حتى لا يلتبس بصف بيانات فيه كلمة "كلية" ضمن نص أطول.
  static bool _isCollegeLabelRow(List<String> row) =>
      row.length <= 3 && row.any((c) => _normalize(c).contains(_normalize('كلية')));

  static const String _ourCollegeName = 'اداره الاعمال';

  /// يستخرج سبب استبعاد كتلة المرشد الحالية من سطر "الكلية" إن وُجد - '' يعني
  /// كليتنا (لا استبعاد)، غير فارغ يعني وجوب استبعاد كل طلاب هذه الكتلة.
  ///
  /// **محاولة سابقة (2026-08-14) استبعدت أي كلية لا تذكر "إدارة الأعمال"
  /// بلا استثناء - سبَّبت رجوعًا حقيقيًا**: طارق حلمى عبدالنبي علي (عضو حقيقي
  /// بملف منسوبي كليتنا، نصاب كامل) اختفت كتلته بالكامل لأن سطر الكلية أسفل
  /// كتلته تاريخيًا لا يذكر "إدارة الأعمال" لسبب إداري معروف مسبقًا (انظر
  /// [[project_tariq_helmy_secondment]]). **إصلاح لاحق (2026-08-15) بدليل
  /// إضافي من سليمان**: مرشدون حقيقيون من كليات أخرى (محمد عبدالله حسين
  /// زميع/قمراء راجح الحميدي السبيعي/إيمان عبدالعزيز أحمد جان طاشكندي -
  /// تحقَّقتُ: كل واحد منهم له عشرات الطلاب موزَّعين على تخصصات كلية تطبيقية
  /// واضحة كـ"الإعلان والاتصال التسويقي"/"السكرتارية التنفيذية"/"تقنية وأمن
  /// الشبكات"، **وبعضها فقط** يحمل نصًا يتطابق حرفيًا مع أحد أقسامنا الخمسة
  /// كـ"قسم المحاسبة" - تخصص بنفس الاسم موجود في الكلية التطبيقية أيضًا) كانوا
  /// يتسرَّبون لتبويب "مرشد خارجي ← طلابنا" رغم استبعاد الاستبعاد الواسع، لأن
  /// دالة [isKnownBachelorDepartment] بالمقارنة النصية وحدها لا تفرّق قسمنا
  /// عن قسم بنفس الاسم بكلية أخرى.
  ///
  /// **الحل المعتمَد الآن**: يُستبعَد سطر الكلية إن لم يذكر "إدارة الأعمال"
  /// (أو فرع محافظة) **إلا إذا كان اسم مرشد هذه الكتلة تحديدًا موجودًا فعليًا
  /// بملف منسوبي الكلية** ([knownAdvisorNameKeys]، يُمرَّر اختياريًا من
  /// الشاشة التي حمَّلت ملف منسوبي الكلية مسبقًا) - يحلّ حالتي طارق حلمى
  /// (معروف بالملف رغم تسمية الكلية الإدارية المختلفة) والمرشدين الحقيقيين
  /// من كليات أخرى (غير معروفين بالملف إطلاقًا) معًا بلا تعارض.
  static String _branchFromCollegeLabelRow(
    List<String> row, {
    String? currentAdvisorName,
    Set<String>? knownAdvisorNameKeys,
  }) {
    final text = row.join(' ');
    for (final branch in _branchCampusNames) {
      if (text.contains(branch)) return branch;
    }
    if (_normalize(text).contains(_normalize(_ourCollegeName))) return '';
    if (currentAdvisorName != null &&
        knownAdvisorNameKeys != null &&
        knownAdvisorNameKeys.contains(normalizeAdvisorNameForMatch(currentAdvisorName))) {
      return '';
    }
    return 'كلية أخرى ($text)';
  }

  /// إن كان الملف فارغًا (لا جدول فيه أصلاً - كملف "مرشدين ليس لهم طلاب" حين
  /// لا توجد حالة واحدة) تُرجَع قائمة فارغة بدل رمي استثناء، لأن هذه حالة
  /// طبيعية متوقَّعة وليست خطأً في الملف.
  ///
  /// [requireDepartment] يُفعَّل فقط لتقرير "بيانات الطلبة الأكاديمية"
  /// (القاعدة) الذي يحوي عمود "التخصص" فعليًا - تقارير ربط المرشد لا تحتاجه
  /// (قسم الطالب فيها عنوان صفحة، ويُستكمَل من القاعدة عند الدمج).
  ///
  /// صف العناوين يُعاد اكتشافه في كل مرة يظهر فيها (تقارير ربط المرشد تكرره
  /// لكل مرشد، وترتيب الأعمدة قد يختلف قليلًا بين كتلة وأخرى بسبب تحويل PDF).
  ///
  /// [shatr] اختياري: إن وُجد عمود "الجنس" في الملف يُستنتَج شطر كل صف منه
  /// تلقائيًا، متجاوزًا [shatr] كليًا. إن لم يوجد العمود، يُحاوَل الاستنتاج من
  /// شطر مرشد كل صف عبر [advisorShatrByName] (خريطة اسم المرشد المطبَّع عبر
  /// [normalizeAdvisorNameForMatch] ← تسمية الشطر، من قائمة مرشدي القسم - لا
  /// يوجد رقم مرشد مشترك بين هذا التقرير وقائمة المرشدين فالمطابقة بالاسم لا
  /// بالرقم) - مفيد لتقارير ربط المرشد التي لا تحوي عمود الجنس ولا حتى عنوان
  /// صفحة يفرّق الشطرين، فيُرفع ملف واحد موحَّد يضم الشطرين معًا ويُفرز
  /// تلقائيًا حسب شطر كل مرشد. إن تعذّرت كل الطرق ولم يُمرَّر [shatr] يُرمى
  /// [ShatrRequiredException] لتطلب الشاشة من المستخدم تحديد الشطر يدويًا.
  ///
  /// [isHealthReport] يُفعَّل فقط لتقرير "الحالة الصحية للطلبة" - عموده
  /// الوحيد المتاح لهذا الغرض اسمه أيضًا "الحالة" حرفيًا (نفس اسم عمود الحالة
  /// الدراسية في تقرير القاعدة)، فلا يمكن تمييز الحالة الصحية الحقيقية
  /// (مثال: "بتر بالقدم") عن الحالة الدراسية العادية ("منتظم") بالاسم وحده -
  /// دون هذا العلم كانت كل الحالات الدراسية العادية تُحتسَب خطأً كحالات صحية.
  static List<AdvisingCaseRecord> parse(
    List<int> docxBytes, {
    Shatr? shatr,
    bool requireDepartment = true,
    Map<String, String>? advisorShatrByName,
    bool isHealthReport = false,
    List<String>? unresolvedShatrRows,
    Map<String, int>? exclusionCounts,
    Set<String>? knownAdvisorNameKeys,
  }) {
    return parseRows(
      _readTableRows(docxBytes),
      shatr: shatr,
      requireDepartment: requireDepartment,
      advisorShatrByName: advisorShatrByName,
      isHealthReport: isHealthReport,
      unresolvedShatrRows: unresolvedShatrRows,
      exclusionCounts: exclusionCounts,
      knownAdvisorNameKeys: knownAdvisorNameKeys,
    );
  }

  /// نفس منطق [parse] لكن على صفوف جاهزة (كل صف قائمة نصوص الأعمدة) بدل
  /// بايتات docx - يتيح تغذيته من مصادر أخرى بنفس بنية الجدول (مثال: قارئ
  /// PDF مباشر في [AdvisingReportPdfParserService] لتقرير "طلاب تابعين
  /// لمرشد") دون تكرار منطق الأعمدة/الفرز/الاستبعاد.
  ///
  /// [unresolvedShatrRows] اختياري: قائمة يمرّرها المستدعي فارغة، تُعبَّأ
  /// بأسماء/مرشدي كل صف تعذّر تحديد شطره (فأُضيف لكلا الشطرين معًا كي لا
  /// يختفي - انظر التعليق عند نقطة الإضافة أدناه لتفصيل الآلية) - للتنبيه
  /// فقط، لا يُستبعَد من [result]. الحالة الشائعة: مرشد الصف غير موجود بملف
  /// منسوبي الكلية،
  /// فلا توجد وسيلة لمعرفة شطره لا من عمود جنس (غير موجود بهذا التقرير) ولا
  /// من خريطة شطر المرشدين.
  ///
  /// [exclusionCounts] اختياري: خريطة يمرّرها المستدعي فارغة، تُعبَّأ بعدد
  /// الصفوف المستبعَدة نهائيًا من [result] لكل سبب (بلا اسم/رقم، دراسات عليا،
  /// قسم غير معروف) - ليعرف المستخدم لماذا عدد السجلات المعتمَد أقل من عدد
  /// صفوف الملف الخام، بدل استبعاد صامت بلا تفسير.
  static List<AdvisingCaseRecord> parseRows(
    List<List<String>> rows, {
    Shatr? shatr,
    bool requireDepartment = true,
    Map<String, String>? advisorShatrByName,
    bool isHealthReport = false,
    List<String>? unresolvedShatrRows,
    Map<String, int>? exclusionCounts,
    Set<String>? knownAdvisorNameKeys,
  }) {
    if (rows.isEmpty) return const [];

    String? resolveShatrLabel(String genderText) {
      final n = _normalize(genderText);
      if (_maleGenderWords.any((w) => n.contains(_normalize(w)))) return Shatr.male.label;
      if (_femaleGenderWords.any((w) => n.contains(_normalize(w)))) return Shatr.female.label;
      return null;
    }

    int nameCol = -1, idCol = -1, deptCol = -1;
    int advisorNameCol = -1, advisorIdCol = -1, advisorDeptCol = -1;
    int gpaCol = -1, conditionCol = -1, genderCol = -1, degreeCol = -1;
    var sawHeader = false;
    var missingRequiredColumns = false;
    var firstHeaderRaw = '';

    String? currentAdvisorId;
    String? currentAdvisorName;

    // '' يعني المقر الرئيسي (لا استبعاد) - يُعاد ضبطه عند كل سطر "الكلية"
    // جديد (يظهر أسفل كل كتلة مرشد)، فيسري على كل طلاب تلك الكتلة تحديدًا.
    var currentBranch = '';

    final result = <AdvisingCaseRecord>[];

    for (final row in rows) {
      if (_isAdvisorHeaderRow(row)) {
        currentAdvisorName = row[0].trim();
        currentAdvisorId = row[1].trim();
        continue;
      }

      if (_isCollegeLabelRow(row)) {
        currentBranch = _branchFromCollegeLabelRow(
          row,
          currentAdvisorName: currentAdvisorName,
          knownAdvisorNameKeys: knownAdvisorNameKeys,
        );
        continue;
      }

      // فحص أوّلي رخيص فقط (تجاهل صفوف لا علاقة لها بالعناوين إطلاقًا) - لا
      // يُعتمَد وحده. أسماء طلاب حقيقية قد تحوي "اسم" كجزء منها (مثال:
      // "اسماعيل") فتُلبِس هذا الفحص الجزئي، فتُعامَل خطأً كصف عناوين جديد
      // يُصفّر فهارس الأعمدة (نتيجة _findColumn تفشل فتُرجِع -1 للجميع)،
      // فتختفي كل الصفوف التالية بصمت (name/id يصيران فارغين). الحسم الفعلي
      // أدناه: لا يُعتمَد الصف كعناوين إلا إذا نجح فعلًا في تحديد عمودي
      // الاسم والرقم معًا - وإلا يُعامَل كصف بيانات عادي.
      if (row.any((c) => _normalize(c).contains(_normalize('اسم')))) {
        final headers = row.map(_normalize).toList();
        final candidateNameCol = _findColumn(headers, ['اسم الطالب', 'اسم الطالبة', 'الاسم']);
        final candidateIdCol = _findColumn(headers, ['رقم الطالب', 'الرقم الجامعي', 'الرقم الاكاديمي']);
        if (candidateNameCol != -1 && candidateIdCol != -1) {
          nameCol = candidateNameCol;
          idCol = candidateIdCol;
          deptCol = _findColumn(headers, ['التخصص', 'القسم العلمي']);
          advisorNameCol = _findColumn(headers, ['اسم المرشد', 'المرشد الاكاديمي']);
          advisorIdCol = _findColumn(headers, ['رقم المرشد']);
          advisorDeptCol = _findColumn(headers, ['قسم المرشد']);
          gpaCol = _findColumn(headers, ['المعدل التراكمي', 'المعدل']);
          conditionCol = _findColumn(headers, ['الحالة الصحية', 'الحالة']);
          genderCol = _findColumn(headers, ['الجنس']);
          degreeCol = _findColumn(headers, ['الدرجة العلمية']);
          if (!sawHeader) {
            firstHeaderRaw = row.join(' | ');
            missingRequiredColumns = requireDepartment && deptCol == -1;
          }
          sawHeader = true;
          continue;
        }
      }

      if (!sawHeader) continue;

      if (currentBranch.isNotEmpty) {
        exclusionCounts?.update('طالب من خارج كليتنا: $currentBranch', (v) => v + 1, ifAbsent: () => 1);
        continue;
      }

      var name = _cell(row, nameCol).trim();
      var id = _cell(row, idCol).trim();
      if (name.isEmpty || id.isEmpty) {
        exclusionCounts?.update('بلا اسم/رقم جامعي', (v) => v + 1, ifAbsent: () => 1);
        continue;
      }

      // انزياح أعمدة PDF: استخراج جداول PDF هنا يُعاد بناؤه هندسيًا من مواضع
      // الكلمات (لا بنية جدول حقيقية - انظر PdfTableRowsExtractor)، فتُقسَّم
      // خلايا الصف حسب فجوة أفقية بين الكلمات. لو كانت الفجوة بين عمودي
      // "الاسم" و"التخصص" لصف معيّن أقل من العتبة المعتمدة (يعتمد على طول
      // الاسم/الخط لذلك الصف تحديدًا)، يندمج العمودان في خلية واحدة فتنزاح كل
      // الخلايا اللاحقة يسارًا خانة واحدة. تحقَّقتُ من البيانات الفعلية
      // المخزَّنة (2026-08-14، حالة "صباء ...") فتبيَّن أن الانزياح الحقيقي
      // هو: خانة "الرقم الجامعي" تصير رقم تسلسل قصير (م، كـ"1")، وخانة
      // "الاسم" تصير الرقم الجامعي الحقيقي (أرقام طويلة)، وخانة "التخصص"
      // تصير [الاسم الكامل][التخصص] مدمَجين - **لا العكس** كما افتُرض بمحاولة
      // إصلاح أولى فشلت (لم تكتشف الحالة إطلاقًا لأنها فحصت الحقل الخطأ).
      // يُكتشَف بعلامتين موثوقتين معًا: رقم جامعي حقيقي دومًا طويل (6+ أرقام)
      // لا قصير كرقم تسلسل، واسم حقيقي لا يكون أبدًا أرقامًا صرفة.
      var deptCellText = deptCol != -1 ? _cell(row, deptCol).trim() : '';
      final idLooksLikeSerial = RegExp(r'^\d{1,3}$').hasMatch(id);
      final nameLooksLikeRealId = RegExp(r'^\d{6,10}$').hasMatch(name);
      if (deptCol != -1 &&
          idLooksLikeSerial &&
          nameLooksLikeRealId &&
          deptCellText.split(RegExp(r'\s+')).length >= 4) {
        final repaired = _splitMergedNameAndDepartment(deptCellText);
        if (repaired != null) {
          id = name; // الرقم الجامعي الحقيقي كان بخانة "الاسم" خطأً.
          name = repaired.$1;
          deptCellText = repaired.$2;
          exclusionCounts?.update(
              'صف أُصلح تلقائيًا (انزياح أعمدة استخراج PDF) - لم يُستبعَد', (v) => v + 1, ifAbsent: () => 1);
        }
      }

      // نص هامش/تذييل الصفحة (مثال: "Page 349 / 2147") قد يُقرَأ أحيانًا كصف
      // بيانات وهمي عند تحويل PDF لكليات أخرى غير مألوفة البنية - الرقم
      // الجامعي الحقيقي أرقام فقط دومًا، فأي قيمة تحوي حروفًا أو "/" ليست
      // رقمًا جامعيًا صحيحًا وتُستبعَد بدل ظهورها كطالب وهمي (لاحظه سليمان
      // 2026-08-14 بتبويب "مرشدنا ← طلاب خارجيون": "349 / 2147"، "Page:").
      if (!RegExp(r'^\d+$').hasMatch(id)) {
        exclusionCounts?.update('رقم جامعي غير صالح (على الأرجح نص هامش صفحة)', (v) => v + 1, ifAbsent: () => 1);
        continue;
      }

      // وحدة الإرشاد الأكاديمي تُعنى بطلبة البكالوريوس فقط - أي درجة أعلى
      // (ماجستير/دكتوراه) تُستبعَد إن وُجد عمود "الدرجة العلمية" في الملف.
      if (degreeCol != -1) {
        final degreeText = _normalize(_cell(row, degreeCol));
        final isGraduate =
            degreeText.contains(_normalize('ماجستير')) || degreeText.contains(_normalize('دكتوراه'));
        if (isGraduate) {
          exclusionCounts?.update('دراسات عليا (ماجستير/دكتوراه)', (v) => v + 1, ifAbsent: () => 1);
          continue;
        }
      }

      // القسم يُوحَّد لنفس صيغة ملف منسوبي الكلية (انظر
      // academic_department_names.dart) وإلا فشلت مقارنته بقسم المرشد/فلتر
      // القسم لمجرد اختلاف نصي شكلي (مثال: "الإدارة" من هذا التقرير مقابل
      // "قسم الادارة" من ملف منسوبي الكلية). برامج الدراسات العليا الخاصة
      // (مثال: "إدارة الأعمال التنفيذي") ليست من الأقسام الخمسة المعروفة
      // فتُستبعَد هنا تلقائيًا حتى لو لم يُفصح عمود "الدرجة العلمية" عنها.
      final normalizedDept = deptCol != -1 ? normalizeDepartmentName(deptCellText) : '';
      if (requireDepartment && !isKnownBachelorDepartment(normalizedDept)) {
        final rawDept = deptCellText;
        exclusionCounts?.update(
          'قسم غير معروف (${rawDept.isEmpty ? "فارغ" : rawDept})',
          (v) => v + 1,
          ifAbsent: () => 1,
        );
        continue;
      }

      // بعض التقارير تكتب المعدل بالفاصلة العشرية العربية "٫" (U+066B) بدل
      // النقطة العادية - double.tryParse لا يتعرف عليها فتفشل قراءة أغلب
      // المعدلات بصمت (تصير null) دون هذا الاستبدال.
      final gpaText = _cell(row, gpaCol).trim().replaceAll('٫', '.');
      final gpa = gpaText.isEmpty ? null : double.tryParse(gpaText);

      // اسم المرشد المرجعي لهذا الصف: من عمود بالجدول نفسه إن وُجد (تقرير
      // "طلاب على غير مرشدهم")، وإلا من آخر صف "بيانات مرشد" منفصل صودف
      // (تقرير "طلاب تابعين لمرشد").
      final rowAdvisorName = advisorNameCol != -1 ? _cell(row, advisorNameCol).trim() : currentAdvisorName;
      String? advisorShatrLabel;
      if (rowAdvisorName != null && rowAdvisorName.isNotEmpty && advisorShatrByName != null) {
        advisorShatrLabel = advisorShatrByName[normalizeAdvisorNameForMatch(rowAdvisorName)];
      }
      final rowShatrLabel = (genderCol != -1 ? resolveShatrLabel(_cell(row, genderCol)) : null) ??
          advisorShatrLabel ??
          shatr?.label;

      AdvisingCaseRecord buildRecord(String shatrLabel) => AdvisingCaseRecord(
            studentId: id,
            studentName: name,
            department: normalizedDept.isNotEmpty ? normalizedDept : deptCellText,
            shatr: shatrLabel,
            advisorNameRaw: rowAdvisorName ?? '',
            advisorId: advisorIdCol != -1 ? _cell(row, advisorIdCol).trim() : (currentAdvisorId ?? ''),
            advisorDepartment: _cell(row, advisorDeptCol).trim(),
            gpa: gpa,
            healthCondition: isHealthReport ? _cell(row, conditionCol).trim() : '',
            enrollmentStatus: isHealthReport ? '' : _cell(row, conditionCol).trim(),
          );

      if (rowShatrLabel == null) {
        // تعذّر تحديد شطر هذا الصف (الحالة الشائعة: مرشده غير موجود بملف
        // منسوبي الكلية فلا تُعرَف صفته منه، ولا عمود جنس بهذا التقرير أصلًا).
        // بدل استبعاده (فيختفي الطالب من كل تحليل رغم أن له مرشدًا فعليًا -
        // ولو غير موثَّق)، يُضاف لكلا الشطرين معًا: الدمج لاحقًا يربط برقم
        // الطالب **داخل شطر واحد فقط** (بيانات الطلبة لنفس الشطر تحديدًا)،
        // فالنسخة بالشطر الخطأ لا تطابق أي طالب هناك وتُتجاهَل تلقائيًا بلا
        // أثر، بينما النسخة الصحيحة تكمل مسارها الطبيعي وتظهر تحت "طلاب على
        // غير مرشدهم" (مرشد موجود لكن غير موثَّق) بدل "بلا مرشد" خطأً.
        unresolvedShatrRows?.add(
          '$name (${rowAdvisorName != null && rowAdvisorName.isNotEmpty ? "مرشد: $rowAdvisorName" : "بلا اسم مرشد"})',
        );
        result.add(buildRecord(Shatr.male.label));
        result.add(buildRecord(Shatr.female.label));
        continue;
      }

      result.add(buildRecord(rowShatrLabel));
    }

    if (!sawHeader) return const [];
    if (missingRequiredColumns) {
      throw Exception(
        'تعذّر التعرّف على الأعمدة المطلوبة في الملف. '
        'العناوين الموجودة فعليًا في صف العناوين: $firstHeaderRaw',
      );
    }
    // لا يوجد عمود جنس، ولا نجح تحديد الشطر عبر أي مرشد لأي صف (خريطة
    // المرشدين قد تكون غير فارغة لكن غير مفيدة هنا - مثال: تقرير "الحالة
    // الصحية" لا يذكر أي مرشد أصلاً) - يُطلَب من المستخدم تحديد الشطر يدويًا.
    if (result.isEmpty && genderCol == -1 && shatr == null) {
      throw const ShatrRequiredException();
    }

    return result;
  }
}
