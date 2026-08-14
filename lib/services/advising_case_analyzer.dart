import '../data/academic_department_names.dart';
import '../data/advising_load_rules.dart';
import '../models/advising_case_record.dart';
import '../models/college_roster_member.dart';
import '../utils/name_display.dart';
import 'advising_report_repository.dart';
import 'college_roster_repository.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

/// عمود "الشطر" في ملف منسوبي الكلية نص حر تكتبه العمادة (مثال: "طلاب" لا
/// "شطر الطلاب" بالضرورة) - لا يُقارَن بالمطابقة الحرفية التامة مطلقًا (كانت
/// تفشل دومًا فيُستبعَد كل الأعضاء بصمت من facultyInScope أدناه - خلل حقيقي
/// اكتُشف 2026-08-14 أثّر على تبويبات "معفَون ولهم طلاب"/"مرشدون بلا
/// طلاب"/"تقرير النصاب"/"حالات صحية غير موزَّعة" كلها معًا). نفس منطق
/// [AdvisingReportParserService]/الشاشات الأخرى - "طالبات" تُفحَص أولًا لأنها
/// تحتوي حروف "طلاب" بترتيب مختلف فلا تلتبس بها.
String? _shatrLabelFromFreeText(String raw) {
  if (raw.contains('طالبات')) return Shatr.female.label;
  if (raw.contains('طلاب')) return Shatr.male.label;
  return null;
}

/// طالب بلا مرشد مسجَّل عليه في التقرير.
typedef UnassignedStudent = AdvisingCaseRecord;

/// طالب مسنَد لمرشد لا يخصّ قسمه (تعارض قسم).
class MismatchedAdvisorCase {
  final AdvisingCaseRecord student;
  final CollegeRosterMember? advisor; // null إن لم يُعثر على المرشد أصلاً في منسوبي الكلية
  const MismatchedAdvisorCase({required this.student, required this.advisor});
}

/// عضو معفى من الإرشاد لكن التقرير يُظهر طلابًا مسنَدين إليه فعليًا - حالة
/// خلل فعلي يستدعي نقل كل طلابه.
class ExemptAdvisorWithStudentsCase {
  final CollegeRosterMember advisor;
  final List<AdvisingCaseRecord> students;
  const ExemptAdvisorWithStudentsCase({required this.advisor, required this.students});
}

/// مرشد (عبء كامل أو جزئي) فوق حصته العادلة داخل قسمه.
class OverloadedAdvisorCase {
  final CollegeRosterMember advisor;
  final int actualCount;
  final double fairShare;
  final int suggestedTransferCount;
  const OverloadedAdvisorCase({
    required this.advisor,
    required this.actualCount,
    required this.fairShare,
    required this.suggestedTransferCount,
  });
}

enum QuotaStatus { over, under, balanced }

/// سطر واحد في "تقرير النصاب" لمرشد واحد - يشمل كل مرشدي القسم (فوق الحصة
/// العادلة أو دونها أو متوازن)، بخلاف [OverloadedAdvisorCase] الذي يقتصر على
/// الفائضين فقط.
class AdvisorQuotaCase {
  final CollegeRosterMember advisor;
  final int actualCount;
  final double fairShare;
  final QuotaStatus status;
  const AdvisorQuotaCase({
    required this.advisor,
    required this.actualCount,
    required this.fairShare,
    required this.status,
  });
}

/// توصية نقل طالب محدَّد بالاسم من مرشده الحالي إلى مرشد آخر أقل حملاً في
/// نفس القسم - toAdvisor يكون null إن تعذَّر إيجاد مرشد مناسب آليًا (لا سعة
/// كافية لدى أي مرشد آخر في القسم)، فيُترك القرار للمنسّق يدويًا.
class TransferSuggestion {
  final AdvisingCaseRecord student;

  /// null حين يكون المرشد الحالي غير موجود إطلاقًا في ملف منسوبي الكلية
  /// (طالب "طلاب على غير مرشدهم" بمرشد مجهول) - استخدم [fromAdvisorNameRaw]
  /// للعرض في هذه الحالة.
  final CollegeRosterMember? fromAdvisor;

  /// اسم المرشد الحالي كما ورد في التقرير - يُستخدم للعرض دائمًا (سواء عُرف
  /// المرشد في ملف منسوبي الكلية أم لا).
  final String fromAdvisorNameRaw;

  final CollegeRosterMember? toAdvisor;
  const TransferSuggestion({
    required this.student,
    required this.fromAdvisor,
    required this.fromAdvisorNameRaw,
    this.toAdvisor,
  });
}

