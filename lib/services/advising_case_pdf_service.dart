import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_brand_kit.dart';

/// يبني تقرير PDF عام (عنوان + جدول بأعمدة/صفوف نصية جاهزة) بنفس الهوية
/// البصرية المعتمدة - يُستخدم لكل تقارير "متابعة حالات الإرشاد" الفرعية
/// (طلاب بلا مرشد، تعارض قسم، توازن التوزيع...) بدل بناء صنف PDF مستقل لكل
/// نوع حالة، لأن الشكل نفسه في الجميع (عنوان + جدول موسَّط).
class AdvisingCasePdfService {
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
    return _cachedLogoBytes ??= rootBundle.load('assets/images/unit_logo_final.png').then((b) => b.buffer.asUint8List());
  }

  static Future<Uint8List> build({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String term = 'الفصل الدراسي الأول 1448هـ',
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final regularFont = pw.Font.ttf(regularBytes.buffer.asByteData());
    final boldFont = pw.Font.ttf(boldBytes.buffer.asByteData());
    final logoBytes = await _loadLogoBytes();
    final logo = pw.MemoryImage(logoBytes);

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
            headers: headers.reversed.toList(),
            data: rows.map((r) => r.reversed.toList()).toList(),
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
