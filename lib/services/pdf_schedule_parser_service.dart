import '../models/course_section_record.dart';
import 'course_schedule_repository.dart' show Shatr;
import 'docx_schedule_parser_service.dart' show ParsedCourseSectionWithShatr;
import 'pdf_table_rows_extractor.dart';

/// نسخة تجريبية (preview) من [DocxScheduleParserService] تقرأ جدول "الحويّة"
/// مباشرة من ملف PDF الأصلي (بلا تحويل يدوي إلى Word) - عبر نفس
/// [PdfTableRowsExtractor] المستخدَم بتقارير الإرشاد.
///
/// **الفرق الجوهري عن قارئ docx**: جدول docx يحوي 16 خلية `<tc>` ثابتة لكل
/// صف حتى لو كانت فارغة، فالفهرسة الثابتة (index) موثوقة دومًا. أما استخراج
/// PDF فيبني الأعمدة من فجوات المسافة بين الكلمات، فالخلية الفارغة **تختفي
/// تمامًا** من الصف بدل أن تبقى فارغة - ما يُزيح كل الأعمدة السابقة لها.
/// الحل هنا: الأعمدة اللاحقة (الشعبة → القاعة) تُقرأ بفهرسة **من نهاية
/// الصف** لأنها لا تكون فارغة أبدًا بصف مادة حقيقي (خلافًا لعمودي "فترة
/// الاختبار"/"جاهزة" اللذين قد يكونان فارغين بالبداية)، بينما "المستفيد"
/// (يحوي كلمة "كلية" دومًا) و"المحاضر" يُستدَلّ عليهما بالبحث عن النص لا
/// بالفهرسة - أداة اختبار (preview) لمقارنة دقتها بنتيجة docx، وليست بديلًا
/// مضمونًا لها بعد.
class PdfScheduleParserService {
  static final RegExp _mmaqarPattern = RegExp('المقر(?!ر)');
  static final RegExp _dayPattern = RegExp(r'^[1-7]$');
  static final RegExp _timePattern = RegExp(r'^\d{1,2}:\d{2}\s*[صم]$');

  // القاعة بمستخرِج PDF تخرج مثل "حضوري)(5101" - كلمة "حضوري" وقوساها الملحقان
  // يُستخرَجون كوحدة نصية واحدة معكوسة الترتيب (خلل اتجاه RTL بالاستخراج، لا
  // علاقة له بموضع العمود) - يُزالان بلا اشتراط ترتيب الأقواس تحديدًا، خلافًا
  // لنظيره بقارئ docx الذي يحذف السلسلة الحرفية "(حضوري)" فقط - دليل فعلي من
  // سليمان (2026-08-24): 620 من 710 شعبة أظهرت "حضوري)(" ضمن القاعة رغم صحة
  // رقمها، بعد مقارنة برمجية بملف Word المرجعي.
  // قاعات "شبكة" الملتصقة برقم (بلا مسافة بينهما بالمصدر الأصلي، مثل
  // "10232شبكة تلفزيونية") تخرج أحيانًا من مستخرِج PDF بترتيب معكوس بين
  // "شبكة" والرقم تحديدًا ("شبكة10232 تلفزيونية") - خلل مستقل عن خلل انعكاس
  // Word (لا علاقة له بمعالجة bidi، بل بترتيب "كلمات" PDF المُستخرَجة) - دليل
  // فعلي من سليمان (2026-08-24) بعد مقارنة برمجية بقارئ Word المُصلَح.
  static final RegExp _reversedGluedNetworkRoom = RegExp(r'^شبكة(\d+)\s+(.*)$');

  static String _normalizeRoom(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (s.contains('أونلاين') || s.contains('اونلاين') || s.contains('أون لاي')) return 'أونلاين';
    s = s.replaceAll(RegExp(r'[()]*حضوري[()]*'), '').trim();
    s = s.replaceAll(RegExp(r'^[()]+|[()]+$'), '').trim();
    final reversedMatch = _reversedGluedNetworkRoom.firstMatch(s);
    if (reversedMatch != null) {
      s = '${reversedMatch.group(1)}شبكة ${reversedMatch.group(2)}';
    }
    return s;
  }

  // لقب "د." أو "د/" قبل اسم المحاضر - غير مُزال بقارئ PDF خلافًا لقارئ docx
  // (استخدَم نفس النمط هناك) - دليل فعلي من سليمان (2026-08-24): 50 من 710
  // شعبة أظهرت اللقب ضمن الاسم بلوحة PDF فقط بعد مقارنة برمجية.
  static final RegExp _titlePrefixPattern = RegExp(r'^\s*[دأا][\.\/]\s*');
  static String? _stripTitlePrefix(String? name) {
    if (name == null) return null;
    return name.replaceFirst(_titlePrefixPattern, '').trim();
  }

