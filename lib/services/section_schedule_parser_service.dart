import 'package:html/parser.dart' as html_parser;

import '../models/course_section_record.dart';
import 'windows1256_decoder.dart';

/// يقرأ ملف "الحوية" الذي يُصدَّر من نظام الجامعة الداخلي بامتداد .xls لكنه
/// فعليًا جدول HTML (Oracle Reports) بترميز Windows-1256.
///
/// يدمج تلقائيًا:
/// - شعبة نظري وشعبة عملي بنفس المقرر ونفس "التسلسل" في سجل واحد (لأن
///   الطالب يسجّل النظري فقط والعملي يُسجَّل تلقائيًا).
/// - الصفوف الفارغة (بلا رمز مقرر) التي تحمل يومًا/وقتًا إضافيًا فقط، بإضافتها
///   كموعد ثانٍ لنفس الشعبة بدل معاملتها كصف مستقل.
class SectionScheduleParserService {
  static final RegExp _courseCodePattern = RegExp(r'^\d+-\d+$');
  static final RegExp _timePattern = RegExp(r'^\d{1,2}:\d{2}\s*[صم]$');
  static final RegExp _dayPattern = RegExp(r'^[1-7]$');

  /// يُرجع قائمة الشعب الفعلية (بعد دمج نظري/عملي والمواعيد المتعددة).
  static List<CourseSectionRecord> parse(List<int> rawBytes) {
    final text = Windows1256Decoder.decode(rawBytes);
    final document = html_parser.parse(text);
    final rows = document.querySelectorAll('tr');

    // كل صف => قائمة نصوص الخلايا (SPAN) بالترتيب، بعد إزالة الفراغات الزائدة.
    final parsedRows = <List<String>>[];
    for (final tr in rows) {
      final spans = tr.querySelectorAll('span');
      final texts = <String>[];
      for (final s in spans) {
        var t = s.text.replaceAll(' ', ' ').trim();
        if (t.isNotEmpty) texts.add(t);
      }
      if (texts.isNotEmpty) parsedRows.add(texts);
    }

    // سجلات وسيطة قبل دمج نظري/عملي: مفتاحها (رمز المقرر، التسلسل، النشاط)
    final _RawActivityRow? Function(List<String>) tryParseMain = _parseMainRow;

    final activityRows = <_RawActivityRow>[];
    _RawActivityRow? lastRow;

    for (final cells in parsedRows) {
      final main = tryParseMain(cells);
      if (main != null) {
        activityRows.add(main);
        lastRow = main;
        continue;
      }
      // صف متابعة (يوم/وقت إضافي فقط) يخص آخر صف رئيسي.
      final meeting = _tryParseContinuationRow(cells);
      if (meeting != null && lastRow != null) {
        lastRow.meetings.add(meeting);
      }
    }

    // دمج نظري + عملي بنفس (رمز المقرر، التسلسل) في سجل واحد.
    final Map<String, _RawActivityRow> theoryByKey = {};
    final Map<String, _RawActivityRow> practicalByKey = {};
    for (final row in activityRows) {
      final key = '${row.courseCode}|${row.sequence}';
      if (row.activity == 'نظري') {
        theoryByKey[key] = row;
      } else if (row.activity == 'عملي') {
        practicalByKey[key] = row;
      }
    }

    final result = <CourseSectionRecord>[];
    for (final entry in theoryByKey.entries) {
      final theory = entry.value;
      final practical = practicalByKey[entry.key];

      // منظومة الجامعة الداخلية تُكرِّر إجمالي ساعات المقرر (عمود "س") على
      // صفّي النظري والعملي معًا بالخطأ (كلاهما يُظهر نفس القيمة، مثلًا 3)،
      // بدل تقسيمها الصحيح. التقسيم الصحيح - حسب توضيح المستخدم المطابق
      // للخطط الدراسية الرسمية 38/47 - هو: العملي = ساعة معتمدة واحدة دائمًا
      // (حتى لو دُرِّس زمنيًا لمدة ساعتين)، والنظري = الباقي من إجمالي ساعات
      // المقرر. لا نجمع قيمتي "س" كما وردتا لأن ذلك يُضاعف العدد خطأً.
      final totalHours = theory.hours;
      final theoryHours = practical != null ? (totalHours - 1).clamp(0, totalHours) : totalHours;
      final practicalHours = practical != null ? 1 : 0;

      result.add(CourseSectionRecord(
        courseCode: theory.courseCode,
        courseName: theory.courseName,
        sequence: theory.sequence,
        theorySection: theory.sectionNumber,
        practicalSection: practical?.sectionNumber,
        meetings: theory.meetings,
        practicalMeetings: practical?.meetings ?? const [],
        instructorName: theory.instructorName,
        practicalInstructorName: practical?.instructorName,
        theoryHours: theoryHours,
        practicalHours: practicalHours,
      ));
    }

    result.sort((a, b) {
      final c = a.courseCode.compareTo(b.courseCode);
      return c != 0 ? c : a.sequence.compareTo(b.sequence);
    });
    return result;
  }

