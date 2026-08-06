import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// يقرأ تاريخ آخر حفظ فعلي لملف xlsx من بيانات وصفه الداخلية
/// (docProps/core.xml -> dcterms:modified) بدلاً من الاعتماد على دالة إكسل
/// حيّة مثل TODAY() التي تتغيّر في كل فتح للملف. إكسل يكتب هذا التاريخ
/// تلقائيًا عند كل حفظ فعلي، فيبقى مجمّدًا بين الحفظات - نفس فكرة "تاريخ
/// السحب" المطبوع داخل جدول الحويّة، المستخدَم في CourseScheduleRepository
/// للتحقق من أن كل ملف جديد أحدث من النسخة المخزّنة قبل قبول رفعه.
class XlsxMetadataService {
  static DateTime? lastSavedAt(Uint8List xlsxBytes) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final coreFile = archive.findFile('docProps/core.xml');
    if (coreFile == null) return null;

    final doc = XmlDocument.parse(utf8.decode(coreFile.content as List<int>));
    final modified = doc
        .findAllElements('dcterms:modified')
        .map((e) => e.innerText)
        .firstOrNull;
    if (modified == null) return null;

    return DateTime.tryParse(modified)?.toLocal();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
