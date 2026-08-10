/// منطق داخلي بحت لتصنيف عبء الإرشاد الأكاديمي لكل عضو بناءً على نص عمود
/// "المنصب" في ملف "قالب بيانات منسوبي الكلية الرسمي" - هذا التصنيف لا
/// يظهر أبدًا كعمود في الملف الذي تعبئه عمادة الكلية (بناءً على طلب صريح:
/// "هذه التفريعات لا يجب أن تصل إلى الجهة التي تضع القائمة")، بل يُحسب هنا
/// داخل التطبيق فقط عند استيراد الملف.
///
/// الأمثلة المرجعية التي بُنيت عليها هذه القواعد (1448هـ):
/// - سالم آل قظيع: عضو قسم الإدارة، تكليف بعمادة البحث العلمي بتخفيض نصاب
///   50% => إرشاد مخفّض 50%.
/// - خليل الرتيعي: معار إلى الكلية التطبيقية => لا إرشاد.
/// - فؤاد جعماني: تكليف بمدير مركز البحوث والاستشارات => لا إرشاد (تفرغ
///   إداري كامل خارج القسم).
/// - عميد الكلية، الوكلاء، رئيس/نائب رئيس وحدة الإرشاد الأكاديمي، رؤساء
///   الأقسام => لا إرشاد.
/// - منسّقو الأقسام => إرشاد مخفّض 50%. منسّقو الكلية (مستوى أعلى) => لا إرشاد.
/// - أمناء الأقسام => لا إرشاد عام، تُسند لهم فقط حالات إرشادية خاصة
///   (كذوي الإعاقة) - حتى لو جمعوا معه منصبًا آخر مُعفيًا (انظر أدناه).
///
/// عضو قد يحمل أكثر من منصب في نفس الوقت (مثال: هبة عبدالصبور - منسّقة
/// الكلية وأمينة قسم معًا => حالات خاصة فقط، رغم أن منسّقة الكلية وحدها
/// معفاة بالكامل). عمود "المنصب" في الملف يبقى نصًا حرًا تُكتب فيه كل
/// المناصب مفصولة بفاصلة بلا أي تغيير في هيكل الملف - المعالجة الذكية
/// لتعدد المناصب تتم هنا فقط: تُجمَع كل المناصب المطابقة أولاً، ثم يُختار
/// الحكم النهائي حسب أولوية الأكثر تقييدًا: حالات خاصة فقط > إعفاء كامل >
/// تخفيض > كامل (مسؤولية أمين القسم تجاه ذوي الإعاقة لا تسقط بمنصب إداري
/// آخر ولو كان معفيًا)، مع إبقاء كل المناصب المطابقة مذكورة في السبب للشفافية.
enum AdvisingLoad {
  /// عبء إرشاد كامل - الوضع الافتراضي لعضو هيئة التدريس على رأس العمل بلا منصب مؤثر
  full,

  /// عبء إرشاد مخفّض (النسبة في [AdvisingLoadResult.reducedToPercent])
  reduced,

  /// معفى بالكامل من الإرشاد العام
  exempt,

  /// لا يُسند له إرشاد عام - فقط حالات إرشادية خاصة (مثل ذوي الإعاقة)
  specialCasesOnly,

  /// حالته مجمّدة مؤقتًا (موقوف الراتب/مجاز/مبتعث/معار) - لا يُسند له أي
  /// إرشاد ولا يُصنَّف بمعفى/جزئي/كامل، بصرف النظر عن قيمة عمود "نصاب
  /// الإرشاد"، لأنه غير متاح فعليًا حاليًا وليس قرار إعفاء إرشادي دائم.
  frozen,
}

class AdvisingLoadResult {
  final AdvisingLoad load;
  final int? reducedToPercent; // مثال: 50 => إرشاد بنصف العبء المعتاد
  final String reason;

  const AdvisingLoadResult(this.load, this.reason, {this.reducedToPercent});
}

