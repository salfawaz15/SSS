import 'excel_parser_service.dart';
import 'report_data_service.dart';

enum ReportScope { overall, department, shatr, advisor }

/// يفلتر قائمة التذاكر حسب نطاق التقرير المطلوب (شامل/قسم/شطر/مرشد) قبل
/// تمريرها لـ ReportDataService.build - بهذا تبقى منطق التجميع والرسوم
/// البيانية موحّدة لكل أنواع التقارير، والفرق الوحيد هو حجم البيانات المُمرَّرة.
class ReportFilterService {
  static List<Map<String, dynamic>> apply(
    List<Map<String, dynamic>> tickets, {
    required ReportScope scope,
    String? department,
    String? shatr,
    String? advisor,
  }) {
    switch (scope) {
      case ReportScope.overall:
        return tickets;
      case ReportScope.department:
        return tickets
            .where((t) =>
                (t['department'] ?? '') == department &&
                (shatr == null || (t['shatr'] ?? '') == shatr))
            .toList();
      case ReportScope.shatr:
        return tickets.where((t) => (t['shatr'] ?? '') == shatr).toList();
      case ReportScope.advisor:
        return tickets
            .where((t) =>
                (t['department'] ?? '') == department &&
                (t['advisor'] ?? '') == advisor &&
                (shatr == null || (t['shatr'] ?? '') == shatr))
            .toList();
    }
  }

  /// أسماء المرشدين الفريدة ضمن قسم معيّن (ويُمكن تضييقها بشطر محدّد) لتعبئة
  /// القائمة المنسدلة ديناميكيًا من بيانات حقيقية.
  static List<String> advisorsInDepartment(
    List<Map<String, dynamic>> tickets,
    String department, {
    String? shatr,
  }) {
    final names = <String>{};
    for (final t in tickets) {
      if ((t['department'] ?? '') != department) continue;
      if (shatr != null && (t['shatr'] ?? '') != shatr) continue;
      final advisor = (t['advisor'] ?? '').toString().trim();
      if (advisor.isNotEmpty) names.add(advisor);
    }
    final list = names.toList()..sort();
    return list;
  }

  static const departments = ExcelParserService.departments;
  static const shatrValues = [ExcelParserService.shatrMale, ExcelParserService.shatrFemale];

  /// كل الإجراءات التي لم تُنجز بعد (فارغة أو "جزئي" أو "لم يتم") - أساس
  /// قائمة "الحالات المتبقية" في تقرير متابعة الإنجاز.
  static List<Map<String, dynamic>> pendingCases(List<Map<String, dynamic>> tickets) {
    final rows = <Map<String, dynamic>>[];
    for (final t in tickets) {
      final actions = (t['actions'] as List?) ?? [];
      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final status = effectiveStatus(action);
        if (status == 'تم الإنجاز') continue;
        rows.add({
          'shatr': t['shatr'],
          'department': t['department'],
          'advisor': t['advisor'],
          'name': t['name'],
          'university_id': t['university_id'],
          'action_type': action['action_type'],
          'course': action['course'],
          'status': status.isEmpty ? 'لم يبدأ' : status,
        });
      }
    }
    return rows;
  }
}
