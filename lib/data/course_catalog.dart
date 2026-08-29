/// معلومات ثابتة عن كل مقرر (القسم المالك، نوع الخطة، ملاحظة تشغيلية) لا
/// تُستخرَج من جدول التسكين الفصلي، لأنها لا تتغيّر كل فصل - بل رُوجعت
/// يدويًا مقابل خطتي 38 و47 الدراسيتين. عند تحديث الخطط الدراسية مستقبلاً
/// تُحدَّث هذه القائمة يدويًا فقط.
class CourseCatalogEntry {
  final String code;
  final String department;
  final List<String> plans; // ['خطة 38'] أو ['خطة 47'] أو كلاهما
  final String? note;
  // إجباري/اختياري ضمن خطة قسمه المالك - مستخرَجة يدويًا من ملفات الخطط
  // الدراسية الرسمية (وليس من ملف التسكين الفصلي، الذي لا يحمل هذا التصنيف
  // إطلاقًا) بطلب سليمان صراحةً (2026-08-27) - راجحة على `note` عند التعارض.
  // مقررات قسم الاقتصاد والتمويل (3 برامج فرعية بترقيم غير متطابق بين
  // الوثائق) استُثنيت عمدًا (تبقى false الافتراضية = إجباري) لعدم توفّر
  // مطابقة موثوقة رمز-برمز حتى الآن.
  final bool elective;

  const CourseCatalogEntry({
    required this.code,
    required this.department,
    required this.plans,
    this.note,
    this.elective = false,
  });
}

class CourseCatalog {
  static const String mgmt = 'قسم الإدارة';
  static const String mkt = 'قسم التسويق';
  static const String mis = 'قسم نظم المعلومات الإدارية';
  static const String acc = 'قسم المحاسبة';
  static const String fin = 'قسم الاقتصاد والتمويل';

  static const List<String> p38 = ['خطة 38'];
  static const List<String> p47 = ['خطة 47'];
  static const List<String> both = ['خطة 38', 'خطة 47'];

  /// القسم "المالك" الحقيقي للمقررات المشتركة بين كل الأقسام، يُستخدَم لمنع
  /// التكرار عند عرض "كل الأقسام معًا".
  static const Map<String, String> _crossDeptOwner = {
    '6601211': mgmt,
    '6603241': mis,
    '6601241': mgmt,
    '6601401': mgmt,
    '6602302': mkt,
    '66014101': mgmt,
    '66033105': mis,
    // متطلبات كلية لكل الأقسام (خطأ اكتُشف 2026-08-29: كانت مُعرَّفة بحقل
    // note بهذا الوصف لكن لم تُدرَج هنا فعليًا، فاختفت من كل الأقسام غير
    // الاقتصاد والتمويل رغم كونها مشتركة - سليمان صراحةً: "قسم الإدارة -
    // طالبات: يوجد مقررات لا توجد مثلا إحصاء الأعمال، رياضيات الأعمال").
    '605201': fin,
    '605202': fin,
    '605204': fin,
    '605206': fin,
    '6605201': fin,
    '6605211': fin,
  };

