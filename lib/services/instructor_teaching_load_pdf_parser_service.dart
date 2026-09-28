import '../models/course_section_record.dart' show CourseMeeting;
import '../models/instructor_teaching_load_report.dart';
import 'pdf_table_rows_extractor.dart';

/// يقرأ تقرير "جدول المحاضرين" الرسمي (عمادة القبول والتسجيل) - صفحة PDF
/// مستقلة لكل عضو هيئة تدريس بكل ما لديه من مقررات (بصرف النظر عن الكلية
/// المصدر - يشمل مواد من خارج الكلية/الكلية التطبيقية/الماجستير، خلافًا لملف
/// "الحويّة" المبني حسب القاعة). يُعاد استخدام [PdfTableRowsExtractor] نفسه
/// (مشترك مع كل قرّاء PDF بالمشروع)، عبر `extractRowsWithPage` تحديدًا لأن كل
/// صفحة هنا سجل مستقل (خلافًا لتقارير الجدول المتصل عبر الصفحات).
///
/// **تنبيه**: بُني هذا القارئ على عيّنات محدودة (صفحة واحدة، ثم عيّنة أوسع
/// لمقارنة الفصول) - لم يُختبَر بعد على الملف الكامل الحقيقي المطلوب رفعه.
/// يلزم تحقق يدوي مقارَن (كنظرائه بالمشروع) قبل اعتماده فعليًا - انظر خطة
/// piped-humming-fox.
class InstructorTeachingLoadPdfParserService {
  static final RegExp _dayPattern = RegExp(r'^[1-7]$');
  static final RegExp _timePattern = RegExp(r'^\d{1,2}:\d{2}\s*[صم]$');
  static final RegExp _numberPattern = RegExp(r'^-?\d+([.,]\d+)?$');

  // لقب "د." قبل اسم المحاضر - يُزال وإلا فشلت مطابقة الاسم لاحقًا مع النسخة
  // "النظيفة" بملف منسوبي الكلية عند عرض الجدول الرسمي داخل بطاقة العضو.
  static final RegExp _titlePrefixPattern = RegExp(r'^\s*[دأا][\.\/]\s*');
  static String _stripTitlePrefix(String name) => name.replaceFirst(_titlePrefixPattern, '').trim();

  static double _num(String s) {
    final cleaned = s.trim().replaceAll(',', '');
    return double.tryParse(cleaned) ?? 0;
  }

  static int _int(String s) => int.tryParse(s.trim()) ?? 0;

  /// يبحث عن قيمة تلي أول خلية تحوي أيًا من `labels` بنفس الصف - يتفادى
  /// الاعتماد على فهرسة ثابتة لأن ترتيب/غياب حقول الرأس يتفاوت بين الملفات
  /// (مثال فعلي: "عبء المرتبة" أحيانًا و"أقصى العبء" أحيانًا أخرى لنفس
  /// المعنى - سليمان 2026-09-28).
  static String? _findHeaderValue(List<List<String>> rows, List<String> labels) {
    for (final row in rows) {
      for (var i = 0; i < row.length; i++) {
        if (labels.any(row[i].contains)) {
          for (var j = i + 1; j < row.length; j++) {
            final v = row[j].trim();
            if (v.isNotEmpty && !labels.any(v.contains)) return v;
          }
        }
      }
    }
    return null;
  }

