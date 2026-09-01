// فحص طارئ: هل صفوف حالات Forms العادية تختفي فعليًا من ملف المرشد بعد
// إضافة قسم النموذج الورقي؟ يحاكي شكل بيانات أقرب للإنتاج (عدة تذاكر بلا
// uploaded_date صريح أحيانًا، حقول متفرقة كما تصدر من ExcelParserService).
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xls;
import 'package:sulaiman/services/advisor_zip_service.dart';
import 'package:sulaiman/models/advisor_roster_entry.dart';

void main() {
  test('حالات Forms العادية تظهر رغم إضافة قسم النموذج الورقي', () async {
    final tickets = [
      {
        'name': 'طالب أول',
        'university_id': '441111111',
        'shatr': 'شطر الطلاب',
        'department': 'قسم الادارة',
        'advisor': 'أ. أحمد',
        'phone': '0500000000',
        'expected_graduate': false,
        'has_disability': false,
        'actions': [
          {'action_type': 'إضافة', 'course': 'مقرر أ', 'course_name': 'مقرر أ', 'course_code': 'C1', 'required_section': '1'},
        ],
      },
      {
        'name': 'طالب ثاني',
        'university_id': '441222222',
        'shatr': 'شطر الطلاب',
        'department': 'قسم الادارة',
        'advisor': 'أ. أحمد',
        'phone': '0500000001',
        'expected_graduate': false,
        'has_disability': false,
        'actions': [
          {'action_type': 'حذف', 'course': 'مقرر ب', 'course_name': 'مقرر ب', 'course_code': 'C2', 'current_section': '2'},
        ],
      },
    ];

    final roster = <AdvisorRosterEntry>[];
    final files = await AdvisorZipService.buildAdvisorFiles(tickets, roster: roster);
    // ignore: avoid_print
    print('عدد الملفات: ${files.length} - المفاتيح: ${files.keys.toList()}');
    expect(files.length, 1);

    final bytes = files.values.first;
    final workbook = xls.Excel.decodeBytes(bytes);
    final sheet = workbook['طلبات المرشد'];
    final allText = sheet.rows.map((r) => r.map((c) => c?.value?.toString() ?? '').join('|')).join('\n');

    // ignore: avoid_print
    print('=== محتوى الملف كاملاً ===');
    // ignore: avoid_print
    print(allText);

    expect(allText, contains('441111111'), reason: 'حالة الطالب الأول يجب أن تظهر');
    expect(allText, contains('441222222'), reason: 'حالة الطالب الثاني يجب أن تظهر');
  });
}
