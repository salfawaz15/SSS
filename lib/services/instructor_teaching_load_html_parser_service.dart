import 'package:html/parser.dart' as html_parser;

import '../models/course_section_record.dart' show CourseMeeting;
import '../models/instructor_teaching_load_report.dart';
import 'windows1256_decoder.dart';

/// يقرأ تقرير "جدول المحاضرين" الرسمي (عمادة القبول والتسجيل) من نسخته
/// المُصدَّرة بامتداد .xls لكنها فعليًا جدول HTML واحد (Oracle Reports،
/// Windows-1256) يحوي كل صفحات كل الأعضاء متتالية بنفس الجدول - **مصدر أدق
/// وأوثق بكثير من نسخة PDF المكافئة**: بنية `<td>` صريحة الترتيب (لا حاجة
/// لإعادة بناء أعمدة من إحداثيات x/y كما في [InstructorTeachingLoadPdfParserService]،
/// ولا مشكلة "علامة مائية" متناثرة تُربِك الاستخراج - العلامة المائية هنا
/// صف واحد صريح مميَّز بلون رمادي باهت يسهل تجاهله). يُفضَّل استخدام هذا
/// القارئ على نظيره PDF كلما توفّر الملفان معًا لنفس البيانات.
///
/// **بنية كل صفحة عضو** (تُفصَل بصفوف عنوان "جدول المحاضر رقم"):
/// - صفوف رأس بتسميات صريحة: المحاضر، رقم المنسوب، الكلية، القسم، المرتبة،
///   المنصب، العبء، عبء المرتبة، الساعات الاضافية، ساعات عمل اداري، ساعات
///   التاهيلي، انتساب مطور.
/// - صف عناوين جدول المقررات (خلفية رمادية #d6d6d6): رقم المقرر، اسم المقرر،
///   نوع الجدول، النشاط، شعبة، الدرجة، ت، المقر، عبء، أسبوعية، ثم أيام
///   الأسبوع (الأحد..الخميس)، فمسجلين.
/// - صف مقرر: أول 10 خلايا (بعد استبعاد الفارغة) ثابتة الترتيب دومًا (لم
///   تُرصَد حالة فارغة لأيٍّ منها بعيّنة حقيقية 72 صفحة - سليمان 2026-09-28)،
///   ثم 0-5 خلايا مواعيد (الفارغة منها تختفي فتصبح متغيرة الطول)، ثم خلية
///   "مسجلين" الأخيرة دومًا - يُعتمَد فهرسة من البداية للثابت ومن النهاية
///   لـ"مسجلين"، ومنطقة وسطى مرِنة بينهما للمواعيد (نفس أسلوب الفهرسة
///   المزدوجة من الطرفين المُتَّبَع بقارئ PDF المكافئ بالمشروع).
class InstructorTeachingLoadHtmlParserService {
  // صيغة الموعد كما تخرج من هذا التصدير تحديدًا (مختلفة عن صيغة قارئ PDF
  // المكافئ حيث القاعة/اليوم/الوقت خلايا منفصلة): نص واحد مدمَج مثل
  // "(35206حضوري)(ر)12:00 - 15:00/" (بقاعة) أو "(ثن)11:00 - 14:00/" (بلا
  // قاعة، تدريب مثلًا) أو "(عن بعد)(ثل)18:00 - 20:00/" - عيّنة حقيقية
  // (سليمان 2026-09-28، ملف "جداول شطر الطلاب اكسل.xls" 72 صفحة).
  static final RegExp _meetingPattern = RegExp(
    r'^(?:\((?:(\d+)?حضوري|عن بعد|أونلاين|اونلاين)\))?\((ح|ثن|ثل|ر|خ)\)(\d{1,2}:\d{2})-(\d{1,2}:\d{2})/?$',
  );
  static const Map<String, int> _dayAbbrev = {'ح': 1, 'ثن': 2, 'ثل': 3, 'ر': 4, 'خ': 5};