  static const Map<String, CourseCatalogEntry> _entries = {
    // قسم الإدارة
    '601201': CourseCatalogEntry(code: '601201', department: mgmt, plans: both),
    '601322': CourseCatalogEntry(code: '601322', department: mgmt, plans: both),
    '601332': CourseCatalogEntry(code: '601332', department: mgmt, plans: both),
    '601423': CourseCatalogEntry(code: '601423', department: mgmt, plans: both),
    '601431': CourseCatalogEntry(code: '601431', department: mgmt, plans: both),
    '601432': CourseCatalogEntry(code: '601432', department: mgmt, plans: both),
    '601436': CourseCatalogEntry(code: '601436', department: mgmt, plans: both),
    '601438': CourseCatalogEntry(code: '601438', department: mgmt, plans: both),
    '66013203': CourseCatalogEntry(code: '66013203', department: mgmt, plans: both),
    '6601321': CourseCatalogEntry(code: '6601321', department: mgmt, plans: both),
    '6601322': CourseCatalogEntry(code: '6601322', department: mgmt, plans: p38),
    '66014201': CourseCatalogEntry(code: '66014201', department: mgmt, plans: both, elective: true),
    '6601421': CourseCatalogEntry(code: '6601421', department: mgmt, plans: p38),
    '66014102': CourseCatalogEntry(code: '66014102', department: mgmt, plans: p38, elective: true),
    '66014103': CourseCatalogEntry(code: '66014103', department: mgmt, plans: p38, elective: true),

    // قسم التسويق
    '602313': CourseCatalogEntry(code: '602313', department: mkt, plans: both),
    '602314': CourseCatalogEntry(code: '602314', department: mkt, plans: both),
    '602315': CourseCatalogEntry(code: '602315', department: mkt, plans: both),
    '602324': CourseCatalogEntry(code: '602324', department: mkt, plans: both),
    '602413': CourseCatalogEntry(code: '602413', department: mkt, plans: both),
    '602420': CourseCatalogEntry(code: '602420', department: mkt, plans: both),
    '602424': CourseCatalogEntry(code: '602424', department: mkt, plans: both, elective: true),
    '602425': CourseCatalogEntry(code: '602425', department: mkt, plans: both),
    '602426': CourseCatalogEntry(code: '602426', department: mkt, plans: both),
    '602427': CourseCatalogEntry(code: '602427', department: mkt, plans: both),
    '602428': CourseCatalogEntry(code: '602428', department: mkt, plans: both),
    '602429': CourseCatalogEntry(code: '602429', department: mkt, plans: both, elective: true),
    '66024210': CourseCatalogEntry(code: '66024210', department: mkt, plans: both, elective: true),
    '6602481': CourseCatalogEntry(code: '6602481', department: mkt, plans: both, elective: true),

    // قسم نظم المعلومات الإدارية
    '603205': CourseCatalogEntry(code: '603205', department: mis, plans: both, note: 'شعبة نظري - العملي يُسجَّل تلقائيًا'),
    '603322': CourseCatalogEntry(code: '603322', department: mis, plans: both),
    '603413': CourseCatalogEntry(code: '603413', department: mis, plans: both, elective: true),
    '603415': CourseCatalogEntry(code: '603415', department: mis, plans: both),
    '603416': CourseCatalogEntry(code: '603416', department: mis, plans: both),
    '603417': CourseCatalogEntry(code: '603417', department: mis, plans: both),
    '6603313': CourseCatalogEntry(code: '6603313', department: mis, plans: both),
    '6603314': CourseCatalogEntry(code: '6603314', department: mis, plans: both),
    '66033202': CourseCatalogEntry(code: '66033202', department: mis, plans: p38),
    '66033208': CourseCatalogEntry(code: '66033208', department: mis, plans: p38),
    '66033209': CourseCatalogEntry(code: '66033209', department: mis, plans: both),
    '66034101': CourseCatalogEntry(code: '66034101', department: mis, plans: both, elective: true),
    '66034103': CourseCatalogEntry(code: '66034103', department: mis, plans: p38),
    '66034104': CourseCatalogEntry(code: '66034104', department: mis, plans: both),
    '66034109': CourseCatalogEntry(code: '66034109', department: mis, plans: p47, elective: true),

    // قسم المحاسبة
    '606204': CourseCatalogEntry(code: '606204', department: acc, plans: both),
    '606311': CourseCatalogEntry(code: '606311', department: acc, plans: both),
    '606312': CourseCatalogEntry(code: '606312', department: acc, plans: both),
    '606321': CourseCatalogEntry(code: '606321', department: acc, plans: both),
    '606323': CourseCatalogEntry(code: '606323', department: acc, plans: both),
    '606412': CourseCatalogEntry(code: '606412', department: acc, plans: both),
    '606414': CourseCatalogEntry(code: '606414', department: acc, plans: both),
    '606416': CourseCatalogEntry(code: '606416', department: acc, plans: both),
    '606418': CourseCatalogEntry(code: '606418', department: acc, plans: both),
    '606461': CourseCatalogEntry(code: '606461', department: acc, plans: both),
    '6604321': CourseCatalogEntry(code: '6604321', department: acc, plans: both),
    '66044101': CourseCatalogEntry(code: '66044101', department: acc, plans: p38),
    '66044102': CourseCatalogEntry(code: '66044102', department: acc, plans: both, elective: true),
    '6604412': CourseCatalogEntry(code: '6604412', department: acc, plans: both),
    '6604421': CourseCatalogEntry(code: '6604421', department: acc, plans: both),
    '6604422': CourseCatalogEntry(code: '6604422', department: acc, plans: p38, elective: true),

    // قسم الاقتصاد والتمويل
    '605201': CourseCatalogEntry(code: '605201', department: fin, plans: both, note: 'متطلب كلية لكل الأقسام'),
    '605202': CourseCatalogEntry(code: '605202', department: fin, plans: both, note: 'متطلب كلية لكل الأقسام'),
    '605204': CourseCatalogEntry(code: '605204', department: fin, plans: both, note: 'متطلب كلية لكل الأقسام'),
    '605206': CourseCatalogEntry(code: '605206', department: fin, plans: both, note: 'متطلب كلية لكل الأقسام'),
    '6605201': CourseCatalogEntry(code: '6605201', department: fin, plans: both, note: 'متطلب كلية لكل الأقسام'),
    '6605211': CourseCatalogEntry(code: '6605211', department: fin, plans: both, note: 'متطلب كلية لكل الأقسام'),
    '605314': CourseCatalogEntry(code: '605314', department: fin, plans: both),
    '605315': CourseCatalogEntry(code: '605315', department: fin, plans: both),
    '605331': CourseCatalogEntry(code: '605331', department: fin, plans: both),
    '605361': CourseCatalogEntry(code: '605361', department: fin, plans: both),
    '605421': CourseCatalogEntry(code: '605421', department: fin, plans: both),
    '605432': CourseCatalogEntry(code: '605432', department: fin, plans: p38, elective: true),
    '605441': CourseCatalogEntry(code: '605441', department: fin, plans: both),
    '605451': CourseCatalogEntry(code: '605451', department: fin, plans: both),
    '605462': CourseCatalogEntry(code: '605462', department: fin, plans: both),
    '605463': CourseCatalogEntry(code: '605463', department: fin, plans: both),
    '605469': CourseCatalogEntry(code: '605469', department: fin, plans: both),
    '6605321': CourseCatalogEntry(code: '6605321', department: fin, plans: both),
    '6605411': CourseCatalogEntry(code: '6605411', department: fin, plans: both, elective: true),
    '605414': CourseCatalogEntry(code: '605414', department: fin, plans: both),
    '66053101': CourseCatalogEntry(code: '66053101', department: fin, plans: both, note: 'متاح أيضًا لقسم الإدارة'),
    '66053102': CourseCatalogEntry(code: '66053102', department: fin, plans: both),
    '66053103': CourseCatalogEntry(code: '66053103', department: fin, plans: both, elective: true),
    '6605311': CourseCatalogEntry(code: '6605311', department: fin, plans: both),
    '6605314': CourseCatalogEntry(code: '6605314', department: fin, plans: p38),
    '6605315': CourseCatalogEntry(code: '6605315', department: fin, plans: both),
    '6605316': CourseCatalogEntry(code: '6605316', department: fin, plans: p38),
    '66053201': CourseCatalogEntry(code: '66053201', department: fin, plans: both, note: 'متاح أيضًا لقسم الإدارة'),
    '66053203': CourseCatalogEntry(code: '66053203', department: fin, plans: both),
    '6605322': CourseCatalogEntry(code: '6605322', department: fin, plans: both),
    '6605324': CourseCatalogEntry(code: '6605324', department: fin, plans: p38),
    '66054102': CourseCatalogEntry(code: '66054102', department: fin, plans: p38),
    '66054105': CourseCatalogEntry(code: '66054105', department: fin, plans: both),
    '6605412': CourseCatalogEntry(code: '6605412', department: fin, plans: both, note: 'متاح أيضًا لقسم الإدارة'),
    '6605414': CourseCatalogEntry(code: '6605414', department: fin, plans: p38),
    '6605416': CourseCatalogEntry(code: '6605416', department: fin, plans: p38),
    '66054201': CourseCatalogEntry(code: '66054201', department: fin, plans: p38),
    '6605421': CourseCatalogEntry(code: '6605421', department: fin, plans: p38),
    '6605424': CourseCatalogEntry(code: '6605424', department: fin, plans: both, elective: true),
    '6605425': CourseCatalogEntry(code: '6605425', department: fin, plans: p38),
    '604364': CourseCatalogEntry(code: '604364', department: fin, plans: p38),
    '604458': CourseCatalogEntry(code: '604458', department: fin, plans: both),
    '604464': CourseCatalogEntry(code: '604464', department: fin, plans: p38),
    '604466': CourseCatalogEntry(code: '604466', department: fin, plans: both),
    '604471': CourseCatalogEntry(code: '604471', department: fin, plans: both),

    // مقررات مشتركة بين كل الأقسام (متطلبات كلية / اختياريات عامة)
    '6601211': CourseCatalogEntry(code: '6601211', department: mgmt, plans: p47, note: 'متطلب كلية إجباري لكل الأقسام'),
    '6603241': CourseCatalogEntry(code: '6603241', department: mis, plans: p47, note: 'متطلب كلية إجباري - شعبة نظري (العملي يُسجَّل تلقائيًا)'),
    '6601241': CourseCatalogEntry(code: '6601241', department: mgmt, plans: p38),
    '6601401': CourseCatalogEntry(code: '6601401', department: mgmt, plans: p47, note: 'اختياري', elective: true),
    '6602302': CourseCatalogEntry(code: '6602302', department: mkt, plans: p47, note: 'اختياري', elective: true),
    '66014101': CourseCatalogEntry(code: '66014101', department: mgmt, plans: p47, note: 'اختياري', elective: true),
    '66033105': CourseCatalogEntry(code: '66033105', department: mis, plans: p47, note: 'اختياري', elective: true),
  };

