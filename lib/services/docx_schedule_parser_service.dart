import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/course_section_record.dart';
import 'course_schedule_repository.dart' show Shatr;

const String _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// "المقر" بلا "ر" بعدها مباشرة - يستثني تطابقها الزائف داخل كلمة "المقرر".
final RegExp _mmaqarPattern = RegExp('المقر(?!ر)');

/// يقرأ جدول "الحويّة" بعد تحويله من PDF إلى Word (.docx) - بديل موثوق تمامًا
/// لملف الإكسل (.xls) الذي يفقد بيانات حقيقية أحيانًا بسبب طريقة تصديره من
/// منظومة الجامعة الداخلية. تحويل PDF إلى Word (عبر برنامج Word نفسه) يحافظ
/// على كل البيانات دون نقصان.
///
/// ملاحظة فنية مهمة: عند تحويل PDF إلى Word، تُخزَّن قيم الوقت (التي تحوي
/// نقطتين ":") بترتيب أرقام معكوس بالكامل بسبب معالجة النص ثنائي الاتجاه في
/// Word (مثلًا "08:00" تصبح "00:80")، بينما بقية الأرقام (رمز المقرر، رقم
/// الشعبة، رقم المحاضر) تبقى صحيحة بلا انعكاس. يُصحَّح هذا تلقائيًا هنا.
class DocxScheduleParserService {
  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

  static String _toWestern(String s) {
    final buffer = StringBuffer();
    for (final ch in s.runes) {
      final idx = _arabicDigits.indexOf(String.fromCharCode(ch));
      buffer.write(idx == -1 ? String.fromCharCode(ch) : idx.toString());
    }
    return buffer.toString();
  }

  static final RegExp _timePattern = RegExp(r'^(\d{2}):(\d{2})\s*([صم])$');
  static final RegExp _dayPattern = RegExp(r'^[1-7]$');

  /// يُصلح انعكاس أرقام الوقت الناتج عن تحويل Word (انظر التعليق أعلى الصنف).
  static String _fixTimeValue(String raw) {
    final match = _timePattern.firstMatch(raw.trim());
    if (match == null) return raw.trim();
    final digits = '${match.group(1)}${match.group(2)}'.split('').reversed.join();
    final fixed = '${digits.substring(0, 2)}:${digits.substring(2, 4)}';
    return '$fixed ${match.group(3)}';
  }

  static String _cellText(XmlElement tc) {
    final buffer = StringBuffer();
    for (final t in tc.findAllElements('t', namespace: _wNs)) {
      buffer.write(t.innerText);
    }
    return _toWestern(buffer.toString()).trim();
  }