/// طالب له حالة صحية/إعاقة مسجَّلة لكنه غير مسنَد للجهة المسؤولة عن الحالات
/// الخاصة في قسمه - إما مسنَد لمرشد عادي، أو بلا مرشد أصلاً. الجهة المسؤولة
/// هي أمين/ة القسم عادةً، أو منسّق/ة القسم إن كان أمين القسم من خارج القسم
/// (تخصصه مختلف عن قسم الطلاب) - انظر توثيق [AdvisingCaseAnalyzer.analyze].
class HealthCaseMismatch {
  final AdvisingCaseRecord student;
  final CollegeRosterMember? currentAdvisor;

  /// الجهة المسؤولة المفترضة (أمين القسم إن كان من داخل القسم، وإلا منسّق
  /// القسم) - null إن لم يوجد أي منهما مسجَّلًا لهذا القسم.
  final CollegeRosterMember? departmentAmin;
  const HealthCaseMismatch({required this.student, required this.currentAdvisor, required this.departmentAmin});
}

/// نتيجة تسوية تقرير "طلاب على غير مرشدهم" الرسمي (كما تصدره منظومة الجامعة
/// دون تصحيح) مقابل ملف منسوبي الكلية المصحَّح يدويًا في موقعنا - يفصل
/// الحالات الحقيقية عن حالات الانتداب المعروفة (كحنان عامر وطارق حلمي) التي
/// تظهر "خطأ" في تقرير الجامعة فقط لأن سجلها الرسمي هناك لم يُصحَّح بعد.
class OfficialMismatchReconciliation {
  /// حالات حقيقية: قسم المرشد المصحَّح في موقعنا لا يزال مخالفًا لقسم الطالب.
  final List<MismatchedAdvisorCase> confirmed;

  /// حالات استُثنيت لأن قسم المرشد المصحَّح في موقعنا يطابق فعليًا قسم
  /// الطالب (انتداب معروف مثل حنان/طارق) - تُحتسب كإحصائية سليمة تحت القسم
  /// الفعلي، لا كخطأ.
  final List<MismatchedAdvisorCase> excusedBySecondment;

  const OfficialMismatchReconciliation({required this.confirmed, required this.excusedBySecondment});
}

class AdvisingCaseAnalysis {
  /// طلاب مسكَّنون لدى مرشد من نفس قسمهم، موجود بملف منسوبي الكلية - الوضع
  /// السليم المستهدف؛ عكس [studentsWithoutAdvisor] (بلا مرشد إطلاقًا) و
  /// [studentsWithWrongDeptAdvisor] (مرشد موجود لكن خطأ/غير موثَّق).
  final List<AdvisingCaseRecord> studentsCorrectlyAssigned;

  final List<UnassignedStudent> studentsWithoutAdvisor;
  final List<MismatchedAdvisorCase> studentsWithWrongDeptAdvisor;
  final List<ExemptAdvisorWithStudentsCase> exemptAdvisorsWithStudents;
  final List<CollegeRosterMember> advisorsWithNoStudents;
  final List<OverloadedAdvisorCase> overloadedAdvisors;

  /// تقرير النصاب الكامل - كل مرشدي القسم (فوق الحصة العادلة أو دونها أو
  /// متوازن)، بخلاف [overloadedAdvisors] الذي يقتصر على الفائضين.
  final List<AdvisorQuotaCase> quotaReport;
  final List<AdvisingCaseRecord> atRiskStudents; // GPA يستدعي متابعة (مقبول/ضعيف)

  /// طلاب مفصولون أكاديميًا - مستبعَدون من كل القوائم أعلاه تمامًا (بلا مرشد/
  /// خطأ قسم/نطاق معدل...)، ويُعرَضون هنا فقط كقائمة منفصلة.
  final List<AdvisingCaseRecord> dismissedStudents;

  /// مرشدون معفَون/حالات خاصة بلا أي خلل (بلا طلاب كما هو متوقَّع منهم) -
  /// حالة طبيعية، تُخفى افتراضيًا وتظهر رمادية فقط عند تفعيل "إظهار الكل".
  final List<CollegeRosterMember> exemptAdvisorsNoIssue;

  /// تقرير إعادة التوزيع: كل طالب يُوصى بنقله (من مرشد معفى وله طلاب، أو من
  /// مرشد فوق الحصة العادلة) مع المرشد المقترح لاستقباله.
  final List<TransferSuggestion> transferSuggestions;

  /// طلاب لهم حالة صحية/إعاقة لكنهم ليسوا لدى أمين قسمهم (المسؤول الوحيد عن
  /// الحالات الخاصة) - إما مسنَدون لمرشد عادي أو بلا مرشد أصلاً.
  final List<HealthCaseMismatch> healthCasesNotWithAmin;

