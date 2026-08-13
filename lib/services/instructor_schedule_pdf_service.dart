import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/course_section_record.dart';
import 'college_roster_lookup_service.dart';
import 'college_roster_repository.dart';
import 'instructor_schedule_table.dart';
import 'pdf_brand_kit.dart';

/// يبني نسخة PDF من الجدول الدراسي لعضو هيئة تدريس واحد، بنفس أعمدة الجدول
/// الرسمي في البوابة الإلكترونية للجامعة (EduGate): قائمة مسطّحة مرتّبة
/// زمنيًا مع إجمالي الساعات المعتمدة، بهوية بصرية موحّدة (أخضر/ذهبي).
class InstructorSchedulePdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _gold = PdfColor.fromHex('C9A227');
  static final _cream = PdfColor.fromHex('FBF9F3');
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
    required String instructorName,
    required String department,
    required List<CourseSectionRecord> records,
    String term = 'الفصل الدراسي الأول 1448هـ',
    String? officeNumber,
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final regularFont = pw.Font.ttf(regularBytes.buffer.asByteData());
    final boldFont = pw.Font.ttf(boldBytes.buffer.asByteData());
    final logoBytes = await _loadLogoBytes();
    final logo = pw.MemoryImage(logoBytes);

    final tableRows = InstructorScheduleTable.buildRows(records);

    // المصدر الوحيد لاسم رئيس القسم وعميد الكلية هو ملف أعضاء هيئة التدريس
    // المعتمد المرفوع عبر الموقع - لا قوائم ثابتة بالكود (college_leadership.dart
    // القديم مصدره ملفات من مجلد المرفقات وليس ملفًا مرفوعًا).
    final roster = await CollegeRosterRepository.load();
    final headHint = CollegeRosterLookupService.departmentHeadName(roster, department) ?? '';
    final deanName = CollegeRosterLookupService.deanName(roster) ?? '';

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    // ترتيب الأعمدة معكوس (RTL): "رمز المقرر" أولًا في القائمة => يظهر
    // أقصى اليمين، مطابقًا لترتيب القراءة الطبيعي.
    final headers = ['الوقت', 'اليوم', 'الساعات', 'الشعبة', 'النشاط', 'اسم المقرر', 'رمز المقرر'];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        footer: (context) => pw.Align(alignment: pw.Alignment.bottomLeft, child: PdfBrandKit.watermark()),
        header: (context) {
          if (context.pageNumber > 1) return pw.SizedBox();
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(logo, boldFont),
              pw.SizedBox(height: 14),
              _infoChipsRow(term, department, instructorName, officeNumber, boldFont, regularFont),
              pw.SizedBox(height: 14),
            ],
          );
        },
        build: (context) => [
          _instructorTable(headers, tableRows, boldFont),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock('عضو هيئة التدريس', instructorName, boldFont),
              _signatureBlock('رئيس القسم', headHint, boldFont),
              _signatureBlock('عميد كلية إدارة الأعمال', deanName, boldFont),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// خلية مدمجة: نظري أعلى وعملي أسفل (بفاصل رفيع) بدل تكرار الصف كاملًا
  /// عندما يكون للمقرر شعبتا نظري وعملي - نفس فكرة جدول "جميع المقررات".
  static const _cellFontSize = 9.5;
  static const _cellTextStyle = pw.TextStyle(fontSize: _cellFontSize);

  static pw.Widget _splitCell(String top, String bottom) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(top, textAlign: pw.TextAlign.center, style: _cellTextStyle),
        pw.Container(height: 0.6, width: 30, margin: const pw.EdgeInsets.symmetric(vertical: 2), color: PdfColors.grey400),
        pw.Text(bottom, textAlign: pw.TextAlign.center, style: _cellTextStyle),
      ],
    );
  }

  static pw.Widget _instructorTable(List<String> headers, List<InstructorScheduleRow> tableRows, pw.Font boldFont) {
    const rowMinHeight = 34.0;
    pw.Widget headerCell(String text) => pw.Container(
          constraints: const pw.BoxConstraints(minHeight: rowMinHeight),
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(text, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: _cellFontSize, color: PdfColors.white)),
        );
    pw.Widget bodyCell(pw.Widget child) => pw.Container(
          constraints: const pw.BoxConstraints(minHeight: rowMinHeight),
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(5),
          child: child,
        );
    pw.Widget textCell(String text) => bodyCell(pw.Text(text, textAlign: pw.TextAlign.center, style: _cellTextStyle));

    if (tableRows.isEmpty) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          pw.TableRow(decoration: pw.BoxDecoration(color: _green), children: headers.map(headerCell).toList()),
          pw.TableRow(children: [
            for (var i = 0; i < headers.length; i++) textCell(i == headers.length - 2 ? 'لا توجد مقررات مسكَّنة لهذا العضو' : '—'),
          ]),
        ],
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(0.8),
        3: pw.FlexColumnWidth(0.8),
        4: pw.FlexColumnWidth(0.9),
        5: pw.FlexColumnWidth(2.2),
        6: pw.FlexColumnWidth(1.1),
      },
      children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: _green), children: headers.map(headerCell).toList()),
        for (var i = 0; i < tableRows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _lightGray.shade(0.3)),
            children: [
              bodyCell(!tableRows[i].hasPractical
                  ? pw.Text(tableRows[i].theoryTimeRange, textAlign: pw.TextAlign.center, style: _cellTextStyle)
                  : _splitCell(tableRows[i].theoryTimeRange, tableRows[i].practicalTimeRange!)),
              bodyCell(!tableRows[i].hasPractical
                  ? pw.Text(tableRows[i].theoryDayName, textAlign: pw.TextAlign.center, style: _cellTextStyle)
                  : _splitCell(tableRows[i].theoryDayName, tableRows[i].practicalDayName!)),
              bodyCell(!tableRows[i].hasPractical
                  ? pw.Text('${tableRows[i].theoryHours}', textAlign: pw.TextAlign.center, style: _cellTextStyle)
                  : _splitCell('${tableRows[i].theoryHours}', '${tableRows[i].practicalHours}')),
              bodyCell(!tableRows[i].hasPractical
                  ? pw.Text(tableRows[i].theorySection, textAlign: pw.TextAlign.center, style: _cellTextStyle)
                  : _splitCell(tableRows[i].theorySection, tableRows[i].practicalSection!)),
              bodyCell(!tableRows[i].hasPractical ? pw.Text('نظري', textAlign: pw.TextAlign.center, style: _cellTextStyle) : _splitCell('نظري', 'عملي')),
              textCell(tableRows[i].courseName),
              textCell(tableRows[i].courseCode),
            ],
          ),
      ],
    );
  }

  static pw.Widget _diamond() {
    return pw.Transform.rotate(angle: 0.785, child: pw.Container(width: 7, height: 7, color: _gold));
  }

  static pw.Widget _header(pw.MemoryImage logo, pw.Font boldFont) {
    return pw.Container(
      color: _cream,
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Image(logo, height: 44),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    _diamond(),
                    pw.SizedBox(width: 8),
                    pw.Text('جدول عضو هيئة التدريس', style: pw.TextStyle(font: boldFont, fontSize: 20, color: _green)),
                    pw.SizedBox(width: 8),
                    _diamond(),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Container(height: 1.4, width: 220, color: _gold),
              ],
            ),
          ),
          pw.SizedBox(width: 56), // موازنة بصرية مقابل عرض الشعار كي يبقى العنوان مركزًا فعليًا
        ],
      ),
    );
  }

  static pw.Widget _infoChipsRow(
    String term,
    String department,
    String instructorName,
    String? officeNumber,
    pw.Font boldFont,
    pw.Font regularFont,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
      children: [
        _infoChip('الفصل الدراسي', term, boldFont, regularFont),
        _infoChip('القسم', department, boldFont, regularFont),
        _infoChip('عضو هيئة التدريس', instructorName, boldFont, regularFont),
        _infoChip('رقم المكتب', (officeNumber == null || officeNumber.isEmpty) ? '—' : officeNumber, boldFont, regularFont),
      ],
    );
  }

  static pw.Widget _infoChip(String label, String value, pw.Font boldFont, pw.Font regularFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _gold, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        color: PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label, style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 3),
          pw.Text(value, style: pw.TextStyle(font: boldFont, fontSize: 11, color: _green), textAlign: pw.TextAlign.center),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(String role, String name, pw.Font boldFont) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(role, style: pw.TextStyle(font: boldFont, fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text(name, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 24),
        pw.Container(width: 140, height: 0.8, color: PdfColors.grey600),
        pw.SizedBox(height: 4),
        pw.Text('التوقيع', style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }
}
