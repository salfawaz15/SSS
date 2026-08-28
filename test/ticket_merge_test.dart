import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sulaiman/services/excel_export_service.dart';
import 'package:sulaiman/services/processed_file_parser_service.dart';
import 'package:sulaiman/services/ticket_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('يدمج حالة الإنجاز والملاحظات في التذكرة الصحيحة عبر الرقم الجامعي', () async {
    final tickets = [
      {
        'name': 'طالب أول',
        'university_id': '443111111',
        'shatr': 'شطر الطلاب',
        'department': 'قسم الادارة',
        'advisor': 'مرشد',
        'phone': '0500000000',
        'expected_graduate': false,
        'has_disability': false,
        'actions': [
          {
            'action_type': 'إضافة شعبة',
            'course': 'مقرر أ',
            'required_section': '101',
            'reason': 'سبب',
          },
          {
            'action_type': 'حذف شعبة',
            'course': 'مقرر ب',
            'current_section': '202',
            'reason': 'سبب آخر',
          },
        ],
      },
      {
        'name': 'طالبة ثانية',
        'university_id': '443222222',
        'shatr': 'شطر الطلاب',
        'department': 'قسم الادارة',
        'advisor': 'مرشد',
        'phone': '0500000001',
        'expected_graduate': false,
        'has_disability': false,
        'actions': [
          {
            'action_type': 'إضافة شعبة',
            'course': 'مقرر ج',
            'required_section': '303',
            'reason': 'سبب',
          },
        ],
      },
    ];

    await TicketRepository.saveAll(tickets);

    // نبني ملف Excel مُصدَّر فعليًا (كما سيرسله التطبيق)، ثم "نحاكي" تعديل
    // المرشد لعمودي الحالة/الملاحظات مباشرة في القيم المُصدَّرة، ثم نمرره
    // إلى نفس مُحلّل الملفات المعالجة الذي سيستخدمه التطبيق فعليًا.
    final rawBytes = (await ExcelExportService.buildDepartmentWorkbook(tickets)).bytes;
    expect(rawBytes, isNotEmpty);

    // نحاكي الصفوف كما لو أُعيدت من المرشد بعد التعبئة (بدل التلاعب بملف
    // Excel الثنائي مباشرة، وهو ما يغطّيه اختبار التنسيق المنفصل)
    final processedRows = [
      {
        'university_id': '443111111',
        'action_type': 'إضافة شعبة',
        'course': 'مقرر أ',
        'section': '101',
        'status': 'تم الإنجاز',
        'notes': 'تمت الإضافة بنجاح',
        'completed_by': 'منسق القسم',
      },
      {
        'university_id': '443111111',
        'action_type': 'حذف شعبة',
        'course': 'مقرر ب',
        'section': '202',
        'status': 'لم يتم',
        'notes': 'الشعبة ممتلئة',
        'completed_by': '',
      },
      {
        'university_id': '999999999', // رقم غير موجود عمدًا
        'action_type': 'إضافة شعبة',
        'course': 'غير موجود',
        'section': '999',
        'status': 'جزئي',
        'notes': '',
        'completed_by': '',
      },
    ];

    final result = await TicketRepository.mergeProcessedRows(processedRows);

    expect(result.matchedCount, 2);
    expect(result.unmatchedCount, 1);

    final updated = await TicketRepository.loadAll();
    final first =
        updated.firstWhere((t) => t['university_id'] == '443111111');
    final actions = (first['actions'] as List).cast<Map<String, dynamic>>();

    final addAction =
        actions.firstWhere((a) => a['action_type'] == 'إضافة شعبة');
    expect(addAction['status'], 'تم الإنجاز');
    expect(addAction['notes'], 'تمت الإضافة بنجاح');
    expect(addAction['completed_by'], 'منسق القسم');

    final deleteAction =
        actions.firstWhere((a) => a['action_type'] == 'حذف شعبة');
    expect(deleteAction['status'], 'لم يتم');
    expect(deleteAction['notes'], 'الشعبة ممتلئة');

    // التذكرة الثانية لم تُمس
    final second =
        updated.firstWhere((t) => t['university_id'] == '443222222');
    final secondActions =
        (second['actions'] as List).cast<Map<String, dynamic>>();
    expect(secondActions.first.containsKey('status'), isFalse);
  });

  test('ProcessedFileParserService يقرأ الملف المُصدَّر بأسماء الأعمدة بشكل صحيح',
      () async {
    final tickets = [
      {
        'name': 'طالب',
        'university_id': '443333333',
        'shatr': 'شطر الطلاب',
        'department': 'قسم المحاسبة',
        'advisor': 'مرشد',
        'phone': '0500000002',
        'expected_graduate': false,
        'has_disability': false,
        'actions': [
          {
            'action_type': 'إضافة شعبة',
            'course': 'مقرر',
            'required_section': '1',
            'reason': 'سبب',
          },
        ],
      },
    ];

    final workbookResult = await ExcelExportService.buildDepartmentWorkbook(tickets);
    final rows = ProcessedFileParserService.parseProcessedRows(workbookResult.bytes);

    expect(rows.length, 1);
    expect(rows.first['university_id'], '443333333');
    expect(rows.first['action_type'], 'إضافة شعبة');
    expect(rows.first['course'], 'مقرر');
    // الحالة/الملاحظات/الجهة المُنجزة فارغة لأن الملف لم يُعالَج بعد
    expect(rows.first['status'], '');
    expect(rows.first['notes'], '');
    expect(rows.first['completed_by'], '');
  });

  test(
    'يميّز بين إجراءات بنفس النوع والمقرر لكن بشعب مختلفة (لا يطغى صف على آخر)',
    () async {
      // حالة واقعية: طالب يطلب "إضافة شعبة" لنفس المقرر لعدة شعب مختلفة
      final tickets = [
        {
          'name': 'طالب',
          'university_id': '111',
          'shatr': 'شطر الطلاب',
          'department': 'قسم الادارة',
          'advisor': 'مرشد',
          'actions': [
            {
              'action_type': 'إضافة شعبة',
              'course': 'مبادئ الإدارة',
              'required_section': '111',
            },
            {
              'action_type': 'إضافة شعبة',
              'course': 'مبادئ الإدارة',
              'required_section': '44',
            },
            {
              'action_type': 'إضافة شعبة',
              'course': 'مبادئ الإدارة',
              'required_section': '33',
            },
            {
              'action_type': 'إضافة شعبة',
              'course': 'مبادئ الإدارة',
              'required_section': '22',
            },
          ],
        },
      ];

      await TicketRepository.saveAll(tickets);

      final processedRows = [
        {
          'university_id': '111',
          'action_type': 'إضافة شعبة',
          'course': 'مبادئ الإدارة',
          'section': '111',
          'status': 'تم الإنجاز',
          'notes': '',
          'completed_by': 'المرشد الأكاديمي',
        },
        {
          'university_id': '111',
          'action_type': 'إضافة شعبة',
          'course': 'مبادئ الإدارة',
          'section': '44',
          'status': 'تم الإنجاز',
          'notes': '',
          'completed_by': 'منسق القسم',
        },
        {
          'university_id': '111',
          'action_type': 'إضافة شعبة',
          'course': 'مبادئ الإدارة',
          'section': '33',
          'status': 'تم الإنجاز',
          'notes': '',
          'completed_by': 'وحدة الإرشاد الأكاديمي',
        },
        {
          'university_id': '111',
          'action_type': 'إضافة شعبة',
          'course': 'مبادئ الإدارة',
          'section': '22',
          'status': 'تم الإنجاز',
          'notes': '',
          'completed_by': 'منسق الكلية',
        },
      ];

      final result = await TicketRepository.mergeProcessedRows(processedRows);
      expect(result.matchedCount, 4);
      expect(result.unmatchedCount, 0);

      final updated = await TicketRepository.loadAll();
      final actions =
          (updated.first['actions'] as List).cast<Map<String, dynamic>>();

      String completedByFor(String section) => actions
          .firstWhere((a) => a['required_section'] == section)['completed_by']
          .toString();

      expect(completedByFor('111'), 'المرشد الأكاديمي');
      expect(completedByFor('44'), 'منسق القسم');
      expect(completedByFor('33'), 'وحدة الإرشاد الأكاديمي');
      expect(completedByFor('22'), 'منسق الكلية');
    },
  );
}