  /// **كل** الطلاب الذين لهم حالة صحية/إعاقة مسجَّلة (سواء كانوا لدى الجهة
  /// الصحيحة أم لا) - للاطلاع على العدد الفعلي الإجمالي، بخلاف
  /// [healthCasesNotWithAmin] الذي يعرض فقط حالات الخطأ.
  final List<AdvisingCaseRecord> healthCaseStudents;

  const AdvisingCaseAnalysis({
    required this.studentsCorrectlyAssigned,
    required this.studentsWithoutAdvisor,
    required this.studentsWithWrongDeptAdvisor,
    required this.exemptAdvisorsWithStudents,
    required this.advisorsWithNoStudents,
    required this.overloadedAdvisors,
    required this.quotaReport,
    required this.atRiskStudents,
    required this.dismissedStudents,
    required this.exemptAdvisorsNoIssue,
    required this.transferSuggestions,
    required this.healthCasesNotWithAmin,
    required this.healthCaseStudents,
  });
}

/// طالب مسنَد لمرشد من خارج كليتنا (غير موجود بملف منسوبي الكلية) رغم أن
/// تخصصه أحد الأقسام الخمسة المعروفة لكليتنا.
typedef ExternalAdvisorCase = AdvisingCaseRecord;

/// طالب من خارج كليتنا (تخصصه ليس أحد الأقسام الخمسة) مسنَد لمرشد من كليتنا.
typedef ExternalStudentCase = AdvisingCaseRecord;

/// نتيجة تصنيف تقرير "كل الكليات" غير المفلتَر (المصدر الوحيد الحالي لتوزيع
/// الطلبة على المرشدين) مقابل ملف منسوبي الكلية - تفصل الحالات الأربع التي
/// طلبها سليمان صراحةً (2026-08-14)، بديلاً عن الاعتماد على أربعة تقارير
/// منفصلة (قاعدة/تابعين لمرشد/غير تابعين/على غير مرشدهم).
class CollegeAdvisingClassification {
  /// طلاب كليتنا مسنَدون لمرشد من كليتنا بنفس تخصصهم - الوضع السليم.
  final List<AdvisingCaseRecord> studentsCorrectlyAssigned;

  /// طلاب كليتنا مسنَدون لمرشد من كليتنا لكن بتخصص مختلف - فارغة تمامًا يعني
  /// "لا يوجد طلبة على غير مرشدهم" (لا رسالة خطأ، حالة سليمة متوقَّعة).
  final List<MismatchedAdvisorCase> studentsWithWrongDeptAdvisor;

  /// طلاب كليتنا (تخصصهم أحد الأقسام الخمسة) لكن مرشدهم من خارج الكلية
  /// (اسمه غير موجود بملف منسوبي الكلية).
  final List<ExternalAdvisorCase> externalAdvisorsWithOurStudents;

  /// طلاب من خارج كليتنا (تخصصهم ليس أحد الأقسام الخمسة) مسنَدون لمرشد من
  /// كليتنا.
  final List<ExternalStudentCase> ourAdvisorsWithExternalStudents;

  /// طلاب كليتنا بلا مرشد إطلاقًا في هذا التقرير.
  final List<AdvisingCaseRecord> studentsWithoutAdvisor;

  const CollegeAdvisingClassification({
    required this.studentsCorrectlyAssigned,
    required this.studentsWithWrongDeptAdvisor,
    required this.externalAdvisorsWithOurStudents,
    required this.ourAdvisorsWithExternalStudents,
    required this.studentsWithoutAdvisor,
  });
}

/// حركة إرشاد واحدة: طالب تغيّر اسم مرشده بين رفعة "كل الكليات" السابقة
/// والحالية.
class AdvisorMovement {
  final AdvisingCaseRecord student;
  final String fromAdvisorNameRaw;
  final String toAdvisorNameRaw;
  const AdvisorMovement({
    required this.student,
    required this.fromAdvisorNameRaw,
    required this.toAdvisorNameRaw,
  });
}

class AdvisingCaseAnalyzer {
  /// توحيد اسم للمطابقة فقط - مُصدَّر ليُستخدم بنفس المنطق عند بناء خريطة
  /// منسوبي الكلية في الشاشة (facultyByNameKey) قبل تمريرها لـ [analyze].
  static String nameKey(String s) => _key(s);

  static String _key(String s) => s
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه');