  /// يستخرج كل تقارير المحاضرين من ملف مجمَّع متعدد الصفحات. صفحة بلا رأس
  /// "المحاضر" جديد (نفس رقم منسوب/اسم سابقه) تُعتبَر امتدادًا لصفوف مقررات
  /// الصفحة السابقة، لا سجلًا مستقلًا.
  static List<InstructorTeachingLoadReport> parse(List<int> pdfBytes) {
    final pageRows = PdfTableRowsExtractor.extractRowsWithPage(pdfBytes);

    final byPage = <int, List<List<String>>>{};
    for (final r in pageRows) {
      byPage.putIfAbsent(r.pageIndex, () => []).add(r.cells);
    }

    final reports = <InstructorTeachingLoadReport>[];
    _PendingReport? current;

    for (final pageIndex in byPage.keys.toList()..sort()) {
      final rawRows = byPage[pageIndex]!;
      final instructorName = _findHeaderValue(rawRows, ['المحاضر']);
      final staffNumber = _findHeaderValue(rawRows, ['رقم المنسوب']);

      // كل صفحة تحمل رقم المنسوب مكرَّرًا كعلامة مائية (watermark) متناثرة
      // خلفية الصفحة (دليل فعلي من سليمان 2026-09-28: عشرات الأسطر المعزولة
      // بنفس الرقم بملف "جدول شطر الطلاب" الحقيقي) - تُحذَف الصفوف المكوَّنة
      // بالكامل من هذا الرقم وحده قبل استخراج جدول المقررات، وإلا فُسِّرت
      // خطأً كصفوف بيانات إضافية.
      final rows = staffNumber == null || staffNumber.trim().isEmpty
          ? rawRows
          : rawRows.where((r) => !(r.isNotEmpty && r.every((c) => c.trim() == staffNumber.trim()))).toList();

      final isNewInstructor = instructorName != null && instructorName.trim().isNotEmpty;

      if (isNewInstructor) {
        if (current != null) reports.add(current.build());
        final semesterLabel = _findSemesterLabel(rows) ?? '';
        current = _PendingReport(
          instructorName: _stripTitlePrefix(instructorName),
          staffNumber: (staffNumber ?? '').trim(),
          college: _findHeaderValue(rows, ['الكلية']) ?? '',
          department: _findHeaderValue(rows, ['القسم']) ?? '',
          rank: _findHeaderValue(rows, ['المرتبة']) ?? '',
          position: _findHeaderValue(rows, ['المنصب']) ?? '',
          load: _num(_findHeaderValue(rows, ['العبء']) ?? '0'),
          maxLoad: _num(_findHeaderValue(rows, ['عبء المرتبة', 'أقصى العبء']) ?? '0'),
          extraHours: _num(_findHeaderValue(rows, ['الساعات الاضافية', 'الساعات الإضافية']) ?? '0'),
          adminHours: _num(_findHeaderValue(rows, ['ساعات عمل اداري', 'ساعات عمل إداري']) ?? '0'),
          qualifyingHours: _num(_findHeaderValue(rows, ['ساعات التاهيلي', 'ساعات التأهيلي']) ?? '0'),
          developedTransferHours: _num(_findHeaderValue(rows, ['انتساب مطور']) ?? '0'),
          semesterLabel: semesterLabel,
          reportDate: _findReportDate(rows),
        );
      }

      if (current == null) continue; // صفحة بلا أي رأس معروف - تُهمَل بأمان.
      current.courses.addAll(_parseCourseRows(rows));
    }
    if (current != null) reports.add(current.build());

    return reports;
  }

  static DateTime? _findReportDate(List<List<String>> rows) {
    final raw = _findHeaderValue(rows, ['التاريخ']);
    if (raw == null) return null;
    final m = RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(raw);
    if (m == null) return null;
    return DateTime.tryParse('${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}');
  }

  static String? _findSemesterLabel(List<List<String>> rows) {
    for (final row in rows) {
      final joined = row.join(' ');
      if (joined.contains('الفصل الدراسي') && joined.contains('للعام الجامعي')) {
        final m = RegExp(r'الفصل الدراسي.*?للعام الجامعي\s*\S+').firstMatch(joined);
        if (m != null) return m.group(0);
      }
    }
    return null;
  }