  static const List<String> departments = [mgmt, acc, mkt, fin, mis];

  /// مقررات اختيارية "متاحة أيضًا" لقسم إضافي محدَّد غير قسمها المالك (وليس
  /// لكل الأقسام) - تُستنتَج من ملاحظة "متاح أيضًا لقسم ..." في تعريف المقرر،
  /// وتجعل المقرر قابلاً للنسخ (يظهر) في قائمة ذلك القسم الإضافي أيضًا دون
  /// نقله من قسمه المالك الأصلي.
  static const Map<String, List<String>> _extraDepartments = {
    '66053101': [mgmt],
    '66053201': [mgmt],
    '6605412': [mgmt],
  };

  static CourseCatalogEntry? lookup(String code) => _entries[code];

  /// للمقررات المشتركة بين كل الأقسام: القسم الذي "يملكها" فعليًا (تُعرَض
  /// تحته فقط عند اختيار "كل الأقسام" لمنع التكرار).
  static String? crossDeptOwner(String code) => _crossDeptOwner[code];

  static bool isSharedAcrossDepartments(String code) => _crossDeptOwner.containsKey(code);

  /// هل يظهر هذا المقرر أيضًا (قابل للنسخ) ضمن قسم إضافي محدَّد بعينه،
  /// إلى جانب قسمه المالك الأصلي؟
  static bool isVisibleInDepartment(String code, String department) =>
      (_extraDepartments[code] ?? const []).contains(department);

