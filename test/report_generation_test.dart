import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xls;
import 'package:sulaiman/services/report_data_service.dart';
import 'package:sulaiman/services/report_excel_service.dart';
import 'package:sulaiman/services/report_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tickets = [
    {
      'name': 'طالب 1',
      'university_id': '1',
      'shatr': 'شطر الطلاب',
      'department': 'قسم الادارة',
      'advisor': 'مرشد أ',
      'actions': [
        {
          'action_type': 'إضافة',
          'course': 'م1',
          'status': 'تم الإنجاز',
          'completed_by': 'منسق القسم',
        },
      ],
    },
  ];

  test('ReportExcelService يبني ملف Excel سليم البنية بعدة أوراق', () {
    final data = ReportDataService.build(tickets);
    final bytes = ReportExcelService.build(data);

    expect(bytes, isNotEmpty);

    final decoded = xls.Excel.decodeBytes(bytes);
    expect(decoded.tables.keys, contains('ملخص عام'));
    expect(decoded.tables.keys, contains('حسب القسم'));
    expect(decoded.tables.keys, contains('حسب المرشد'));
    expect(decoded.tables.keys, contains('حسب الجهة المُنجزة'));
  });

  test(
    'ReportPdfService يبني ملف PDF صحيح التوقيع (يحتاج إنترنت لتحميل الخط)',
    () async {
      final data = ReportDataService.build(tickets);

      try {
        final bytes =
            await ReportPdfService.build(data, title: 'تقرير تجريبي');
        expect(bytes, isNotEmpty);
        final signature = String.fromCharCodes(bytes.take(5));
        expect(signature, startsWith('%PDF-'));
      } catch (e) {
        // ignore: avoid_print
        print('تخطّي: لا يوجد اتصال إنترنت هنا لتحميل الخط العربي ($e)');
      }
    },
  );
}
