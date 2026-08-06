import '../models/college_roster_member.dart';
import 'teaching_load_regulation.dart';

/// ترتيب موحّد لأي قائمة تعرض أعضاء هيئة التدريس في الموقع، حسب تعليمات
/// صريحة:
/// 1) الشطر: طلاب قبل طالبات.
/// 2) القسم (حسب الترتيب المعتمد: الإدارة، المحاسبة، التسويق، الاقتصاد
///    والتمويل، نظم المعلومات الإدارية) - يُستثنى عند تحديد قسم واحد مسبقًا.
/// 3) مناصب قيادية بترتيب هرمي صريح: وكيل الجامعة، عميد، وكلاء الكلية،
///    رئيس/ة قسم، رئيس/نائب رئيس وحدة، منسّق/ة الكلية، أمين/ة قسم، منسّق/ة
///    القسم، مستشار - ثم المكلَّفون خارجيًا (نسبة تخفيض صريحة أو تكليف بلا
///    نسبة)، ثم المعارون - كلهم يتقدَّمون على من ليس له أي منصب/تكليف.
/// 4) لمن ليس له أي منصب من القائمة أعلاه: أصحاب النصاب المخفَّض (الأقل
///    نصابًا أولاً)، ثم الدرجة العلمية (أستاذ فأعلى).
/// 5) رقم المنسوب تصاعديًا (الأقدم/الأصغر رقمًا أولاً).
class FacultySortOrder {
  static const List<String> _departmentKeywords = [
    'الادارة',
    'المحاسبة',
    'التسويق',
    'الاقتصاد',
    'نظم المعلومات',
  ];

  static const List<String> _rankOrder = [
    'استاذ',
    'استاذ مشارك',
    'استاذ مساعد',
    'محاضر',
    'معيد',
  ];

  // بالترتيب المطلوب بالضبط؛ الأكثر تحديدًا يُفحص أولاً ("وكيل الكلية
  // للتدريب" قبل "وكيل الكلية" العادي، لأن الأولى تحتوي الثانية كنص).
  // المطابقة تمر عبر [_normalizePosition] (تحذف "ال" التعريف وتوحّد الهمزة)
  // فتتحمّل أي صيغة واردة سواء "وكيل الجامعة" (الإملاء الكامل) أو "وكيل
  // جامعة" (قالب الكلية الجديد بلا "ال") بلا حاجة لتكرار كل صيغة هنا.
  // القائمة تغطي كل المناصب المعروفة (انظر lib/data/position_catalog.dart)
  // بترتيب هرمي صريح - عضو بأي منصب من هذه القائمة يتقدَّم دائمًا على من
  // ليس له منصب، وبينهم حسب هذا الترتيب نفسه (بدل أن تُترك بعض المناصب
  // كـ"رئيس وحدة"/"أمين قسم" بلا ترتيب فتقع عشوائيًا بين من له نصاب مخفَّض
  // ومن ليس له، حسب الدرجة العلمية فقط).
  // تعليمات صريحة مؤكَّدة بمثال حقيقي (قسم نظم المعلومات الإدارية): وكيل
  // كلية > أمين قسم > رئيس/نائب رئيس وحدة > منسّق قسم/وحدة > مستشار - أمين
  // القسم يتقدَّم حتى على رئيس/نائب رئيس وحدة الإرشاد، ومنسّق الكلية يبقى
  // قبل الأمناء (تعليمات سابقة).
  static const List<String> _leadershipTiers = [
    'وكيل الجامعة',
    'عميد',
    'وكيل الكلية للتدريب',
    'وكيل الكلية',
    'وكيلة الكلية',
    'رئيس قسم',
    'رئيسة قسم',
    'منسق الكلية',
    'منسقة الكلية',
    'أمين قسم',
    'أمينة قسم',
    'رئيس وحدة',
    'رئيسة وحدة',
    'نائب رئيس وحدة',
    'نائبة رئيسة وحدة',
    'منسق قسم',
    'منسقة قسم',
    'منسق وحدة',
    'منسقة وحدة',
    'مستشار',
  ];

  /// نسبة تخفيض صريحة مذكورة في نص المنصب نفسه (مثال: "مكلف بتخفيض 50%")
  /// أو تكليف خارجي بلا نسبة - يُرتَّب بعد كل المناصب القيادية أعلاه.
  static final RegExp _percentPattern = RegExp(r'\d{1,3}\s*%');

  static String _normalize(String s) =>
      s.trim().replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');

