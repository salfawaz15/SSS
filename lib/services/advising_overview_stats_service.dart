import 'advising_case_analyzer.dart';

/// ملخص "مؤشرات رئيسية لحالات الإرشاد" (الكل/تابعين لمرشد/ذوي الإعاقة/بلا
/// مرشد/على غير مرشدهم) - نفس أرقام `advising_cases_admin_screen.dart`
/// بالموقع حرفيًا (نفس الصيغ بالضبط، راجع `_buildStatsGrid`/`_classification`/
/// `_analysis` هناك)، مُستخرَجة هنا كخدمة عامة قابلة لإعادة الاستخدام من
/// تطبيق "بوابة الإرشاد" الجوّالة بلا تكرار الحساب (القسم 37) وبلا أي تغيير
/// على الشاشة الأصلية بالموقع.
class AdvisingOverviewStats {
  final int total;
  final int assigned;
  final int assignedWithDisability;
  final int withoutAdvisor;
  final int wrongAdvisor;
  final int wrongAdvisorWithDisability;
  // "الكل" الحقيقي (كل طالب مهما كانت حالته أو كونه مستجدًا) و"المنتظمون"
  // و"الحالات الأخرى" - نفس بطاقات advising_cases_admin_screen.dart بالموقع
  // حرفيًا (سليمان صراحةً 2026-09-30)، تُستخدَم بتطبيق الجوال بدل بطاقات
  // "على غير مرشدهم/بلا مرشد/تابعين لمرشد – ذوي الإعاقة" السابقة.
  final int allStudents;
  final int regular;
  final int otherStatuses;

  const AdvisingOverviewStats({
    required this.total,
    required this.assigned,
    required this.assignedWithDisability,
    required this.withoutAdvisor,
    required this.wrongAdvisor,
    required this.wrongAdvisorWithDisability,
    required this.allStudents,
    required this.regular,
    required this.otherStatuses,
  });
}

/// توزيع "تابعين لمرشد"/"على غير مرشدهم" على قسم-شطر واحد - لجدول لوحة
/// الإدارة الجوّالة (`admin_summary_screen.dart` تبويب "الإرشاد")، بنفس نمط
/// جدولَي "الإنجاز حسب القسم" بقسم "الحذف والإضافة".
class AdvisingDepartmentBreakdown {
  final String shatr;
  final String department;
  final int assigned;
  final int wrongAdvisor;

  const AdvisingDepartmentBreakdown({
    required this.shatr,
    required this.department,
    required this.assigned,
    required this.wrongAdvisor,
  });
}

class AdvisingOverviewStatsService {
  static Future<AdvisingOverviewStats> load() async {
    final classification = await _loadClassification();
    return _buildStats(classification.classification, classification.analysisMale, classification.analysisFemale);
  }

  static Future<List<AdvisingDepartmentBreakdown>> loadDepartmentBreakdown() async {
    final loaded = await _loadClassification();
    final c = loaded.classification;

    String key(String shatr, String department) => '$shatr|$department';
    final assignedCounts = <String, int>{};
    final wrongCounts = <String, int>{};
    final meta = <String, ({String shatr, String department})>{};

    for (final s in c.studentsCorrectlyAssigned) {
      final k = key(s.shatr, s.department);
      assignedCounts[k] = (assignedCounts[k] ?? 0) + 1;
      meta[k] = (shatr: s.shatr, department: s.department);
    }
    for (final m in c.studentsWithWrongDeptAdvisor) {
      final s = m.student;
      final k = key(s.shatr, s.department);
      wrongCounts[k] = (wrongCounts[k] ?? 0) + 1;
      meta[k] = (shatr: s.shatr, department: s.department);
    }

    final allKeys = {...assignedCounts.keys, ...wrongCounts.keys};
    return [
      for (final k in allKeys)
        AdvisingDepartmentBreakdown(
          shatr: meta[k]!.shatr,
          department: meta[k]!.department,
          assigned: assignedCounts[k] ?? 0,
          wrongAdvisor: wrongCounts[k] ?? 0,
        ),
    ];
  }

  static Future<
      ({
        CollegeAdvisingClassification classification,
        AdvisingCaseAnalysis analysisMale,
        AdvisingCaseAnalysis analysisFemale,
      })> _loadClassification() async {
    final data = await AdvisingCaseAnalyzer.loadCollegeScopedStudents();

    final classification = AdvisingCaseAnalyzer.classifyAllColleges(
      academicRecords: [...data.academicMaleRaw, ...data.academicFemaleRaw],
      allCollegeRecords: [...data.allCollegesMaleRaw, ...data.allCollegesFemaleRaw],
      allCollegeRecordsPrevious: [...data.allCollegesMalePrevious, ...data.allCollegesFemalePrevious],
      facultyByNameKey: data.facultyByKey,
    );

    final analysisMale = AdvisingCaseAnalyzer.analyze(students: data.male, facultyByNameKey: data.facultyByKey);
    final analysisFemale = AdvisingCaseAnalyzer.analyze(students: data.female, facultyByNameKey: data.facultyByKey);

    return (classification: classification, analysisMale: analysisMale, analysisFemale: analysisFemale);
  }

  static AdvisingOverviewStats _buildStats(
    CollegeAdvisingClassification classification,
    AdvisingCaseAnalysis analysisMale,
    AdvisingCaseAnalysis analysisFemale,
  ) {
    final assignedWithDisability = analysisMale.healthCasesWithAmin.length + analysisFemale.healthCasesWithAmin.length;

    final wrongAdvisorWithDisability =
        classification.studentsWithWrongDeptAdvisor.where((c) => c.student.hasHealthCondition).length;

    final total = classification.studentsCorrectlyAssigned.length +
        classification.studentsWithoutAdvisor.length +
        classification.studentsWithWrongDeptAdvisor.length +
        classification.externalAdvisorsWithOurStudents.length +
        classification.ourAdvisorsWithExternalStudents.length;

    final regular = total + classification.newStudents.length;
    final allStudents = regular + classification.dismissedStudents.length;

    return AdvisingOverviewStats(
      total: total,
      assigned: classification.studentsCorrectlyAssigned.length,
      assignedWithDisability: assignedWithDisability,
      withoutAdvisor: classification.studentsWithoutAdvisor.length,
      wrongAdvisor: classification.studentsWithWrongDeptAdvisor.length,
      wrongAdvisorWithDisability: wrongAdvisorWithDisability,
      allStudents: allStudents,
      regular: regular,
      otherStatuses: classification.dismissedStudents.length,
    );
  }
}
