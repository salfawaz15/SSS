import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/name_display.dart';
import 'pdf_brand_kit.dart';
import 'student_status_card_service.dart';

/// يبني ملف PDF بصفحة واحدة لبطاقة حالة طالب واحد (تقرير المرشد + طلبها
/// المقدَّم + ملاحظة المرشد) - قابلة للإرسال مباشرة للطالب أو العميد أو أي
/// جهة، بنفس هوية `PdfBrandKit` المعتمدة لكل ملفات الوحدة.
class StudentStatusCardPdfService {
  static final _gold = PdfColor.fromHex('C9A227');
  static final _lightGray = PdfColor.fromHex('EEF2F0');
  static final _line = PdfColor.fromHex('DCE3DF');
  static final _ok = PdfColor.fromHex('1C7A4E');
  static final _okBg = PdfColor.fromHex('E7F4EC');
  static final _pending = PdfColor.fromHex('96731A');
  static final _pendingBg = PdfColor.fromHex('FBF2DE');
  static final _warn = PdfColor.fromHex('B3261E');
  static final _warnBg = PdfColor.fromHex('FBEAE9');
  static final _inkSoft = PdfColor.fromHex('4B5A55');

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

  static (String label, PdfColor fg, PdfColor bg) _statusStyle(StudentStatusCardData data) {
    final decision = data.ticket?.advisorDecision;
    if (data.ticket == null || data.ticket!.actions.isEmpty) return ('لا يوجد طلب مقدَّم', _inkSoft, _lightGray);
    if (decision == null) return ('بانتظار المرشد/ة', _pending, _pendingBg);
    final status = decision.advisorStatus;
    if (status.contains('رفض')) return ('مرفوض - يحتاج متابعة', _warn, _warnBg);
    if (status.isNotEmpty) return ('تمت الموافقة', _ok, _okBg);
    return ('بانتظار المرشد/ة', _pending, _pendingBg);
  }

  static Future<Uint8List> build(StudentStatusCardData data) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final regularFont = pw.Font.ttf(regularBytes.buffer.asByteData());
    final boldFont = pw.Font.ttf(boldBytes.buffer.asByteData());
    final logo = pw.MemoryImage(await _loadLogoBytes());

    final r = data.record;
    final ticket = data.ticket;
    final (statusLabel, statusFg, statusBg) = _statusStyle(data);
    final decision = ticket?.advisorDecision;

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfBrandKit.header(title: 'بطاقة حالة طالب/ة', logo: logo, generatedAt: DateTime.now()),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(colors: [PdfBrandKit.greenDark, PdfBrandKit.green]),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(displayName(r.studentName),
                      style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.white)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${r.department}  ·  ${r.shatr}  ·  المرشد/ة: ${displayName(r.advisorNameRaw).isEmpty ? 'غير محدَّد' : displayName(r.advisorNameRaw)}  ·  الرقم الجامعي: ${r.studentId}',
                    style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.white),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: pw.BoxDecoration(color: statusBg, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(statusLabel, style: pw.TextStyle(font: boldFont, fontSize: 11, color: statusFg)),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _panel(boldFont, 'تقرير المرشد', [
                  _kv('الحالة الصحية', r.healthCondition.isEmpty ? 'لا يوجد' : r.healthCondition),
                  _kv('حالة القيد', r.enrollmentStatus.isEmpty ? 'منتظم/ة' : r.enrollmentStatus),
                  _kv('المعدل التراكمي', r.gpa?.toStringAsFixed(2) ?? 'غير مسجَّل بالتقرير'),
                ])),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: _panel(
                    boldFont,
                    ticket == null || ticket.actions.isEmpty ? 'الطلب المقدَّم' : 'الطلب المقدَّم (${ticket.actions.length})',
                    ticket == null || ticket.actions.isEmpty
                        ? [pw.Text('لم تتقدَّم بأي طلب إضافة/حذف/تعديل حتى الآن.', style: pw.TextStyle(fontSize: 9, color: _inkSoft))]
                        : ticket.actions
                            .map((a) => pw.Container(
                                  margin: const pw.EdgeInsets.only(bottom: 6),
                                  padding: const pw.EdgeInsets.all(6),
                                  decoration: pw.BoxDecoration(color: _lightGray, borderRadius: pw.BorderRadius.circular(5)),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Row(
                                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                        children: [
                                          pw.Expanded(child: pw.Text(a.courseName, style: pw.TextStyle(font: boldFont, fontSize: 9))),
                                          pw.Container(
                                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: pw.BoxDecoration(color: _gold, borderRadius: pw.BorderRadius.circular(999)),
                                            child: pw.Text(a.actionType, style: pw.TextStyle(fontSize: 7.5, color: PdfBrandKit.greenDark)),
                                          ),
                                        ],
                                      ),
                                      if (a.reason.trim().isNotEmpty)
                                        pw.Text(a.reason, style: pw.TextStyle(fontSize: 8, color: _inkSoft)),
                                    ],
                                  ),
                                ))
                            .toList(),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: _lightGray,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border(right: pw.BorderSide(color: _gold, width: 2.5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ملاحظة المرشد/ة على الحالة',
                      style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfBrandKit.greenDark)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    decision == null || decision.advisorNotes.trim().isEmpty
                        ? 'لم يكتب المرشد/ة أي ملاحظة بعد - الطلب لم يُفتَح من قِبله/ا.'
                        : '"${decision.advisorNotes.trim()}"',
                    style: pw.TextStyle(fontSize: 9, color: decision == null ? _inkSoft : PdfColors.black),
                  ),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Divider(color: _line),
            pw.Text('صادرة عن وحدة الإرشاد الأكاديمي والخريجين - جامعة الطائف', style: pw.TextStyle(fontSize: 7.5, color: _inkSoft)),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _panel(pw.Font boldFont, String title, List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: _gold)),
          pw.SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: pw.TextStyle(fontSize: 9, color: _inkSoft)),
            pw.Text(v, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
}
