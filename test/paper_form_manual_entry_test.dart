// اختبار محلي (لا يمسّ Firestore) لميزة "حالات النموذج الورقي" بملف المرشد.
//
// ملاحظة منهجية: محاولة محاكاة "كتابة المرشد بخلايا متفرّقة" عبر
// `sheet.cell(...).value=` أو `insertRowIterables` على نفس الملف الناتج من
// buildDepartmentWorkbook تصطدم بخلل حقيقي في مكتبة `excel` (v4.0.6) نفسها:
// أي صف يقع أسفل صف فيه دمج خلايا (merge) بنفس نطاق الأعمدة يُعامَل خطأً
// كأنه جزء من نفس الدمج، فتُسقَط كتابات الأعمدة الداخلية للنطاق - هذا خلل
// بالمكتبة المستخدَمة هنا للاختبار فقط (Microsoft Excel الحقيقي لا يفعل هذا
// عند كتابة المرشد الفعلية بجهازه). لذلك يُقسَّم الاختبار لجزأين مستقلَّين:
// (1) تحقّق بنيوي على مخرجات buildDepartmentWorkbook (عدد/نطاق صفوف النموذج
// الورقي وعنوانه)، و(2) تحقّق على ProcessedFileParserService عبر ملف Excel
// بسيط (بلا أي دمج خلايا) يحاكي شكل صف نموذج ورقي مُعبَّأ فعليًا - يغطي نفس
// العقد الأساسي (كل الحقول اللازمة لإنشاء/تحديث تذكرة تُقرأ صحيحة).
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:sulaiman/services/excel_export_service.dart';
import 'package:sulaiman/services/processed_file_parser_service.dart';