  /// نفس [_normalize] مع حذف "ال" التعريف من بداية كل كلمة - يُستخدم فقط
  /// لمطابقة المناصب القيادية، لأن قالب الكلية الجديد يكتب "وكيل جامعة" بلا
  /// "ال" بينما كلمات هذا الملف مكتوبة بالإملاء الكامل "وكيل الجامعة".
  static String _normalizePosition(String s) =>
      _normalize(s)
          .split(RegExp(r'\s+'))
          .map((w) => w.replaceFirst(RegExp(r'^ال'), ''))
          .join(' ');

  /// اسم القسم بلا كلمة "قسم" في بداية النص - لأغراض العرض فقط.
  static String displayDepartment(String department) =>
      department.trim().replaceFirst(RegExp(r'^قسم\s+'), '');

  static int departmentRank(String department) {
    final n = _normalize(department);
    for (var i = 0; i < _departmentKeywords.length; i++) {
      if (n.contains(_departmentKeywords[i])) return i;
    }
    return _departmentKeywords.length;
  }

  static int academicRankOrder(String academicRank) {
    final words = _normalize(academicRank)
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceFirst(RegExp(r'^ال'), ''))
        .join(' ');
    final index = _rankOrder.indexOf(words);
    return index == -1 ? _rankOrder.length : index;
  }

  static String _combinedPositions(CollegeRosterMember m) =>
      [m.position, m.position2, m.position3].join(' ');

  /// فهرس المستوى القيادي (0 = وكيل الجامعة .. الأعلى)، أو null لو ما فيه
  /// أي منصب من القائمة المحدَّدة صراحةً ولا تكليف - "المكلفون خارجيًا"
  /// (نسبة تخفيض صريحة أو تكليف بلا نسبة) يأتون بعد كل المناصب القيادية
  /// الصريحة، أعلى من عضو عادي بلا أي منصب. المعارون/المجازون/المبتعثون لا
  /// يدخلون هنا إطلاقًا - انظر [absenceTierIndex] (غير متواجدين فعليًا،
  /// يُرتَّبون أسفل الجميع حتى لو حملوا منصبًا قياديًا اسميًا).
  /// يختار أطول كلمة مفتاحية مطابقة (الأكثر تحديدًا) بدل أول مطابقة حسب
  /// ترتيب القائمة - كلمات عامة قصيرة مثل "عميد" قد تظهر كسلسلة فرعية داخل
  /// نص لا علاقة له بالعميد إطلاقًا (مثال: "مستشار عميد شؤون الطلاب" لعضو
  /// نائب رئيس وحدة، تحتوي كلمة "عميد" لكنه ليس عميدًا) - المطابقة بترتيب
  /// القائمة وحدها كانت تُصنّفه خطأً في مرتبة العميد. اختيار الأطول يضمن أن
  /// "نائب رئيس وحدة" (منصبه الفعلي) يتغلّب دائمًا على أي كلمة عامة أقصر
  /// وردت ضمن نص منصب آخر له، بصرف النظر عن ترتيبهما في القائمة.
  static int? leadershipTierIndex(CollegeRosterMember m) {
    final combined = _combinedPositions(m);
    final text = _normalizePosition(combined);
    int? bestIndex;
    var bestLength = -1;
    for (var i = 0; i < _leadershipTiers.length; i++) {
      final keyword = _normalizePosition(_leadershipTiers[i]);
      if (text.contains(keyword) && keyword.length > bestLength) {
        bestIndex = i;
        bestLength = keyword.length;
      }
    }
    if (bestIndex != null) return bestIndex;
    if (text.contains('تكليف') || _percentPattern.hasMatch(combined)) {
      return _leadershipTiers.length;
    }
    return null;
  }

  /// فهرس "غير متواجد فعليًا" (0 = معار .. الأدنى)، أو null لعضو متواجد.
  /// تعليمات صريحة: يظهرون أسفل القائمة بالكامل (حتى أسفل الأعضاء العاديين
  /// بلا أي منصب)، بالترتيب: معار، فمجاز، فمبتعث.
  static int? absenceTierIndex(CollegeRosterMember m) {
    final text = _normalizePosition(_combinedPositions(m));
    if (text.contains('معار')) return 0;
    if (text.contains('مجاز')) return 1;
    if (text.contains('مبتعث')) return 2;
    return null;
  }

  /// الحد الأعلى الفعلي للنصاب (لأغراض ترتيب "أصحاب النصاب المخفَّض" فقط) -
  /// null لو غير محسوب (لا درجة علمية معروفة ولا منصب مؤثر).
  static int? _effectiveMaxHours(CollegeRosterMember m) =>
      m.teachingLoadHours ??
      TeachingLoadRegulation.effectiveMaxHoursFor(
        academicRank: m.academicRank,
        combinedPositions: _combinedPositions(m),
        quotaReductionNote: m.quotaReductionNote,
        positions: [m.position, m.position2, m.position3],
      );

  static int compareMembers(
    CollegeRosterMember a,
    CollegeRosterMember b, {
    bool compareDepartment = true,
  }) {
    // الشطر أولاً: طلاب قبل طالبات - تعليمات صريحة (الترتيب العام: الشطر
    // ثم القسم ثم قاعدة المنصب/الدرجة).
    final s = _shatrRank(a.shatr).compareTo(_shatrRank(b.shatr));
    if (s != 0) return s;

    // غير المتواجدين فعليًا (معار/مجاز/مبتعث) أسفل القائمة بالكامل ضمن نفس
    // الشطر - **قبل** مقارنة القسم، حتى لا يظهر عضو غائب في منتصف قسمه
    // فيبدو وكأنه ضمن الأعضاء المتواجدين، بل يتجمّع كل الغائبين (من أي قسم)
    // في مجموعة واحدة أسفل الشطر نفسه.
    final aAbsence = absenceTierIndex(a);
    final bAbsence = absenceTierIndex(b);
    if (aAbsence != null && bAbsence == null) return 1;
    if (aAbsence == null && bAbsence != null) return -1;
    if (aAbsence != null && bAbsence != null) {
      final t = aAbsence.compareTo(bAbsence);
      if (t != 0) return t;
    } else {
      if (compareDepartment) {
        final d = departmentRank(a.department).compareTo(departmentRank(b.department));
        if (d != 0) return d;
      }

      // من نصابه التدريسي "الحد الأدنى" (3 ساعات ثابتة - قرار العمادة
      // الصريح في عمود "نصاب عضو هيئة التدريس") يتقدَّم دائمًا على من ليس
      // كذلك، منطقيًا: تخفيض النصاب للحد الأدنى يعني أنه في منصب قيادي
      // عليا. بينهم يُفصَل حسب ترتيب المناصب القيادية نفسه أدناه (وكيل
      // الجامعة، عميد، وكلاء، رؤساء أقسام، تكاليف أخرى).
      final aMin = a.teachingLoadHours == 3;
      final bMin = b.teachingLoadHours == 3;
      if (aMin && !bMin) return -1;
      if (!aMin && bMin) return 1;

      // المناصب القيادية المحدَّدة صراحةً - من له منصب من القائمة يتقدَّم على
      // من ليس له، وبينهم حسب ترتيب القائمة نفسها.
      final aTier = leadershipTierIndex(a);
      final bTier = leadershipTierIndex(b);
      if (aTier != null || bTier != null) {
        final sentinel = _leadershipTiers.length + 1;
        final aVal = aTier ?? sentinel;
        final bVal = bTier ?? sentinel;
        final t = aVal.compareTo(bVal);
        if (t != 0) return t;
      } else {
        // لا منصب قيادي لأي منهما - من له نصاب مخفَّض (من غير القياديين)
        // يتقدَّم، والأقل نصابًا أولاً.
        final aMax = _effectiveMaxHours(a);
        final bMax = _effectiveMaxHours(b);
        final aReduced = a.quotaReductionNote.trim().isNotEmpty;
        final bReduced = b.quotaReductionNote.trim().isNotEmpty;
        if (aReduced || bReduced) {
          if (aReduced && !bReduced) return -1;
          if (!aReduced && bReduced) return 1;
          if (aMax != null && bMax != null) {
            final m = aMax.compareTo(bMax);
            if (m != 0) return m;
          }
        }
      }
    }

    final r = academicRankOrder(a.academicRank)
        .compareTo(academicRankOrder(b.academicRank));
    if (r != 0) return r;

    final an = int.tryParse(a.staffNumber);
    final bn = int.tryParse(b.staffNumber);
    if (an != null && bn != null) return an.compareTo(bn);
    if (an != null) return -1;
    if (bn != null) return 1;
    return a.staffNumber.compareTo(b.staffNumber);
  }

  /// ترتيب الشطر (طلاب قبل طالبات) - مُتاح للاستخدام العام لأي فرز آخر
  /// خارج أعضاء هيئة التدريس (مثال: ترتيب الإداريين في شاشة بيانات منسوبي
  /// الكلية).
  static int shatrRank(String shatr) => _shatrRank(shatr);

  static int _shatrRank(String shatr) {
    if (shatr.contains('الطلاب') || shatr == 'طلاب') return 0;
    if (shatr.contains('الطالبات') || shatr == 'طالبات') return 1;
    return 2;
  }
}
