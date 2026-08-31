import 'dart:convert';

import '../models/course_section_record.dart';
import 'course_schedule_repository.dart' show Shatr;
import 'docx_schedule_parser_service.dart' show ParsedCourseSectionWithShatr;
import 'windows1256_decoder.dart';

/// يقرأ جدول "الحويّة" من تصدير CSV المباشر للمنظومة الداخلية (Windows-1256،
/// فاصل ";") بدل تحويله لـWord أو PDF أولًا - أبسط وأدق من كليهما لأن الفواصل
/// صريحة وثابتة العدد بالملف (24 خلية لكل صف)، لا مُستنتَجة هندسيًا من مواضع
/// كلمات كما في [PdfScheduleParserService]. اختبرته أداة معاينة مستقلة
/// (Artifact) قبل هذا الكود على ملف حقيقي (سليمان 2026-08-27): 127 مقررًا،
/// 321 شعبة، 12581 مسجَّلًا، مطابقة تامة لعينة يدوية من الملف الخام.
///
/// **بنية الملف** (كل صف بفاصل ";"، الخلية الأولى دومًا فارغة):
/// عمود[1]=الشعبة، [4]=رمز المقرر-عدد الساعات (مثال "601201-3")، [5]=اسم
/// المقرر، [6]=الساعات، [7]=النشاط (نظري/عملي)، [9]=التسلسل، [10]=اعلى حد،
/// [12]=المسجلين، [13]=اليوم، [15]=من، [16]=إلى، [17]=القاعة، [20]=المحاضر،
/// [21]=المستفيد، [22]=جاهزة.
///
/// **شُعب متعددة الأيام**: الموعد الثاني (وما بعده) لنفس الشعبة يظهر بصف
/// منفصل بلا رقم شعبة (عمود[1] فارغ) وبعمود اليوم[13] فقط معبَّأ - يُلحَق
/// بمواعيد آخر شعبة صودفت، **حتى عبر فاصل صفحة** (رأس "المقر :" يتكرر كل صفحة
/// بالملف بلا إعادة ضبط "آخر شعبة" - وإلا انقطع موعد شعبة حقيقي عبَرت صفحتين).
///
/// الشطر يُمرَّر افتراضيًا عبر [shatr] (يُستدَلّ عليه من اسم الملف عادةً، لأن
/// أغلب ملفات هذه المنظومة منفصلة أصلًا لكل شطر)، لكنه يُحدَّث تلقائيًا من نص
/// خانة "المقر" داخل الملف نفسه إن ذُكرت كلمة "طالبات"/"طلاب" - لدعم الملفات
/// النادرة التي تدمج الشطرين معًا (انظر التعليق داخل [parseSectionsWithShatr]).
class CsvScheduleParserService {
  static const List<String> _theoryActivity = ['نظري'];
  static const List<String> _practicalActivity = ['عملي'];

  static List<ParsedCourseSectionWithShatr> parseSectionsWithShatr(List<int> csvBytes, {Shatr? shatr}) {
    final text = Windows1256Decoder.decode(csvBytes);
    final activityRows = <_RawRow>[];
    _RawRow? lastRow;
    // بعض الملفات تصدَّر بشطر واحد فقط لكل ملف (يُستدَلّ عليه من اسم الملف عبر
    // [shatr] الممرَّر)، لكن أخرى ("...مستفيد شطرين...") تدمج الشطرين معًا
    // بملف واحد - يُميَّز كل قسم بنص خانة "المقر :" المتكرر كل صفحة: "حويّة
    // طالبات" للطالبات، و"حويّة" وحدها (بلا كلمة جندرية) للطلاب - سليمان
    // صراحةً (2026-08-31، ملف حقيقي "دراسي مستفيد شطرين"). يبدأ بالشطر
    // الممرَّر افتراضيًا ويُحدَّث كل مرة تُصادَف فيها خانة "المقر" جديدة.
    Shatr? currentShatr = shatr;

    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty || !line.contains(';')) continue;
      // المسافات داخل بعض الخلايا (مثال: "المستفيد") تخرج أحيانًا كمسافة
      // غير فاصلة (NBSP، U+00A0) لا مسافة عادية - تُوحَّد هنا وإلا فشلت كل
      // مطابقة نصية تحوي أكثر من كلمة (مثال حقيقي: "كلية إدارة الأعمال" لم
      // تُطابَق رغم تطابق كل كلمة على حدة - سليمان 2026-08-27).
      final cells = line.split(';').map((c) => c.trim().replaceAll('\u00A0', ' ')).toList();
      String at(int i) => i < cells.length ? cells[i] : '';

