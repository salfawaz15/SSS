import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// يعالج ملف xlsx مُولَّد مسبقًا (كأرشيف ZIP/XML وفق مواصفة OOXML) لإضافة
/// قائمة منسدلة على عمود معيّن، وحماية الشيت بحيث تبقى أعمدة محدّدة قابلة
/// للتعديل فقط. مكتبة `excel` المستخدمة في المشروع لا تدعم أيًا من الاثنين
/// مباشرة، لذا تتم المعالجة يدويًا على مستوى XML.
/// قائمة منسدلة واحدة مطلوب إضافتها لعمود معيّن
class DropdownColumn {
  final int columnIndex;
  final List<String> options;

  const DropdownColumn({required this.columnIndex, required this.options});
}

class ExcelProtectionService {
  static const String protectionPassword = 'Sulaiman';
  static const List<String> statusOptions = ['تم الإنجاز', 'جزئي', 'لم يتم'];

  /// يقفل كل الأعمدة في الشيت الأول عدا [unlockedColumnIndexes] (صفر-فهرسة)،
  /// ويضيف قائمة منسدلة لكل عنصر في [dropdowns]، لعدد صفوف بيانات
  /// [dataRowCount] (بدون احتساب صف العناوين).
  static Uint8List protect(
    Uint8List xlsxBytes, {
    required List<DropdownColumn> dropdowns,
    required List<int> unlockedColumnIndexes,
    required int dataRowCount,
  }) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);

    final stylesFile = archive.findFile('xl/styles.xml')!;
    final stylesXml = XmlDocument.parse(
      utf8.decode(stylesFile.content as List<int>),
    );
    final unlockedStyleIndex = _addUnlockedStyle(stylesXml);

    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final sheetXml = XmlDocument.parse(
      utf8.decode(sheetFile.content as List<int>),
    );
    _unlockColumns(sheetXml, unlockedColumnIndexes, unlockedStyleIndex);
    _addSheetProtection(sheetXml);
    _addDropdowns(sheetXml, dropdowns, dataRowCount);

    final newArchive = Archive();
    for (final file in archive.files) {
      if (!file.isFile) continue;

      if (file.name == 'xl/styles.xml') {
        final bytes = utf8.encode(stylesXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (file.name == 'xl/worksheets/sheet1.xml') {
        final bytes = utf8.encode(sheetXml.toXmlString());
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        final content = file.content as List<int>;
        newArchive.addFile(ArchiveFile(file.name, content.length, content));
      }
    }

    return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
  }

  /// يضيف نمط خلية جديد بخاصية "غير مقفل" في نهاية cellXfs، ويرجّع فهرسه
  static int _addUnlockedStyle(XmlDocument stylesXml) {
    final cellXfs = stylesXml.findAllElements('cellXfs').first;
    final existingXfs = cellXfs.findElements('xf').toList();
    final template = existingXfs.last;

    final newXf = template.copy();
    newXf.children.add(
      XmlElement(XmlName('protection'), [XmlAttribute(XmlName('locked'), '0')]),
    );
    cellXfs.children.add(newXf);

    final newIndex = existingXfs.length;
    cellXfs.setAttribute('count', (newIndex + 1).toString());
    return newIndex;
  }

  static void _unlockColumns(
    XmlDocument sheetXml,
    List<int> unlockedColumnIndexes,
    int unlockedStyleIndex,
  ) {
    final unlockedLetters = unlockedColumnIndexes.map(_columnLetter).toSet();

    final rows = sheetXml.findAllElements('row');
    for (final row in rows) {
      final rowNumber = row.getAttribute('r');
      if (rowNumber == '1') continue; // تخطّي صف العناوين

      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final letters = ref.replaceAll(RegExp(r'\d'), '');
        if (unlockedLetters.contains(letters)) {
          cell.setAttribute('s', unlockedStyleIndex.toString());
        }
      }
    }
  }

  static void _addSheetProtection(XmlDocument sheetXml) {
    final worksheet = sheetXml.rootElement;
    final sheetData = worksheet.findElements('sheetData').first;

    final protectionElement = XmlElement(XmlName('sheetProtection'), [
      XmlAttribute(XmlName('sheet'), '1'),
      XmlAttribute(XmlName('objects'), '1'),
      XmlAttribute(XmlName('scenarios'), '1'),
      XmlAttribute(XmlName('password'), _hashPassword(protectionPassword)),
    ]);

    sheetData.parent!.children.insert(
      sheetData.parent!.children.indexOf(sheetData) + 1,
      protectionElement,
    );
  }

  static void _addDropdowns(
    XmlDocument sheetXml,
    List<DropdownColumn> dropdowns,
    int dataRowCount,
  ) {
    if (dropdowns.isEmpty) return;

    final worksheet = sheetXml.rootElement;
    final protectionEl = worksheet.findElements('sheetProtection').first;
    final lastRow = dataRowCount + 1; // +1 لصف العناوين

    final validationElements = dropdowns.map((dropdown) {
      final letter = _columnLetter(dropdown.columnIndex);
      final sqref = '${letter}2:$letter$lastRow';

      final formula = XmlElement(XmlName('formula1'), [], [
        XmlText('"${dropdown.options.join(',')}"'),
      ]);

      return XmlElement(
        XmlName('dataValidation'),
        [
          XmlAttribute(XmlName('type'), 'list'),
          XmlAttribute(XmlName('allowBlank'), '1'),
          XmlAttribute(XmlName('showInputMessage'), '1'),
          XmlAttribute(XmlName('showErrorMessage'), '1'),
          XmlAttribute(XmlName('sqref'), sqref),
        ],
        [formula],
      );
    }).toList();

    final validationsElement = XmlElement(XmlName('dataValidations'), [
      XmlAttribute(XmlName('count'), validationElements.length.toString()),
    ], validationElements);

    protectionEl.parent!.children.insert(
      protectionEl.parent!.children.indexOf(protectionEl) + 1,
      validationsElement,
    );
  }

  /// يحوّل فهرس عمود صفر-فهرسة إلى حرف/أحرف عمود Excel (0 -> A, 25 -> Z, 26 -> AA)
  static String _columnLetter(int index) {
    var n = index;
    var result = '';
    do {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    } while (n >= 0);
    return result;
  }

  /// خوارزمية Excel القياسية القديمة لتجزئة كلمة مرور حماية الشيت
  static String _hashPassword(String password) {
    var hash = 0;
    for (var i = password.length - 1; i >= 0; i--) {
      hash ^= password.codeUnitAt(i);
      final highBit = (hash & 0x4000) == 0x4000 ? 1 : 0;
      hash = (hash << 1) & 0x7FFF;
      hash |= highBit;
    }
    hash ^= password.length;
    hash ^= 0xCE4B;
    return hash.toRadixString(16).toUpperCase();
  }
}