  // نص القاعة الحقيقي دومًا رقم و/أو كلمة من مفردات القاعات (شبكة/أونلاين/عن
  // بعد/حضوري) - لا يتجاوز 3 كلمات أبدًا. إن كانت الخلية المُلتقَطة بصف
  // المتابعة (انظر التعليق بالحلقة الرئيسية) اسم محاضر مندمج خطأً بنفس الصف
  // (4+ كلمات عربية صرفة بلا رقم)، تُرفَض هنا بدل قبولها كقاعة خاطئة - دليل
  // فعلي من سليمان (2026-08-24): شعبة 602429/6604422 أظهرتا اسم محاضر كامل
  // بحقل القاعة بعد مقارنة برمجية بـWord.
  static bool _looksLikeRoom(String s) {
    if (s.isEmpty) return true;
    if (RegExp(r'\d').hasMatch(s)) return true;
    if (s.contains('شبكة') || s.contains('أونلاين') || s.contains('اونلاين') ||
        s.contains('عن بعد') || s.contains('حضوري')) {
      return true;
    }
    return s.split(RegExp(r'\s+')).length <= 1;
  }

  static ({bool isMarker, Shatr? shatr}) _shatrFromText(String text) {
    if (!_mmaqarPattern.hasMatch(text)) return (isMarker: false, shatr: null);
    const branchKeywords = ['الخرمة', 'تربة', 'رنية'];
    if (branchKeywords.any(text.contains)) return (isMarker: true, shatr: null);
    return (isMarker: true, shatr: text.contains('طالبات') ? Shatr.female : Shatr.male);
  }

