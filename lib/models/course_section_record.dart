/// موعد أسبوعي واحد لشعبة (يوم + وقت). المقرر قد يُدرَّس أكثر من يوم في
/// الأسبوع لنفس الشعبة، فتكون له أكثر من موعد.
class CourseMeeting {
  final int day; // 1=الأحد .. 5=الخميس
  final String from;
  final String to;

  const CourseMeeting({required this.day, required this.from, required this.to});

  static const List<String> dayNames = [
    '', // لا يوجد يوم رقم 0
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
  ];

  String get dayName => (day >= 1 && day <= 5) ? dayNames[day] : 'يوم غير معروف ($day)';

  Map<String, dynamic> toJson() => {'day': day, 'from': from, 'to': to};

  factory CourseMeeting.fromJson(Map<String, dynamic> json) => CourseMeeting(
        day: json['day'] as int,
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
      );
}

/// شعبة فعلية واحدة لمقرر (نظري، مرتبط بشعبة عملي إن وُجدت بنفس التسلسل).
class CourseSectionRecord {
  final String courseCode; // رمز المقرر بلا "-N" الساعات، مثل 601201
  final String courseName;
  final int sequence; // التسلسل
  final String theorySection; // رقم الشعبة النظرية - هي ما يُسجَّله الطالب
  final String? practicalSection; // رقم الشعبة العملية المرتبطة (إن وُجدت)
  final List<CourseMeeting> meetings; // مواعيد الشعبة النظرية
  final List<CourseMeeting> practicalMeetings; // مواعيد الشعبة العملية (لجدول المحاضر فقط)
  final String? instructorName; // محاضر الشعبة النظرية
  final String? practicalInstructorName; // محاضر الشعبة العملية (قد يختلف عن محاضر النظري)
  final int theoryHours; // عدد الساعات المعتمدة لنشاط النظري (من عمود "الساعات" في الملف)
  final int practicalHours; // عدد الساعات المعتمدة لنشاط العملي (0 إن لم توجد شعبة عملية)

  const CourseSectionRecord({
    required this.courseCode,
    required this.courseName,
    required this.sequence,
    required this.theorySection,
    this.practicalSection,
    required this.meetings,
    this.practicalMeetings = const [],
    this.instructorName,
    this.practicalInstructorName,
    this.theoryHours = 0,
    this.practicalHours = 0,
  });

  Map<String, dynamic> toJson() => {
        'courseCode': courseCode,
        'courseName': courseName,
        'sequence': sequence,
        'theorySection': theorySection,
        'practicalSection': practicalSection,
        'meetings': meetings.map((m) => m.toJson()).toList(),
        'practicalMeetings': practicalMeetings.map((m) => m.toJson()).toList(),
        'instructorName': instructorName,
        'practicalInstructorName': practicalInstructorName,
        'theoryHours': theoryHours,
        'practicalHours': practicalHours,
      };

  factory CourseSectionRecord.fromJson(Map<String, dynamic> json) => CourseSectionRecord(
        courseCode: json['courseCode'] as String,
        courseName: json['courseName'] as String,
        sequence: json['sequence'] as int,
        theorySection: json['theorySection'] as String,
        practicalSection: json['practicalSection'] as String?,
        meetings: (json['meetings'] as List<dynamic>? ?? [])
            .map((m) => CourseMeeting.fromJson(m as Map<String, dynamic>))
            .toList(),
        practicalMeetings: (json['practicalMeetings'] as List<dynamic>? ?? [])
            .map((m) => CourseMeeting.fromJson(m as Map<String, dynamic>))
            .toList(),
        instructorName: json['instructorName'] as String?,
        practicalInstructorName: json['practicalInstructorName'] as String?,
        theoryHours: json['theoryHours'] as int? ?? 0,
        practicalHours: json['practicalHours'] as int? ?? 0,
      );
}
