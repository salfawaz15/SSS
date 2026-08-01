import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart' as xls;
import 'package:archive/archive.dart';
import 'package:sulaiman/services/excel_export_service.dart';
import 'package:sulaiman/services/excel_protection_service.dart';

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

  final rawBytes = ExcelExportService.buildDepartmentWorkbook(tickets);

  final dataRowCount = tickets.fold<int>(0, (sum, t) {
    final actions = (t['actions'] as List?) ?? [];
    return sum + (actions.isEmpty ? 1 : actions.length);
  });

  final protectedBytes = ExcelProtectionService.protect(
    rawBytes,
    statusColumnIndex: ExcelExportService.statusColumnIndex,
    unlockedColumnIndexes: [
      ExcelExportService.statusColumnIndex,
      ExcelExportService.notesColumnIndex,
    ],
    dataRowCount: dataRowCount,
  );

  File('build/protected_sample.xlsx').writeAsBytesSync(protectedBytes);

  // 1. تحقق بنيوي: إعادة قراءة الملف بمكتبة excel للتأكد أنه غير تالف
  final decoded = xls.Excel.decodeBytes(protectedBytes);
  final sheet = decoded.tables[decoded.tables.keys.first]!;
  print('عدد الصفوف بعد إعادة القراءة: ${sheet.maxRows} (متوقع ${dataRowCount + 1})');
  print('عدد الأعمدة: ${sheet.maxColumns} (متوقع 14)');

  // 2. تحقق من محتوى XML الخام: sheetProtection + dataValidations + عدد cellXfs
  final archive = ZipDecoder().decodeBytes(protectedBytes);
  final sheetXml = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
  final stylesXml = utf8.decode(archive.findFile('xl/styles.xml')!.content as List<int>);

  print('يحتوي sheetProtection: ${sheetXml.contains('<sheetProtection')}');
  print('يحتوي dataValidations: ${sheetXml.contains('<dataValidations')}');
  print('يحتوي قائمة الحالة: ${sheetXml.contains('تم الإنجاز')}');

  final passwordMatch = RegExp(r'password="([0-9A-F]+)"').firstMatch(sheetXml);
  print('كلمة المرور المُشفّرة: ${passwordMatch?.group(1)}');

  final cellXfsCountMatch = RegExp(r'<cellXfs count="(\d+)"').firstMatch(stylesXml);
  print('عدد cellXfs بعد الإضافة: ${cellXfsCountMatch?.group(1)}');

  // عدّ خلايا العمود M (حالة) و N (ملاحظات) غير المقفلة (s الجديد)
  final newStyleIndex = int.parse(cellXfsCountMatch!.group(1)!) - 1;
  final unlockedCellPattern = RegExp('s="$newStyleIndex"');
  final unlockedCount = unlockedCellPattern.allMatches(sheetXml).length;
  print('عدد الخلايا غير المقفلة (متوقع ${dataRowCount * 2}): $unlockedCount');
}
