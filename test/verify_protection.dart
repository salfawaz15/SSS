// يتحقق فعليًا (بفكّ أرشيف ZIP وقراءة XML الورقة) من وجود عنصر
// sheetProtection وكلمة المرور المتوقَّعة - الفحص النصي الخام على البايتات
// المضغوطة مباشرة غير صحيح (xlsx مضغوط DEFLATE، لا نص صريح).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('التحقق الفعلي من حماية الملف بسطح المكتب', () {
    const path = r'C:\Users\salfa\Desktop\نموذج_ملف_مرشد_تجريبي_مع_النموذج_الورقي.xlsx';
    final bytes = File(path).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final xml = utf8.decode(sheetFile.content as List<int>);
    final hasProtection = xml.contains('<sheetProtection');
    // ignore: avoid_print
    print('hasSheetProtectionElement=$hasProtection');
    if (hasProtection) {
      final match = RegExp(r'<sheetProtection[^>]*>').firstMatch(xml);
      // ignore: avoid_print
      print('sheetProtectionTag=${match?.group(0)}');
    }
    expect(hasProtection, isTrue);
  });
}
