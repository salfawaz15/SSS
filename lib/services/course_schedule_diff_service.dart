import '../models/course_schedule_change.dart';
import '../models/course_section_record.dart';

/// يقارن نسخة سابقة وأخرى جديدة من جدول مقررات شطر واحد، ويُنتج قائمة
/// تغييرات (إضافة شعبة/حذفها/تغيير عضو هيئة تدريس) - مفتاح المطابقة هو
/// "رمز المقرر + رقم الشعبة النظرية" (ما يسجّله الطالب فعليًا). عدد الطلاب
/// المسجَّلين وأعلى حد **لا يُقارَنان أبدًا** - تقلّبهما طبيعي بين الرفعات
/// ولا يُعتبر تغييرًا يستحق تسجيلًا.
class CourseScheduleDiffService {
  static String _key(CourseSectionRecord r) => '${r.courseCode}|${r.theorySection}';

  static String _dayTimeText(CourseSectionRecord r) {
    if (r.meetings.isEmpty) return 'بلا موعد محدَّد';
    return r.meetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join('، ');
  }

  static List<CourseScheduleChangeEntry> diff({
    required String shatrLabel,
    required List<CourseSectionRecord> previous,
    required List<CourseSectionRecord> current,
  }) {
    final previousByKey = {for (final r in previous) _key(r): r};
    final currentByKey = {for (final r in current) _key(r): r};
    final changes = <CourseScheduleChangeEntry>[];

    for (final entry in currentByKey.entries) {
      final old = previousByKey[entry.key];
      final r = entry.value;
      final dayTime = _dayTimeText(r);
      if (old == null) {
        changes.add(CourseScheduleChangeEntry(
          type: CourseScheduleChangeType.added,
          shatr: shatrLabel,
          courseCode: r.courseCode,
          courseName: r.courseName,
          section: r.theorySection,
          dayTimeText: dayTime,
          instructorName: r.instructorName,
          note: 'تمت إضافة شعبة رقم ${r.theorySection} (${r.courseName}) - $dayTime'
              '${r.instructorName != null ? '، سُكِّنت لـ ${r.instructorName}' : ''}.',
        ));
        continue;
      }
      if ((old.instructorName ?? '').trim() != (r.instructorName ?? '').trim()) {
        changes.add(CourseScheduleChangeEntry(
          type: CourseScheduleChangeType.instructorChanged,
          shatr: shatrLabel,
          courseCode: r.courseCode,
          courseName: r.courseName,
          section: r.theorySection,
          dayTimeText: dayTime,
          instructorName: r.instructorName,
          previousInstructorName: old.instructorName,
          note: 'تم تغيير عضو هيئة التدريس للشعبة رقم ${r.theorySection} (${r.courseName}) '
              'من "${old.instructorName ?? 'بلا محاضر'}" إلى "${r.instructorName ?? 'بلا محاضر'}".',
        ));
      }
      if ((old.practicalInstructorName ?? '').trim() != (r.practicalInstructorName ?? '').trim() &&
          (r.practicalSection != null || old.practicalSection != null)) {
        changes.add(CourseScheduleChangeEntry(
          type: CourseScheduleChangeType.instructorChanged,
          shatr: shatrLabel,
          courseCode: r.courseCode,
          courseName: r.courseName,
          section: r.practicalSection ?? old.practicalSection ?? r.theorySection,
          dayTimeText: dayTime,
          instructorName: r.practicalInstructorName,
          previousInstructorName: old.practicalInstructorName,
          note: 'تم تغيير عضو هيئة التدريس (عملي) للشعبة رقم ${r.practicalSection ?? old.practicalSection} (${r.courseName}) '
              'من "${old.practicalInstructorName ?? 'بلا محاضر'}" إلى "${r.practicalInstructorName ?? 'بلا محاضر'}".',
        ));
      }
    }

    for (final entry in previousByKey.entries) {
      if (currentByKey.containsKey(entry.key)) continue;
      final r = entry.value;
      changes.add(CourseScheduleChangeEntry(
        type: CourseScheduleChangeType.removed,
        shatr: shatrLabel,
        courseCode: r.courseCode,
        courseName: r.courseName,
        section: r.theorySection,
        dayTimeText: _dayTimeText(r),
        instructorName: r.instructorName,
        note: 'تم حذف الشعبة رقم ${r.theorySection} (${r.courseName}).',
      ));
    }

    return changes;
  }
}
