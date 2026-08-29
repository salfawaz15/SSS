import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/course_catalog.dart';
import '../models/course_section_record.dart';
import 'course_schedule_repository.dart';
import 'outside_course_repository.dart';
import 'pdf_brand_kit.dart';

/// يبني ملف PDF واحدًا بمواد قسم واحد لشطر واحد بصيغة "ما يحق للطالب رؤيته
/// فقط" - رمز المقرر واسمه واليوم والوقت ورقم الشعبة، بلا رقم القاعة أو اسم
/// عضو هيئة التدريس أو عدد المسجلين (بيانات تشغيلية داخلية لا تخص الطالب) -
/// بطلب سليمان صراحةً (2026-08-27): "المواد الدراسية لطلبة كلية إدارة
/// الأعمال - 10 ملفات (لكل قسم ولكل شطر) بما هو متاح للطالب أن يشاهده".
class CourseScheduleStudentPdfService {
  static final _greenDark = PdfColor.fromHex('0D3324');
  static final _lightGray = PdfColor.fromHex('E5E9E7');

  /// نفس منطق تصفية "نسخ فورمز" بشاشة إدارة المقررات (القسم المالك + المقررات
  /// المشتركة بين كل الأقسام + المقررات "المتاحة أيضًا" لهذا القسم تحديدًا) -
  /// لأن الطالب يحتاج رؤية كل ما يُتاح له تسجيله فعليًا ضمن قسمه، لا مقررات
  /// القسم المالك فقط.
  static List<CourseSectionRecord> recordsForDepartment(
    List<CourseSectionRecord> all,
    String department,
  ) {
    final filtered = all.where((r) {
      final entry = CourseCatalog.lookup(r.courseCode);
      final own = entry?.department == department;
      final shared = CourseCatalog.isSharedAcrossDepartments(r.courseCode);
      final extra = CourseCatalog.isVisibleInDepartment(r.courseCode, department);
      return own || shared || extra;
    }).toList()
      ..sort((a, b) {
        final c = a.courseCode.compareTo(b.courseCode);
        if (c != 0) return c;
        return a.theorySection.compareTo(b.theorySection);
      });
    return filtered;
  }

