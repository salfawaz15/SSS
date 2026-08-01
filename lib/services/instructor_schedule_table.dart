import '../models/course_section_record.dart';

/// صف واحد جاهز للعرض في جدول عضو هيئة التدريس (على الشاشة أو في PDF)،
/// بنفس أعمدة الجدول الرسمي المعتمد في البوابة الإلكترونية للجامعة
/// (EduGate). يمثّل الصف مقررًا واحدًا (رمز/اسم يظهران مرة واحدة فقط)؛
/// عناصر النظري والعملي تظهران مدمجتين داخل بقية الأعمدة (النظري أعلى
/// والعملي أسفل) بلا تكرار الصف بالكامل - نفس فكرة جدول "جميع المقررات".
class InstructorScheduleRow {
  final String courseCode;
  final String courseName;
  final String theorySection;
  final int theoryHours;
  final String theoryDayName;
  final String theoryTimeRange;
  final String? practicalSection;
  final int practicalHours;
  final String? practicalDayName;
  final String? practicalTimeRange;

  const InstructorScheduleRow({
    required this.courseCode,
    required this.courseName,
    required this.theorySection,
    required this.theoryHours,
    required this.theoryDayName,
    required this.theoryTimeRange,
    this.practicalSection,
    this.practicalHours = 0,
    this.practicalDayName,
    this.practicalTimeRange,
  });

  bool get hasPractical => practicalSection != null;
}

class InstructorScheduleTable {
  static int? _minutesOf(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*([صم])$').firstMatch(raw.trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final isPm = match.group(3) == 'م';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  static int _sortKey(CourseMeeting m) => m.day * 24 * 60 + (_minutesOf(m.from) ?? 0);

  /// "لم يُحدَّد الوقت" - تُستخدم حين تكون الشعبة مسكَّنة (لها عضو هيئة
  /// تدريس) لكن لم يُسجَّل لها يوم/وقت بعد في نظام الجامعة (حالة نادرة).
  static const String noTimePlaceholder = 'لم يُحدَّد الوقت';

  static String _joinMeetings(List<CourseMeeting> meetings, String Function(CourseMeeting) map) {
    if (meetings.isEmpty) return noTimePlaceholder;
    final sorted = [...meetings]..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    return sorted.map(map).join('\n');
  }

  /// يُرجع صفًا واحدًا لكل مقرر (شعبة) مرتّبًا زمنيًا حسب أول موعد نظري
  /// (الأحد فالاثنين...حسب الوقت)، مع دمج النظري والعملي لنفس المقرر في
  /// نفس الصف بلا تكرار رمز/اسم المقرر. "غير مسكَّنة" تعني عدم وجود اسم عضو
  /// هيئة تدريس؛ العملي بلا محاضر خاص به يُستبعد من جدول هذا العضو (يُعامَل
  /// المقرر وكأن له شعبة نظري واحدة فقط)، لكن غياب اليوم/الوقت وحده لا
  /// يُخفي الشعبة - يظهر بدله "لم يُحدَّد الوقت".
  static List<InstructorScheduleRow> buildRows(List<CourseSectionRecord> records) {
    final sortedRecords = [...records]..sort((a, b) {
        final aKey = a.meetings.isEmpty ? 0 : a.meetings.map(_sortKey).reduce((x, y) => x < y ? x : y);
        final bKey = b.meetings.isEmpty ? 0 : b.meetings.map(_sortKey).reduce((x, y) => x < y ? x : y);
        return aKey.compareTo(bKey);
      });

    return [
      for (final r in sortedRecords)
        InstructorScheduleRow(
          courseCode: r.courseCode,
          courseName: r.courseName,
          theorySection: r.theorySection,
          theoryHours: r.theoryHours,
          theoryDayName: _joinMeetings(r.meetings, (m) => m.dayName),
          theoryTimeRange: _joinMeetings(r.meetings, (m) => '${m.from} - ${m.to}'),
          practicalSection: (r.practicalSection != null && r.practicalInstructorName != null) ? r.practicalSection : null,
          practicalHours: (r.practicalSection != null && r.practicalInstructorName != null) ? r.practicalHours : 0,
          practicalDayName: (r.practicalSection != null && r.practicalInstructorName != null)
              ? _joinMeetings(r.practicalMeetings, (m) => m.dayName)
              : null,
          practicalTimeRange: (r.practicalSection != null && r.practicalInstructorName != null)
              ? _joinMeetings(r.practicalMeetings, (m) => '${m.from} - ${m.to}')
              : null,
        ),
    ];
  }

  /// إجمالي الساعات المعتمدة: مجموع ساعات النظري والعملي لكل شعبة مرة واحدة
  /// (وليس لكل موعد أسبوعي)، تمامًا كما يُحسَب في الجدول الرسمي.
  static int totalCreditHours(List<CourseSectionRecord> records) {
    var total = 0;
    for (final r in records) {
      total += r.theoryHours + r.practicalHours;
    }
    return total;
  }
}
