/// الحد الأعلى للنصاب التدريسي (وحدات/ساعات معتمدة) لكل درجة علمية، حسب
/// لائحة أعضاء هيئة التدريس الرسمية (المادة الرابعة عشرة) - قاعدة تنظيمية
/// ثابتة، لا بيانات أشخاص، فلا تخضع لسياسة "الاعتماد فقط على ملفات مرفوعة".
class TeachingLoadRegulation {
  // المفاتيح مطبَّعة بلا "ال" التعريف وبلا همزة (نفس صيغة عمود "الدرجة
  // العلمية" الفعلية في ملف أعضاء هيئة التدريس المرفوع، مثل "محاضر" و"استاذ
  // مشارك" بلا "ال") - المطابقة تمر عبر [_normalize] فتتحمّل أي صيغة واردة
  // (بـ"ال" أو بدونها، بهمزة أو بدونها).
  static const Map<String, int> _maxHoursByRank = {
    'استاذ': 10,
    'استاذ مشارك': 12,
    'استاذ مساعد': 14,
    'محاضر': 16,
    'معيد': 16,
  };

  static String _normalize(String s) {
    final unified = s.trim().replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه');
    // يُزال "ال" التعريف من بداية كل كلمة على حدة (لا من بداية النص فقط)،
    // لأن "الأستاذ المشارك" تحتاج تصير "استاذ مشارك" لا "استاذ المشارك".
    return unified
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceFirst(RegExp(r'^ال'), ''))
        .join(' ');
  }

  /// الحد الأعلى النظامي للدرجة العلمية المعطاة (بأي صيغة كتابة)، أو null
  /// إن كانت الدرجة غير معروفة (فارغة أو خارج القائمة الخمسة).
  static int? maxHoursFor(String? academicRank) {
    if (academicRank == null || academicRank.trim().isEmpty) return null;
    return _maxHoursByRank[_normalize(academicRank)];
  }

  /// المناصب المعروفة حاليًا التي تُخفَّض نصابها التدريسي إلى 3 ساعات ثابتة
  /// بصرف النظر عن الدرجة العلمية - حسب تعليمات صريحة، وهذه القائمة الوحيدة
  /// المعتمدة حاليًا (لا تخفيض تلقائي بأي نسبة أخرى مهما ذُكرت في المنصب).
  static const List<String> _fixedThreeHourPositions = [
    'عميد',
    'عميدة',
    'وكيل',
    'وكيلة',
    'رئيس قسم',
    'رئيسة قسم',
    'رئيس مركز البحوث والاستشارات',
    'الشراكات الاستراتيجية',
    // القيمة المعيارية الجديدة لعمود "المنصب" (انظر lib/data/position_catalog.dart) -
    // "الحد الأدنى" يعني 3 ساعات ثابتة، بنفس معاملة عميد/وكيل/رئيس قسم.
    'مكلف بالحد الأدنى',
    'مستشار',
  ];
  // ملاحظة: "رئيس وحدة"/"نائب رئيس وحدة" الإرشاد الأكاديمي **معفيان من
  // الإرشاد فقط** (advising_load_rules.dart) لكن لا يستحقان أي تخفيض في
  // النصاب التدريسي - تعليمات صريحة، فالإعفاء الإرشادي والتخفيض التدريسي
  // سياستان منفصلتان لا تلزم إحداهما الأخرى (بخلاف عميد/وكيل/رئيس قسم حيث
  // يتطابقان).

  /// عبارات تعني أن العضو لا يُحتسب في النصاب إطلاقًا (يُستبعد بالكامل).
  static const List<String> _excludedKeywords = [
    'مجاز',
    'مجازة',
    'مبتعث',
    'مبتعثة',
    'معار',
    'معارة',
  ];

  /// تطبيع الهمزة/التاء المربوطة وحذف "ال" التعريف من بداية كل كلمة، قبل
  /// مطابقة نص المنصب - يحمي من نفس أعطال الإملاء المُصلَحة في
  /// lib/data/advising_load_rules.dart (مثال: "معارة" بلا همزة، أو أي منصب
  /// جديد يُكتب بصيغة مغايرة عمّا في القوائم أدناه).
  static String _normalizePosition(String s) => _normalize(s);

  static bool isExcluded(String combinedPositions) =>
      _excludedKeywords.any((k) => _normalizePosition(combinedPositions).contains(_normalizePosition(k)));

  /// مطابقة تامة (بعد التطبيع) لكل حقل منصب على حدة - لا تُطابِق كلمة عامة
  /// قصيرة مثل "مستشار" مجرَّد وجودها كسلسلة فرعية ضمن حقل آخر يصف منصبًا
  /// مختلفًا تمامًا (مثال: عضو منصبه "نائب رئيس وحدة" وحقله الآخر "مستشار
  /// عميد شؤون الطلاب" - لقب شرفي ثانوي، وليس تعيينًا فعليًا بمنصب "مستشار"
  /// الذي يستحق تخفيض 3 ساعات). المطابقة السابقة كانت تبحث عن السلسلة داخل
  /// نص مدمج فتقع في نفس فخ الاحتواء الجزئي الذي أُصلح في
  /// lib/data/faculty_sort_order.dart وlib/services/college_roster_lookup_service.dart.
  static bool _isFixedThreeHour(List<String> positions) => positions
      .where((p) => p.trim().isNotEmpty)
      .any((p) => _fixedThreeHourPositions.contains(_normalizePosition(p).trim()));

  static final RegExp _hoursNotePattern = RegExp(r'(\d{1,2})\s*ساع');
  static final RegExp _percentNotePattern = RegExp(r'(\d{1,3})\s*%');

  /// يفسّر نص "ملاحظات تخفيض النصاب" الحر (مثل "3 ساعات" أو "50%" أو نص
  /// آخر تكتبه العمادة) إلى رقم فعلي - "X ساعات" يُقرأ كرقم ثابت مباشرة،
  /// و"X%" يُقرأ كنسبة من الحد النظامي حسب الدرجة العلمية. نص لا يحوي رقمًا
  /// مفهومًا (تعليق حر بلا رقم) يُتجاهَل رقميًا فيُكمَل بالمنطق العادي.
  static int? _parseNote(String note, int? rankBase) {
    if (note.trim().isEmpty) return null;
    final hoursMatch = _hoursNotePattern.firstMatch(note);
    if (hoursMatch != null) return int.parse(hoursMatch.group(1)!);
    final percentMatch = _percentNotePattern.firstMatch(note);
    if (percentMatch != null && rankBase != null) {
      return (rankBase * int.parse(percentMatch.group(1)!) / 100).round();
    }
    return null;
  }

  /// الحد الأعلى الفعلي للنصاب لعضو معيّن، بالأولوية التالية:
  /// 1) "ملاحظات تخفيض النصاب" اللي تكتبها العمادة صراحةً ("3 ساعات"،
  ///    "50%"...) - المرجع الحاسم الأول، أضمن من أي تخمين نصي من المنصب.
  /// 2) مناصب معروفة (عميد/وكيل/رئيس قسم/رئيس مركز البحوث والاستشارات/
  ///    مستشار الشراكات الاستراتيجية) = 3 ساعات ثابتة، لو لا ملاحظة صريحة.
  /// 3) الحد النظامي حسب الدرجة العلمية وحدها.
  /// يرجع null لو العضو مستبعَد بالكامل (مجاز/مبتعث/معار) ولا توجد ملاحظة
  /// صريحة (ملاحظة صريحة مكتوبة تُحترَم حتى لو كان مجازًا، فقرار العمادة أعلى).
  static int? effectiveMaxHoursFor({
    required String? academicRank,
    required String combinedPositions,
    String quotaReductionNote = '',
    List<String>? positions,
  }) {
    final fromNote = _parseNote(quotaReductionNote, maxHoursFor(academicRank));
    if (fromNote != null) return fromNote;
    if (isExcluded(combinedPositions)) return null;
    // القيمة المعيارية الجديدة "مكلف بتخفيض N%" في عمود "المنصب" نفسه (بدل
    // كتابتها في عمود "ملاحظات تخفيض النصاب" المنفصل) - تُفسَّر بنفس منطق
    // _parseNote أعلاه.
    final fromPosition = _parseNote(combinedPositions, maxHoursFor(academicRank));
    if (fromPosition != null) return fromPosition;
    // مطابقة تامة لكل حقل منصب على حدة إن أُرسِلت القائمة (أدق - انظر
    // [_isFixedThreeHour])، وإلا احتواء جزئي على النص المدمج كمسار احتياطي
    // متوافق خلفيًا مع أي استدعاء لم يُحدَّث بعد.
    if (positions != null) {
      if (_isFixedThreeHour(positions)) return 3;
    } else {
      final normalizedPositions = _normalizePosition(combinedPositions);
      if (_fixedThreeHourPositions.any((p) => normalizedPositions.contains(_normalizePosition(p)))) return 3;
    }
    return maxHoursFor(academicRank);
  }
}
