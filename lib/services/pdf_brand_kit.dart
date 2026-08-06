import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// هوية بصرية موحّدة لكل ملفات PDF الصادرة عن الوحدة (تقارير، جداول
/// إرشاد، جداول مقررات، نصاب تدريسي، دليل التشغيل...) - قبل هذا الملف كان
/// كل ملف PDF يبني ترويسة/تذييل خاصين به من الصفر بألوان وتخطيطات مختلفة،
/// بحيث لا يمكن التعرّف على أن ملفًا ما صادر عن الوحدة لمجرد النظر إليه
/// بلا قراءة محتواه. هذا الملف هو المرجع الوحيد الآن لشكل الترويسة/التذييل،
/// ويُستدعى من كل خدمات *_pdf_service.dart بدل إعادة كتابته في كل مرة.
class PdfBrandKit {
  static final green = PdfColor.fromHex('154B36');
  static final greenDark = PdfColor.fromHex('0D3324');
  static final gold = PdfColor.fromHex('C9A227');
  static final lightGray = PdfColor.fromHex('E5E9E7');
  static final grayText = PdfColor.fromHex('666666');

  /// شريط ترويسة موحّد: شعار الوحدة + اسمها على اليمين (بخلفية بيضاء صغيرة
  /// خلف الشعار حتى لا تظهر حواف الشعار المموَّهة كخطوط بيضاء على الأخضر)،
  /// والعنوان + تاريخ الإصدار على اليسار، وشارة اختيارية (subtitle) أسفله
  /// لتوضيح نطاق التقرير (قسم/شطر/مرحلة...).
  static pw.Widget header({
    required String title,
    required pw.MemoryImage logo,
    String? subtitle,
    DateTime? generatedAt,
  }) {
    final dateLabel = generatedAt == null
        ? null
        : '${generatedAt.year}/${generatedAt.month.toString().padLeft(2, '0')}/${generatedAt.day.toString().padLeft(2, '0')}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(colors: [greenDark, green]),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Image(logo, height: 24, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    'وحدة الإرشاد الأكاديمي والخريجين',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.white),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  ),
                  if (dateLabel != null) ...[
                    pw.SizedBox(height: 2),
                    pw.Text('تاريخ الإصدار: $dateLabel', style: pw.TextStyle(fontSize: 8, color: PdfColors.white)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (subtitle != null) ...[
          pw.SizedBox(height: 6),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: pw.BoxDecoration(color: gold, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(
                subtitle,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: greenDark),
              ),
            ),
          ),
        ],
        pw.SizedBox(height: 10),
      ],
    );
  }

  /// تذييل موحّد: خط فاصل رفيع + "صفحة X من Y - وحدة الإرشاد الأكاديمي
  /// والخريجين" بحيث يظهر مصدر الملف حتى لو انفصلت الصفحة عن بقية التقرير.
  static pw.Widget footer(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: lightGray),
        pw.Text(
          'صفحة ${context.pageNumber} من ${context.pagesCount}  -  وحدة الإرشاد الأكاديمي والخريجين',
          style: pw.TextStyle(fontSize: 8, color: grayText),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }
}
