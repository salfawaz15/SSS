import '../data/academic_department_names.dart';
import '../models/college_roster_member.dart';
import 'advisor_name_matching.dart';
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
        if (isCompletedStatus(status)) continue;
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

  /// نفس تذاكر القسم لكن بعد استبعاد أي إجراء "أنجزه المرشد" فعليًا
  /// (advisor_status = 'تم التنفيذ') - أي إبقاء فقط ما لم يباشره المرشد
  /// إطلاقًا أو باشره بـ"لم يتم التنفيذ"، على مستوى كل إجراء منفرد لا
  /// التذكرة كاملة - بطلب سليمان صراحةً (2026-08-31: أكّد أن هذا هو
  /// السلوك الصحيح المطلوب فعليًا بعد تراجع مؤقت لتصنيف التذكرة كاملة).
  /// تُستبعد التذاكر التي لم يتبقَّ لها أي إجراء بعد الفلترة حتى لا تظهر
  /// أسطر فارغة بلا إجراءات بملف الإكسل.
  static List<Map<String, dynamic>> pendingAdvisorTickets(List<Map<String, dynamic>> tickets) {
    final result = <Map<String, dynamic>>[];
    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final remaining = actions.where((a) => !isCompletedStatus((a['advisor_status'] ?? '').toString().trim())).toList();
      if (remaining.isEmpty) continue;
      result.add({...ticket, 'actions': remaining});
    }
    return result;
  }

  /// عكس [pendingAdvisorTickets] تمامًا - يُبقي فقط الإجراءات التي أنجزها
  /// المرشد فعليًا (advisor_status = 'تم التنفيذ')، على مستوى كل إجراء
  /// منفرد لا التذكرة كاملة (نفس منطق [pendingAdvisorTickets] بالضبط).
  static List<Map<String, dynamic>> completedAdvisorTickets(List<Map<String, dynamic>> tickets) {
    final result = <Map<String, dynamic>>[];
    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final remaining = actions.where((a) => isCompletedStatus((a['advisor_status'] ?? '').toString().trim())).toList();
      if (remaining.isEmpty) continue;
      result.add({...ticket, 'actions': remaining});
    }
    return result;
  }

  /// كل تذاكر المرشدين الذين لم ينجزوا **ولو إجراء واحد** ضمن التذاكر
  /// الممرَّرة (صفر advisor_status = 'تم التنفيذ' عبر كل تذاكر المرشد
  /// بالكامل) - أساس قائمة "الأعضاء المقصّرون" وملف حالاتهم المُرسَل
  /// لرئيس القسم بطلب سليمان صراحةً (2026-08-31).
  static List<Map<String, dynamic>> delinquentAdvisorTickets(List<Map<String, dynamic>> tickets) {
    // مطابقة متسامحة بنفس منطق [normalizeAdvisorNameForMatch] (تتجاهل
    // الألقاب وصور الهمزة/التاء المربوطة) - وإلا يظهر مرشد أنجز فعليًا ضمن
    // "المقصّرين" فقط لأن اسمه كُتب بصيغة مختلفة قليلًا بتذكرة أخرى (سليمان
    // صراحةً 2026-08-31: هتان عبدالعزيز راجح الشريف أنجز فعليًا وظهر خطأً).
    final advisorsWithProgress = <String>{};
    for (final ticket in tickets) {
      final actions = (ticket['actions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final hasCompleted = actions.any((a) => isCompletedStatus((a['advisor_status'] ?? '').toString().trim()));
      if (!hasCompleted) continue;
      final advisor = (ticket['advisor'] ?? '').toString().trim();
      if (advisor.isNotEmpty) advisorsWithProgress.add(normalizeAdvisorNameForMatch(advisor));
    }
    return tickets.where((t) {
      final advisor = (t['advisor'] ?? '').toString().trim();
      return advisor.isNotEmpty && !advisorsWithProgress.contains(normalizeAdvisorNameForMatch(advisor));
    }).toList();
  }

  /// أسماء المرشدين المقصّرين الفريدة (مرتّبة أبجديًا) - لعرضها بقائمة قصيرة
  /// بواجهة لوحة الإدارة بجانب زر تنزيل ملفاتهم.
  static List<String> delinquentAdvisorNames(List<Map<String, dynamic>> tickets) {
    final names = <String>{};
    for (final t in delinquentAdvisorTickets(tickets)) {
      final advisor = (t['advisor'] ?? '').toString().trim();
      if (advisor.isNotEmpty) names.add(advisor);
    }
    final list = names.toList()..sort();
    return list;
  }

  /// خريطة "شطر|قسم" (بحسب بيانات كل تذكرة كما هي فعليًا) -> أسماء المرشدين
  /// الذين لم يُنجزوا أي حالة إطلاقًا **عبر كل تذاكرهم بالنظام بالكامل** (لا
  /// فقط تذاكر هذا القسم تحديدًا - وإلا لو أُسندت له حالة واحدة خطأً بقسم آخر
  /// فقد يظهر مقصّرًا رغم إنجازه الفعلي بقسمه الصحيح)، مع تحذير صريح يُلحَق
  /// بأي اسم قسمه المسجَّل بالقائمة الرسمية الشاملة لمنسوبي الكلية
  /// (collegeRoster، من ملف العمادة المعتمد) يخالف قسم هذه التذكرة - للمراجعة
  /// اليدوية الإلزامية قبل إرسال أي بريد مساءلة. **لا** تُستخدَم قائمة
  /// advisor_roster لهذا الغرض لأنها غير شاملة أصلاً (مخصَّصة فقط لتوزيع عبء
  /// منسّق/مرشد في إجازة) - سليمان صراحةً (2026-08-31): استخدامها سابقًا هنا
  /// أنتج تحذيرات "غير مسجَّل" خاطئة لأعضاء حقيقيين غير مُدرَجين فيها أصلاً.
  /// حساسية الموضوع عالية لأن القائمة تُرسَل مباشرة لرؤساء الأقسام: حالة
  /// حقيقية ظهرت فيها "زكية...العوفي" (مسجَّلة بقسم الاقتصاد والتمويل فعليًا)
  /// تحت قسم النظم بسبب خطأ إدخال اسم المرشد بنموذج Microsoft Forms لتذكرة
  /// طالبة واحدة بذلك القسم.
  // حالات انتداب حقيقية موثَّقة صراحةً (سليمان صراحةً 2026-08-31 عن هاتين
  // الحالتين تحديدًا): مسجَّلتان/مسجَّل رسميًا بقسم لكن يعملان فعليًا بقسم
  // آخر - لا تُعتبَران خطأ إدخال ولا تستحقان تحذيرًا رغم مخالفة القسم الرسمي
  // بملف منسوبي الكلية. أي تطابق جزئي بالاسم كافٍ (أسماء مختصرة هنا عمدًا).
  static const _knownSecondments = {
    'حنان عامر': 'قسم الاقتصاد و التمويل',
    'طارق حلمي': 'قسم نظم المعلومات الادارية',
  };

  static Map<String, List<String>> delinquentAdvisorNamesByGroupVerified(
    List<Map<String, dynamic>> allTickets,
    List<CollegeRosterMember> collegeRoster,
  ) {
    final delinquentTickets = delinquentAdvisorTickets(allTickets);
    final rosterByNormalizedName = <String, CollegeRosterMember>{
      for (final r in collegeRoster) normalizeAdvisorNameForMatch(r.name): r,
    };
    final result = <String, Set<String>>{};
    for (final t in delinquentTickets) {
      final advisor = (t['advisor'] ?? '').toString().trim();
      if (advisor.isEmpty) continue;
      final shatr = (t['shatr'] ?? '').toString();
      final department = (t['department'] ?? '').toString();
      final normalizedAdvisor = normalizeAdvisorNameForMatch(advisor);
      final rosterEntry = rosterByNormalizedName[normalizedAdvisor];
      String? secondmentDepartment;
      for (final entry in _knownSecondments.entries) {
        if (normalizedAdvisor.contains(normalizeAdvisorNameForMatch(entry.key))) {
          secondmentDepartment = entry.value;
          break;
        }
      }
      String label;
      if (secondmentDepartment != null) {
        label = normalizeDepartmentName(secondmentDepartment) == normalizeDepartmentName(department)
            ? advisor
            : '$advisor ⚠️ قسمه بعد الانتداب: $secondmentDepartment - تحقّق يدويًا';
      } else if (rosterEntry == null) {
        label = '$advisor ⚠️ غير موجود بملف منسوبي الكلية - تحقّق يدويًا';
      } else if (normalizeDepartmentName(rosterEntry.department) != normalizeDepartmentName(department)) {
        label = '$advisor ⚠️ قسمه الفعلي بملف منسوبي الكلية: ${rosterEntry.department} - تحقّق يدويًا';
      } else {
        label = advisor;
      }
      result.putIfAbsent('$shatr|$department', () => {}).add(label);
    }
    return {for (final e in result.entries) e.key: (e.value.toList()..sort())};
  }
}
