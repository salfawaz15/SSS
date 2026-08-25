import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// يُصلح عيوب توافق معروفة بملفات xlsx (خصوصًا المُصدَّرة من Microsoft
/// Forms - نفس المصدر ينتجها بثبات بكل تصدير) والتي تجعل حزمة `excel`
/// في Dart تفشل بصمت أو باستثناء رغم أن الملف يفتح طبيعيًا ببرنامج Excel:
///
/// 1. مسارات مطلقة `Target="/xl/..."` بملفات `.rels` بدل مسارات نسبية -
///    `excel` تلصق `xl/` أمام القيمة حرفيًا فينتج مسار مضاعَف غير موجود
///    (`Damaged Excel file: styles`).
/// 2. بادئة نطاق أسماء `x:` على كل عنصر (`<x:sheet>` بدل `<sheet>`) -
///    `excel` يبحث بأسماء بلا بادئة فلا يجد شيئًا (فشل صامت بلا استثناء،
///    الجدول يُقرأ فارغًا).
/// 3. خلايا فارغة موسومة زورًا `t="s"` بلا عنصر `<v>` بداخلها
///    (`Bad state: No element`).
/// 4. عنصر `<numFmts>` يحوي `numFmtId` أقل من 164 (خاص بملفات اختبارية
///    تُولَّد عبر SheetJS بدون خيارات معيّنة، لا ملفات Forms الحقيقية) -
///    حزمة `excel` تفترض بصرامة أن كل تنسيق مخصَّص يبدأ من المعرّف 164،
///    فترمي `Exception: custom numFmtId starts at 164 but found a value
///    of ...`. الحل الموثَّق: حذف عنصر `<numFmts>` بالكامل من `styles.xml`
///    (تُهمَل تنسيقات الأرقام المخصَّصة، لا قيم الخلايا نفسها).
///
/// يُطبَّق دائمًا وبأمان (بلا تأثير لو الملف سليم أصلاً - كل الاستبدالات
/// idempotent) قبل أي محاولة قراءة بأي مكان يستقبل ملف xlsx مرفوعًا، ويعيد
/// البايتات الأصلية دون تعديل لو تعذّرت المعالجة لأي سبب.
Uint8List sanitizeXlsxBytes(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    var changed = false;
    final fixedArchive = Archive();

    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final name = file.name;
      final content = file.content as List<int>;
      List<int> fixedContent = content;

      if (name.endsWith('.rels')) {
        final text = utf8.decode(content, allowMalformed: true);
        final fixed = text.replaceAll('Target="/xl/', 'Target="');
        if (fixed != text) {
          changed = true;
          fixedContent = utf8.encode(fixed);
        }
      } else if (name.startsWith('xl/') && name.endsWith('.xml')) {
        final text = utf8.decode(content, allowMalformed: true);
        var fixed = text
            .replaceAll('<x:', '<')
            .replaceAll('</x:', '</')
            .replaceAll('xmlns:x="', 'xmlns="');
        if (name.startsWith('xl/worksheets/')) {
          fixed = fixed.replaceAllMapped(
            RegExp(r'(<c\b[^>]*?)\s+t="s"([^>]*?)/>'),
            (m) => '${m[1]}${m[2]}/>',
          );
        }
        if (name == 'xl/styles.xml') {
          final numFmtsMatch = RegExp(r'<numFmts[^>]*>(.*?)</numFmts>', dotAll: true).firstMatch(fixed);
          if (numFmtsMatch != null) {
            final hasInvalidId = RegExp(r'numFmtId="(\d+)"').allMatches(numFmtsMatch.group(1)!).any(
                  (m) => (int.tryParse(m.group(1)!) ?? 164) < 164,
                );
            if (hasInvalidId) {
              fixed = fixed.replaceRange(numFmtsMatch.start, numFmtsMatch.end, '');
            }
          }
        }
        if (fixed != text) {
          changed = true;
          fixedContent = utf8.encode(fixed);
        }
      }

      fixedArchive.addFile(
        ArchiveFile(name, fixedContent.length, fixedContent),
      );
    }

    if (!changed) {
      return bytes;
    }
    final encoded = ZipEncoder().encode(fixedArchive);
    if (encoded == null) {
      return bytes;
    }
    return Uint8List.fromList(encoded);
  } catch (_) {
    return bytes;
  }
}