class AdvisingLoadRules {
  /// القيم الصحيحة الوحيدة المعتمدة لعمود "نصاب الإرشاد" - تُستخدم عند رفع
  /// الملف لتنبيه المستخدم بأي قيمة مكتوبة يدويًا خارج هذه القائمة (خطأ
  /// إملائي محتمل) بدل الاعتماد على قائمة منسدلة داخل الإكسل نفسه (جُرِّبت
  /// وتبيّن أنها تكسر قراءة مكتبة `excel` المستخدَمة بالموقع - انظر الذاكرة).
  static const List<String> validAdvisingQuotaValues = [
    'بدون تخفيض نصاب',
    '50%',
    'معفي من الارشاد',
    'حالات خاصة',
  ];
  /// عبارات تعني إعفاءً كاملاً بذاتها بلا حاجة لنسبة تخفيض
  static const List<String> _fullExemptKeywords = [
    'عميد الكلية',
    'عميدة الكلية',
    'وكيل الكلية',
    'وكيلة الكلية',
    'وكيل الجامعة',
    'وكيلة الجامعة',
    'رئيس وحدة الإرشاد',
    'رئيسة وحدة الإرشاد',
    'نائب رئيس وحدة الإرشاد',
    'نائبة رئيس وحدة الإرشاد',
    // صيغ مختصرة بديلة قد تُكتب بها نفس المناصب في ملف الكلية (بذكر "الوحدة"
    // فقط بدل "وحدة الإرشاد" كاملة - لا وحدة أخرى بهذا السياق في الكلية).
    'رئيس الوحدة',
    'رئيسة الوحدة',
    'نائب رئيس الوحدة',
    'نائبة رئيس الوحدة',
    'نائبة رئيسة الوحدة',
    'رئيس قسم',
    'رئيسة قسم',
    'خارج الكلية',
    // صيغ القائمة المعيارية الجديدة لعمود "المنصب" (بلا "ال" التعريف، انظر
    // lib/data/position_catalog.dart) - تُضاف هنا إلى جانب الصيغ القديمة
    // (وليس بدلاً منها) حتى يستمر عمل البيانات المرفوعة سابقًا بالنص الحر
    // القديم دون انقطاع لحين إعادة رفع الملف بالقالب الجديد.
    'عميد',
    'عميدة',
    'وكيل كلية',
    'وكيلة كلية',
    'وكيل كلية للتدريب',
    'وكيلة كلية للتدريب',
    'رئيس وحدة',
    'رئيسة وحدة',
    'نائب رئيس وحدة',
    'نائبة رئيسة وحدة',
    // "مكلف بالحد الأدنى" = نفس فئة عميد/وكيل/رئيس قسم (3 ساعات تدريس ثابتة
    // في lib/data/teaching_load_regulation.dart) - يُعامَل بنفس الإعفاء
    // الكامل من الإرشاد.
    'مكلف بالحد الأدنى',
    'مستشار',
    // منسّق/ة الكلية (مستوى أعلى من منسّق القسم) معفى بالكامل من الإرشاد -
    // بخلاف منسّق القسم الذي يُخفَّض له 50% فقط (انظر _defaultHalfLoadKeywords).
    'منسق الكلية',
    'منسقة الكلية',
  ];

  /// عبارات تعني إرشادًا مخفّضًا 50% بذاتها (بلا حاجة لذكر نسبة صراحة) -
  /// منسّق/ة القسم فقط (منسّق/ة الكلية معفى بالكامل - انظر _fullExemptKeywords)
  static const List<String> _defaultHalfLoadKeywords = [
    'منسق قسم',
    'منسقة قسم',
    'منسق وحدة',
    'منسقة وحدة',
  ];

  /// عبارات تعني عدم إسناد إرشاد عام - فقط حالات خاصة
  static const List<String> _specialCasesOnlyKeywords = ['أمين قسم', 'أمينة قسم'];

  /// عبارات تعني تجميد حالة الإرشاد مؤقتًا (غير متاح فعليًا حاليًا) - أولوية
  /// مطلقة تتغلّب حتى على قيمة عمود "نصاب الإرشاد" الصريحة، لأن موقوفًا عن
  /// العمل أو مبتعثًا لا يُسند له إرشاد بصرف النظر عمّا تكتبه العمادة في ذلك
  /// العمود لحين عودته الفعلية.
  static const List<String> _frozenKeywords = [
    'موقوف الراتب',
    'معار',
    'معارة',
    'مبتعث',
    'مبتعثة',
    'مجاز',
    'مجازة',
  ];

  /// أسماء الأقسام العلمية الخمسة (بلا "قسم") - تُستخدم لتحديد هل منصب
  /// "أمين/ة قسم" الذي يحمله عضو هو لقسمه هو أم لقسم آخر (مثال: هبة
  /// عبدالصبور - قسمها الاقتصاد والتمويل، لكنها أمينة قسم التسويق، قسم
  /// مختلف تمامًا).
  static const List<String> _deptKeywords = ['الادارة', 'المحاسبة', 'التسويق', 'الاقتصاد', 'نظم المعلومات'];

