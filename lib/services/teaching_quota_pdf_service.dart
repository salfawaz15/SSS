import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_brand_kit.dart';

/// صف واحد جاهز للطباعة في تقرير النصاب التدريسي - مستقل عن أي حالة شاشة،
/// يبنيه المستدعي من _QuotaRow.
class TeachingQuotaPdfRow {
  final String name;
  final String department;
  final int actualHours;
  final int? maxHours;
  final String? note;

  const TeachingQuotaPdfRow({
    required this.name,
    required this.department,
    required this.actualHours,
    required this.maxHours,
    required this.note,
  });
}

/// يبني نسخة PDF من تقرير النصاب التدريسي (دون النصاب / فوق النصاب)،
/// بنفس الهوية البصرية لبقية مطبوعات الوحدة.
class TeachingQuotaPdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _gold = PdfColor.fromHex('C9A227');
  static final _lightGray = PdfColor.fromHex('F7F5EF');

  static Future<pw.Font>? _cachedRegularFont;
  static Future<pw.Font>? _cachedBoldFont;

  static Future<pw.Font> _regularFont() => _cachedRegularFont ??= () async {
        final bytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
        return pw.Font.ttf(bytes);
      }();
  static Future<pw.Font> _boldFont() => _cachedBoldFont ??= () async {
        final bytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
        return pw.Font.ttf(bytes);
      }();

  static Future<pw.MemoryImage> _logo() async {
    final bytes = await rootBundle.load('assets/images/unit_logo_final.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static Future<Uint8List> build({
    required String scopeLabel,
    required List<TeachingQuotaPdfRow> rows,
  }) async {
    final regular = await _regularFont();
    final bold = await _boldFont();
    final logo = await _logo();

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        header: (context) {
          if (context.pageNumber > 1) return pw.SizedBox();
          return pw.Column(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: pw.BoxDecoration(color: _green, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text('تقرير النصاب التدريسي',
                          maxLines: 2,
                          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 13)),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Image(logo, height: 32),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text('وحدة الإرشاد الأكاديمي والخريجين',
                          textAlign: pw.TextAlign.right,
                          maxLines: 2,
                          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(scopeLabel, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (context) => pw.Stack(
          children: [
            pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(top: 8),
              child: pw.Text('صفحة ${context.pageNumber} من ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ),
            pw.Positioned(left: 0, bottom: 0, child: PdfBrandKit.watermark()),
          ],
        ),
        build: (context) => [
          // ترتيب الأعمدة معكوس عمدًا (الملاحظة أولاً..الاسم أخيرًا) لأن
          // pw.Table يرتّب أعمدته فعليًا من يسار الصفحة لا حسب اتجاه النص،
          // فليظهر "الاسم" في أقصى يمين الصفحة (بداية القراءة العربية) لازم
          // يكون آخر عنصر في المصفوفة.
          pw.Table(
            border: pw.TableBorder.all(color: _gold, width: 0.6),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: pw.FlexColumnWidth(2.6),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(2.2),
              4: pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _green),
                children: [
                  _cell('الملاحظة', bold: true, color: PdfColors.white),
                  _cell('الحد النظامي', bold: true, color: PdfColors.white),
                  _cell('الساعات الفعلية', bold: true, color: PdfColors.white),
                  _cell('القسم', bold: true, color: PdfColors.white),
                  _cell('الاسم', bold: true, color: PdfColors.white),
                ],
              ),
              for (var i = 0; i < rows.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _lightGray),
                  children: [
                    _cell(rows[i].note ?? 'مطابق للنصاب'),
                    _cell(rows[i].maxHours?.toString() ?? '—'),
                    _cell('${rows[i].actualHours}'),
                    _cell(rows[i].department),
                    _cell(rows[i].name),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Center(
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      ),
    );
  }
}