  /// رمز المقرر من نص خيار جاهز بصيغة "رمز - اسم (نوع)" كما في
  /// [outsideCollegeCourses].
  static String outsideCourseCode(String option) => option.split(' - ').first.trim();

  /// إجباري/اختياري لمقرر من خارج الكلية - مُستخرَج من لاحقة "(إجباري)"/
  /// "(اختياري)" الصريحة بنص [outsideCollegeCourses] نفسه (بخلاف مقررات
  /// الكلية التي تحتاج حقل [CourseCatalogEntry.elective] لأنها لا تحمل هذا
  /// الوسم بنص واحد جاهز). يُستخدَم لعرض نفس التصنيف على شعب فعلية
  /// (CourseSectionRecord) لا الخيارات النصية فقط.
  static bool isOutsideCourseElective(String code) {
    final match = outsideCollegeCourses.where((o) => outsideCourseCode(o) == code);
    if (match.isEmpty) return false;
    return match.first.contains('اختياري');
  }

  /// يقاطع [outsideCollegeCourses] الثابتة مع رموز مقررات فعلية (مستخرجة من
  /// ملف حويّة الجامعة الشامل لهذا الفصل)، فيستبعد ما لم يُطرَح فعليًا هذا
  /// الفصل من القائمة الثابتة، ويتجاهل أي رمز في الملف لا يخصّ الكلية أصلاً.
  static List<String> filterOutsideCoursesByOfferedCodes(Set<String> offeredCodes) =>
      outsideCollegeCourses.where((o) => offeredCodes.contains(outsideCourseCode(o))).toList();

