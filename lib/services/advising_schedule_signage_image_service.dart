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

      var safeName = _sanitizeFileName(card.label);
      final count = usedNames.update(safeName, (v) => v + 1, ifAbsent: () => 1);
      if (count > 1) safeName = '${safeName}_$count';

      // البطاقة `pw.MultiPage` قد تفيض لصفحة ثانية إن لم يتّسع الجدول مع
      // الترويسة بصفحة واحدة (`Row` لا يُقسَّم بين الصفحات، فتُدفَع كتلة
      // الجدول كاملة للصفحة التالية) - أخذ الصفحة الأولى فقط (`rasters.first`)
      // كان يُنتج صورة بلا جدول إطلاقًا (الترويسة فقط) بينما الجدول الفعلي
      // بصفحة ثانية مُهمَلة تمامًا - دليل فعلي من سليمان (2026-08-25): بطاقة
      // "الاقتصاد والتمويل - شطر الطالبات - الثلاثاء - الفترة الأولى" (15
      // مرشدة) ظهرت فارغة تمامًا تحت مربع الفترة. تُصدَّر الآن كل صفحات
      // البطاقة كصور منفصلة (يندر أن تتجاوز صفحتين) بدل فقد المحتوى بصمت.
      for (var pageIndex = 0; pageIndex < rasters.length; pageIndex++) {
        final pngBytes = await rasters[pageIndex].toPng();
        final pageName = rasters.length > 1 ? '${safeName}_ص${pageIndex + 1}' : safeName;
        archive.addFile(ArchiveFile('$pageName.png', pngBytes.length, pngBytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  /// نفس صور [buildZip] حرفيًا (نفس تصميم/دقة بطاقات شاشات العرض)، لكن
  /// مُنظَّمة داخل الملف المضغوط بمجلد لكل شطر ثم مجلد فرعي لكل قسم - بحيث
  /// تحتوي شاشة القسم الواحد على فتراته وحده بلا اختلاط مع أي قسم آخر (طلب
  /// سليمان صراحةً 2026-08-27: "لكل قسم شاشة يريد أن يضع فتراته دون داخل
  /// مع أي قسم آخر") - بدل الملف المسطَّح الحالي حيث تتجاور صور كل الأقسام
  /// بلا فواصل مجلدات.
  static Future<Uint8List> buildZipByDepartment({
    required Map<(String, String), List<AdvisingScheduleSlot>> byDeptShatr,
  }) async {
    final cards = await AdvisingSchedulePdfService.buildSignageCards(byDeptShatr: byDeptShatr);

    final archive = Archive();
    final usedNames = <String, int>{};

    for (final card in cards) {
      final rasters = await Printing.raster(card.pdfBytes, dpi: _dpi).toList();
      if (rasters.isEmpty) continue;

      final folder = '${card.shatr}/${_sanitizeFileName(card.department)}';
      var safeName = _sanitizeFileName(card.label);
      final nameKey = '$folder/$safeName';
      final count = usedNames.update(nameKey, (v) => v + 1, ifAbsent: () => 1);
      if (count > 1) safeName = '${safeName}_$count';

      for (var pageIndex = 0; pageIndex < rasters.length; pageIndex++) {
        final pngBytes = await rasters[pageIndex].toPng();
        final pageName = rasters.length > 1 ? '${safeName}_ص${pageIndex + 1}' : safeName;
        archive.addFile(ArchiveFile('$folder/$pageName.png', pngBytes.length, pngBytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  static String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }
}