  static String? _mentionedDepartmentKeyword(String normalizedText) {
    for (final k in _deptKeywords) {
      if (normalizedText.contains(_normalizeHamza(k))) return k;
    }
    return null;
  }

  /// يبحث عن نسبة تخفيض مذكورة صراحة في النص، مثل "تخفيض نصاب 50%"
  static final RegExp _percentPattern = RegExp(r'(\d{1,3})\s*%');

  /// توحيد صور الهمزة على الألف (أ/إ/آ -> ا)، التاء المربوطة/الهاء (ة -> ه)،
  /// وحذف "ال" التعريف من بداية كل كلمة - قبل أي مقارنة نصية. ملف منسوبي
  /// الكلية يكتب أحيانًا "امين قسم" بلا همزة، أو "امينه" بهاء بدل التاء
  /// المربوطة، أو "وكيل جامعة" بلا "ال" (قالب الكلية الجديد 1447/1448هـ) -
  /// بينما الكلمات المفتاحية هنا مكتوبة "أمين قسم"/"أمينة"/"وكيل الجامعة"
  /// بالإملاء الرسمي الكامل، فيفشل `String.contains` في المطابقة بصمت
  /// ويُصنَّف العضو خطأً بعبء إرشاد كامل. التطبيع يُطبَّق على النص المدخَل
  /// والكلمات المفتاحية معًا فيبقى الكشف يعمل بصرف النظر عن اختلاف الإملاء.
  static String _normalizeHamza(String s) {
    final unified = s.trim().replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه');
    return unified.split(RegExp(r'\s+')).map((w) => w.replaceFirst(RegExp(r'^ال'), '')).join(' ');
  }

  /// عمود "نصاب الإرشاد" (سابقًا "ملاحظات تخفيض النصاب") الذي باتت العمادة
  /// تكتب فيه تصنيف الإرشاد صراحةً لكل عضو: "معفي من الارشاد"/"حالات خاصة"/
  /// نسبة (رقميًا مثل 0.5 أو نصًا مثل "50%"/"إرشاد جزئي") - هذا **المرجع
  /// الحاسم الأول** إن وُجد، يتغلّب على أي استنتاج من نص المنصب (الذي قد
  /// يُخطئ، مثال: عضو منصبه يحوي كلمة "مستشار" فيُعفى بالكامل خطأً رغم أن
  /// العمادة صرّحت في هذا العمود بأن نصابه 50% فقط). فارغ = لا يوجد تصنيف
  /// صريح، فيُستكمَل بالاستنتاج القديم من نص المنصب أدناه.
  static AdvisingLoadResult? _classifyFromNote(String advisingNote) {
    final note = advisingNote.trim();
    if (note.isEmpty) return null;
    final normalized = _normalizeHamza(note);

    if (normalized.contains(_normalizeHamza('معفي')) || normalized.contains(_normalizeHamza('معفى'))) {
      return AdvisingLoadResult(AdvisingLoad.exempt, 'نصاب الإرشاد من ملف العمادة: "$note"');
    }
    if (normalized.contains(_normalizeHamza('خاصة'))) {
      return AdvisingLoadResult(AdvisingLoad.specialCasesOnly, 'نصاب الإرشاد من ملف العمادة: "$note"');
    }
    if (normalized.contains(_normalizeHamza('بدون تخفيض'))) {
      return AdvisingLoadResult(AdvisingLoad.full, 'نصاب الإرشاد من ملف العمادة: "$note"');
    }

    // نسبة قد تُكتب رقمًا عشريًا مباشرة (خلية إكسل بصيغة نسبة مئوية، مثل
    // 0.5)، أو نصًا "50%"، أو التسمية الجاهزة "إرشاد جزئي" (بلا رقم).
    final asDouble = double.tryParse(note);
    final percentMatch = _percentPattern.firstMatch(note);
    int? percent;
    if (asDouble != null) {
      percent = (asDouble <= 1 ? asDouble * 100 : asDouble).round();
    } else if (percentMatch != null) {
      percent = int.parse(percentMatch.group(1)!);
    } else if (normalized.contains(_normalizeHamza('جزئي'))) {
      percent = 50;
    }
    if (percent != null) {
      return AdvisingLoadResult(AdvisingLoad.reduced, 'نصاب الإرشاد من ملف العمادة: "$note"', reducedToPercent: percent);
    }
    return null;
  }

