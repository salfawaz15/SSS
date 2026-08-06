import '../models/college_roster_member.dart';
import '../utils/name_display.dart';

/// يستخرج مناصب رسمية (عميد الكلية، رئيس قسم، منسّق قسم) من عمود "المنصب"
/// (وحتى 3 مناصب لكل عضو) في ملف أعضاء هيئة التدريس المعتمد المرفوع عبر
/// الموقع - هذا المصدر الوحيد المسموح لهذي الأسماء من الآن (بدل القوائم
/// الثابتة القديمة official_coordinators.dart وcollege_leadership.dart،
/// اللتين مصدرهما ملفات من مجلد المرفقات وليستا مرفوعتين عبر الموقع).
class CollegeRosterLookupService {
  static Iterable<String> _positions(CollegeRosterMember m) =>
      [m.position, m.position2, m.position3].where((p) => p.isNotEmpty);

  /// أزواج (منصب، توضيحه) - يُستخدم عند الحاجة للتمييز بين نفس المنصب
  /// المعياري العام لجهات مختلفة (مثال: "عميد" قد تعني عميد هذه الكلية أو
  /// عميد جهة أخرى تمامًا - التوضيح هو الفاصل الوحيد، انظر
  /// lib/data/position_catalog.dart).
  static Iterable<(String position, String detail)> _positionsWithDetail(CollegeRosterMember m) sync* {
    if (m.position.isNotEmpty) yield (m.position, m.positionDetail);
    if (m.position2.isNotEmpty) yield (m.position2, m.position2Detail);
    if (m.position3.isNotEmpty) yield (m.position3, m.position3Detail);
  }

  static bool _hasPosition(CollegeRosterMember m, String keyword) =>
      _positions(m).any((p) => p.contains(keyword));

  /// مطابقة تامة (بعد إزالة الفراغات الطرفية) بدل الاحتواء الجزئي - تُستخدم
  /// لمناصب "الرأس الواحد" (عميد الكلية، رئيس القسم...) حتى لا يُطابَق خطأً
  /// من يحمل منصبًا يذكر نفس الكلمة ضمن مسمى مختلف تمامًا (مثال: "مستشار
  /// عميد الكلية" ليس هو نفسه "عميد الكلية" - عضو إداري مستشار للعميد لا
  /// عميدًا، رغم احتواء نصه على كلمة "عميد الكلية" كسلسلة فرعية).
  static bool _hasExactPosition(CollegeRosterMember m, Set<String> exactValues) =>
      _positions(m).any((p) => exactValues.contains(p.trim()));

  /// اسم عميد الكلية مجرّدًا من اللقب، أو null إن لم يوجد بعد في الملف المرفوع.
  /// يطابق الصيغة الحرة القديمة ("عميد الكلية") مباشرة، والقيمة المعيارية
  /// الجديدة ("عميد" بلا تحديد) فقط إن كان توضيحها يذكر هذه الكلية تحديدًا -
  /// لأن "عميد" وحدها قد تخص جهة أخرى تمامًا يشغلها عضو هذه الكلية بتكليف
  /// (مثال: عميد قبول وتسجيل).
  static String? deanName(List<CollegeRosterMember> roster) {
    for (final m in roster) {
      if (_hasExactPosition(m, {'عميد الكلية', 'عميدة الكلية', 'عميد كلية', 'عميدة كلية'})) {
        return displayName(m.name);
      }
      final matchesGenericDean = _positionsWithDetail(m).any(
        (p) => (p.$1 == 'عميد' || p.$1 == 'عميدة') && p.$2.contains('كلية إدارة الأعمال'),
      );
      if (matchesGenericDean) return displayName(m.name);
    }
    return null;
  }

  /// اسم رئيس/ة القسم المعني، أو null إن لم يوجد بعد
  static String? departmentHeadName(List<CollegeRosterMember> roster, String department) {
    for (final m in roster) {
      if (m.department == department && _hasExactPosition(m, {'رئيس قسم', 'رئيسة قسم'})) {
        return displayName(m.name);
      }
    }
    return null;
  }

  /// سجل منسّق/ة القسم المعني لنفس الشطر كاملاً (اسم، بريد...)، أو null إن
  /// لم يوجد بعد في الملف المرفوع
  static CollegeRosterMember? coordinatorMemberFor(
    List<CollegeRosterMember> roster,
    String department,
    String shatr,
  ) {
    for (final m in roster) {
      if (m.department == department &&
          m.shatr == shatr &&
          _hasExactPosition(m, {'منسق قسم', 'منسقة قسم'})) {
        return m;
      }
    }
    return null;
  }

  /// اسم منسّق/ة القسم المعني لنفس الشطر (منسّق لا يُؤنَّث كمسمى وظيفي رسمي،
  /// لكن نطابق شطر العضو الفعلي لعرضه)، أو null إن لم يوجد بعد
  static ({String name, bool male})? coordinatorFor(
    List<CollegeRosterMember> roster,
    String department,
    String shatr,
  ) {
    final m = coordinatorMemberFor(roster, department, shatr);
    if (m == null) return null;
    return (name: displayName(m.name), male: shatr.contains('الطلاب'));
  }

  /// اسم رئيس/نائب رئيس وحدة الإرشاد الأكاديمي المسؤول عن هذا الشطر تحديدًا
  /// (عضو واحد لكل شطر)، أو null إن لم يوجد بعد. يطابق الصيغة الحرة القديمة
  /// ("وحدة الإرشاد") والقيمة المعيارية الجديدة لعمود المنصب ("رئيس وحدة"/
  /// "نائب رئيس وحدة") معًا - انظر lib/data/position_catalog.dart.
  static String? unitManagerFor(List<CollegeRosterMember> roster, String shatr) {
    for (final m in roster) {
      if (m.shatr == shatr &&
          (_hasPosition(m, 'وحدة الإرشاد') || _hasPosition(m, 'رئيس وحدة') || _hasPosition(m, 'رئيسة وحدة'))) {
        return displayName(m.name);
      }
    }
    return null;
  }
}