  /// يدمج تقرير "طلاب تابعين لمرشد" (فيه اسم/رقم/قسم المرشد) مع تقرير
  /// "بيانات الطلبة الأكاديمية" (فيه القسم والمعدل) - المطابقة بالرقم
  /// الجامعي (مفتاح موثوق، بخلاف الاسم الذي قد يُكتب بصور مختلفة). أي طالب
  /// في القاعدة لا يظهر في تقرير الربط يبقى بلا مرشد (advisorNameRaw فارغ).
  static List<AdvisingCaseRecord> mergeAdvisorLinks(
    List<AdvisingCaseRecord> base,
    List<AdvisingCaseRecord> assigned,
  ) {
    final assignedById = {for (final a in assigned) a.studentId: a};
    return base.map((s) {
      final link = assignedById[s.studentId];
      if (link == null) return s;
      return s.copyWith(
        advisorNameRaw: link.advisorNameRaw,
        advisorId: link.advisorId,
        advisorDepartment: link.advisorDepartment,
      );
    }).toList();
  }

  /// يدمج تقرير "طلاب على غير مرشدهم" الرسمي كمصدر ربط مرشد إضافي - **فقط
  /// للطلاب الذين لم يظهروا أصلاً في تقرير "طلاب تابعين لمرشد"** (لا يُستبدَل
  /// ربط موجود). ضروري لأن الجامعة قد تصنّف طالبًا "على غير مرشده" بدل
  /// "تابع لمرشد" لمجرد أن قسم مرشده المسجَّل لديها غير مصحَّح (حالة انتداب)،
  /// فيغيب تمامًا عن تقرير "تابعين لمرشد" رغم أن له مرشدًا فعليًا. الحالات
  /// الحقيقية (غير المستثناة) تُدمَج أيضًا بنفس الطريقة، فتُحتسَب ضمن حمل
  /// المرشد الفعلي، وتبقى مصنَّفة كخطأ في [analyze] لأن قسمه لا يطابق فعليًا.
  static List<AdvisingCaseRecord> mergeGapsFromMismatchReport(
    List<AdvisingCaseRecord> students,
    List<AdvisingCaseRecord> mismatchReport,
  ) {
    final byId = {for (final m in mismatchReport) m.studentId: m};
    return students.map((s) {
      if (s.hasAdvisor) return s;
      final m = byId[s.studentId];
      if (m == null) return s;
      return s.copyWith(
        advisorNameRaw: m.advisorNameRaw,
        advisorId: m.advisorId,
        advisorDepartment: m.advisorDepartment,
      );
    }).toList();
  }

  /// يصنّف سجلات تقرير "كل الكليات" غير المفلتَر (المصدر الوحيد الحالي لتوزيع
  /// الطلبة على المرشدين) إلى الحالات الأربع + "بلا مرشد" - انظر توثيق
  /// [CollegeAdvisingClassification]. المطابقة بقسم المرشد **المصحَّح فعليًا**
  /// من ملف منسوبي الكلية (لا القسم الحرفي الرسمي) - فحالات الانتداب المعروفة
  /// (طارق حلمي/حنان عامر/غراس أبو الشامات...) تُحسَب تلقائيًا ضمن قسمها
  /// الفعلي المصحَّح بلا أي استثناء أسماء مكتوب هنا.
  static CollegeAdvisingClassification classifyAllColleges({
    required List<AdvisingCaseRecord> allCollegeRecords,
    required Map<String, CollegeRosterMember> facultyByNameKey,
  }) {
    final correctlyAssigned = <AdvisingCaseRecord>[];
    final wrongDept = <MismatchedAdvisorCase>[];
    final externalAdvisors = <ExternalAdvisorCase>[];
    final externalStudents = <ExternalStudentCase>[];
    final withoutAdvisor = <AdvisingCaseRecord>[];

    for (final r in allCollegeRecords) {
      final studentInOurCollege = isKnownBachelorDepartment(normalizeDepartmentName(r.department));

      if (!r.hasAdvisor) {
        if (studentInOurCollege) withoutAdvisor.add(r);
        continue;
      }

      final advisor = facultyByNameKey[_key(displayName(r.advisorNameRaw))];

      if (advisor != null && studentInOurCollege) {
        if (advisor.department == r.department) {
          correctlyAssigned.add(r);
        } else {
          wrongDept.add(MismatchedAdvisorCase(student: r, advisor: advisor));
        }
      } else if (advisor == null && studentInOurCollege) {
        externalAdvisors.add(r);
      } else if (advisor != null && !studentInOurCollege) {
        externalStudents.add(r);
      }
      // advisor == null && !studentInOurCollege: لا علاقة له بكليتنا إطلاقًا - يُتجاهَل.
    }

    return CollegeAdvisingClassification(
      studentsCorrectlyAssigned: correctlyAssigned,
      studentsWithWrongDeptAdvisor: wrongDept,
      externalAdvisorsWithOurStudents: externalAdvisors,
      ourAdvisorsWithExternalStudents: externalStudents,
      studentsWithoutAdvisor: withoutAdvisor,
    );
  }