  /// يحوّل صفوف جدول المقررات أسفل رأس المحاضر لقائمة [TeachingLoadCourseRow].
  /// فهرسة الأعمدة من **نهاية الصف** (نمط `pdf_schedule_parser_service.dart`)
  /// لأن الأعمدة اللاحقة (رقم المقرر → المقر) لا تخلو أبدًا بصف مادة حقيقي.
  static List<TeachingLoadCourseRow> _parseCourseRows(List<List<String>> rows) {
    final result = <TeachingLoadCourseRow>[];
    TeachingLoadCourseRow? last;

    for (final cells in rows) {
      final n = cells.length;
      String at(int fromEnd) => (n - fromEnd) >= 0 ? cells[n - fromEnd] : '';

      // صف مادة حقيقي: يحمل رقم مقرر بصيغة "12345-N".
      final courseCodeRaw = at(1);
      final looksLikeMainRow = RegExp(r'^\d{4,7}-\d+$').hasMatch(courseCodeRaw.trim());

      if (looksLikeMainRow) {
        final courseName = at(2);
        final activity = at(3);
        final sectionStr = at(4);
        final degree = at(5);
        final tStr = at(6);
        final supervisor = at(7);
        final place = at(8);
        final loadStr = at(9);
        final scheduleType = _findScheduleType(cells);
        final registeredStr = _findTrailingNumber(cells);

        last = TeachingLoadCourseRow(
          courseCode: courseCodeRaw.split('-').first,
          courseName: courseName.trim(),
          scheduleType: scheduleType,
          activity: activity.trim(),
          section: sectionStr.trim(),
          degree: degree.trim(),
          t: tStr.trim(),
          supervisor: supervisor.trim(),
          place: place.trim(),
          load: _num(loadStr),
          registered: _int(registeredStr),
          meetings: _extractMeetings(cells),
        );
        result.add(last);
      } else if (last != null) {
        // صف متابعة (موعد إضافي بلا رمز مقرر جديد) - يُضاف كموعد إضافي لآخر
        // مادة، بنفس منطق صفوف المتابعة بقارئ الحويّة.
        final extra = _extractMeetings(cells);
        if (extra.isNotEmpty) {
          result[result.length - 1] = TeachingLoadCourseRow(
            courseCode: last.courseCode,
            courseName: last.courseName,
            scheduleType: last.scheduleType,
            activity: last.activity,
            section: last.section,
            degree: last.degree,
            t: last.t,
            supervisor: last.supervisor,
            place: last.place,
            load: last.load,
            registered: last.registered,
            meetings: [...last.meetings, ...extra],
          );
          last = result.last;
        }
      }
    }
    return result;
  }

  static String _findScheduleType(List<String> cells) {
    const knownTypes = ['انتساب مطور', 'دبلوم مدفوع', 'مدمج مدفوع', 'إنتظام'];
    for (final cell in cells) {
      for (final t in knownTypes) {
        if (cell.contains(t)) return t;
      }
    }
    return '';
  }

  static String _findTrailingNumber(List<String> cells) {
    for (var i = cells.length - 1; i >= 0; i--) {
      if (_numberPattern.hasMatch(cells[i].trim())) return cells[i].trim();
    }
    return '0';
  }

  static List<CourseMeeting> _extractMeetings(List<String> cells) {
    final meetings = <CourseMeeting>[];
    final timeIdx = <int>[];
    for (var i = 0; i < cells.length; i++) {
      if (_timePattern.hasMatch(cells[i].trim())) timeIdx.add(i);
    }
    for (var k = 0; k + 1 < timeIdx.length; k += 2) {
      final toIdx = timeIdx[k];
      final fromIdx = timeIdx[k + 1];
      final to = cells[toIdx].trim();
      final from = cells[fromIdx].trim();
      int? day;
      String room = '';
      for (var i = fromIdx + 1; i < cells.length; i++) {
        final c = cells[i].trim();
        if (day == null && _dayPattern.hasMatch(c)) {
          day = int.parse(c);
          continue;
        }
        if (c.isNotEmpty) room = c;
      }
      if (day != null) {
        meetings.add(CourseMeeting(day: day, from: from, to: to, room: room));
      }
    }
    return meetings;
  }
}

class _PendingReport {
  final String instructorName;
  final String staffNumber;
  final String college;
  final String department;
  final String rank;
  final String position;
  final double load;
  final double maxLoad;
  final double extraHours;
  final double adminHours;
  final double qualifyingHours;
  final double developedTransferHours;
  final String semesterLabel;
  final DateTime? reportDate;
  final List<TeachingLoadCourseRow> courses = [];

  _PendingReport({
    required this.instructorName,
    required this.staffNumber,
    required this.college,
    required this.department,
    required this.rank,
    required this.position,
    required this.load,
    required this.maxLoad,
    required this.extraHours,
    required this.adminHours,
    required this.qualifyingHours,
    required this.developedTransferHours,
    required this.semesterLabel,
    required this.reportDate,
  });

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
