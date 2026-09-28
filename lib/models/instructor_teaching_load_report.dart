import 'course_section_record.dart' show CourseMeeting;

/// صف مقرر واحد ضمن جدول محاضر رسمي (عمادة القبول والتسجيل) - يختلف عن
/// [CourseSectionRecord] لأنه غير مرتبط بشعبة نظري+عملي مدمَجة، بل صف مستقل
/// كما يظهر حرفيًا بالتقرير الرسمي لكل محاضر (نظري وعملي صفّان منفصلان).
class TeachingLoadCourseRow {
  final String courseCode; // "رقم المقرر" بلا لاحقة الساعات
  final String courseName;
  final String scheduleType; // "نوع الجدول": إنتظام / انتساب مطور / دبلوم مدفوع / مدمج مدفوع...
  final String activity; // "النشاط": نظري / عملي / تدريب
  final String section; // "شعبة"
  final String degree; // "الدرجة": البكالوريوس / دبلوم / دراسات عليا...
  final String t; // عمود "ت" كما يظهر بالتقرير (نص خام - معناه غير مؤكَّد بعد)
  final String supervisor; // "المشرف" - غالبًا فارغ، يظهر مع مقررات التدريب الميداني
  final String place; // "المقر": حوية غالبًا - القيمة البديلة تكشف مصدرًا خارجيًا
  final double load; // "عبء" لهذا الصف تحديدًا
  final int registered; // "مسجلين"
  final List<CourseMeeting> meetings;

  const TeachingLoadCourseRow({
    required this.courseCode,
    required this.courseName,
    required this.scheduleType,
    required this.activity,
    required this.section,
    required this.degree,
    required this.t,
    required this.supervisor,
    required this.place,
    required this.load,
    required this.registered,
    required this.meetings,
  });

  Map<String, dynamic> toJson() => {
        'courseCode': courseCode,
        'courseName': courseName,
        'scheduleType': scheduleType,
        'activity': activity,
        'section': section,
        'degree': degree,
        't': t,
        'supervisor': supervisor,
        'place': place,
        'load': load,
        'registered': registered,
        'meetings': meetings.map((m) => m.toJson()).toList(),
      };

  factory TeachingLoadCourseRow.fromJson(Map<String, dynamic> json) => TeachingLoadCourseRow(
        courseCode: json['courseCode'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        scheduleType: json['scheduleType'] as String? ?? '',
        activity: json['activity'] as String? ?? '',
        section: json['section'] as String? ?? '',
        degree: json['degree'] as String? ?? '',
        t: json['t'] as String? ?? '',
        supervisor: json['supervisor'] as String? ?? '',
        place: json['place'] as String? ?? '',
        load: (json['load'] as num?)?.toDouble() ?? 0,
        registered: json['registered'] as int? ?? 0,
        meetings: (json['meetings'] as List<dynamic>? ?? [])
            .map((m) => CourseMeeting.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// جدول محاضر رسمي كامل (صفحة واحدة بتقرير "جدول المحاضرين" - عمادة القبول
/// والتسجيل) لعضو هيئة تدريس واحد **بفصل دراسي واحد**. نفس العضو قد تتكرر له
/// عدة صفحات (فصول مختلفة) بنفس الملف المجمَّع - `docKey` يفرّق بينها.
class InstructorTeachingLoadReport {
  final String instructorName; // "المحاضر"
  final String staffNumber; // "رقم المنسوب"
  final String college; // "الكلية"
  final String department; // "القسم"
  final String rank; // "المرتبة"
  final String position; // "المنصب"
  final double load; // "العبء" الإجمالي
  final double maxLoad; // "عبء المرتبة" أو "أقصى العبء" (نفس المعنى، تسمية متغيّرة بالملف)
  final double extraHours; // "الساعات الإضافية"
  final double adminHours; // "ساعات عمل إداري"
  final double qualifyingHours; // "ساعات التاهيلي"
  final double developedTransferHours; // "انتساب مطور"
  final String semesterLabel; // نص الفصل والعام كما ورد بتذييل الصفحة، مثال: "الفصل الدراسي الأول للعام الجامعي 1447هـ"
  final DateTime? reportDate;
  final List<TeachingLoadCourseRow> courses;

  const InstructorTeachingLoadReport({
    required this.instructorName,
    required this.staffNumber,
    required this.college,
    required this.department,
    required this.rank,
    required this.position,
    required this.load,
    required this.maxLoad,
    required this.extraHours,
    required this.adminHours,
    required this.qualifyingHours,
    required this.developedTransferHours,
    required this.semesterLabel,
    required this.reportDate,
    required this.courses,
  });

  /// مفتاح فريد لكل (عضو + فصل دراسي) - وليس رقم المنسوب وحده، لأن الملف
  /// المجمَّع قد يحوي عدة فصول لنفس العضو (دليل فعلي من سليمان 2026-09-28).
  String get docKey => '${staffNumber}_${semesterLabel.trim()}'
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('/', '-');

  Map<String, dynamic> toJson() => {
        'instructorName': instructorName,
        'staffNumber': staffNumber,
        'college': college,
        'department': department,
        'rank': rank,
        'position': position,
        'load': load,
        'maxLoad': maxLoad,
        'extraHours': extraHours,
        'adminHours': adminHours,
        'qualifyingHours': qualifyingHours,
        'developedTransferHours': developedTransferHours,
        'semesterLabel': semesterLabel,
        'reportDate': reportDate?.toIso8601String(),
        'courses': courses.map((c) => c.toJson()).toList(),
      };

  factory InstructorTeachingLoadReport.fromJson(Map<String, dynamic> json) => InstructorTeachingLoadReport(
        instructorName: json['instructorName'] as String? ?? '',
        staffNumber: json['staffNumber'] as String? ?? '',
        college: json['college'] as String? ?? '',
        department: json['department'] as String? ?? '',
        rank: json['rank'] as String? ?? '',
        position: json['position'] as String? ?? '',
        load: (json['load'] as num?)?.toDouble() ?? 0,
        maxLoad: (json['maxLoad'] as num?)?.toDouble() ?? 0,
        extraHours: (json['extraHours'] as num?)?.toDouble() ?? 0,
        adminHours: (json['adminHours'] as num?)?.toDouble() ?? 0,
        qualifyingHours: (json['qualifyingHours'] as num?)?.toDouble() ?? 0,
        developedTransferHours: (json['developedTransferHours'] as num?)?.toDouble() ?? 0,
        semesterLabel: json['semesterLabel'] as String? ?? '',
        reportDate: json['reportDate'] == null ? null : DateTime.tryParse(json['reportDate'] as String),
        courses: (json['courses'] as List<dynamic>? ?? [])
            .map((c) => TeachingLoadCourseRow.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
