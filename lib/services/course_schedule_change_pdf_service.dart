import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/course_schedule_change.dart';
import 'pdf_brand_kit.dart';

/// يبني ملف PDF بتغييرات جدول المقررات (الحويّة) المكتشَفة تلقائيًا بين
/// رفعتين (إضافة شعبة/حذفها/تغيير عضو هيئة تدريس) - يُنزَّل مباشرة بعد كل
/// رفعة تحوي رفعة سابقة تُقارَن بها (انظر نقطة الاستدعاء بـ
/// `runUploadCourses`، upload_flows.dart)، حتى يعرف رافع الملف فورًا ما تغيّر
/// دون مقارنة يدوية بين نسختين.
class CourseScheduleChangePdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _greenDark = PdfColor.fromHex('0D3324');
  static final _addedBg = PdfColor.fromHex('EAF3EE');
  static final _removedBg = PdfColor.fromHex('FDEAEA');
  static final _changedBg = PdfColor.fromHex('FBF3DD');
  static final _lightGray = PdfColor.fromHex('E5E9E7');

  static String _typeLabel(CourseScheduleChangeType t) => switch (t) {
        CourseScheduleChangeType.added => 'إضافة',
        CourseScheduleChangeType.removed => 'حذف',
        CourseScheduleChangeType.instructorChanged => 'تغيير محاضر',
      };

  static PdfColor _typeColor(CourseScheduleChangeType t) => switch (t) {
        CourseScheduleChangeType.added => _addedBg,
        CourseScheduleChangeType.removed => _removedBg,
        CourseScheduleChangeType.instructorChanged => _changedBg,
      };

  static Future<Uint8List> build(List<CourseScheduleChangeEntry> changes) async {
    final regularBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final boldBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
    final logoBytes = await rootBundle.load('assets/images/unit_logo_final.png');
    final regularFont = pw.Font.ttf(regularBytes);
    final boldFont = pw.Font.ttf(boldBytes);
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final generatedAt = DateTime.now();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    final added = changes.where((c) => c.type == CourseScheduleChangeType.added).toList();
    final removed = changes.where((c) => c.type == CourseScheduleChangeType.removed).toList();
    final instructorChanged = changes.where((c) => c.type == CourseScheduleChangeType.instructorChanged).toList();

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => PdfBrandKit.header(
          title: 'تغييرات جدول المقررات (الحويّة)',
          logo: logo,
          subtitle: 'مقارنة بآخر رفعة معتمدة سابقة',
          generatedAt: generatedAt,
        ),
        footer: PdfBrandKit.footer,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: _lightGray, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _stat('شُعب مُضافة', '${added.length}', _green),
                _stat('شُعب محذوفة', '${removed.length}', PdfColor.fromHex('C0392B')),
                _stat('تغيير محاضر', '${instructorChanged.length}', PdfColor.fromHex('C9A227')),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          if (changes.isEmpty)
            pw.Text('لا توجد تغييرات مقارنة بآخر رفعة معتمدة.', style: const pw.TextStyle(fontSize: 11))
          else
            _changesTable(changes),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _stat(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: color)),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  static pw.Widget _changesTable(List<CourseScheduleChangeEntry> changes) {
    final headers = ['نوع التغيير', 'الشطر', 'رمز المقرر', 'اسم المقرر', 'الشعبة', 'الموعد', 'التفاصيل'];
    final rows = changes.map((c) {
      return [
        _typeLabel(c.type),
        c.shatr,
        c.courseCode,
        c.courseName,
        c.section,
        c.dayTimeText,
        c.note,
      ];
    }).toList();

    final rtlHeaders = headers.reversed.toList();
    final rtlRows = rows.map((r) => r.reversed.toList()).toList();

    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: _greenDark),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellAlignment: pw.Alignment.centerRight,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
      cellDecoration: (index, data, rowNum) {
        if (rowNum == 0) return const pw.BoxDecoration();
        return pw.BoxDecoration(color: _typeColor(changes[rowNum - 1].type));
      },
    );
  }
}
