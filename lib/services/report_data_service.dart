import '../models/advisor_roster_entry.dart';
import 'advisor_zip_service.dart';
import 'excel_export_service.dart';
import 'excel_parser_service.dart';

/// عدّادات حالة الإنجاز لمجموعة إجراءات (عامة، أو لقسم، أو لمرشد)
class StatusCounts {
  int total = 0;
  int completed = 0;
  int partial = 0;
  int notDone = 0;
  // "فارغة" = المرشد لم يبدأ العمل على الحالة إطلاقًا - مختلفة عن "لم يتم"
  // (عولجت لكن المرشد لا يملك صلاحية إكمالها، تحتاج تصعيدًا).
  int blank = 0;

  double get completionRate => total == 0 ? 0 : completed / total;

  void addStatus(String? status) {
    total++;
    switch (status) {
      case 'تم الإنجاز':
        completed++;
        break;
      case 'جزئي':
        partial++;
        break;
      case 'لم يتم':
        notDone++;
        break;
      default:
        blank++;
        break;
    }
  }

  /// مقياس "هل اشتغل الشخص على الحالة أم لا" - أي قيمة مكتوبة (بصرف النظر عن
  /// محتواها) تُحتسب "اشتغل"، والفراغ فقط يُحتسب "لم يشتغل". يُستخدم لأداء
  /// المرشد/منسق القسم/منسق الكلية، لا لحالة الحل الفعلية للطلب.
  void addWorked(String? status) {
    total++;
    if (status != null && status.trim().isNotEmpty) {
      completed++;
    } else {
      blank++;
    }
  }
}

class AdvisorReport {
  final String name;
  final StatusCounts counts = StatusCounts();

  AdvisorReport(this.name);
}

class DepartmentReport {
  final String shatr;
  final String department;
  final StatusCounts counts = StatusCounts();
  // أداء منسّق القسم (اشتغل/لم يشتغل على عمود حالته) - قسم واحد = منسّق واحد عادة
  final StatusCounts coordinatorCounts = StatusCounts();
  final Map<String, AdvisorReport> _advisorsByName = {};

  DepartmentReport(this.shatr, this.department);

  List<AdvisorReport> get advisors => _advisorsByName.values.toList();

  AdvisorReport advisor(String name) {
    return _advisorsByName.putIfAbsent(name, () => AdvisorReport(name));
  }
}

/// أداء منسّق الكلية على مستوى شطر كامل (لا يوجد اسم منسّق كلية لكل تذكرة،
/// فيُقاس على مستوى الشطر الذي يمثله)
class ShatrReport {
  final String shatr;
  final StatusCounts collegeCounts = StatusCounts();

  ShatrReport(this.shatr);
}

enum AdvisorProgressStatus { notStarted, inProgress, complete }

/// صف واحد في "تقرير متابعة الإنجاز" - أداء مرشد واحد ضمن قسم/شطر، مع
/// تصنيف حالة واضح (لم يبدأ/قيد التنفيذ/مكتمل) لتسهيل المتابعة اليومية.
class AdvisorProgress {
  final String shatr;
  final String department;
  final String advisorName;
  final StatusCounts counts;

  const AdvisorProgress({
    required this.shatr,
    required this.department,
    required this.advisorName,
    required this.counts,
  });

  AdvisorProgressStatus get status {
    if (counts.completed == 0) return AdvisorProgressStatus.notStarted;
    if (counts.completed >= counts.total) return AdvisorProgressStatus.complete;
    return AdvisorProgressStatus.inProgress;
  }

  String get statusLabel {
    switch (status) {
      case AdvisorProgressStatus.notStarted:
        return 'لم يبدأ العمل';
      case AdvisorProgressStatus.inProgress:
        return 'قيد التنفيذ';
      case AdvisorProgressStatus.complete:
        return 'مكتمل';
    }
  }
}

