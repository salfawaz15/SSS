import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_brand_kit.dart';

/// صف واحد جاهز للطباعة في تقرير "دليل مقررات الحذف والإضافة".
class CourseTablePdfRow {
  final String department;
  final String courseCode;
  final String courseName;
  final String? shatrLabel; // يُعرض فقط عند اختيار "كل الشطرين"
  final String theorySection;
  final String? practicalSection;
  final int theoryHours;
  final int practicalHours;
  final int theoryMaxCapacity;
  final int? practicalMaxCapacity;
  final int theoryRegistered;
  final int? practicalRegistered;
  final String dayText;
  final String? practicalDayText;
  final String timeText;
  final String? practicalTimeText;
  final String instructorName;
  final String? practicalInstructorName;

  const CourseTablePdfRow({
    required this.department,
    required this.courseCode,
    required this.courseName,
    this.shatrLabel,
    required this.theorySection,
    this.practicalSection,
    required this.theoryHours,
    required this.practicalHours,
    required this.theoryMaxCapacity,
    this.practicalMaxCapacity,
    required this.theoryRegistered,
    this.practicalRegistered,
    required this.dayText,
    this.practicalDayText,
    required this.timeText,
    this.practicalTimeText,
    required this.instructorName,
    this.practicalInstructorName,
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
    required String title,
    String term = 'الفصل الدراسي الأول 1448هـ',
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final regularFont = pw.Font.ttf(regularBytes.buffer.asByteData());
    final boldFont = pw.Font.ttf(boldBytes.buffer.asByteData());
    final logoBytes = await _loadLogoBytes();
    final logo = pw.MemoryImage(logoBytes);

    // ترتيب الأعمدة بصيغة LTR (بحيث يظهر آخر عنصر أول عمود من اليمين فعليًا)،
    // مطابق للتنسيق المعتمد للنظري/العملي: اسم المقرر، الشعبة، المقرر، عدد
    // الساعات، النشاط، اعلى حد، المسجلين، اليوم، الوقت، المحاضر (بلا رقم
    // محاضر)، ثم الشطر والملاحظات. القسم لا يظهر كعمود لأن العنوان الديناميكي
    // (title) يذكره أصلاً عند تصفية قسم واحد.
    final headers = [
      if (showShatrColumn) 'الشطر',
      'المحاضر',
      'الوقت',
      'اليوم',
      'المسجلين',
      'اعلى حد',
      'النشاط',
      'عدد الساعات',
      'المقرر',
      'الشعبة',
      'اسم المقرر',
    ];

    String twoLine(String top, String? bottom) => bottom == null ? top : '$top\n$bottom';
    String twoLineInt(int top, int? bottom) => bottom == null ? '$top' : '$top\n$bottom';

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        footer: (context) => pw.Align(alignment: pw.Alignment.bottomLeft, child: PdfBrandKit.watermark()),
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
                        pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 15, color: _green)),
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
              final hasPractical = r.practicalSection != null;
              return [
                if (showShatrColumn) r.shatrLabel ?? '',
                twoLine(r.instructorName, r.practicalInstructorName),
                twoLine(r.timeText, hasPractical ? r.practicalTimeText : null),
                twoLine(r.dayText, hasPractical ? r.practicalDayText : null),
                twoLineInt(r.theoryRegistered, hasPractical ? r.practicalRegistered : null),
                twoLineInt(r.theoryMaxCapacity, hasPractical ? r.practicalMaxCapacity : null),
                hasPractical ? 'نظري\nعملي' : 'نظري',
                twoLineInt(r.theoryHours, hasPractical ? r.practicalHours : null),
                r.courseCode,
                twoLine(r.theorySection, r.practicalSection),
                r.courseName,
              ];
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
