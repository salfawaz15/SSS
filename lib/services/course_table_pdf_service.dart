import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// صف واحد جاهز للطباعة في تقرير "دليل مقررات الحذف والإضافة".
class CourseTablePdfRow {
  final String department;
  final String courseCode;
  final String courseName;
  final String plans;
  final String? shatrLabel; // يُعرض فقط عند اختيار "كل الشطرين"
  final String theorySection;
  final String? practicalSection;
  final String meetingsText;
  final String? practicalMeetingsText;
  final String instructorName;
  final String? practicalInstructorName;
  final String note;

  const CourseTablePdfRow({
    required this.department,
    required this.courseCode,
    required this.courseName,
    required this.plans,
    this.shatrLabel,
    required this.theorySection,
    this.practicalSection,
    required this.meetingsText,
    this.practicalMeetingsText,
    required this.instructorName,
    this.practicalInstructorName,
    required this.note,
  });
}

/// يبني نسخة PDF من جدول مقررات الحذف والإضافة بنفس الهوية البصرية المعتمدة
/// (الشعار وألوان الوحدة)، مطابقة لما يظهر على الشاشة مع مراعاة تصفية الشطر.
class CourseTablePdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _lightGray = PdfColor.fromHex('E5E9E7');

  static Future<(Uint8List, Uint8List)>? _cachedFontBytes;
  static Future<(Uint8List, Uint8List)> _loadFontBytes() {
    return _cachedFontBytes ??= () async {
      final regularBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      final boldBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
      return (regularBytes.buffer.asUint8List(), boldBytes.buffer.asUint8List());
    }();
  }

  static Future<Uint8List>? _cachedLogoBytes;
  static Future<Uint8List> _loadLogoBytes() {
    return _cachedLogoBytes ??= rootBundle.load('assets/images/unit_logo_light.png').then((b) => b.buffer.asUint8List());
  }

  static Future<Uint8List> build({
    required List<CourseTablePdfRow> rows,
    required bool showShatrColumn,
    String term = 'الفصل الدراسي الأول 1448هـ',
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final regularFont = pw.Font.ttf(regularBytes.buffer.asByteData());
    final boldFont = pw.Font.ttf(boldBytes.buffer.asByteData());
    final logoBytes = await _loadLogoBytes();
    final logo = pw.MemoryImage(logoBytes);

    // ترتيب الأعمدة معكوس (RTL) بحيث يظهر "القسم" أول عمود من اليمين.
    final headers = [
      'ملاحظات',
      'المحاضر',
      'الأيام والوقت',
      'الشعبة',
      if (showShatrColumn) 'الشطر',
      'نوع الخطة',
      'اسم المقرر',
      'رمز المقرر',
      'القسم',
    ].reversed.toList();

    String twoLine(String top, String? bottom) => bottom == null ? top : '$top\n$bottom';

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        header: (context) {
          if (context.pageNumber > 1) return pw.SizedBox();
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Image(logo, height: 40),
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text('دليل مقررات الحذف والإضافة',
                            style: pw.TextStyle(font: boldFont, fontSize: 15, color: _green)),
                        pw.SizedBox(height: 3),
                        pw.Text(term, style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 40),
                ],
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows.map((r) {
              final cells = [
                r.note,
                twoLine(r.instructorName, r.practicalInstructorName),
                twoLine(r.meetingsText, r.practicalMeetingsText),
                twoLine(r.theorySection, r.practicalSection),
                if (showShatrColumn) r.shatrLabel ?? '',
                r.plans,
                r.courseName,
                r.courseCode,
                r.department,
              ];
              return cells.reversed.toList();
            }).toList(),
            headerStyle: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.black),
            headerDecoration: pw.BoxDecoration(color: _lightGray),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        ],
      ),
    );

    return doc.save();
  }
}