/// آخر حالة غير فارغة تصعيديًا (المرشد ← منسق القسم ← منسق الكلية) - تحدد
/// هل الحالة محلولة فعليًا، بصرف النظر عمن أنجزها
String effectiveStatus(Map<String, dynamic> action) {
  final college = (action['college_status'] ?? '').toString().trim();
  if (college.isNotEmpty) return college;
  final coordinator = (action['coordinator_status'] ?? '').toString().trim();
  if (coordinator.isNotEmpty) return coordinator;
  return (action['advisor_status'] ?? '').toString().trim();
}

/// اسم الجهة التي أنجزت الحالة فعليًا ('تم الإنجاز') - أول من كتبها تصعيديًا
/// (المرشد ← منسق القسم ← منسق الكلية)، أو فارغ لو لم تُنجَز
String effectiveCompletedBy(Map<String, dynamic> action) {
  if ((action['advisor_status'] ?? '').toString().trim() == 'تم الإنجاز') {
    return 'المرشد الأكاديمي';
  }
  if ((action['coordinator_status'] ?? '').toString().trim() == 'تم الإنجاز') {
    return 'منسق القسم';
  }
  if ((action['college_status'] ?? '').toString().trim() == 'تم الإنجاز') {
    return 'منسق الكلية';
  }
  return '';
}

class ReportData {
  final StatusCounts overall = StatusCounts();
  final List<DepartmentReport> departments;
  final List<ShatrReport> shatrReports;
  final Map<String, int> completedByOverall = {
    for (final option in ExcelExportService.completionSourceOptions) option: 0,
    'غير محدد': 0,
  };

  ReportData(this.departments, this.shatrReports);
}

class ReportDataService {
  static ReportData build(
    List<Map<String, dynamic>> tickets, {
    List<AdvisorRosterEntry>? roster,
  }) {
    final departmentsByKey = <String, DepartmentReport>{};

    // عند توفر قائمة مرشدي القسم، نستخدم نفس تجميع "تفريغ المنسّق" المستخدَم
    // لبناء ملفات ZIP - فهرس من الرقم الجامعي إلى اسم من يعالج الحالة فعليًا
    // (بدل المرشد الرسمي المسجَّل في النموذج فقط)، حتى لا يظهر منسّق قسم في
    // التقرير وكأن لديه حالات معلَّقة بعد أن تفرَّغ منها فعليًا.
    final effectiveAdvisorByUniversityId = <String, String>{};
    if (roster != null && roster.isNotEmpty) {
      final groups = AdvisorZipService.resolveEffectiveGroups(tickets, roster: roster);
      for (final entry in groups.entries) {
        for (final t in entry.value) {
          final universityId = (t['university_id'] ?? '').toString();
          if (universityId.isNotEmpty) {
            effectiveAdvisorByUniversityId[universityId] = entry.key;
          }
        }
      }
    }

    // نُنشئ إدخالًا لكل الأقسام العشرة الثابتة أولاً، حتى تظهر في التقرير
    // حتى لو كانت بلا أي حالات (صفر بدل الاختفاء من التقرير)
    for (final shatr in [
      ExcelParserService.shatrMale,
      ExcelParserService.shatrFemale,
    ]) {
      for (final department in ExcelParserService.departments) {
        final key = '$shatr|$department';
        departmentsByKey[key] = DepartmentReport(shatr, department);
      }
    }

    final shatrByKey = <String, ShatrReport>{
      for (final shatr in [ExcelParserService.shatrMale, ExcelParserService.shatrFemale])
        shatr: ShatrReport(shatr),
    };

    final data = ReportData(departmentsByKey.values.toList(), shatrByKey.values.toList());

    for (final ticket in tickets) {
      final shatr = (ticket['shatr'] ?? '').toString();
      final department = (ticket['department'] ?? '').toString();
      final universityId = (ticket['university_id'] ?? '').toString();
      final advisorName = effectiveAdvisorByUniversityId[universityId] ??
          (ticket['advisor'] ?? '').toString();
      final key = '$shatr|$department';

      final departmentReport = departmentsByKey.putIfAbsent(
        key,
        () => DepartmentReport(shatr, department),
      );
      final shatrReport = shatrByKey.putIfAbsent(shatr, () => ShatrReport(shatr));

      final actions = (ticket['actions'] as List?) ?? [];
      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final status = effectiveStatus(action);

        data.overall.addStatus(status);
        departmentReport.counts.addStatus(status);
        departmentReport.coordinatorCounts.addWorked(action['coordinator_status']?.toString());
        shatrReport.collegeCounts.addWorked(action['college_status']?.toString());
        if (advisorName.isNotEmpty) {
          departmentReport.advisor(advisorName).counts.addWorked(action['advisor_status']?.toString());
        }

        if (status == 'تم الإنجاز') {
          final bucket = effectiveCompletedBy(action);
          final key = bucket.isEmpty ? 'غير محدد' : bucket;
          data.completedByOverall[key] = (data.completedByOverall[key] ?? 0) + 1;
        }
      }
    }

