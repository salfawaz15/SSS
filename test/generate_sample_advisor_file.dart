// يولّد ملف مرشد تجريبي حقيقي (محمي، بنفس آلية الإنتاج الكاملة عبر
// AdvisorZipService) فيه حالات من الأيام الثلاثة + قسم النموذج الورقي،
// ويحفظه على سطح المكتب ليجربه سليمان يدويًا بإكسل حقيقي.
// يُشغَّل بـ: flutter test test/generate_sample_advisor_file.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sulaiman/services/advisor_zip_service.dart';

void main() {
  test('توليد ملف مرشد تجريبي على سطح المكتب', () async {
    final tickets = [
      {
        'name': 'سارة العتيبي',
        'university_id': '441000111',
        'shatr': 'الطالبات',
        'department': 'قسم نظم المعلومات الادارية',
        'advisor': 'أ. منى الحربي',
        'phone': '0500000001',
        'has_disability': false,
        'expected_graduate': false,
        'uploaded_date': '2026-08-30', // الأحد
        'actions': [
          {
            'action_type': 'إضافة',
            'course': 'IS301 - نظم دعم القرار',
            'course_name': 'نظم دعم القرار',
            'course_code': 'IS301',
            'required_section': '2',
            'current_section': '',
            'reason_detail': '',
            'advisor_status': '',
            'advisor_notes': '',
          }
        ],
      },
      {
        'name': 'نورة القحطاني',
        'university_id': '441000222',
        'shatr': 'الطالبات',
        'department': 'قسم نظم المعلومات الادارية',
        'advisor': 'أ. منى الحربي',
        'phone': '0500000002',
        'has_disability': false,
        'expected_graduate': false,
        'uploaded_date': '2026-08-31', // الاثنين
        'actions': [
          {
            'action_type': 'حذف',
            'course': 'IS210 - قواعد بيانات',
            'course_name': 'قواعد بيانات',
            'course_code': 'IS210',
            'required_section': '',
            'current_section': '1',
            'reason_detail': '',
            'advisor_status': '',
            'advisor_notes': '',
          }
        ],
      },
      {
        'name': 'ريم الدوسري',
        'university_id': '441000333',
        'shatr': 'الطالبات',
        'department': 'قسم نظم المعلومات الادارية',
        'advisor': 'أ. منى الحربي',
        'phone': '0500000003',
        'has_disability': false,
        'expected_graduate': false,
        'uploaded_date': '2026-09-01', // الثلاثاء (اليوم الأخير)
        'actions': [
          {
            'action_type': 'إضافة',
            'course': 'IS220 - تحليل نظم',
            'course_name': 'تحليل نظم',
            'course_code': 'IS220',
            'required_section': '3',
            'current_section': '',
            'reason_detail': '',
            'advisor_status': '',
            'advisor_notes': '',
          }
        ],
      },
    ];

    final files = await AdvisorZipService.buildAdvisorFiles(tickets);
    expect(files.length, 1);

    final bytes = files.values.first;
    final outPath = r'C:\Users\salfa\Desktop\نموذج_ملف_مرشد_تجريبي_مع_النموذج_الورقي.xlsx';
    File(outPath).writeAsBytesSync(bytes);

    // ignore: avoid_print
    print('تم الحفظ: $outPath (${bytes.length} بايت)');
  });
}
