import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:printing/printing.dart';

import '../models/advising_schedule.dart';
import 'advising_schedule_pdf_service.dart';

/// يحوّل بطاقات شاشات العرض (يوم × قسم × شطر، كل بطاقة PDF أحادي الصفحة من
/// [AdvisingSchedulePdfService.buildSignageCards]) إلى صور PNG مضغوطة داخل
/// ملف ZIP واحد - طلب سليمان 2026-08-24: إرسالها لسكرتارية الكلية لعرضها
/// كشرائح (slideshow) على شاشات الإسياب بالكلية بدل ملف PDF طويل.
class AdvisingScheduleSignageImageService {
  /// دقة الصورة (نقطة/إنش) - قيمة تعطي وضوحًا كافيًا على شاشة إسياب كبيرة
  /// بلا حجم ملف مبالغ فيه.
  static const double _dpi = 200;

  static Future<Uint8List> buildZip({
    required Map<(String, String), List<AdvisingScheduleSlot>> byDeptShatr,
  }) async {
    final cards = await AdvisingSchedulePdfService.buildSignageCards(byDeptShatr: byDeptShatr);

    final archive = Archive();
    final usedNames = <String, int>{};

    for (final card in cards) {
      final rasters = await Printing.raster(card.pdfBytes, dpi: _dpi).toList();
      if (rasters.isEmpty) continue;
      final pngBytes = await rasters.first.toPng();

      var safeName = _sanitizeFileName(card.label);
      final count = usedNames.update(safeName, (v) => v + 1, ifAbsent: () => 1);
      if (count > 1) safeName = '${safeName}_$count';

      archive.addFile(ArchiveFile('$safeName.png', pngBytes.length, pngBytes));
    }

    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  static String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }
}