      if (at(1).contains('المقر')) {
        final label = at(3);
        if (label.contains('طالبات')) {
          currentShatr = Shatr.female;
        } else if (label.contains('طلاب')) {
          currentShatr = Shatr.male;
        } else if (label.isNotEmpty) {
          currentShatr = Shatr.male;
        }
        continue;
      }
      if (at(1) == 'الشعبة' || (at(1).isEmpty && at(13) == 'الأيام')) continue;
      if (cells.every((c) => c.isEmpty)) continue;

      final section = at(1);
      final courseCodeRaw = at(4);
      final hasSectionRow = section.isNotEmpty && courseCodeRaw.isNotEmpty;

      if (hasSectionRow) {
        final activity = at(7);
        final day = int.tryParse(at(13));
        final from = at(15);
        final to = at(16);
        final room = _normalizeRoom(at(17));
        final meetings = <CourseMeeting>[];
        if (day != null && day >= 1 && day <= 7 && from.isNotEmpty && to.isNotEmpty) {
          meetings.add(CourseMeeting(day: day, from: from, to: to, room: room));
        }

        final row = _RawRow(
          courseCode: courseCodeRaw.split('-').first,
          courseName: at(5),
          activity: activity,
          sequence: int.tryParse(at(9)) ?? 0,
          sectionNumber: section,
          meetings: meetings,
          instructorName: at(20).isEmpty ? null : at(20),
          hours: int.tryParse(at(6)) ?? 0,
          registered: int.tryParse(at(12)) ?? 0,
          maxCapacity: int.tryParse(at(10)) ?? 0,
          beneficiary: at(21),
          shatr: currentShatr,
        );
        activityRows.add(row);
        lastRow = row;
        continue;
      }

      // صف متابعة: موعد إضافي لآخر شعبة صودفت (قد تكون بصفحة سابقة).
      final day = int.tryParse(at(13));
      final from = at(15);
      final to = at(16);
      if (lastRow != null && day != null && day >= 1 && day <= 7 && from.isNotEmpty && to.isNotEmpty) {
        lastRow.meetings.add(CourseMeeting(day: day, from: from, to: to, room: _normalizeRoom(at(17))));
      }
    }

    final Map<String, _RawRow> theoryByKey = {};
    final Map<String, _RawRow> practicalByKey = {};
    for (final row in activityRows) {
      final key = '${row.courseCode}|${row.sequence}|${row.beneficiary}';
      if (_theoryActivity.contains(row.activity)) {
        theoryByKey[key] = row;
      } else if (_practicalActivity.contains(row.activity)) {
        practicalByKey[key] = row;
      }
    }

    final result = <ParsedCourseSectionWithShatr>[];
    for (final entry in theoryByKey.entries) {
      final theory = entry.value;
      final practical = practicalByKey[entry.key];

      final totalHours = theory.hours;
      final theoryHours = practical != null ? (totalHours - 1).clamp(0, totalHours) : totalHours;
      final practicalHours = practical != null ? 1 : 0;

      result.add(ParsedCourseSectionWithShatr(
        beneficiary: theory.beneficiary,
        shatr: theory.shatr,
        record: CourseSectionRecord(
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
          theoryMaxCapacity: theory.maxCapacity,
          theoryRegistered: theory.registered,
          practicalMaxCapacity: practical?.maxCapacity,
          practicalRegistered: practical?.registered,
        ),
      ));
    }

    result.sort((a, b) {
      final c = a.record.courseCode.compareTo(b.record.courseCode);
      return c != 0 ? c : a.record.sequence.compareTo(b.record.sequence);
    });
    return result;
  }

  static String _normalizeRoom(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (s.contains('أونلاين') || s.contains('اونلاين') || s.contains('أون لاي')) return 'أونلاين';
    if (s.contains('عن بعد')) return 'عن بعد';
    s = s.replaceAll(RegExp(r'[()]*حضوري[()]*'), '').trim();
    s = s.replaceAll(RegExp(r'^[()]+|[()]+$'), '').trim();
    return s;
  }
}

class _RawRow {
  final String courseCode;
  final String courseName;
  final String activity;
  final int sequence;
  final String sectionNumber;
  final List<CourseMeeting> meetings;
  final String? instructorName;
  final int hours;
  final int registered;
  final int maxCapacity;
  final String beneficiary;
  final Shatr? shatr;

  _RawRow({
    required this.courseCode,
    required this.courseName,
    required this.activity,
    required this.sequence,
    required this.sectionNumber,
    required this.meetings,
    required this.instructorName,
    required this.hours,
    required this.registered,
    required this.maxCapacity,
    required this.beneficiary,
    this.shatr,
  });
}