  static Future<Uint8List> build({
    required String department,
    required String shatrLabel,
    required List<CourseSectionRecord> records,
    List<CourseSectionRecord> outsideRecords = const [],
    bool includeNotes = false,
  }) async {
    final regularBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final boldBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
    final logoBytes = await rootBundle.load('assets/images/unit_logo_final.png');
    final regularFont = pw.Font.ttf(regularBytes);
    final boldFont = pw.Font.ttf(boldBytes);
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final generatedAt = DateTime.now();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _header(
          logo: logo,
          subtitle: '${department.replaceFirst(RegExp(r'^قسم\s+'), '')} - $shatrLabel',
          generatedAt: generatedAt,
        ),
        footer: PdfBrandKit.footer,
        build: (context) => [
          if (records.isEmpty)
            pw.Text('لا توجد مواد متاحة لهذا القسم/الشطر بعد.', style: const pw.TextStyle(fontSize: 11))
          else
            _coursesTable(records, includeNotes: includeNotes),
          // مقررات من خارج الكلية (متطلبات/اختياريات تُدرَّس عبر كليات أخرى) -
          // متاحة لكل الأقسام بالتساوي (بطلب سليمان صراحةً 2026-08-27)، فتُضاف
          // دائمًا في نهاية الجدول بقسم/عنوان منفصل يوضّح أنها من خارج الكلية،
          // لا ضمن جدول القسم نفسه حتى لا تُفهَم خطأً كمقررات يطرحها القسم.
          if (outsideRecords.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: PdfBrandKit.gold, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(
                'مقررات من خارج الكلية',
                style: pw.TextStyle(color: _greenDark, fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
            ),
            pw.SizedBox(height: 6),
            _coursesTable(outsideRecords, includeNotes: includeNotes),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// نسخة من [PdfBrandKit.header] بلا الخلفية البيضاء خلف الشعار - بطلب
  /// سليمان صراحةً (2026-08-27) لهذا الملف تحديدًا، فلا تُعدَّل النسخة
  /// المشتركة بـ[PdfBrandKit] حتى لا تتأثر ملفات PDF أخرى تعتمد عليها.
  static pw.Widget _header({
    required pw.MemoryImage logo,
    required String subtitle,
    required DateTime generatedAt,
  }) {
    final dateLabel =
        '${generatedAt.year}/${generatedAt.month.toString().padLeft(2, '0')}/${generatedAt.day.toString().padLeft(2, '0')}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(colors: [PdfBrandKit.greenDark, PdfBrandKit.green]),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                children: [
                  pw.Image(logo, height: 28, fit: pw.BoxFit.contain),
                  pw.SizedBox(width: 10),
                  pw.Text('وحدة الإرشاد الأكاديمي والخريجين', style: pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('المواد الدراسية المتاحة',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  pw.SizedBox(height: 2),
                  pw.Text('تاريخ الإصدار: $dateLabel', style: pw.TextStyle(fontSize: 8, color: PdfColors.white)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: pw.BoxDecoration(color: PdfBrandKit.gold, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _greenDark)),
          ),
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }

  /// حضوري/عن بعد فقط (بلا رقم القاعة نفسه، الذي لا يحق للطالب معرفته) -
  /// مُستنتَج من عمود "القاعة" الخام (يحوي "عن بعد"/"أونلاين" للمواعيد عن
  /// بعد، أو رقم قاعة فعلي للحضوري).
  static String _attendanceLabel(String room) {
    if (room.contains('أونلاين') || room.contains('عن بعد')) return 'عن بعد';
    return 'حضوري';
  }

  /// "مقفلة" = المسجلين ≥ أعلى حد (تجريبي بطلب سليمان 2026-08-29 - عمود
  /// "ملاحظات" اختياري لمعرفة الطالب أي شعبة مقفلة، بلا أرقام أو تفاصيل
  /// إضافية، فقط الكلمة نفسها).
  static String _capacityNote(int registered, int maxCapacity) => registered >= maxCapacity ? 'مقفلة' : 'متاحة';

  static pw.Widget _coursesTable(List<CourseSectionRecord> records, {bool includeNotes = false}) {
    final headers = ['رمز المقرر', 'اسم المقرر', 'النوع', 'الشعبة', 'اليوم', 'الوقت', 'الحضور', if (includeNotes) 'ملاحظات'];
    final rows = <List<String>>[];
    for (final r in records) {
      // ترتيب المواعيد حسب يوم الأسبوع (الأحد..الخميس) - بيانات الملف
      // المرفوع لا تضمن هذا الترتيب، فتظهر أحيانًا بترتيب عشوائي بلا هذا الفرز.
      final theoryMeetings = [...r.meetings]..sort((a, b) => a.day.compareTo(b.day));
      rows.add([
        r.theoryCourseCodeFull,
        r.courseName,
        'نظري',
        r.theorySection,
        theoryMeetings.isEmpty ? '-' : theoryMeetings.map((m) => m.dayName).join('\n'),
        theoryMeetings.isEmpty ? '-' : theoryMeetings.map((m) => '${m.from} - ${m.to}').join('\n'),
        theoryMeetings.isEmpty ? '-' : theoryMeetings.map((m) => _attendanceLabel(m.room)).join('\n'),
        if (includeNotes) _capacityNote(r.theoryRegistered, r.theoryMaxCapacity),
      ]);
      // الشعبة العملية المرتبطة (إن وُجدت) تُعرَض كصف مستقل بنفس اسم/رمز
      // المقرر - الطالب يحتاج معرفة موعدها أيضًا لا موعد النظري فقط.
      if (r.practicalSection != null) {
        final practicalMeetings = [...r.practicalMeetings]..sort((a, b) => a.day.compareTo(b.day));
        rows.add([
          r.practicalCourseCodeFull,
          r.courseName,
          'عملي',
          r.practicalSection!,
          practicalMeetings.isEmpty ? '-' : practicalMeetings.map((m) => m.dayName).join('\n'),
          practicalMeetings.isEmpty ? '-' : practicalMeetings.map((m) => '${m.from} - ${m.to}').join('\n'),
          practicalMeetings.isEmpty ? '-' : practicalMeetings.map((m) => _attendanceLabel(m.room)).join('\n'),
          if (includeNotes) _capacityNote(r.practicalRegistered ?? 0, r.practicalMaxCapacity ?? 0),
        ]);
      }
    }

    final rtlHeaders = headers.reversed.toList();
    final rtlRows = rows.map((r) => r.reversed.toList()).toList();

    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: _greenDark),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.center,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
      cellDecoration: (index, data, rowNum) {
        if (rowNum == 0) return const pw.BoxDecoration();
        return pw.BoxDecoration(color: rowNum.isEven ? _lightGray : PdfColors.white);
      },
    );
  }

  static String _sanitizeFileName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// ملف مضغوط (ZIP) لشطر واحد يحوي 5 ملفات PDF، ملف واحد لكل قسم من أقسام
  /// الكلية الخمسة - هذا ما يُنزَّل فعليًا من زر التنزيل تحت بطاقة كل شطر.
  static Future<Uint8List> buildZipForShatr({
    required String shatrLabel,
    required String shatrFileWord,
    required List<CourseSectionRecord> records,
    List<CourseSectionRecord> outsideRecords = const [],
    bool includeNotes = false,
  }) async {
    final archive = Archive();
    for (final department in CourseCatalog.departments) {
      final deptRecords = recordsForDepartment(records, department);
      final pdfBytes = await build(
        department: department,
        shatrLabel: shatrLabel,
        records: deptRecords,
        outsideRecords: outsideRecords,
        includeNotes: includeNotes,
      );
      // اسم الملف ثابت الصيغة عمدًا ("قسم [الاسم] - طلاب/طالبات.pdf") حتى لا
      // يتغيّر بين تنزيلة وأخرى مهما تحدَّثت المقررات لاحقًا - بطلب سليمان
      // صراحةً (2026-08-29).
      final fileName = '${_sanitizeFileName(department)} - $shatrFileWord.pdf';
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));
    }
    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }
}

/// اختصار لتحميل بيانات شطر معيّن ثم بناء ملفه المضغوط مباشرة - يُستخدَم من
/// زر التنزيل بصفحة "رفع الملفات" حتى لا تحتاج الشاشة الاحتفاظ بكل السجلات
/// بحالتها (تحمَّل عند الطلب فقط).
Future<Uint8List> buildCourseScheduleStudentZip(Shatr shatr, {bool includeNotes = false}) async {
  final records = await CourseScheduleRepository.loadSchedule(shatr);
  final outsideRecords = await OutsideCourseRepository.loadSections(shatr);
  return CourseScheduleStudentPdfService.buildZipForShatr(
    shatrLabel: shatr.label,
    shatrFileWord: shatr == Shatr.male ? 'طلاب' : 'طالبات',
    records: records,
    outsideRecords: outsideRecords,
    includeNotes: includeNotes,
  );
}