  static AdvisingLoadResult classify(String? positionText, {String advisingNote = '', String ownDepartment = ''}) {
    final normalizedPositionText = _normalizeHamza((positionText ?? '').trim());
    for (final k in _frozenKeywords) {
      if (normalizedPositionText.contains(_normalizeHamza(k))) {
        return AdvisingLoadResult(AdvisingLoad.frozen, 'حالة الموظف مجمّدة مؤقتًا: "$k"');
      }
    }

    final fromNote = _classifyFromNote(advisingNote);
    if (fromNote != null) return fromNote;

    final rawText = (positionText ?? '').trim();
    if (rawText.isEmpty || rawText == 'لا يوجد') {
      return const AdvisingLoadResult(AdvisingLoad.full, 'لا يوجد منصب مؤثر - عبء إرشاد كامل');
    }
    final text = _normalizeHamza(rawText);
    bool contains(String keyword) => text.contains(_normalizeHamza(keyword));

    // 1) اجمع كل المناصب/الإشارات المطابقة في النص أولاً، بلا توقّف عند أول تطابق
    final matchedExempt = _fullExemptKeywords.where(contains).toList();
    final matchedSpecialCasesOnly = _specialCasesOnlyKeywords.where(contains).toList();
    final matchedHalfLoad = _defaultHalfLoadKeywords.where(contains).toList();

    final hasPercent = _percentPattern.hasMatch(text);
    final explicitPercent = hasPercent ? int.parse(_percentPattern.firstMatch(text)!.group(1)!) : null;
    final isOutsideAssignment = text.contains('تكليف') || text.contains('مدير مركز');

    final matches = <String>[
      ...matchedExempt,
      ...matchedSpecialCasesOnly,
      ...matchedHalfLoad,
      if (isOutsideAssignment && !hasPercent) 'تكليف إداري كامل خارج القسم',
      if (hasPercent) 'تخفيض نصاب $explicitPercent% مذكور صراحة',
    ];

    // 2) اختر الحكم النهائي بأولوية الأكثر تقييدًا: حالات خاصة فقط > إعفاء
    // كامل > تخفيض > كامل - بغض النظر عن ترتيب ظهور المناصب في النص.
    // "حالات خاصة فقط" (أمين/ة قسم) تتغلّب حتى على الإعفاء الكامل، لأن
    // مسؤولية أمين القسم تجاه حالات ذوي الإعاقة لا تسقط بمنصب إداري آخر -
    // **بشرط أن تكون أمانة القسم لقسمه هو نفسه**. أمين/ة قسم لقسم آخر غير
    // قسمه لا تُنشئ عليه أي مسؤولية تجاه طلاب ذلك القسم الآخر، فتُتجاهَل
    // كليًا ويُحكَم بالمنصب الآخر وحده (مثال: هبة عبدالصبور - منسّقة الكلية
    // وأمينة قسم التسويق، لكن قسمها هي الاقتصاد والتمويل => معفاة بالكامل
    // بحكم منسّقة الكلية فقط، لا حالات خاصة).
    final ownDeptKeyword = _mentionedDepartmentKeyword(_normalizeHamza(ownDepartment));
    final aminDeptKeyword = _mentionedDepartmentKeyword(text);
    final aminForOwnDepartment =
        aminDeptKeyword == null || ownDeptKeyword == null || aminDeptKeyword == ownDeptKeyword;

    AdvisingLoad? load;
    int? reducedToPercent;

    if (matchedSpecialCasesOnly.isNotEmpty && aminForOwnDepartment) {
      load = AdvisingLoad.specialCasesOnly;
    } else if (matchedExempt.isNotEmpty || (isOutsideAssignment && !hasPercent)) {
      load = AdvisingLoad.exempt;
    } else if (hasPercent) {
      load = AdvisingLoad.reduced;
      reducedToPercent = explicitPercent;
    } else if (matchedHalfLoad.isNotEmpty) {
      load = AdvisingLoad.reduced;
      reducedToPercent = 50;
    }

    if (load == null) {
      return AdvisingLoadResult(AdvisingLoad.full, 'منصب لا يؤثر على عبء الإرشاد: "$text"');
    }

    final reason = matches.length > 1
        ? 'أكثر من منصب مؤثر معًا (${matches.join('، ')}) - الحكم الأشد تقييدًا هو الفاصل'
        : matches.first;

    return AdvisingLoadResult(load, reason, reducedToPercent: reducedToPercent);
  }
}