  static _RawActivityRow? _parseMainRow(List<String> cells) {
    final codeIndex = cells.indexWhere((c) => _courseCodePattern.hasMatch(c));
    if (codeIndex < 1) return null; // لازم يسبقه رقم الشعبة

    final sectionNumber = cells[codeIndex - 1];
    if (int.tryParse(sectionNumber) == null) return null;

    final courseCode = cells[codeIndex].split('-').first;
    if (codeIndex + 3 >= cells.length) return null;
    final courseName = cells[codeIndex + 1];
    final hours = int.tryParse(cells[codeIndex + 2]) ?? 0;
    final activity = cells[codeIndex + 3];
    if (activity != 'نظري' && activity != 'عملي') return null;
    final sequence = (codeIndex + 4 < cells.length) ? int.tryParse(cells[codeIndex + 4]) ?? 0 : 0;

    final tail = cells.sublist((codeIndex + 5).clamp(0, cells.length));
    final meetings = <CourseMeeting>[];
    var i = 0;
    while (i < tail.length) {
      if (_dayPattern.hasMatch(tail[i]) &&
          i + 2 < tail.length &&
          _timePattern.hasMatch(tail[i + 1]) &&
          _timePattern.hasMatch(tail[i + 2])) {
        meetings.add(CourseMeeting(day: int.parse(tail[i]), from: tail[i + 1], to: tail[i + 2]));
        i += 3;
      } else {
        i += 1;
      }
    }

    String? instructorName;
    for (var j = 0; j < tail.length; j++) {
      if (tail[j].startsWith('(') && j > 0) {
        final candidate = tail[j - 1];
        final isJunk = candidate == 'نعم' ||
            candidate == 'لا' ||
            int.tryParse(candidate) != null ||
            _timePattern.hasMatch(candidate) ||
            _dayPattern.hasMatch(candidate);
        if (!isJunk) {
          instructorName = candidate;
        }
        break;
      }
    }
    // احتياطي: لا يوجد عمود "المستفيد" مملوء لهذا الصف (الجدول لم يُستكمل
    // بعد لهذه الشعبة) - نأخذ آخر نص عربي غير رقمي في ذيل الصف كاسم المحاضر.
    if (instructorName == null) {
      for (var j = tail.length - 1; j >= 0; j--) {
        final candidate = tail[j];
        if (candidate == 'نعم' || candidate == 'لا') continue;
        if (candidate.trim().isEmpty) continue;
        if (int.tryParse(candidate) != null) continue;
        if (candidate.startsWith('(')) continue; // خلية "المستفيد" (كلية ...) وليست اسم محاضر
        if (_timePattern.hasMatch(candidate) || _dayPattern.hasMatch(candidate)) continue;
        instructorName = candidate;
        break;
      }
    }

    instructorName = _stripTitlePrefix(instructorName);

    return _RawActivityRow(
      courseCode: courseCode,
      courseName: courseName,
      activity: activity,
      sequence: sequence,
      sectionNumber: sectionNumber,
      meetings: meetings,
      instructorName: instructorName,
      hours: hours,
    );
  }

  /// يحذف أي لقب (د./ د/ أ./ أ/ ا./ ا/) من بداية اسم المحاضر، حسب طلب المستخدم
  /// الصريح بعدم إظهار أي لقب قبل الأسماء في أي مكان بالتطبيق.
  static final RegExp _titlePrefixPattern = RegExp(r'^\s*[دأا][\.\/]\s*');
  static String? _stripTitlePrefix(String? name) {
    if (name == null) return null;
    return name.replaceFirst(_titlePrefixPattern, '').trim();
  }

  static CourseMeeting? _tryParseContinuationRow(List<String> cells) {
    if (cells.length != 3) return null;
    if (!_dayPattern.hasMatch(cells[0])) return null;
    if (!_timePattern.hasMatch(cells[1]) || !_timePattern.hasMatch(cells[2])) return null;
    return CourseMeeting(day: int.parse(cells[0]), from: cells[1], to: cells[2]);
  }
}

class _RawActivityRow {
  final String courseCode;
  final String courseName;
  final String activity;
  final int sequence;
  final String sectionNumber;
  final List<CourseMeeting> meetings;
  final String? instructorName;
  final int hours;

  _RawActivityRow({
    required this.courseCode,
    required this.courseName,
    required this.activity,
    required this.sequence,
    required this.sectionNumber,
    required this.meetings,
    required this.instructorName,
    required this.hours,
  });
}
