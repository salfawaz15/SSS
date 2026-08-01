import 'package:flutter_test/flutter_test.dart';
import 'package:sulaiman/services/report_data_service.dart';

void main() {
  test('يحسب إحصائيات التقرير بشكل صحيح على كل المستويات', () {
    final tickets = [
      {
        'name': 'طالب 1',
        'university_id': '1',
        'shatr': 'شطر الطلاب',
        'department': 'قسم الادارة',
        'advisor': 'مرشد أ',
        'actions': [
          {'action_type': 'إضافة', 'course': 'م1', 'status': 'تم الإنجاز', 'completed_by': 'منسق القسم'},
          {'action_type': 'حذف', 'course': 'م2', 'status': 'جزئي'},
        ],
      },
      {
        'name': 'طالب 2',
        'university_id': '2',
        'shatr': 'شطر الطلاب',
        'department': 'قسم الادارة',
        'advisor': 'مرشد ب',
        'actions': [
          {'action_type': 'إضافة', 'course': 'م3', 'status': 'لم يتم'},
        ],
      },
      {
        'name': 'طالبة 3',
        'university_id': '3',
        'shatr': 'شطر الطالبات',
        'department': 'قسم المحاسبة',
        'advisor': 'مرشدة ج',
        'actions': [
          {'action_type': 'إضافة', 'course': 'م4', 'status': 'تم الإنجاز', 'completed_by': 'وحدة الإرشاد الأكاديمي'},
        ],
      },
    ];

    final data = ReportDataService.build(tickets);

    // الملخص العام
    expect(data.overall.total, 4);
    expect(data.overall.completed, 2);
    expect(data.overall.partial, 1);
    expect(data.overall.notDone, 1);
    expect(data.overall.completionRate, 0.5);

    // حسب القسم - قسم الادارة لشطر الطلاب
    final idara = data.departments.firstWhere(
      (d) => d.department == 'قسم الادارة' && d.shatr == 'شطر الطلاب',
    );
    expect(idara.counts.total, 3);
    expect(idara.counts.completed, 1);
    expect(idara.counts.partial, 1);
    expect(idara.counts.notDone, 1);

    // حسب القسم - قسم المحاسبة لشطر الطالبات
    final accounting = data.departments.firstWhere(
      (d) => d.department == 'قسم المحاسبة' && d.shatr == 'شطر الطالبات',
    );
    expect(accounting.counts.total, 1);
    expect(accounting.counts.completed, 1);

    // قسم بلا أي حالات يجب أن يظهر بصفر (لأنه من القائمة الثابتة)
    final marketing = data.departments.firstWhere(
      (d) => d.department == 'قسم التسويق' && d.shatr == 'شطر الطلاب',
    );
    expect(marketing.counts.total, 0);

    // حسب المرشد
    final advisorA = idara.advisors.firstWhere((a) => a.name == 'مرشد أ');
    expect(advisorA.counts.total, 2);
    expect(advisorA.counts.completed, 1);

    final advisorB = idara.advisors.firstWhere((a) => a.name == 'مرشد ب');
    expect(advisorB.counts.total, 1);
    expect(advisorB.counts.completed, 0);

    // حسب الجهة المُنجزة (فقط للحالات "تم الإنجاز")
    expect(data.completedByOverall['منسق القسم'], 1);
    expect(data.completedByOverall['وحدة الإرشاد الأكاديمي'], 1);
    expect(data.completedByOverall['المرشد الأكاديمي'], 0);
  });
}
