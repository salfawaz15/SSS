import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:archive/archive.dart';
import 'package:sulaiman/services/advisor_zip_service.dart';

void main() {
  final tickets = [
    {
      'name': 'طالب تجريبي 1',
      'university_id': '443123456',
      'shatr': 'شطر الطلاب',
      'department': 'قسم اختبار',
      'advisor': 'مرشد تجريبي',
      'phone': '0500000000',
      'expected_graduate': true,
      'has_disability': false,
      'actions': [
        {
          'action_type': 'إضافة شعبة',
          'course': 'مقرر 1',
          'required_section': '101',
          'reason': 'اختبار',
        },
        {
          'action_type': 'حذف شعبة',
          'course': 'مقرر 2',
          'current_section': '102',
          'reason': 'اختبار2',
        },
      ],
    },
    {
      'name': 'طالب تجريبي 2',
      'university_id': '443987654',
      'shatr': 'شطر الطلاب',
      'department': 'قسم اختبار',
      'advisor': 'مرشد تجريبي',
      'phone': '0500000001',
      'expected_graduate': false,
      'has_disability': false,
      'actions': [],
    },
  ];

  // نفس مسار الإنتاج الفعلي حرفيًا (AdvisorZipService.buildZip) بدل تكرار
  // منطق البناء/الحماية هنا - يضمن أن الاختبار يعكس ما يستلمه المرشد فعليًا
  final zipBytes = AdvisorZipService.buildZip(tickets);
  final zipArchive = ZipDecoder().decodeBytes(zipBytes);
  final xlsxFile = zipArchive.files.firstWhere((f) => f.name.endsWith('.xlsx'));
  final protectedBytes = Uint8List.fromList(xlsxFile.content as List<int>);

  Directory('build').createSync(recursive: true);
  File('build/protected_sample.xlsx').writeAsBytesSync(protectedBytes);

  // 1. تحقق بنيوي: إعادة قراءة الملف بمكتبة excel للتأكد أنه غير تالف
  final decoded = xls.Excel.decodeBytes(protectedBytes);
  final sheet = decoded.tables[decoded.tables.keys.first]!;
  print('اسم الملف داخل الأرشيف: ${xlsxFile.name}');
  print('عدد الصفوف بعد إعادة القراءة: ${sheet.maxRows}');
  print('عدد الأعمدة: ${sheet.maxColumns} (متوقع 19)');
  print('أسماء الأوراق: ${decoded.tables.keys.toList()}');

  // 2. تحقق من محتوى XML الخام: sheetProtection + dataValidations + عدد cellXfs
  final archive = ZipDecoder().decodeBytes(protectedBytes);
  final sheetXml = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
  final stylesXml = utf8.decode(archive.findFile('xl/styles.xml')!.content as List<int>);

  print('يحتوي sheetProtection: ${sheetXml.contains('<sheetProtection')}');
  print('يحتوي dataValidations: ${sheetXml.contains('<dataValidations')}');
  print('يحتوي عنصر drawing يتيم (يجب أن يكون false): ${sheetXml.contains('<drawing')}');
  print('يحتوي قائمة الحالة (تم التنفيذ/لم يتم التنفيذ): ${sheetXml.contains('تم التنفيذ') && sheetXml.contains('لم يتم التنفيذ')}');
  print('يحتوي صيغة نطاق الأسباب (مرجع بدل نص حرفي): ${sheetXml.contains('قائمة الأسباب')}');

  final passwordMatch = RegExp(r'password="([0-9A-F]+)"').firstMatch(sheetXml);
  print('كلمة المرور المُشفّرة: ${passwordMatch?.group(1)}');

  final cellXfsCountMatch = RegExp(r'<cellXfs count="(\d+)"').firstMatch(stylesXml);
  print('عدد cellXfs بعد الإضافة: ${cellXfsCountMatch?.group(1)}');
}