  /// يقارن رفعة "كل الكليات" السابقة بالحالية (بمطابقة الرقم الجامعي) ويُخرج
  /// كل طالب تغيّر اسم مرشده بينهما - "تقرير حركات الإرشاد" الذي طلبه سليمان
  /// صراحةً (2026-08-14) ليعرف كل عملية نقل طالب من مرشد لآخر أولًا بأول.
  static List<AdvisorMovement> detectAdvisorMovements({
    required List<AdvisingCaseRecord> previous,
    required List<AdvisingCaseRecord> current,
  }) {
    final previousById = {for (final p in previous) p.studentId: p};
    final movements = <AdvisorMovement>[];
    for (final c in current) {
      final p = previousById[c.studentId];
      if (p == null) continue;
      final fromKey = _key(displayName(p.advisorNameRaw));
      final toKey = _key(displayName(c.advisorNameRaw));
      if (fromKey.isEmpty && toKey.isEmpty) continue;
      if (fromKey != toKey) {
        movements.add(AdvisorMovement(
          student: c,
          fromAdvisorNameRaw: p.advisorNameRaw,
          toAdvisorNameRaw: c.advisorNameRaw,
        ));
      }
    }
    return movements;
  }

  /// تحميل مشترك لكل الشاشات الأربع المعتمِدة على تقرير "كل الكليات" (متابعة
  /// حالات الإرشاد بلوحة الإدارة، لوحة الإرشاد، بحث عن مرشد، صفحة منسّق
  /// القسم) - بدل تكرار نفس تسلسل التحميل/الفلترة في كل شاشة على حدة. يُرجع
  /// لكل شطر: سجلات كليتنا فقط (مفلتَرة + مدموجة بذوي الإعاقة) بالإضافة
  /// للسجلات الخام غير المفلتَرة (لازمة لتصنيفات المرشدين/الطلاب من خارج
  /// الكلية) وخريطة منسوبي الكلية.
  static Future<
      ({
        List<AdvisingCaseRecord> male,
        List<AdvisingCaseRecord> female,
        List<AdvisingCaseRecord> allCollegesMaleRaw,
        List<AdvisingCaseRecord> allCollegesFemaleRaw,
        List<AdvisingCaseRecord> allCollegesMalePrevious,
        List<AdvisingCaseRecord> allCollegesFemalePrevious,
        Map<String, CollegeRosterMember> facultyByKey,
      })> loadCollegeScopedStudents() async {
    final results = await Future.wait([
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allCollegesPrevious),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allCollegesPrevious),
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.health),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.health),
      CollegeRosterRepository.load(),
    ]);
    final allMale = results[0] as List<AdvisingCaseRecord>;
    final allFemale = results[1] as List<AdvisingCaseRecord>;
    final previousMale = results[2] as List<AdvisingCaseRecord>;
    final previousFemale = results[3] as List<AdvisingCaseRecord>;
    final healthMale = results[4] as List<AdvisingCaseRecord>;
    final healthFemale = results[5] as List<AdvisingCaseRecord>;
    final roster = results[6] as List<CollegeRosterMember>;

    final facultyByKey = {for (final m in roster) nameKey(displayName(m.name)): m};

    List<AdvisingCaseRecord> scopeToCollege(List<AdvisingCaseRecord> all, List<AdvisingCaseRecord> health) {
      final scoped =
          all.where((r) => isKnownBachelorDepartment(normalizeDepartmentName(r.department))).toList();
      return mergeHealthConditions(scoped, health);
    }

    return (
      male: scopeToCollege(allMale, healthMale),
      female: scopeToCollege(allFemale, healthFemale),
      allCollegesMaleRaw: allMale,
      allCollegesFemaleRaw: allFemale,
      allCollegesMalePrevious: previousMale,
      allCollegesFemalePrevious: previousFemale,
      facultyByKey: facultyByKey,
    );
  }

  /// يدمج تقرير "الحالة الصحية للطلبة" (نوع الحالة/الإعاقة) مع القائمة -
  /// مطابقة بالرقم الجامعي كذلك.
  static List<AdvisingCaseRecord> mergeHealthConditions(
    List<AdvisingCaseRecord> students,
    List<AdvisingCaseRecord> healthReport,
  ) {
    final healthById = {for (final h in healthReport) h.studentId: h};
    return students.map((s) {
      final h = healthById[s.studentId];
      if (h == null) return s;
      return s.copyWith(healthCondition: h.healthCondition);
    }).toList();
  }

  /// يدمج معدل النسخة السابقة (قبل آخر رفعة) - "النطاق السابق" - مطابقة
  /// بالرقم الجامعي. طالب مستجد لا يظهر في النسخة السابقة يبقى بلا نطاق سابق.
  static List<AdvisingCaseRecord> mergePreviousGpa(
    List<AdvisingCaseRecord> students,
    List<AdvisingCaseRecord> previous,
  ) {
    final previousById = {for (final p in previous) p.studentId: p};
    return students.map((s) {
      final p = previousById[s.studentId];
      if (p == null) return s;
      return s.copyWith(previousGpa: p.gpa);
    }).toList();
  }

  /// يسوّي تقرير "طلاب على غير مرشدهم" الرسمي (مصدره منظومة الجامعة، قد لا
  /// يعكس تصحيحات الانتداب اليدوية) مقابل قسم الطالب الفعلي من تقرير القاعدة
  /// وقسم المرشد المصحَّح من ملف منسوبي الكلية - فيفصل الحالات الحقيقية عن
  /// حالات الانتداب المعروفة تلقائيًا (بلا أي استثناء أسماء مكتوب في الكود).
  static OfficialMismatchReconciliation reconcileOfficialMismatchReport({
    required List<AdvisingCaseRecord> officialMismatchReport,
    required List<AdvisingCaseRecord> base,
    required Map<String, CollegeRosterMember> facultyByNameKey,
  }) {
    final baseById = {for (final s in base) s.studentId: s};
    final confirmed = <MismatchedAdvisorCase>[];
    final excused = <MismatchedAdvisorCase>[];

    for (final row in officialMismatchReport) {
      final student = baseById[row.studentId] ?? row;
      final advisor = facultyByNameKey[_key(displayName(row.advisorNameRaw))];
      final item = MismatchedAdvisorCase(student: student, advisor: advisor);
      if (advisor != null && advisor.department == student.department) {
        excused.add(item);
      } else {
        confirmed.add(item);
      }
    }

    return OfficialMismatchReconciliation(confirmed: confirmed, excusedBySecondment: excused);
  }

  /// وزن المرشد من إجمالي حصة القسم العادلة، حسب عبء إرشاده: كامل = 1، جزئي
  /// = النسبة، معفى/حالات خاصة = صفر (لا يُحسَب ضمن التوزيع العام إطلاقًا).
  static double _weightOf(CollegeRosterMember m) {
    switch (m.advisingLoad) {
      case AdvisingLoad.full:
        return 1.0;
      case AdvisingLoad.reduced:
        return (m.reducedToPercent ?? 50) / 100.0;
      case AdvisingLoad.exempt:
      case AdvisingLoad.specialCasesOnly:
      case AdvisingLoad.frozen:
        return 0.0;
    }
  }

  static AdvisingCaseAnalysis analyze({
    required List<AdvisingCaseRecord> students,
    required Map<String, CollegeRosterMember> facultyByNameKey,
  }) {
    CollegeRosterMember? advisorOf(AdvisingCaseRecord s) =>
        facultyByNameKey[_key(displayName(s.advisorNameRaw))];

    // الطلاب المفصولون أكاديميًا يُستبعَدون كليًا من كل التحليل أدناه (بلا
    // مرشد/خطأ قسم/توازن توزيع/نطاق معدل...) ويُعرَضون في قائمتهم الخاصة فقط.
    final dismissed = students.where((s) => s.isAcademicallyDismissed).toList();
    final activeStudents = students.where((s) => !s.isAcademicallyDismissed).toList();

    final correctlyAssigned = <AdvisingCaseRecord>[];
    final withoutAdvisor = <UnassignedStudent>[];
    final wrongDept = <MismatchedAdvisorCase>[];
    final byAdvisorKey = <String, List<AdvisingCaseRecord>>{};

    for (final s in activeStudents) {
      if (!s.hasAdvisor) {
        withoutAdvisor.add(s);
        continue;
      }
      final advisor = advisorOf(s);
      // حل مؤقت: المرشد غير الموجود إطلاقًا في ملف منسوبي الكلية (اسمه لا
      // يطابق أي عضو) يُعامَل معاملة "خطأ قسم" أيضًا (يظهر ضمن "طلاب على غير
      // مرشدهم") حتى يُتحقَّق منه يدويًا من المنظومة الجامعية ويُضاف/يُصحَّح
      // في ملف منسوبي الكلية - بدل تجاهل حالته بصمت.
      if (advisor == null || advisor.department != s.department) {
        wrongDept.add(MismatchedAdvisorCase(student: s, advisor: advisor));
      } else {
        correctlyAssigned.add(s);
      }
      final key = _key(displayName(s.advisorNameRaw));
      byAdvisorKey.putIfAbsent(key, () => []).add(s);
    }

    final exemptWithStudents = <ExemptAdvisorWithStudentsCase>[];
    final exemptNoIssue = <CollegeRosterMember>[];
    final noStudents = <CollegeRosterMember>[];
    final overloaded = <OverloadedAdvisorCase>[];
    final quotaReport = <AdvisorQuotaCase>[];
    final transfers = <TransferSuggestion>[];

    // مجموعة أعضاء هيئة التدريس الفريدة الظاهرة في نطاق هذا الشطر/الأقسام
    // المرفوعة (لا كل منسوبي الكلية) - نحصرها من المرشدين الظاهرين فعليًا في
    // بيانات الطلاب زائد كل عضو يحمل عبء إرشاد (كامل/جزئي) في نفس الأقسام،
    // حتى يظهر "مرشد بلا طلاب" حتى لو لم يُذكر اسمه إطلاقًا في التقرير.
    final departmentsInScope = activeStudents.map((s) => s.department).toSet();
    final shatrInScope = activeStudents.isEmpty ? null : activeStudents.first.shatr;
    final facultyInScope = facultyByNameKey.values
        .where((m) =>
            departmentsInScope.contains(m.department) &&
            (shatrInScope == null || _shatrLabelFromFreeText(m.shatr) == shatrInScope))
        .toSet()
        .toList();

    for (final member in facultyInScope) {
      final key = _key(displayName(member.name));
      final assigned = byAdvisorKey[key] ?? const <AdvisingCaseRecord>[];

      if (member.advisingLoad == AdvisingLoad.exempt) {
        if (assigned.isNotEmpty) {
          exemptWithStudents.add(ExemptAdvisorWithStudentsCase(advisor: member, students: assigned));
        } else {
          exemptNoIssue.add(member);
        }
        continue;
      }
      if (member.advisingLoad == AdvisingLoad.specialCasesOnly) {
        exemptNoIssue.add(member);
        continue;
      }
      // حالته مجمّدة (موقوف الراتب/مبتعث/معار/مجاز) - لا يُتوقَّع منه إرشاد
      // حاليًا فلا يُعامَل كـ"مرشد بلا طلاب"، لكنه لا يُعرض ضمن قائمة المعفين
      // أيضًا لأن التجميد مؤقت وليس قرار إعفاء إرشادي.
      if (member.advisingLoad == AdvisingLoad.frozen) continue;

      if (assigned.isEmpty) {
        noStudents.add(member);
      }
    }

    // توازن التوزيع لكل قسم على حدة: الحصة العادلة = وزن المرشد × (إجمالي
    // الطلاب المسندين فعليًا لمرشدين في القسم ÷ مجموع أوزان مرشدي القسم).
    for (final dept in departmentsInScope) {
      final deptFaculty = facultyInScope.where((m) => m.department == dept && _weightOf(m) > 0).toList();
      if (deptFaculty.isEmpty) continue;

      final totalWeight = deptFaculty.fold<double>(0, (sum, m) => sum + _weightOf(m));
      if (totalWeight <= 0) continue;

      int countOf(CollegeRosterMember m) => byAdvisorKey[_key(displayName(m.name))]?.length ?? 0;

      final totalAssigned = deptFaculty.fold<int>(0, (sum, m) => sum + countOf(m));

      // سعة الاستقبال المتاحة لكل مرشد دون الحصة العادلة في هذا القسم -
      // تُستهلَك أدناه عند توزيع طلاب المعفَين والفائضين آليًا.
      final remainingCapacity = <String, int>{};
      for (final m in deptFaculty) {
        final actual = countOf(m);
        final fairShare = _weightOf(m) * (totalAssigned / totalWeight);
        final over = actual - fairShare;
        if (over >= 1) {
          overloaded.add(OverloadedAdvisorCase(
            advisor: m,
            actualCount: actual,
            fairShare: fairShare,
            suggestedTransferCount: over.round(),
          ));
        } else if (fairShare - actual >= 0.5) {
          remainingCapacity[_key(displayName(m.name))] = (fairShare - actual).round();
        }
        quotaReport.add(AdvisorQuotaCase(
          advisor: m,
          actualCount: actual,
          fairShare: fairShare,
          status: over >= 1
              ? QuotaStatus.over
              : (fairShare - actual >= 0.5 ? QuotaStatus.under : QuotaStatus.balanced),
        ));
      }

      CollegeRosterMember? pickReceiver() {
        for (final m in deptFaculty) {
          final k = _key(displayName(m.name));
          if ((remainingCapacity[k] ?? 0) > 0) return m;
        }
        return null;
      }

      void consumeCapacity(CollegeRosterMember m) {
        final k = _key(displayName(m.name));
        remainingCapacity[k] = (remainingCapacity[k] ?? 0) - 1;
      }

      // 1) طلاب المرشدين المعفَين وجوبًا (كل طلابهم بلا استثناء).
      for (final c in exemptWithStudents.where((c) => c.advisor.department == dept)) {
        for (final s in c.students) {
          final receiver = pickReceiver();
          if (receiver != null) consumeCapacity(receiver);
          transfers.add(TransferSuggestion(
              student: s, fromAdvisor: c.advisor, fromAdvisorNameRaw: c.advisor.name, toAdvisor: receiver));
        }
      }

      // 2) فائض المرشدين فوق الحصة العادلة (عدد الطلاب المقترح نقلهم فقط).
      for (final o in overloaded.where((o) => o.advisor.department == dept)) {
        final studentsOfAdvisor = byAdvisorKey[_key(displayName(o.advisor.name))] ?? const [];
        final sorted = [...studentsOfAdvisor]..sort((a, b) => a.studentName.compareTo(b.studentName));
        for (final s in sorted.take(o.suggestedTransferCount)) {
          final receiver = pickReceiver();
          if (receiver != null) consumeCapacity(receiver);
          transfers.add(TransferSuggestion(
              student: s, fromAdvisor: o.advisor, fromAdvisorNameRaw: o.advisor.name, toAdvisor: receiver));
        }
      }

      // 3) طلاب "على غير مرشدهم" (قسم المرشد يخالف قسمهم، أو المرشد غير
      // معروف إطلاقًا في ملف منسوبي الكلية) - يُقترح لهم مرشد من قسمهم
      // الصحيح بنفس آلية الحصة العادلة، ليعرف المنسّق فورًا لمن يُحوَّل
      // الطالب بدل البحث يدويًا.
      for (final c in wrongDept.where((c) => c.student.department == dept)) {
        final receiver = pickReceiver();
        if (receiver != null) consumeCapacity(receiver);
        transfers.add(TransferSuggestion(
          student: c.student,
          fromAdvisor: c.advisor,
          fromAdvisorNameRaw: c.student.advisorNameRaw,
          toAdvisor: receiver,
        ));
      }
    }

    final atRisk = activeStudents.where((s) => gpaStatusOf(s.gpa).needsAttention).toList();

    // حالات صحية/إعاقة: يجب أن يكون مرشد الطالب هو أمين قسمه (حالات خاصة
    // فقط) - أي طالب له حالة صحية ومرشده الحالي غير أمين القسم (أو بلا مرشد
    // أصلاً) يُسجَّل هنا. استثناء: إن كان أمين القسم من خارج القسم (تخصصه
    // مختلف - عندها لا يُصنَّف specialCasesOnly أصلاً لهذا القسم في
    // [AdvisingLoadRules.classify]، فيغيب من aminByDept)، تُقبَل حالاته لدى
    // منسّق/ة القسم بدلًا منه.
    final aminByDept = {
      for (final m in facultyInScope.where((m) => m.advisingLoad == AdvisingLoad.specialCasesOnly)) m.department: m,
    };
    bool isDeptCoordinator(CollegeRosterMember m) {
      final text = _key([m.position, m.position2, m.position3].join(' '));
      return (text.contains(_key('منسق قسم')) || text.contains(_key('منسقة قسم'))) &&
          !text.contains(_key('منسق الكلية')) &&
          !text.contains(_key('منسقة الكلية'));
    }

    final coordinatorByDept = {
      for (final m in facultyInScope.where(isDeptCoordinator)) m.department: m,
    };
    final healthMismatches = <HealthCaseMismatch>[];
    final healthCaseStudents = activeStudents.where((s) => s.hasHealthCondition).toList();
    for (final s in healthCaseStudents) {
      final responsible = aminByDept[s.department] ?? coordinatorByDept[s.department];
      final currentAdvisor = s.hasAdvisor ? advisorOf(s) : null;
      final isWithResponsible = responsible != null &&
          currentAdvisor != null &&
          _key(displayName(responsible.name)) == _key(displayName(currentAdvisor.name));
      if (!isWithResponsible) {
        healthMismatches.add(HealthCaseMismatch(student: s, currentAdvisor: currentAdvisor, departmentAmin: responsible));
      }
    }

    return AdvisingCaseAnalysis(
      studentsCorrectlyAssigned: correctlyAssigned,
      studentsWithoutAdvisor: withoutAdvisor,
      studentsWithWrongDeptAdvisor: wrongDept,
      healthCasesNotWithAmin: healthMismatches,
      healthCaseStudents: healthCaseStudents,
      exemptAdvisorsWithStudents: exemptWithStudents,
      advisorsWithNoStudents: noStudents,
      overloadedAdvisors: overloaded,
      quotaReport: quotaReport,
      atRiskStudents: atRisk,
      dismissedStudents: dismissed,
      exemptAdvisorsNoIssue: exemptNoIssue,
      transferSuggestions: transfers,
    );
  }
}