void main() {
  test('buildDepartmentWorkbook يضيف قسم نموذج ورقي بنطاق صفوف صحيح', () async {
    final tickets = [
      {
        'name': 'سارة العتيبي',
        'university_id': '441000111',
        'shatr': 'الطالبات',
        'department': 'قسم نظم المعلومات الادارية',
        'advisor': 'أ. منى الحربي',
        'uploaded_date': '2026-08-30', // الأحد
        'actions': [
          {
            'action_type': 'إضافة',
            'course': 'IS301 - نظم دعم القرار',
            'course_name': 'نظم دعم القرار',
            'course_code': 'IS301',
            'required_section': '2',
            'current_section': '',
          }
        ],
      },
      {
        'name': 'نورة القحطاني',
        'university_id': '441000222',
        'shatr': 'الطالبات',
        'department': 'قسم نظم المعلومات الادارية',
        'advisor': 'أ. منى الحربي',
        'uploaded_date': '2026-08-31', // الاثنين
        'actions': [
          {
            'action_type': 'حذف',
            'course': 'IS210 - قواعد بيانات',
            'course_name': 'قواعد بيانات',
            'course_code': 'IS210',
            'required_section': '',
            'current_section': '1',
          }
        ],
      },
      {
        'name': 'ريم الدوسري',
        'university_id': '441000333',
        'shatr': 'الطالبات',
        'department': 'قسم نظم المعلومات الادارية',
        'advisor': 'أ. منى الحربي',
        'uploaded_date': '2026-09-01', // الثلاثاء (اليوم الأخير)
        'actions': [
          {
            'action_type': 'إضافة',
            'course': 'IS220 - تحليل نظم',
            'course_name': 'تحليل نظم',
            'course_code': 'IS220',
            'required_section': '3',
            'current_section': '',
          }
        ],
      },
    ];

    final result = await ExcelExportService.buildDepartmentWorkbook(
      tickets,
      includeInstructions: true,
      includePaperFormRows: true,
    );

    // النطاق موجود وبعدد الصفوف المتوقَّع.
    expect(result.paperFormFirstRow, isNotNull);
    expect(result.paperFormLastRow, isNotNull);
    expect(
      result.paperFormLastRow! - result.paperFormFirstRow! + 1,
      ExcelExportService.paperFormExtraRowCount,
    );

    final workbook = xls.Excel.decodeBytes(result.bytes);
    final sheet = workbook['طلبات المرشد'];

    // عنوان القسم موجود ضمن الملف (بصرف النظر عن رقم الصف الدقيق).
    final allText = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString() ?? '').join('|'))
        .join('\n');
    expect(allText, contains('النموذج الورقي'));
    expect(allText, contains(ExcelExportService.paperFormInstructionsText.substring(0, 20)));

    // الحالات العادية الثلاث ما زالت موجودة بلا أي تأثير من القسم الجديد.
    expect(allText, contains('441000111'));
    expect(allText, contains('441000222'));
    expect(allText, contains('441000333'));
  });

  test('ProcessedFileParserService يقرأ صف نموذج ورقي مُعبَّأ بكل الحقول اللازمة', () {
    // ملف بسيط بلا أي دمج خلايا - صف عناوين ثم 3 صفوف بيانات: حالة عادية
    // مطابَقة، وحالتا نموذج ورقي (طالب جديد كليًا + إجراء إضافي لطالبة موجودة).
    final workbook = xls.Excel.createExcel();
    final sheetName = workbook.getDefaultSheet()!;
    final sheet = workbook[sheetName];

    xls.CellValue? cell(String v) => v.isEmpty ? null : xls.TextCellValue(v);
    List<xls.CellValue?> buildRow({
      required String name,
      required String universityId,
      required String shatr,
      required String department,
      required String advisor,
      required String actionType,
      required String courseName,
      required String courseCode,
      required String addSection,
      required String reason,
      required String advisorStatus,
      String advisorNotes = '',
    }) {
      final row = List<xls.CellValue?>.filled(ExcelExportService.columnCount, null);
      row[0] = cell(name);
      row[1] = cell(universityId);
      row[4] = cell(shatr);
      row[5] = cell(department);
      row[6] = cell(advisor);
      row[10] = cell(actionType);
      row[11] = cell(courseName);
      row[12] = cell(courseCode);
      row[13] = cell(addSection);
      row[17] = cell(reason);
      row[18] = cell(advisorStatus);
      row[19] = cell(advisorNotes);
      return row;
    }

    final headerRow = <xls.CellValue?>[
      xls.TextCellValue(ExcelExportService.studentNameHeader),
      xls.TextCellValue(ExcelExportService.universityIdHeader),
      xls.TextCellValue(ExcelExportService.remainingHoursHeader),
      xls.TextCellValue(ExcelExportService.gpaHeader),
      xls.TextCellValue(ExcelExportService.shatrHeader),
      xls.TextCellValue(ExcelExportService.departmentHeader),
      xls.TextCellValue(ExcelExportService.advisorNameHeader),
      xls.TextCellValue('رقم الجوال'),
      xls.TextCellValue('تصنيف أولوية التخرج'),
      xls.TextCellValue('ذوي إعاقة'),
      xls.TextCellValue(ExcelExportService.actionTypeHeader),
      xls.TextCellValue(ExcelExportService.courseNameHeader),
      xls.TextCellValue(ExcelExportService.courseCodeHeader),
      xls.TextCellValue(ExcelExportService.addSectionHeader),
      xls.TextCellValue(ExcelExportService.deleteSectionHeader),
      xls.TextCellValue(ExcelExportService.currentSectionHeader),
      xls.TextCellValue(ExcelExportService.requestedSectionHeader),
      xls.TextCellValue(ExcelExportService.reasonHeader),
      xls.TextCellValue(ExcelExportService.advisorStatusHeader),
      xls.TextCellValue(ExcelExportService.advisorNotesHeader),
      xls.TextCellValue(ExcelExportService.advisorOtherReasonHeader),
      xls.TextCellValue(ExcelExportService.coordinatorStatusHeader),
      xls.TextCellValue(ExcelExportService.coordinatorNotesHeader),
      xls.TextCellValue(ExcelExportService.collegeStatusHeader),
      xls.TextCellValue(ExcelExportService.collegeNotesHeader),
    ];
    sheet.appendRow(headerRow);

    // صف حالة عادية (كما لو رفعها المرشد من القسم المعتاد بالملف).
    sheet.appendRow(buildRow(
      name: 'سارة العتيبي',
      universityId: '441000111',
      shatr: 'الطالبات',
      department: 'قسم نظم المعلومات الادارية',
      advisor: 'أ. منى الحربي',
      actionType: 'إضافة',
      courseName: 'نظم دعم القرار',
      courseCode: 'IS301',
      addSection: '2',
      reason: '',
      advisorStatus: 'تم التنفيذ',
    ));

    // حالة ورقية 1: طالب جديد كليًا وصلت ورقته يوم الأحد (لكن يُدخِلها المرشد
    // اليوم لأنه نسيها وقتها) - لا تذكرة له أصلاً بالنظام.
    sheet.appendRow(buildRow(
      name: 'خالد الشمري',
      universityId: '441000999',
      shatr: 'الطالبات',
      department: 'قسم نظم المعلومات الادارية',
      advisor: 'أ. منى الحربي',
      actionType: 'إضافة',
      courseName: 'برمجة 1',
      courseCode: 'CS101',
      addSection: '4',
      reason: 'استلمها المرشد ورقيًا يوم الأحد',
      advisorStatus: 'تم التنفيذ',
    ));

    // حالة ورقية 2: طالبة لها تذكرة أصلاً (سارة أعلاه ليست هي، بل نورة) لكن
    // بمقرر إضافي مختلف عمّا لديها إلكترونيًا - يجب أن تُضاف كإجراء ثانٍ.
    sheet.appendRow(buildRow(
      name: 'نورة القحطاني',
      universityId: '441000222',
      shatr: 'الطالبات',
      department: 'قسم نظم المعلومات الادارية',
      advisor: 'أ. منى الحربي',
      actionType: 'إضافة',
      courseName: 'شبكات حاسب',
      courseCode: 'IS250',
      addSection: '1',
      reason: 'استلمها المرشد ورقيًا',
      advisorStatus: 'لم يتم التنفيذ',
      advisorNotes: 'الشعبة مكتملة (اكتملت طاقتها الاستيعابية)',
    ));

    final bytes = Uint8List.fromList(workbook.encode()!);
    final rows = ProcessedFileParserService.parseProcessedRows(bytes);

    expect(rows.length, 3);

    final normalRow = rows.firstWhere((r) => r['university_id'] == '441000111');
    expect(normalRow['course_code'], 'IS301');
    expect(normalRow['advisor_status'], 'تم التنفيذ');

    final paperRow1 = rows.firstWhere((r) => r['university_id'] == '441000999');
    expect(paperRow1['name'], 'خالد الشمري');
    expect(paperRow1['course_code'], 'CS101');
    expect(paperRow1['required_section'], '4');
    expect(paperRow1['shatr'], 'الطالبات');
    expect(paperRow1['department'], 'قسم نظم المعلومات الادارية');
    expect(paperRow1['advisor'], 'أ. منى الحربي');
    expect(paperRow1['advisor_status'], 'تم التنفيذ');

    final paperRow2 = rows.firstWhere((r) => r['university_id'] == '441000222');
    expect(paperRow2['name'], 'نورة القحطاني');
    expect(paperRow2['course_code'], 'IS250');
    expect(paperRow2['required_section'], '1');
    expect(paperRow2['advisor_status'], 'لم يتم التنفيذ');
    expect(paperRow2['advisor_notes'], 'الشعبة مكتملة (اكتملت طاقتها الاستيعابية)');
  });
}
