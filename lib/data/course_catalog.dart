/// معلومات ثابتة عن كل مقرر (القسم المالك، نوع الخطة، ملاحظة تشغيلية) لا
/// تُستخرَج من جدول التسكين الفصلي، لأنها لا تتغيّر كل فصل - بل رُوجعت
/// يدويًا مقابل خطتي 38 و47 الدراسيتين. عند تحديث الخطط الدراسية مستقبلاً
/// تُحدَّث هذه القائمة يدويًا فقط.
class CourseCatalogEntry {
  final String code;
  final String department;
  final List<String> plans; // ['خطة 38'] أو ['خطة 47'] أو كلاهما
  final String? note;

  const CourseCatalogEntry({
    required this.code,
    required this.department,
    required this.plans,
    this.note,
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
    '66014201': CourseCatalogEntry(code: '66014201', department: mgmt, plans: both),
    '6601421': CourseCatalogEntry(code: '6601421', department: mgmt, plans: p38),
    '66014102': CourseCatalogEntry(code: '66014102', department: mgmt, plans: p38),
    '66014103': CourseCatalogEntry(code: '66014103', department: mgmt, plans: p38),

    // قسم التسويق
    '602313': CourseCatalogEntry(code: '602313', department: mkt, plans: both),
    '602314': CourseCatalogEntry(code: '602314', department: mkt, plans: both),
    '602315': CourseCatalogEntry(code: '602315', department: mkt, plans: both),
    '602324': CourseCatalogEntry(code: '602324', department: mkt, plans: both),
    '602413': CourseCatalogEntry(code: '602413', department: mkt, plans: both),
    '602420': CourseCatalogEntry(code: '602420', department: mkt, plans: both),
    '602424': CourseCatalogEntry(code: '602424', department: mkt, plans: both),
    '602425': CourseCatalogEntry(code: '602425', department: mkt, plans: both),
    '602426': CourseCatalogEntry(code: '602426', department: mkt, plans: both),
    '602427': CourseCatalogEntry(code: '602427', department: mkt, plans: both),
    '602428': CourseCatalogEntry(code: '602428', department: mkt, plans: both),
    '602429': CourseCatalogEntry(code: '602429', department: mkt, plans: both),
    '66024210': CourseCatalogEntry(code: '66024210', department: mkt, plans: both),
    '6602481': CourseCatalogEntry(code: '6602481', department: mkt, plans: both),

    // قسم نظم المعلومات الإدارية
    '603205': CourseCatalogEntry(code: '603205', department: mis, plans: both, note: 'شعبة نظري - العملي يُسجَّل تلقائيًا'),
    '603322': CourseCatalogEntry(code: '603322', department: mis, plans: both),
    '603413': CourseCatalogEntry(code: '603413', department: mis, plans: both),
    '603415': CourseCatalogEntry(code: '603415', department: mis, plans: both),
    '603416': CourseCatalogEntry(code: '603416', department: mis, plans: both),
    '603417': CourseCatalogEntry(code: '603417', department: mis, plans: both),
    '6603313': CourseCatalogEntry(code: '6603313', department: mis, plans: both),
    '6603314': CourseCatalogEntry(code: '6603314', department: mis, plans: both),
    '66033202': CourseCatalogEntry(code: '66033202', department: mis, plans: p38),
    '66033208': CourseCatalogEntry(code: '66033208', department: mis, plans: p38),
    '66033209': CourseCatalogEntry(code: '66033209', department: mis, plans: both),
    '66034101': CourseCatalogEntry(code: '66034101', department: mis, plans: both),
    '66034103': CourseCatalogEntry(code: '66034103', department: mis, plans: p38),
    '66034104': CourseCatalogEntry(code: '66034104', department: mis, plans: both),
    '66034109': CourseCatalogEntry(code: '66034109', department: mis, plans: p47),

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
    '66044102': CourseCatalogEntry(code: '66044102', department: acc, plans: both),
    '6604412': CourseCatalogEntry(code: '6604412', department: acc, plans: both),
    '6604421': CourseCatalogEntry(code: '6604421', department: acc, plans: both),
    '6604422': CourseCatalogEntry(code: '6604422', department: acc, plans: p38),

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
    '605432': CourseCatalogEntry(code: '605432', department: fin, plans: p38),
    '605441': CourseCatalogEntry(code: '605441', department: fin, plans: both),
    '605451': CourseCatalogEntry(code: '605451', department: fin, plans: both),
    '605462': CourseCatalogEntry(code: '605462', department: fin, plans: both),
    '605463': CourseCatalogEntry(code: '605463', department: fin, plans: both),
    '605469': CourseCatalogEntry(code: '605469', department: fin, plans: both),
    '6605321': CourseCatalogEntry(code: '6605321', department: fin, plans: both),
    '6605411': CourseCatalogEntry(code: '6605411', department: fin, plans: both),
    '605414': CourseCatalogEntry(code: '605414', department: fin, plans: both),
    '66053101': CourseCatalogEntry(code: '66053101', department: fin, plans: both, note: 'متاح أيضًا لقسم الإدارة'),
    '66053102': CourseCatalogEntry(code: '66053102', department: fin, plans: both),
    '66053103': CourseCatalogEntry(code: '66053103', department: fin, plans: both),
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
    '6605424': CourseCatalogEntry(code: '6605424', department: fin, plans: both),
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
    '6601401': CourseCatalogEntry(code: '6601401', department: mgmt, plans: p47, note: 'اختياري'),
    '6602302': CourseCatalogEntry(code: '6602302', department: mkt, plans: p47, note: 'اختياري'),
    '66014101': CourseCatalogEntry(code: '66014101', department: mgmt, plans: p47, note: 'اختياري'),
    '66033105': CourseCatalogEntry(code: '66033105', department: mis, plans: p47, note: 'اختياري'),
  };

  static const List<String> departments = [mgmt, acc, mkt, fin, mis];

  static CourseCatalogEntry? lookup(String code) => _entries[code];

  /// للمقررات المشتركة بين كل الأقسام: القسم الذي "يملكها" فعليًا (تُعرَض
  /// تحته فقط عند اختيار "كل الأقسام" لمنع التكرار).
  static String? crossDeptOwner(String code) => _crossDeptOwner[code];

  static bool isSharedAcrossDepartments(String code) => _crossDeptOwner.containsKey(code);
}
