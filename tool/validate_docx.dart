import 'dart:io';
import 'package:sulaiman/services/docx_schedule_parser_service.dart';

void main() {
  final bytes = File(r'المرفقات\المواد\جداول الاقسام-الفصل الدراسي الأول 1448هـ 1\الحوية-طلاب.docx').readAsBytesSync();
  final records = DocxScheduleParserService.parse(bytes);
  final exportDate = DocxScheduleParserService.extractExportDate(bytes);
  print('exportDate: $exportDate');
  print('total records: ${records.length}');

  for (final r in records) {
    if (r.courseCode == '6603241' && (r.theorySection == '1349' || r.theorySection == '1354' || r.theorySection == '1371')) {
      print('${r.courseCode} seq${r.sequence} theory=${r.theorySection} practical=${r.practicalSection} '
          'theoryHours=${r.theoryHours} practicalHours=${r.practicalHours} instructor=${r.instructorName} '
          'meetings=${r.meetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join(',')} '
          'practicalMeetings=${r.practicalMeetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join(',')}');
    }
    if (r.courseCode == '6603313' && r.theorySection == '1802') {
      print('${r.courseCode} seq${r.sequence} theory=${r.theorySection} practical=${r.practicalSection} '
          'instructor=${r.instructorName} practicalInstructor=${r.practicalInstructorName} '
          'meetings=${r.meetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join(',')} '
          'practicalMeetings=${r.practicalMeetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join(',')}');
    }
  }
}