  /// متطلبات ومقررات "من خارج الكلية" (إجباري/اختياري) - موجودة ضمن خطة
  /// الكلية نفسها تحت هذا التصنيف، لكنها تُدرَّس فعليًا عبر كليات أخرى (لا
  /// تظهر في ملف "الحويّة" الخاص بالكلية لأن التدريس ليس من أقسامها)، لذا لا
  /// مصدر تلقائي حي لها كبقية المقررات ولا بد من تحديثها هنا يدويًا عند
  /// تغيّر الخطة. متطابقة حاليًا بين شطري الطلاب والطالبات.
  static const List<String> outsideCollegeCourses = [
    '104999 - مهارات اللغة الإنجليزية (إجباري)',
    '20041302 - الثقافة الإسلامية (العقيدة والشريعة) (إجباري)',
    '20041303 - الثقافة الإسلامية (السنة في الإسلام) (إجباري)',
    '2004313 - ثقافة إسلامية (النظام الاجتماعي في الإسلام) (إجباري)',
    '2004414 - ثقافة إسلامية (حقوق الإنسان) (إجباري)',
    '1031101 - مهارات اللغة العربية (إجباري)',
    '3171101 - المهارات الجامعية (إجباري)',
    '20032310 - البيئة القانونية للأعمال (إجباري)',
    '105125 - تاريخ المملكة العربية السعودية (إجباري)',
    '2001114 - ملامح السيرة النبوية (إجباري)',
    '20031301 - مبادئ القانون (إجباري)',
    '2003215 - حقوق الإنسان (إجباري)',
    '3051123 - العمل التطوعي والمسؤولية المجتمعية (إجباري)',
    '2021110 - المهارات الإحصائية (إجباري)',
    '3051111 - مهارات الكتابة الأكاديمية (إجباري)',
    '6605320 - الوعي المالي والادخار (اختياري)',
    '1081113 - تعزيز الصحة النفسية (اختياري)',
    '2011116 - الثقافة البيئية (اختياري)',
    '2061114 - الثقافة الغذائية (اختياري)',
    '3191117 - اللياقة والثقافة الرياضية (اختياري)',
    '3731115 - الثقافة الصحية (اختياري)',
    '1061120 - صناعة المحتوى الرقمي (اختياري)',
    '44041122 - التصميم والجرافيك (اختياري)',
    '5011119 - تطبيقات الذكاء الاصطناعي (اختياري)',
    '501121 - مقدمة في البرمجة (اختياري)',
    '5011121 - البرمجة لغير المختصين (اختياري)',
    '5021118 - مهارات الحاسب وتقنية المعلومات (اختياري)',
    '2031113 - الأمن والسلامة المهنية (اختياري)',
  ];
}