  static List<ParsedCourseSectionWithShatr> parseSectionsWithShatr(List<int> pdfBytes) {
    final rows = PdfTableRowsExtractor.extract(pdfBytes);

    final activityRows = <_RawRow>[];
    _RawRow? lastRow;
    Shatr? currentShatr;

    for (final cells in rows) {
      final marker = _shatrFromText(cells.join(' '));
      if (marker.isMarker) {
        currentShatr = marker.shatr;
        continue;
      }

      final n = cells.length;
      String at(int fromEnd) => (n - fromEnd) >= 0 ? cells[n - fromEnd] : '';

      // فهرسة من نهاية الصف - انظر توثيق الصنف أعلاه لترتيب الأعمدة.
      final section = at(1);
      final courseCodeRaw = at(2);
      final courseName = at(3);
      final hoursStr = at(4);
      final activity = at(5);
      final sequenceStr = at(6);
      final maxCapStr = at(7);
      final registeredStr = at(8);

      final isMain = (activity == 'نظري' || activity == 'عملي') &&
          courseCodeRaw.contains('-') &&
          section.isNotEmpty;

      if (isMain) {
        final dayStr = at(9);
        final from = at(10);
        final to = at(11);
        final room = _normalizeRoom(at(12));

        String beneficiary = '';
        String? instructor;
        // البحث عن خلية "المستفيد" (تحوي "كلية" دومًا) بالجزء الأمامي من
        // الصف المتبقي بعد الأعمدة المرساة من النهاية (section..room).
        // ترتيب docx الفعلي: ...المستفيد(index2)، المحاضر(index3)، القاعة
        // (index4)... - أي "المحاضر" يأتي **بعد** "المستفيد" مباشرة بالمصفوفة
        // (خطأ سابق هنا كان يقرأ الخلية التي *قبل* المستفيد خطأً - سليمان
        // صراحةً 2026-08-24 بعد دليل فعلي: شعبة 989 أظهرت محاضرًا فارغًا
        // بلوحة PDF رغم وجوده صراحةً بلوحة Word المقابلة).
        final searchLimit = n - 12;
        for (var i = 0; i < searchLimit; i++) {
          if (cells[i].contains('كلية')) {
            // "المستفيد" قد يشمل أكثر من كلية، فتُقسَّم أحيانًا على أكثر من
            // خليتين أو ثلاث متتالية بمستخرِج PDF (مثال فعلي: "(كلية إدارة
            // الأعمال - (" ثم "(كلية" ثم "العلوم - )" بثلاث خلايا منفصلة -
            // خليةُ التكملة الأخيرة لا تحوي كلمة "كلية" نفسها فلا يكفي شرط
            // احتوائها عليها) - يُستدَلّ بدل ذلك على استمرار نص "المستفيد" عبر
            // وجود قوس/شرطة (علامات لا تظهر أبدًا باسم محاضر)، ويتوقف الدمج
            // عند أول خلية خالية من هذه العلامات (بداية اسم المحاضر) - دليل
            // فعلي من سليمان (2026-08-24) بعد مقارنة برمجية بقارئ Word:
            // "(كلية إدارة الأعمال - ( (كلية" ظهرت مقطوعة بدل "(كلية إدارة
            // الأعمال - ) (كلية العلوم - )" الكاملة حتى بعد إصلاح أول.
            // بعض حالات الكلية الثانية تنقسم على 3 خلايا وسطها خلية "جسر" بلا
            // أي علامة (مثل "العلوم" وحدها بين "(كلية" و"- )") - يُستشرَف
            // أماميًا (خليتان) لوجود علامة لاحقة قبل قبول خلية بلا علامة، بدل
            // التوقف عندها فورًا - دليل فعلي من سليمان (2026-08-24) بعد
            // مقارنة برمجية ثالثة: 14 من 710 شعبة بقيت مقطوعة رغم الإصلاح
            // السابق لأن خلية الجسر هذه أوقفت الدمج قبل أوانه.
            bool hasMarker(String c) => c.contains('كلية') || c.contains('(') || c.contains(')') || c.contains('-');
            var j = i;
            final parts = <String>[];
            while (j < searchLimit) {
              final cell = cells[j];
              if (!hasMarker(cell)) {
                final futureMarker = (j + 1 < searchLimit && hasMarker(cells[j + 1])) ||
                    (j + 2 < searchLimit && hasMarker(cells[j + 2]));
                if (!futureMarker) break;
              }
              parts.add(cell);
              j++;
            }
            beneficiary = parts.join(' ');
            if (j < searchLimit) {
              final next = cells[j].trim();
              if (next.isNotEmpty && next != 'نعم' && next != 'لا' && !next.contains('كلية')) {
                instructor = _stripTitlePrefix(next);
              }
            }
            break;
          }
        }

        final sequence = int.tryParse(sequenceStr) ?? 0;
        final hours = int.tryParse(hoursStr) ?? 0;
        final registered = int.tryParse(registeredStr) ?? 0;
        final maxCapacity = int.tryParse(maxCapStr) ?? 0;
        final day = int.tryParse(dayStr);
        final meetings = <CourseMeeting>[];
        if (day != null && _dayPattern.hasMatch('$day') && from.isNotEmpty && to.isNotEmpty) {
          meetings.add(CourseMeeting(day: day, from: from, to: to, room: room));
        }

        final row = _RawRow(
          courseCode: courseCodeRaw.split('-').first,
          courseName: courseName,
          activity: activity,
          sequence: sequence,
          sectionNumber: section,
          meetings: meetings,
          instructorName: instructor,
          hours: hours,
          registered: registered,
          maxCapacity: maxCapacity,
          beneficiary: beneficiary,
          shatr: currentShatr,
        );
        activityRows.add(row);
        lastRow = row;
      } else if (lastRow != null) {
        // صف متابعة محتمل (يوم/وقت إضافي فقط، بلا رمز مقرر) - الصف هنا قصير
        // جدًا وغير موثوق الطول، فيُستدَلّ على الحقول بالبحث عن نمط الوقت/اليوم
        // بدل فهرسة ثابتة. ترتيب الأعمدة بالمستند الأصلي: قاعة ثم إلى ثم من
        // ثم اليوم (بهذا الترتيب تحديدًا) - يُستغَلّ لتفادي التباس رقم اليوم
        // (١-٥) مع أرقام أخرى صغيرة، بتقييد البحث عنه بعد خليتَي الوقت.
        final timeIdx = <int>[];
        for (var i = 0; i < cells.length; i++) {
          if (_timePattern.hasMatch(cells[i])) timeIdx.add(i);
        }
        if (timeIdx.length >= 2) {
          final toIdx = timeIdx[0];
          final fromIdx = timeIdx[1];
          final to = cells[toIdx];
          final from = cells[fromIdx];
          int? day;
          for (var i = fromIdx + 1; i < cells.length; i++) {
            if (_dayPattern.hasMatch(cells[i])) {
              day = int.parse(cells[i]);
              break;
            }
          }
          // نص غير شبيه بقاعة بهذا الموضع (اسم مندمج خطأً مثلًا) لا يعني أن
          // الموعد نفسه وهمي - Word نفسه يُظهر مواعيد ثانية حقيقية (كالخميس
          // مساءً) بقاعة فارغة أحيانًا - فتُعتبَر القاعة فارغة فقط بدل إسقاط
          // الموعد بأكمله - دليل فعلي من سليمان (2026-08-24) بعد مقارنة
          // برمجية ثانية: الإسقاط الكامل أفقد مواعيد حقيقية موجودة بـWord.
          var room = '';
          for (var i = toIdx - 1; i >= 0; i--) {
            if (cells[i].trim().isNotEmpty) {
              final cell = cells[i].trim();
              room = _looksLikeRoom(cell) ? _normalizeRoom(cell) : '';
              break;
            }
          }
          if (day != null) {
            lastRow.meetings.add(CourseMeeting(day: day, from: from, to: to, room: room));
          }
        }
      }
    }

    final Map<String, _RawRow> theoryByKey = {};
    final Map<String, _RawRow> practicalByKey = {};
    for (final row in activityRows) {
      final key = '${row.courseCode}|${row.sequence}|${row.shatr}|${row.beneficiary}';
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