  // العلامة المائية: صف مستقل بخلية واحدة فقط، رقم منسوب مكرَّر بلون رمادي
  // باهت (#b7b7b7) - يُكتفى هنا باكتشافها بنمطها (رقم من 6-7 خانات وحيد
  // بالصف) بدل الاعتماد على تحليل CSS (أبسط وكافٍ عمليًا).
  static bool _looksLikeWatermarkRow(List<String> cells) =>
      cells.length == 1 && RegExp(r'^\d{6,8}$').hasMatch(cells.first.trim());

  static double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;
  static int _int(String s) => int.tryParse(s.trim()) ?? 0;

  static List<InstructorTeachingLoadReport> parse(List<int> rawBytes) {
    final text = Windows1256Decoder.decode(rawBytes);
    final document = html_parser.parse(text);
    final trs = document.querySelectorAll('tr');

    final rows = <List<String>>[];
    for (final tr in trs) {
      final spans = tr.querySelectorAll('span');
      final texts = <String>[];
      for (final s in spans) {
        final t = s.text.replaceAll(' ', ' ').trim();
        if (t.isNotEmpty) texts.add(t);
      }
      if (texts.isNotEmpty && !_looksLikeWatermarkRow(texts)) rows.add(texts);
    }

    final reports = <InstructorTeachingLoadReport>[];
    _PendingReport? current;
    List<TeachingLoadCourseRow>? pendingCourses;

    // يتجاهَل أي خلية "مرشَّحة" تنتهي بـ":" (تسمية حقل أخرى لا قيمة فعلية) -
    // حقل بلا قيمة (مثل "المنصب:" فارغًا لأعضاء بلا منصب إداري) لا يجعل
    // البحث يلتقط خطأً تسمية الحقل التالي بنفس الصف كقيمة له.
    String? findValue(List<String> row, String label) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].contains(label)) {
          for (var j = i + 1; j < row.length; j++) {
            final v = row[j].trim();
            if (v.isEmpty) continue;
            if (v.endsWith(':') || v.endsWith('：')) return null;
            return v;
          }
        }
      }
      return null;
    }

    void flush() {
      final pending = current;
      if (pending != null) {
        pending.courses.addAll(pendingCourses ?? const []);
        reports.add(pending.build());
      }
      current = null;
      pendingCourses = null;
    }

    for (final row in rows) {
      final joined = row.join(' ');

      if (joined.contains('جدول') && joined.contains('المحاضر') && joined.contains('رقم')) {
        flush();
        continue; // صف عنوان فقط - الرأس الفعلي بالصفوف التالية.
      }

      final instructorValue = findValue(row, 'المحاضر');
      if (current == null && instructorValue != null) {
        current = _PendingReport(instructorName: instructorValue);
        pendingCourses = [];
      }
      if (current == null) continue;

      final semMatch = RegExp(r'الفصل الدراسي.*?للعام الجامعي\s*\S+').firstMatch(joined);
      if (semMatch != null) current!.semesterLabel = semMatch.group(0)!;

      final dateValue = findValue(row, 'التاريخ');
      if (dateValue != null) {
        final m = RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(dateValue);
        if (m != null) {
          current!.reportDate = DateTime.tryParse('${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}');
        }
      }

      final v = findValue(row, 'رقم المنسوب');
      if (v != null) current!.staffNumber = v;
      final college = findValue(row, 'الكلية');
      if (college != null) current!.college = college;
      final dept = findValue(row, 'القسم');
      if (dept != null) current!.department = dept;
      final rank = findValue(row, 'المرتبة');
      if (rank != null) current!.rank = rank;
      final position = findValue(row, 'المنصب');
      if (position != null) current!.position = position;
      final load = findValue(row, 'العبء');
      if (load != null) current!.load = _num(load);
      final maxLoad = findValue(row, 'عبء المرتبة') ?? findValue(row, 'أقصى العبء');
      if (maxLoad != null) current!.maxLoad = _num(maxLoad);
      final extraHours = findValue(row, 'الساعات الاضافية') ?? findValue(row, 'الساعات الإضافية');
      if (extraHours != null) current!.extraHours = _num(extraHours);
      final adminHours = findValue(row, 'ساعات عمل اداري') ?? findValue(row, 'ساعات عمل إداري');
      if (adminHours != null) current!.adminHours = _num(adminHours);
      final qualifyingHours = findValue(row, 'ساعات التاهيلي') ?? findValue(row, 'ساعات التأهيلي');
      if (qualifyingHours != null) current!.qualifyingHours = _num(qualifyingHours);
      final developedTransfer = findValue(row, 'انتساب مطور');
      if (developedTransfer != null) current!.developedTransferHours = _num(developedTransfer);

      // صف عناوين جدول المقررات - يُتجاهَل (يُعرَف بأول خلية "رقم المقرر" حرفيًا).
      if (row.isNotEmpty && row.first.trim() == 'رقم المقرر') continue;

      // صف "المجموع" الختامي - لا يخص مادة، يُتجاهَل.
      if (joined.contains('المجموع')) continue;

      // صف مادة حقيقي: أول خلية تطابق "رقم-ساعات".
      if (row.isNotEmpty && RegExp(r'^\d{4,7}-\d+$').hasMatch(row.first.trim())) {
        // 10 حقول ثابتة (رقم المقرر..أسبوعية) + خلية "مسجلين" الأخيرة على
        // الأقل = 11 - أي صف أقصر منها بيانات ناقصة، يُتجاهَل بأمان بدل تخمين.
        if (row.length < 11) continue;
        final courseCode = row[0];
        final courseName = row[1];
        final scheduleType = row[2];
        final activity = row[3];
        final section = row[4];
        final degree = row[5];
        final t = row[6];
        final place = row[7];
        final load2 = row[8];
        // row[9] = "أسبوعية" (إجمالي الساعات الفعلي بالجدول - غير مخزَّن
        // بنموذج الصف حاليًا، يظهر أيضًا بصف "المجموع" الختامي لكل عضو).
        final registered = row.last;
        final meetingTexts = row.sublist(10, row.length - 1);

        final meetings = <CourseMeeting>[];
        for (final mt in meetingTexts) {
          final m = _meetingPattern.firstMatch(mt.replaceAll(' ', ''));
          if (m == null) continue;
          final room = m.group(1) ?? '';
          final dayAbbrev = m.group(2)!;
          final day = _dayAbbrev[dayAbbrev];
          if (day == null) continue;
          meetings.add(CourseMeeting(day: day, from: m.group(3)!, to: m.group(4)!, room: room));
        }

        pendingCourses!.add(TeachingLoadCourseRow(
          courseCode: courseCode.split('-').first,
          courseName: courseName.trim(),
          scheduleType: scheduleType.trim(),
          activity: activity.trim(),
          section: section.trim(),
          degree: degree.trim(),
          t: t.trim(),
          supervisor: '',
          place: place.trim(),
          load: _num(load2),
          registered: _int(registered),
          meetings: meetings,
        ));
      }
    }
    flush();

    return reports;
  }
}

class _PendingReport {
  String instructorName;
  String staffNumber = '';
  String college = '';
  String department = '';
  String rank = '';
  String position = '';
  double load = 0;
  double maxLoad = 0;
  double extraHours = 0;
  double adminHours = 0;
  double qualifyingHours = 0;
  double developedTransferHours = 0;
  String semesterLabel = '';
  DateTime? reportDate;
  final List<TeachingLoadCourseRow> courses = [];

  _PendingReport({required this.instructorName});

  InstructorTeachingLoadReport build() => InstructorTeachingLoadReport(
        instructorName: instructorName,
        staffNumber: staffNumber,
        college: college,
        department: department,
        rank: rank,
        position: position,
        load: load,
        maxLoad: maxLoad,
        extraHours: extraHours,
        adminHours: adminHours,
        qualifyingHours: qualifyingHours,
        developedTransferHours: developedTransferHours,
        semesterLabel: semesterLabel,
        reportDate: reportDate,
        courses: courses,
      );
}