  /// تاريخ سحب البيانات من المنظومة الداخلية (كما يظهر أعلى كل صفحة في
  /// الملف الأصلي)، لمقارنته عند كل رفعة جديدة والتأكد أنها أحدث من السابقة.
  static DateTime? extractExportDate(List<int> docxBytes) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    for (final name in ['word/header1.xml', 'word/header2.xml', 'word/header3.xml']) {
      ArchiveFile? file;
      for (final f in archive.files) {
        if (f.name == name) {
          file = f;
          break;
        }
      }
      if (file == null) continue;
      final xmlStr = utf8.decode(file.content as List<int>);
      final doc = XmlDocument.parse(xmlStr);
      final texts = doc.findAllElements('t', namespace: _wNs).map((t) => t.innerText).toList();
      // ترتيب النصوص الفعلي في رأس الصفحة: "Date :" ثم "Page :" ثم التاريخ
      // الهجري ثم التاريخ الميلادي (وهو المطلوب هنا).
      final dateLabelIndex = texts.indexOf('Date :');
      if (dateLabelIndex != -1 && dateLabelIndex + 3 < texts.length) {
        final raw = _toWestern(texts[dateLabelIndex + 3]).trim(); // مثل 28-07-2026
        final parts = raw.split('-');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            return DateTime(year, month, day);
          }
        }
      }
    }
    return null;
  }

  /// يُرجع كل شعب الجدول من ملف .docx (نفس مخرجات SectionScheduleParserService
  /// لكن من مصدر Word بدل HTML).
  static List<CourseSectionRecord> parse(List<int> docxBytes) =>
      parseSections(docxBytes).map((s) => s.record).toList();

  /// كـ[parse] لكنه يحتفظ بعمود "المستفيد" الخام لكل شعبة - يُستخدم لتصنيف
  /// شعب ملف "الحويّة" الشامل تلقائيًا حسب الكلية المستفيدة عند رفعه دفعة
  /// واحدة (بدل الاعتماد على أن يكون الملف مُصفّى مسبقًا لكليتنا فقط).
  static List<ParsedCourseSection> parseSections(List<int> docxBytes) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    final xmlStr = utf8.decode(docFile.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);

    final rows = <List<String>>[];
    for (final tr in doc.findAllElements('tr', namespace: _wNs)) {
      final cells = tr.findAllElements('tc', namespace: _wNs).map(_cellText).toList();
      if (cells.isNotEmpty) rows.add(cells);
    }

    // ترتيب الأعمدة الثابت في جدول Word الناتج عن تحويل PDF (تحقّقنا منه
    // يدويًا): فترة الاختبار، جاهزة، المستفيد، المحاضر، رقم المحاضر، إلى،
    // من، الأيام، المسجلين، اعلى حد، التسلسل، النشاط، س، اسم المقرر، المقرر، الشعبة.
    const colTo = 5, colFrom = 6, colDay = 7, colRegistered = 8, colMaxCapacity = 9;
    const colSequence = 10, colActivity = 11;
    const colHours = 12, colCourseName = 13, colCourseCode = 14, colSection = 15;
    const colInstructor = 3;
    const colBeneficiary = 2;

    final activityRows = <_RawActivityRow>[];
    _RawActivityRow? lastRow;

    for (final cells in rows) {
      if (cells.length < 16) continue;
      final activity = cells[colActivity];
      final isMain = activity == 'نظري' || activity == 'عملي';

      if (isMain && cells[colCourseCode].contains('-') && cells[colSection].isNotEmpty) {
        final courseCode = cells[colCourseCode].split('-').first;
        final sectionNumber = cells[colSection];
        final sequence = int.tryParse(cells[colSequence]) ?? 0;
        final hours = int.tryParse(cells[colHours]) ?? 0;
        final registered = int.tryParse(cells[colRegistered]) ?? 0;
        final maxCapacity = int.tryParse(cells[colMaxCapacity]) ?? 0;
        final meetings = <CourseMeeting>[];
        final day = int.tryParse(cells[colDay]);
        final from = cells[colFrom];
        final to = cells[colTo];
        if (day != null && _dayPattern.hasMatch('$day') && from.isNotEmpty && to.isNotEmpty) {
          meetings.add(CourseMeeting(day: day, from: _fixTimeValue(from), to: _fixTimeValue(to)));
        }
        var instructorName = cells[colInstructor].isEmpty ? null : cells[colInstructor];
        instructorName = _stripTitlePrefix(instructorName);

        final row = _RawActivityRow(
          courseCode: courseCode,
          courseName: cells[colCourseName],
          activity: activity,
          sequence: sequence,
          sectionNumber: sectionNumber,
          meetings: meetings,
          instructorName: instructorName,
          hours: hours,
          registered: registered,
          maxCapacity: maxCapacity,
          beneficiary: cells[colBeneficiary],
        );
        activityRows.add(row);
        lastRow = row;
      } else if (lastRow != null) {
        // صف متابعة: يوم/وقت إضافي فقط لآخر شعبة رئيسية (بلا رمز مقرر جديد).
        final day = int.tryParse(cells[colDay]);
        final from = cells[colFrom];
        final to = cells[colTo];
        if (day != null && _dayPattern.hasMatch('$day') && from.isNotEmpty && to.isNotEmpty) {
          lastRow.meetings.add(CourseMeeting(day: day, from: _fixTimeValue(from), to: _fixTimeValue(to)));
        }
      }
    }

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

    final result = <ParsedCourseSection>[];
    for (final entry in theoryByKey.entries) {
      final theory = entry.value;
      final practical = practicalByKey[entry.key];

      final totalHours = theory.hours;
      final theoryHours = practical != null ? (totalHours - 1).clamp(0, totalHours) : totalHours;
      final practicalHours = practical != null ? 1 : 0;

      result.add(ParsedCourseSection(
        beneficiary: theory.beneficiary,
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

  static final RegExp _titlePrefixPattern = RegExp(r'^\s*[دأا][\.\/]\s*');
  static String? _stripTitlePrefix(String? name) {
    if (name == null) return null;
    return name.replaceFirst(_titlePrefixPattern, '').trim();
  }

  /// كـ[parseSections] لكن لملف Word ناتج عن تحويل PDF **يحوي الشطرين معًا**
  /// (لا ملفًا مفصولاً مسبقًا لشطر واحد) - يحدَّد شطر كل شعبة تلقائيًا من
  /// حقل "المقر" الذي يتكرر كنص عادي داخل تدفّق محتوى المستند نفسه (ليس رأس
  /// صفحة Word حقيقي - أول محاولة اعتمدت على رؤوس الأقسام `sectPr` فشلت
  /// تمامًا: 359 شعبة كلها بلا شطر محدَّد، لأن أداة تحويل PDF إلى Word لا
  /// تستخدم آلية الرؤوس الحقيقية بل تكتب كل شيء كفقرات/جداول متتالية بنفس
  /// تدفّق المستند - سليمان صراحةً بعد نتيجة التجربة الأولى 2026-08-17): كل
  /// فقرة أو صف جدول يحوي "المقر" يُحدِّث الشطر الحالي فورًا ("طالبات" ضمن
  /// النص = شطر طالبات، وإلا فطلاب)، ويُطبَّق هذا الشطر على كل صفوف الجدول
  /// التالية حتى ظهور "المقر" التالي.
  /// [debugMarkers] معامل تشخيصي اختياري - إن مُرِّر، تُضاف إليه كل النصوص
  /// الخام التي احتوت "المقر" فعليًا كما استُخرجت من الملف (بلا أي معالجة)،
  /// حتى نرى بالضبط شكل النص الذي تنتجه أداة تحويل PDF إلى Word - ضروري
  /// لتشخيص سبب عدم اكتشاف "طالبات" إطلاقًا رغم اكتشاف "المقر" (سليمان
  /// صراحةً 2026-08-17 بعد نتيجة 0 شعبة طالبات من إجمالي 3017 سطر).
  static List<ParsedCourseSectionWithShatr> parseSectionsWithShatr(
    List<int> docxBytes, {
    List<String>? debugMarkers,
  }) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    ArchiveFile? findFile(String name) {
      for (final f in archive.files) {
        if (f.name == name) return f;
      }
      return null;
    }

    final docFile = findFile('word/document.xml');
    if (docFile == null) return const [];
    final doc = XmlDocument.parse(utf8.decode(docFile.content as List<int>));

    final bodies = doc.findAllElements('body', namespace: _wNs);
    if (bodies.isEmpty) return const [];
    final body = bodies.first;

    Shatr? shatrFromText(String text) {
      // "المقر" بلا الحرف "ر" بعدها مباشرة - وإلا فهي جزء من "المقرر" (عمود
      // "اسم المقرر" برأس كل جدول مواد بكل صفحة)، وهو تطابق زائف كان يُعيد
      // تصنيف الشطر خطأً لـ"طلاب" فور كل صف رأس جدول، فيمحو تصنيف "طالبات"
      // الصحيح المكتشَف للتو (دليل فعلي من نص خام أرسله سليمان 2026-08-17).
      if (!_mmaqarPattern.hasMatch(text)) return null;
      if (debugMarkers != null && debugMarkers.length < 20 && !debugMarkers.contains(text)) {
        debugMarkers.add(text);
      }
      return text.contains('طالبات') ? Shatr.female : Shatr.male;
    }

    final rows = <List<String>>[];
    final rowShatr = <Shatr?>[];
    Shatr? currentShatr;

    void scanParagraph(XmlElement p) {
      final text = p.findAllElements('t', namespace: _wNs).map((t) => t.innerText).join();
      final detected = shatrFromText(text);
      if (detected != null) currentShatr = detected;
    }

    void scanTable(XmlElement tbl) {
      for (final tr in tbl.findAllElements('tr', namespace: _wNs)) {
        final cells = tr.findAllElements('tc', namespace: _wNs).map(_cellText).toList();
        if (cells.isEmpty) continue;
        final rowText = cells.join(' ');
        final detected = shatrFromText(rowText);
        if (detected != null) {
          currentShatr = detected;
          continue; // صف معلومات ("المقر") وليس صف مادة فعلي - لا يُضاف كبيانات
        }
        rows.add(cells);
        rowShatr.add(currentShatr);
      }
    }

    void walk(XmlElement el) {
      for (final child in el.childElements) {
        if (child.name.local == 'tbl') {
          scanTable(child);
        } else if (child.name.local == 'p') {
          scanParagraph(child);
        } else {
          walk(child); // بعض أدوات التحويل تُغلِّف المحتوى بعناصر وسيطة (مثل sdt)
        }
      }
    }

    walk(body);

    const colTo = 5, colFrom = 6, colDay = 7, colRegistered = 8, colMaxCapacity = 9;
    const colSequence = 10, colActivity = 11;
    const colHours = 12, colCourseName = 13, colCourseCode = 14, colSection = 15;
    const colInstructor = 3;
    const colBeneficiary = 2;

    final activityRows = <_RawActivityRow>[];
    _RawActivityRow? lastRow;

    for (var i = 0; i < rows.length; i++) {
      final cells = rows[i];
      final shatr = rowShatr[i];
      if (cells.length < 16) continue;
      final activity = cells[colActivity];
      final isMain = activity == 'نظري' || activity == 'عملي';

      if (isMain && cells[colCourseCode].contains('-') && cells[colSection].isNotEmpty) {
        final courseCode = cells[colCourseCode].split('-').first;
        final sectionNumber = cells[colSection];
        final sequence = int.tryParse(cells[colSequence]) ?? 0;
        final hours = int.tryParse(cells[colHours]) ?? 0;
        final registered = int.tryParse(cells[colRegistered]) ?? 0;
        final maxCapacity = int.tryParse(cells[colMaxCapacity]) ?? 0;
        final meetings = <CourseMeeting>[];
        final day = int.tryParse(cells[colDay]);
        final from = cells[colFrom];
        final to = cells[colTo];
        if (day != null && _dayPattern.hasMatch('$day') && from.isNotEmpty && to.isNotEmpty) {
          meetings.add(CourseMeeting(day: day, from: _fixTimeValue(from), to: _fixTimeValue(to)));
        }
        var instructorName = cells[colInstructor].isEmpty ? null : cells[colInstructor];
        instructorName = _stripTitlePrefix(instructorName);

        final row = _RawActivityRow(
          courseCode: courseCode,
          courseName: cells[colCourseName],
          activity: activity,
          sequence: sequence,
          sectionNumber: sectionNumber,
          meetings: meetings,
          instructorName: instructorName,
          hours: hours,
          registered: registered,
          maxCapacity: maxCapacity,
          beneficiary: cells[colBeneficiary],
          shatr: shatr,
        );
        activityRows.add(row);
        lastRow = row;
      } else if (lastRow != null) {
        final day = int.tryParse(cells[colDay]);
        final from = cells[colFrom];
        final to = cells[colTo];
        if (day != null && _dayPattern.hasMatch('$day') && from.isNotEmpty && to.isNotEmpty) {
          lastRow.meetings.add(CourseMeeting(day: day, from: _fixTimeValue(from), to: _fixTimeValue(to)));
        }
      }
    }

    final Map<String, _RawActivityRow> theoryByKey = {};
    final Map<String, _RawActivityRow> practicalByKey = {};
    for (final row in activityRows) {
      final key = '${row.courseCode}|${row.sequence}|${row.shatr}';
      if (row.activity == 'نظري') {
        theoryByKey[key] = row;
      } else if (row.activity == 'عملي') {
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
  final int registered;
  final int maxCapacity;
  final String beneficiary;
  final Shatr? shatr;

  _RawActivityRow({
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

/// شعبة مُستخرَجة مع عمود "المستفيد" الخام (اسم الكلية المستفيدة كما ورد
/// بالملف) - يُستخدم لتصنيف الشعب تلقائيًا (شعب كليتنا مقابل شعب كليات
/// أخرى) عند رفع ملف "الحويّة" الشامل لكل الجامعة دفعة واحدة.
class ParsedCourseSection {
  final CourseSectionRecord record;
  final String beneficiary;

  const ParsedCourseSection({required this.record, required this.beneficiary});
}

/// كـ[ParsedCourseSection] لكن مع الشطر المكتشَف تلقائيًا من حقل "المقر"
/// (انظر [DocxScheduleParserService.parseSectionsWithShatr]). قد يكون null
/// إن تعذّر تحديد الشطر (مثلاً ملف بلا فواصل أقسام واضحة).
class ParsedCourseSectionWithShatr {
  final CourseSectionRecord record;
  final String beneficiary;
  final Shatr? shatr;

  const ParsedCourseSectionWithShatr({required this.record, required this.beneficiary, required this.shatr});
}
