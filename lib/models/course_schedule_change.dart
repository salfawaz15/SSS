import 'package:cloud_firestore/cloud_firestore.dart';

enum CourseScheduleChangeType { added, removed, instructorChanged }

/// تغيير واحد مكتشَف تلقائيًا بين نسخة سابقة وجديدة من جدول المقررات لشطر
/// معيّن (إضافة شعبة/حذفها/تغيير عضو هيئة تدريس) - مخزَّن بشكل دائم/تراكمي
/// (كل رفعة تُضيف تغييراتها، لا استبدال) بنفس مبدأ AdvisorMovementRepository.
/// عدد الطلاب المسجَّلين **لا يُعتبر تغييرًا** أبدًا - تقلّبه طبيعي بين الرفعات.
class CourseScheduleChangeEntry {
  final CourseScheduleChangeType type;
  final String shatr;
  final String courseCode;
  final String courseName;
  final String section;
  final String dayTimeText;
  final String? instructorName;
  final String? previousInstructorName;
  final String note;
  final DateTime? detectedAt;

  const CourseScheduleChangeEntry({
    required this.type,
    required this.shatr,
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.dayTimeText,
    this.instructorName,
    this.previousInstructorName,
    required this.note,
    this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'shatr': shatr,
        'courseCode': courseCode,
        'courseName': courseName,
        'section': section,
        'dayTimeText': dayTimeText,
        'instructorName': instructorName,
        'previousInstructorName': previousInstructorName,
        'note': note,
        'detectedAt': FieldValue.serverTimestamp(),
      };

  factory CourseScheduleChangeEntry.fromDoc(Map<String, dynamic> json) => CourseScheduleChangeEntry(
        type: CourseScheduleChangeType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CourseScheduleChangeType.added,
        ),
        shatr: json['shatr'] as String? ?? '',
        courseCode: json['courseCode'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        section: json['section'] as String? ?? '',
        dayTimeText: json['dayTimeText'] as String? ?? '',
        instructorName: json['instructorName'] as String?,
        previousInstructorName: json['previousInstructorName'] as String?,
        note: json['note'] as String? ?? '',
        detectedAt: (json['detectedAt'] as Timestamp?)?.toDate(),
      );
}