    // إعادة بناء قائمة الأقسام والشطور كاملة (تشمل أي قسم/شطر إضافي ظهر
    // بالبيانات الفعلية ولم يكن ضمن القائمة الثابتة، احتياطًا)
    data.departments
      ..clear()
      ..addAll(departmentsByKey.values);
    data.shatrReports
      ..clear()
      ..addAll(shatrByKey.values);

    return data;
  }

  /// يرتّب كل المرشدين الذين لديهم حالات فعلية حسب نسبة الإنجاز تصاعديًا
  /// (الأسوأ أولاً) - أساس "تقرير متابعة الإنجاز" الذي يُظهر فورًا من لم
  /// يبدأ العمل بعد بدل البحث يدويًا داخل كل ملف قسم.
  static List<AdvisorProgress> rankedAdvisors(ReportData data) {
    final rows = <AdvisorProgress>[];
    for (final department in data.departments) {
      for (final advisor in department.advisors) {
        if (advisor.counts.total == 0) continue;
        rows.add(AdvisorProgress(
          shatr: department.shatr,
          department: department.department,
          advisorName: advisor.name,
          counts: advisor.counts,
        ));
      }
    }
    _sortByRate(rows);
    return rows;
  }

  static void _sortByRate(List<AdvisorProgress> rows) {
    rows.sort((a, b) {
      final rateCompare = a.counts.completionRate.compareTo(b.counts.completionRate);
      if (rateCompare != 0) return rateCompare;
      return b.counts.total.compareTo(a.counts.total);
    });
  }

  /// ترتيب أداء منسّقي الأقسام (اشتغل/لم يشتغل على حالاتهم) - قسم واحد يمثّل
  /// منسّقًا واحدًا عادة
  static List<AdvisorProgress> rankedCoordinators(ReportData data) {
    final rows = <AdvisorProgress>[];
    for (final department in data.departments) {
      if (department.coordinatorCounts.total == 0) continue;
      rows.add(AdvisorProgress(
        shatr: department.shatr,
        department: department.department,
        advisorName: department.department,
        counts: department.coordinatorCounts,
      ));
    }
    _sortByRate(rows);
    return rows;
  }

  /// ترتيب أداء منسّقي الكلية (اشتغل/لم يشتغل) على مستوى كل شطر
  static List<AdvisorProgress> rankedCollegeCoordinators(ReportData data) {
    final rows = <AdvisorProgress>[];
    for (final shatrReport in data.shatrReports) {
      if (shatrReport.collegeCounts.total == 0) continue;
      rows.add(AdvisorProgress(
        shatr: shatrReport.shatr,
        department: '',
        advisorName: shatrReport.shatr,
        counts: shatrReport.collegeCounts,
      ));
    }
    _sortByRate(rows);
    return rows;
  }
}
