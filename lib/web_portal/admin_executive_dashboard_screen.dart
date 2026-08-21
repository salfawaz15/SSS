import 'package:flutter/material.dart';

import '../data/academic_department_names.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/report_data_service.dart' show TicketAdvisorOutcome, ticketOutcomeForField;
import '../services/stage_download_service.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';
import 'upload_hub_screen.dart';

/// لوحة الإدارة الرئيسية (Executive Dashboard) - أول ما يراه مدير الوحدة بعد
/// الدخول. أُعيدت صياغتها مرتين بطلب سليمان (2026-08-19): الأولى تحويلها من
/// صفحة روابط إلى لوحة مراقبة وقرار حقيقية، والثانية (هذه النسخة) لتصحيح
/// المصطلحات (إدارة الوحدة لا "الإدارة" وحدها - لبس مع قسم الإدارة العلمي)،
/// تكثيف الأحجام (Compact) بعد أن كانت البطاقات أكبر من حجم معلوماتها،
/// تمثيل مسار سير العمل الإداري الحقيقي (6 مراحل لا 5)، إعادة استخدام
/// المؤشرات الدائرية (Donut) من التصميم الأول، إضافة قسم "حالة الإنجاز حسب
/// نوع الإجراء"، وتحويل "تحتاج تدخل إدارة الوحدة" لهرم تدرّجي (شطر ← قسم
/// علمي ← تفاصيل) بدل عرض أسماء الطلبة مباشرة بالصفحة الرئيسية.
///
/// **رُبطت ببيانات Firestore الحقيقية (2026-08-20)** - كل الأقسام مربوطة
/// بـ`FirestoreTicketService.watchAllTickets()` و`StageDownloadService.watchAll()`
/// عدا "آخر النشاطات" (التبويب الثاني بالبطاقة اليمنى) الذي يبقى Mock مؤقتًا
/// (بموافقة سليمان صراحةً) لأنه يحتاج سجل حركات لحظي غير موجود بالنظام بعد.
/// بنية الـWidgets وتصميمها البصري **مجمَّدة (UI Frozen)** بشكل عام - أي
/// تعديل بصري يحتاج طلبًا صريحًا من سليمان لكل حالة على حدة (لا يُفترَض
/// تلقائيًا عند ربط بيانات جديدة). استثناء وحيد صريح: قسم "متابعة سير العمل"
/// أُعيد تصميمه فعليًا (2026-08-21) من شريط 6 مراحل بأرقام مجردة إلى ثلاث
/// بطاقات دور (مرشد/منسّق قسم/منسّق كلية) بطلب سليمان المباشر - راجع
/// [_RoleProgress] و[_RoleProgressCard].
class AdminExecutiveDashboardScreen extends StatelessWidget {
  const AdminExecutiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'لوحة الإدارة',
      showBackButton: false,
      navItems: buildAdminNavItems(context, current: 'dashboard'),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchAllTickets(),
        builder: (context, ticketsSnap) {
          return StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: StageDownloadService.watchAll(),
            builder: (context, downloadsSnap) {
              if (!ticketsSnap.hasData) {
                return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
              }
              final data = _DashboardData.compute(ticketsSnap.data!, downloadsSnap.data ?? const {});
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _LastUpdateBar(),
                          const SizedBox(height: 14),
                          _FilterableDashboardContent(data: data),
                          const SizedBox(height: 18),
                          _MainGrid(data: data),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// الأقسام العلمية الخمسة بترتيبها المعتمَد الثابت (سليمان: "نبدأ بالإدارة
/// وننتهي بنظم المعلومات") - مصدر واحد لهذا الترتيب يُستخدَم في حساب الأداء
/// وفي فرز مستوى الأقسام بـ"تحتاج تدخل إدارة الوحدة" معًا.
const _kCanonicalDepartmentOrder = [
  'قسم الإدارة',
  'قسم المحاسبة',
  'قسم التسويق',
  'قسم الاقتصاد والتمويل',
  'قسم نظم المعلومات الإدارية',
];

/// أعلى أعمدة حالة (`advisor_status`/`coordinator_status`/`college_status`)
/// عن "تم الإنجاز فعليًا" - نفس القيمة المعتمدة بـ`FirestoreTicketService`
/// و`excel_export_service.dart`.
const _kCompletedMarker = 'تم الإنجاز';

/// قيمة "تم" الخاصة بعمود المرشد الأكاديمي تحديدًا (قائمته المنسدلة ثنائية:
/// تم التنفيذ/لم يتم التنفيذ، بخلاف عمودي منسق القسم/الكلية اللذين ما زالا
/// يستخدمان [_kCompletedMarker]) - راجع [ExcelProtectionService.advisorActionStatusOptions]
const _kAdvisorCompletedMarker = 'تم التنفيذ';

enum _Stage { advisor, deptReview, collegeReview, closed }

class _ActionCompute {
  final String actionType;
  final _Stage stage;
  final bool overdue;
  final bool advisorTouched;
  const _ActionCompute({required this.actionType, required this.stage, required this.overdue, required this.advisorTouched});
}

class _MutableStats {
  int total = 0;
  int overdue = 0;
  int completed = 0;
  int get processing => total - overdue - completed;
  _DeptShatrStats toStats() => _DeptShatrStats(total: total, processing: processing, overdue: overdue, completed: completed);
}

class _MutableActionType {
  int total = 0;
  int completed = 0;
  int processing = 0;
  int notStarted = 0;
}

/// يحوّل تذاكر Firestore الخام + سجلات تنزيل المراحل إلى كل الأرقام التي
/// تحتاجها اللوحة دفعة واحدة - مصدر واحد يضمن اتساق كل الأرقام ببعضها
/// (نفس الضمان الذي وفّرته `_kDepartmentPerf` سابقًا للبيانات الوهمية).
class _DashboardData {
  final List<Map<String, dynamic>> tickets;
  final Map<String, Map<String, dynamic>> downloads;
  final List<_DepartmentPerf> departmentPerf;
  final List<_ManagementCase> managementCases;
  final int totalRequests;
  final int totalCompleted;
  final int totalOverdue;

  const _DashboardData({
    required this.tickets,
    required this.downloads,
    required this.departmentPerf,
    required this.managementCases,
    required this.totalRequests,
    required this.totalCompleted,
    required this.totalOverdue,
  });

  static String _displayDepartment(String rawDepartment) {
    final normalized = normalizeDepartmentName(rawDepartment);
    switch (normalized) {
      case 'قسم الادارة':
        return 'قسم الإدارة';
      case 'قسم الاقتصاد و التمويل':
        return 'قسم الاقتصاد والتمويل';
      case 'قسم نظم المعلومات الادارية':
        return 'قسم نظم المعلومات الإدارية';
      default:
        return normalized;
    }
  }

  /// يصنّف إجراءً واحدًا: أين هو الآن بمسار سير العمل، وهل تجاوز مهلته -
  /// المهلة تُحسب من لحظة تنزيل الملف (بطلب سليمان صراحةً 2026-08-20: "من
  /// تاريخ تنزيل الملف يبدأ العدّ") لا من تاريخ رفع ملف الفورمز، بيوم واحد
  /// لكل من المرشد ومنسّق القسم (كلٌّ من تنزيله هو)، ومنسّق الكلية بلا مهلة
  /// إطلاقًا ("ليس له وقت ولا تأخير").
  /// أين إجراء واحد الآن بمسار سير العمل - يعتمد فقط على نصوص الحالة الثلاث
  /// (بلا توقيت)، فيصلح لإعادة الاستخدام في أي حساب لا يحتاج "التأخر" (مثل
  /// [_computeActionTypeStats] المُفلتَر).
  static _Stage _stageOf(Map<String, dynamic> action) {
    final advisorStatus = (action['advisor_status'] ?? '').toString();
    final coordinatorStatus = (action['coordinator_status'] ?? '').toString();
    final collegeStatus = (action['college_status'] ?? '').toString();

    if (collegeStatus == _kCompletedMarker) return _Stage.closed;
    if (coordinatorStatus == _kCompletedMarker) return _Stage.collegeReview;
    if (advisorStatus == _kAdvisorCompletedMarker || advisorStatus == _kCompletedMarker) return _Stage.deptReview;
    return _Stage.advisor;
  }

  static _ActionCompute _classifyAction(
    Map<String, dynamic> action,
    DateTime? advisorDownloadedAt,
    DateTime? coordinatorDownloadedAt,
    DateTime now,
  ) {
    final advisorStatus = (action['advisor_status'] ?? '').toString();
    final actionType = (action['action_type'] ?? '').toString();
    final stage = _stageOf(action);

    var overdue = false;
    if (stage == _Stage.advisor && advisorDownloadedAt != null) {
      overdue = now.difference(advisorDownloadedAt).inHours >= 24;
    } else if (stage == _Stage.deptReview && coordinatorDownloadedAt != null) {
      overdue = now.difference(coordinatorDownloadedAt).inHours >= 24;
    }

    return _ActionCompute(actionType: actionType, stage: stage, overdue: overdue, advisorTouched: advisorStatus.isNotEmpty);
  }

  static String _formatWaiting(DateTime? advisorDl, DateTime? coordDl, DateTime now) {
    final ref = coordDl ?? advisorDl;
    if (ref == null) return 'غير محدَّد';
    final diff = now.difference(ref);
    if (diff.inDays >= 1) return '${diff.inDays} ${diff.inDays == 1 ? 'يوم' : 'أيام'}';
    if (diff.inHours >= 1) return '${diff.inHours} ${diff.inHours == 1 ? 'ساعة' : 'ساعات'}';
    return 'أقل من ساعة';
  }

  factory _DashboardData.compute(
    List<Map<String, dynamic>> tickets,
    Map<String, Map<String, dynamic>> downloads,
  ) {
    final now = DateTime.now();

    DateTime? downloadTime(String shatr, String department, String field) {
      final doc = downloads['${shatr}_$department'];
      final ts = doc == null ? null : doc[field];
      if (ts == null) return null;
      try {
        return (ts as dynamic).toDate() as DateTime;
      } catch (_) {
        return null;
      }
    }

    final deptTotals = <String, _MutableStats>{};
    final cases = <_ManagementCase>[];
    var totalOverdue = 0;

    for (final ticket in tickets) {
      final shatrRaw = (ticket['shatr'] ?? '').toString();
      final shatrKey = shatrRaw == ExcelParserService.shatrMale ? 'male' : 'female';
      final rawDept = (ticket['department'] ?? '').toString();
      final displayDept = _displayDepartment(rawDept);
      final studentName = (ticket['name'] ?? '').toString();

      final advisorDl = downloadTime(shatrRaw, rawDept, 'advisor_downloaded_at');
      final coordDl = downloadTime(shatrRaw, rawDept, 'coordinator_downloaded_at');

      final actions = (ticket['actions'] as List?) ?? const [];
      final statKey = '$displayDept|$shatrKey';
      final stats = deptTotals.putIfAbsent(statKey, () => _MutableStats());
      final ticketOverdueActions = <_ActionCompute>[];

      for (final raw in actions) {
        final action = Map<String, dynamic>.from(raw as Map);
        final computed = _classifyAction(action, advisorDl, coordDl, now);

        stats.total++;
        if (computed.stage == _Stage.closed) {
          stats.completed++;
        }
        if (computed.stage != _Stage.closed && computed.overdue) {
          stats.overdue++;
          totalOverdue++;
          ticketOverdueActions.add(computed);
        }

      }

      // "مصعدة لإدارة الوحدة" حُذفت كمعيار مستقل (كانت تعتمد على إعاقة/توقع
      // تخرج بصرف النظر عن العمل الفعلي على الحالة - سليمان 2026-08-21: "لا
      // يوجد حالات تطلب تدخل إدارة الوحدة" بهذا المعيار، ومنسّق الكلية بلا
      // مهلة زمنية أصلًا فلا مؤشر تلقائي موضوعي لتدخل الوحدة على مستواه).
      // يبقى "متأخرة" (تجاوزت مهلة المرشد/منسّق القسم فقط) المؤشر الوحيد.
      if (ticketOverdueActions.isNotEmpty) {
        cases.add(_ManagementCase(
          shatr: shatrKey,
          department: displayDept,
          student: studentName,
          type: ticketOverdueActions.first.actionType,
          status: 'متأخرة',
          reason: 'تجاوزت مدة المعالجة',
          waiting: _formatWaiting(advisorDl, coordDl, now),
          severity: _CaseSeverity.overdue,
        ));
      }
    }

    final departmentPerf = _kCanonicalDepartmentOrder.map((name) {
      final male = deptTotals['$name|male']?.toStats() ?? const _DeptShatrStats(total: 0, processing: 0, overdue: 0, completed: 0);
      final female = deptTotals['$name|female']?.toStats() ?? const _DeptShatrStats(total: 0, processing: 0, overdue: 0, completed: 0);
      return _DepartmentPerf(name: name, male: male, female: female);
    }).toList();

    final totalRequests = departmentPerf.fold<int>(0, (s, d) => s + d.male.total + d.female.total);
    final totalCompleted = departmentPerf.fold<int>(0, (s, d) => s + d.male.completed + d.female.completed);

    cases.sort((a, b) => a.severity.index.compareTo(b.severity.index));

    return _DashboardData(
      tickets: tickets,
      downloads: downloads,
      departmentPerf: departmentPerf,
      managementCases: cases,
      totalRequests: totalRequests,
      totalCompleted: totalCompleted,
      totalOverdue: totalOverdue,
    );
  }
}

/// نتيجة إجراءات دور واحد (مرشد/منسّق قسم/منسّق كلية) لمجموعة تذاكر معيّنة -
/// تُحسَب من [tickets] مباشرة عبر [ticketOutcomeForField]، فتصلح لكل من
/// الإجمالي العام وأي فلترة لاحقة (شطر/قسم) بلا حاجة لإعادة استعلام
/// Firestore - الفلترة تحدث محليًا على القائمة نفسها.
List<_RoleProgress> _computeRoleProgress(List<Map<String, dynamic>> tickets) {
  final advisor = {for (final o in TicketAdvisorOutcome.values) o: 0};
  final coordinator = {for (final o in TicketAdvisorOutcome.values) o: 0};
  final college = {for (final o in TicketAdvisorOutcome.values) o: 0};

  for (final ticket in tickets) {
    final advisorOutcome = ticketOutcomeForField(ticket, 'advisor_status');
    advisor[advisorOutcome] = (advisor[advisorOutcome] ?? 0) + 1;
    final coordinatorOutcome = ticketOutcomeForField(ticket, 'coordinator_status');
    coordinator[coordinatorOutcome] = (coordinator[coordinatorOutcome] ?? 0) + 1;
    final collegeOutcome = ticketOutcomeForField(ticket, 'college_status');
    college[collegeOutcome] = (college[collegeOutcome] ?? 0) + 1;
  }

  return [
    _RoleProgress(role: 'المرشدون الأكاديميون', breakdown: advisor),
    _RoleProgress(role: 'منسّقو الأقسام العلمية', breakdown: coordinator),
    _RoleProgress(role: 'منسّقو الكلية', breakdown: college),
  ];
}

class _KpiStats {
  final int totalRequests;
  final int totalCompleted;
  final int totalOverdue;
  const _KpiStats({required this.totalRequests, required this.totalCompleted, required this.totalOverdue});
}

/// نفس مؤشرات "الإغلاق النهائي/المتأخر" الأصلية لكن قابلة لإعادة الحساب على
/// أي مجموعة تذاكر مُفلترة - يحتاج [downloads] (بخلاف الدالتين الأخريين)
/// لأن حساب "التأخر" يعتمد على توقيت التنزيل لا نصوص الحالة فقط.
_KpiStats _computeKpiStats(List<Map<String, dynamic>> tickets, Map<String, Map<String, dynamic>> downloads) {
  final now = DateTime.now();
  DateTime? downloadTime(String shatr, String department, String field) {
    final doc = downloads['${shatr}_$department'];
    final ts = doc == null ? null : doc[field];
    if (ts == null) return null;
    try {
      return (ts as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  var total = 0, completed = 0, overdue = 0;
  for (final ticket in tickets) {
    final shatrRaw = (ticket['shatr'] ?? '').toString();
    final rawDept = (ticket['department'] ?? '').toString();
    final advisorDl = downloadTime(shatrRaw, rawDept, 'advisor_downloaded_at');
    final coordDl = downloadTime(shatrRaw, rawDept, 'coordinator_downloaded_at');
    final actions = (ticket['actions'] as List?) ?? const [];
    for (final raw in actions) {
      final action = Map<String, dynamic>.from(raw as Map);
      final computed = _DashboardData._classifyAction(action, advisorDl, coordDl, now);
      total++;
      if (computed.stage == _Stage.closed) completed++;
      if (computed.stage != _Stage.closed && computed.overdue) overdue++;
    }
  }
  return _KpiStats(totalRequests: total, totalCompleted: completed, totalOverdue: overdue);
}

/// نفس فكرة [_computeRoleProgress] لكن لتوزيع نوع الإجراء (إضافة/حذف/تعديل) -
/// يعتمد فقط على نصوص الحالة ([_DashboardData._stageOf]، بلا توقيت)، فيصلح
/// لإعادة الحساب على أي مجموعة تذاكر مُفلترة محليًا.
List<_ActionTypeStats> _computeActionTypeStats(List<Map<String, dynamic>> tickets) {
  const typeLabels = {'إضافة': 'طلبات الإضافة', 'حذف': 'طلبات الحذف', 'تعديل': 'طلبات تعديل الشعبة'};
  final acc = <String, _MutableActionType>{};

  for (final ticket in tickets) {
    final actions = (ticket['actions'] as List?) ?? const [];
    for (final raw in actions) {
      final action = Map<String, dynamic>.from(raw as Map);
      final stage = _DashboardData._stageOf(action);
      final actionType = (action['action_type'] ?? '').toString();
      final advisorStatus = (action['advisor_status'] ?? '').toString();

      final typeAcc = acc.putIfAbsent(actionType, () => _MutableActionType());
      typeAcc.total++;
      if (stage == _Stage.closed) {
        typeAcc.completed++;
      } else if (stage == _Stage.advisor && advisorStatus.isEmpty) {
        typeAcc.notStarted++;
      } else {
        typeAcc.processing++;
      }
    }
  }

  return typeLabels.entries.map((e) {
    final acc0 = acc[e.key];
    return _ActionTypeStats(label: e.value, completed: acc0?.completed ?? 0, processing: acc0?.processing ?? 0, notStarted: acc0?.notStarted ?? 0);
  }).toList();
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionTitle({required this.title, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    // فونت عناوين الأقسام رُفع إلى 18-20px (سليمان 2026-08-19: "عنوان متابعة
    // سير العمل 18-20px" - يُطبَّق على كل عناوين اللوحة بنفس المكوّن حفاظًا
    // على اتساق بصري واحد بدل عنوان استثنائي لقسم واحد).
    return Row(
      children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Icon(icon, size: 19, color: AppColors.greenDark),
        const SizedBox(width: 7),
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppColors.greenDark)),
        ),
        ?trailing,
      ],
    );
  }
}

/// مؤشر دائري مصغَّر (Donut) - نفس الأسلوب البصري الذي أُعجب سليمان به
/// بالتصميم الأول، بحجم Compact يناسب الاستخدام داخل بطاقات ووحدات صغيرة
/// بدل التوسّع بحجم كبير كالسابق.
class _MiniDonut extends StatelessWidget {
  final double percent;
  final Color color;
  final double size;
  final double strokeWidth;
  final String? centerText;

  const _MiniDonut({
    required this.percent,
    required this.color,
    this.size = 32,
    this.strokeWidth = 4.5,
    this.centerText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(value: 1, strokeWidth: strokeWidth, color: Colors.grey.shade200),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: percent.clamp(0, 1),
              strokeWidth: strokeWidth,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (centerText != null)
            Text(centerText!, style: TextStyle(fontSize: size * 0.27, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// شريط صغير هادئ: مؤشر بيانات حيّة + رابط نصي خافت لصفحة "رفع ملفات"
/// المستقلة (باسم "إدارة البيانات" لا تكرار اسمها هنا - موجودة أصلاً بشريط
/// التنقّل العلوي). كان نص تاريخ ثابتًا وهميًا قبل الربط الفعلي بـFirestore
/// (2026-08-20) - استبدل بمؤشر "حيّة" صادق بدل تاريخ مزيَّف لا معنى له بعد
/// أن أصبحت الصفحة تُحدَّث لحظيًا مع أي تغيير بقاعدة البيانات.
class _LastUpdateBar extends StatelessWidget {
  const _LastUpdateBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('البيانات حيّة - تتحدّث تلقائيًا فور أي تغيير', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
        Text('  |  ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
        InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadHubScreen())),
          child: Text(
            'إدارة البيانات',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.grey.shade500,
              decoration: TextDecoration.underline,
              decorationColor: Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }
}

/// فلتر واحد أعلى الصفحة (شطر/قسم/حالة) يتحكم بالمؤشرات + حالة الإنجاز حسب
/// نوع الإجراء + متابعة سير العمل معًا - بلا تكرار الفلتر بأي قسم منها
/// (سليمان 2026-08-21: "فلتر واحد فقط أعلى الصفحة يتحكم بكل شيء"). الترتيب
/// (يمين إلى يسار بالعربية): شريحة "الكل" (إعادة تعيين عامة) ← الشطر ←
/// الأقسام العلمية ← الحالة (ذوو الإعاقة/الخريجون).
class _FilterableDashboardContent extends StatefulWidget {
  final _DashboardData data;
  const _FilterableDashboardContent({required this.data});

  @override
  State<_FilterableDashboardContent> createState() => _FilterableDashboardContentState();
}

class _FilterableDashboardContentState extends State<_FilterableDashboardContent> {
  _ShatrFilter _shatr = _ShatrFilter.all;
  // null = "الكل" - نفس تمييز فلتر القسم بقية اللوحة.
  String? _department;
  _PriorityFilter _priority = _PriorityFilter.all;

  bool get _hasFilter => _shatr != _ShatrFilter.all || _department != null || _priority != _PriorityFilter.all;

  List<Map<String, dynamic>> get _filteredTickets {
    return widget.data.tickets.where((t) {
      if (_shatr != _ShatrFilter.all) {
        final shatrRaw = (t['shatr'] ?? '').toString();
        final wantMale = _shatr == _ShatrFilter.male;
        final isMale = shatrRaw == ExcelParserService.shatrMale;
        if (isMale != wantMale) return false;
      }
      if (_department != null) {
        final dept = _DashboardData._displayDepartment((t['department'] ?? '').toString());
        if (dept != _department) return false;
      }
      if (_priority == _PriorityFilter.graduate && t['expected_graduate'] != true) return false;
      if (_priority == _PriorityFilter.disability && t['has_disability'] != true) return false;
      return true;
    }).toList();
  }

  void _resetAll() => setState(() {
        _shatr = _ShatrFilter.all;
        _department = null;
        _priority = _PriorityFilter.all;
      });

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTickets;
    final kpi = _computeKpiStats(filtered, widget.data.downloads);
    final actionTypeStats = _computeActionTypeStats(filtered);
    final roleProgress = _computeRoleProgress(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ResetAllChip(active: !_hasFilter, onTap: _resetAll),
              _ShatrFilterDropdown(value: _shatr, onChanged: (v) => setState(() => _shatr = v)),
              _DepartmentFilterDropdown(value: _department, onChanged: (v) => setState(() => _department = v)),
              _PriorityFilterDropdown(value: _priority, onChanged: (v) => setState(() => _priority = v)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _KpiRow(kpi: kpi),
        const SizedBox(height: 18),
        _ActionTypeSection(stats: actionTypeStats),
        const SizedBox(height: 18),
        _WorkflowSection(roleProgress: roleProgress),
      ],
    );
  }
}

/// 4 بطاقات تشغيلية Compact - أصغر بنحو 20% من النسخة السابقة، مع مؤشر دائري
/// مصغَّر لبطاقة نسبة الإنجاز بدل أيقونة ثابتة.
class _KpiRow extends StatelessWidget {
  final _KpiStats kpi;
  const _KpiRow({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final total = kpi.totalRequests;
    final completed = kpi.totalCompleted;
    final rate = total == 0 ? 0 : (completed / total * 100).round();
    final pending = total - completed;
    final overdue = kpi.totalOverdue;

    final cards = <Widget>[
      _KpiCard(
        title: 'طلبات تحتاج إجراء',
        value: '$pending',
        meta: 'من إجمالي $total طلبًا',
        icon: Icons.pending_actions_outlined,
        accent: AppColors.green,
      ),
      _KpiCard(
        title: 'طلبات متأخرة',
        value: '$overdue',
        meta: overdue == 0 ? 'لا توجد طلبات متأخرة' : 'يلزم متابعتها',
        icon: Icons.schedule_outlined,
        accent: AppColors.gold,
      ),
      _KpiCard(
        title: 'نسبة الإغلاق النهائي',
        value: '$rate%',
        meta: '$completed من أصل $total طلبًا',
        icon: Icons.donut_large_outlined,
        accent: AppColors.greenDark,
        donutPercent: rate / 100,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth < 650 ? 1 : (constraints.maxWidth < 1100 ? 2 : 3);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final c in cards) SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns, child: c),
        ],
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String meta;
  final IconData icon;
  final Color accent;
  final double? donutPercent;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.meta,
    required this.icon,
    required this.accent,
    this.donutPercent,
  });

  @override
  Widget build(BuildContext context) {
    // minHeight لا height ثابت - يمنع أي Overflow نهائيًا مهما كان المحتوى
    // (سليمان 2026-08-19: ظهر BOTTOM OVERFLOWED 4px مع height ثابت وخط أكبر -
    // "لا يتم حل المشكلة بالقص، بل برفع الارتفاع عند الحاجة"). المحتوى يبقى
    // مُمركَزًا كوحدة واحدة عبر Center، والخطوط رُفعت للحد المطلوب صراحةً
    // (لا مزيد من التصغير): عنوان 14، رقم 28، وصف 12.
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          // لمسة هوية دقيقة (خط ذهبي رفيع 3px) بدل إطار ذهبي حول البطاقة
          // كاملة - القسم لا يحمل عنوانًا خاصًا به فوقه (بخلاف بقية الأقسام)
          // فهذه اللمسة تعوّض حضور الهوية هنا تحديدًا (سليمان 2026-08-19).
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(width: 3, height: 30, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(3))),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (donutPercent != null)
                  _MiniDonut(percent: donutPercent!, color: accent, size: 46, strokeWidth: 5.5)
                else
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
                    child: Icon(icon, size: 23, color: accent),
                  ),
                const SizedBox(width: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 3),
                      Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.greenDark, height: 1)),
                      const SizedBox(height: 3),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// متابعة سير العمل - أُعيد تصميمها (سليمان 2026-08-21: "أريد فعلًا أتابع سير
/// العمل للمرشدين والمنسّقين ومنسّقي الكلية") من شريط 6 مراحل بأرقام مجردة
/// إلى ثلاث بطاقات دور واحدة لكل مستوى تصعيد (مرشد ← منسّق قسم ← منسّق كلية)،
/// كل بطاقة تُظهر دائمًا وبلا حاجة لأي نقر تصنيف كل طالب من واقع البيانات
/// الفعلية: منفَّذ بالكامل/تنفيذ جزئي/مرفوض بالكامل/لم يُعمَل عليه بعد -
/// بنفس منطق [ticketOutcomeForField] لكل من الأعمدة الثلاثة.
class _RoleProgress {
  final String role;
  final Map<TicketAdvisorOutcome, int> breakdown;
  const _RoleProgress({required this.role, required this.breakdown});

  int get total => breakdown.values.fold(0, (a, b) => a + b);
  int get complete => breakdown[TicketAdvisorOutcome.complete] ?? 0;
  int get partial => breakdown[TicketAdvisorOutcome.partial] ?? 0;
  int get rejected => breakdown[TicketAdvisorOutcome.rejected] ?? 0;
  int get notStarted => breakdown[TicketAdvisorOutcome.notStarted] ?? 0;
}

class _WorkflowSection extends StatelessWidget {
  final List<_RoleProgress> roleProgress;
  const _WorkflowSection({required this.roleProgress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(title: 'متابعة سير العمل', icon: Icons.timeline_outlined),
          const SizedBox(height: 4),
          Text('حالة الطلبات فعليًا عند كل مستوى - كل رقم من واقع ما أُدخِل بالملفات', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            final cards = roleProgress.map((r) => _RoleProgressCard(progress: r)).toList();
            if (narrow) {
              return Column(children: [for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 10), cards[i]]]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i != cards.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// "حالة الإنجاز حسب نوع الإجراء" - قسم مستقل أعلى الصفحة، يشترك بنفس فلتر
/// [_DashboardFilterBar] بلا فلتر خاص به (سليمان 2026-08-21).
class _ActionTypeSection extends StatelessWidget {
  final List<_ActionTypeStats> stats;
  const _ActionTypeSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(title: 'حالة الإنجاز حسب نوع الإجراء', icon: Icons.pie_chart_outline_rounded),
          const SizedBox(height: 10),
          _ActionTypeStatsRow(stats: stats),
        ],
      ),
    );
  }
}

enum _PriorityFilter { all, graduate, disability }

class _DepartmentFilterDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _DepartmentFilterDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: Colors.grey.shade600),
          selectedItemBuilder: (context) => [
            const Text('القسم العلمي'),
            for (final d in _kCanonicalDepartmentOrder)
              Text(d.replaceFirst('قسم ', ''), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
          ],
          items: [
            const DropdownMenuItem(value: null, child: Text('القسم العلمي')),
            for (final d in _kCanonicalDepartmentOrder) DropdownMenuItem(value: d, child: Text(d.replaceFirst('قسم ', ''))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ShatrFilterDropdown extends StatelessWidget {
  final _ShatrFilter value;
  final ValueChanged<_ShatrFilter> onChanged;
  const _ShatrFilterDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_ShatrFilter>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: Colors.grey.shade600),
          selectedItemBuilder: (context) => const [
            Text('الشطر'),
            Text('الطلاب', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
            Text('الطالبات', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
          ],
          items: const [
            DropdownMenuItem(value: _ShatrFilter.all, child: Text('الشطر')),
            DropdownMenuItem(value: _ShatrFilter.male, child: Text('الطلاب')),
            DropdownMenuItem(value: _ShatrFilter.female, child: Text('الطالبات')),
          ],
          onChanged: (v) => onChanged(v ?? _ShatrFilter.all),
        ),
      ),
    );
  }
}

class _PriorityFilterDropdown extends StatelessWidget {
  final _PriorityFilter value;
  final ValueChanged<_PriorityFilter> onChanged;
  const _PriorityFilterDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_PriorityFilter>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: Colors.grey.shade600),
          selectedItemBuilder: (context) => const [
            Text('الحالة'),
            Text('ذوي الإعاقة', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
            Text('المتوقع تخرجهم', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
          ],
          items: const [
            DropdownMenuItem(value: _PriorityFilter.all, child: Text('الحالة')),
            DropdownMenuItem(value: _PriorityFilter.disability, child: Text('ذوي الإعاقة')),
            DropdownMenuItem(value: _PriorityFilter.graduate, child: Text('المتوقع تخرجهم')),
          ],
          onChanged: (v) => onChanged(v ?? _PriorityFilter.all),
        ),
      ),
    );
  }
}

/// شريحة "الكل" (إعادة تعيين كل الفلاتر الثلاثة دفعة واحدة) - أول عنصر
/// بترتيب الفلتر (يمين الصف بالعربية RTL)، منفصلة عن فلتر الشطر نفسه (بطلب
/// سليمان صراحةً 2026-08-21: "الكل" عنصر عام مستقل، لا خيارًا ضمن الشطر).
class _ResetAllChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _ResetAllChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: active ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
        child: Text('الكل', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700)),
      ),
    );
  }
}

class _RoleProgressCard extends StatelessWidget {
  final _RoleProgress progress;
  const _RoleProgressCard({required this.progress});

  static const _completeColor = AppColors.green;
  static const _partialColor = AppColors.gold;
  static const _rejectedColor = Color(0xFFD9534F);
  static const _notStartedColor = Color(0xFF9AA5B1);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(progress.role, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.greenDark)),
              ),
              Text('${progress.total}', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 12),
          _outcomeRow('منفَّذ بالكامل', progress.complete, progress.total, _completeColor),
          const SizedBox(height: 8),
          _outcomeRow('تنفيذ جزئي', progress.partial, progress.total, _partialColor),
          const SizedBox(height: 8),
          _outcomeRow('مرفوض بالكامل', progress.rejected, progress.total, _rejectedColor),
          const SizedBox(height: 8),
          _outcomeRow('لم يُعمَل عليه بعد', progress.notStarted, progress.total, _notStartedColor),
        ],
      ),
    );
  }

  Widget _outcomeRow(String label, int value, int total, Color color) {
    final rate = total == 0 ? 0.0 : value / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
            Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 6, color: Colors.grey.shade200),
              FractionallySizedBox(widthFactor: rate.clamp(0.0, 1.0), child: Container(height: 6, color: color)),
            ],
          ),
        ),
      ],
    );
  }
}

/// إحصائيات قسم علمي واحد لشطر واحد - تُجمَع (male+female) لعرض "الكل".
class _DeptShatrStats {
  final int total;
  final int processing;
  final int overdue;
  final int completed;
  const _DeptShatrStats({required this.total, required this.processing, required this.overdue, required this.completed});

  int get rate => total == 0 ? 0 : (completed / total * 100).round();

  _DeptShatrStats operator +(_DeptShatrStats other) => _DeptShatrStats(
        total: total + other.total,
        processing: processing + other.processing,
        overdue: overdue + other.overdue,
        completed: completed + other.completed,
      );
}

class _DepartmentPerf {
  final String name;
  final _DeptShatrStats male;
  final _DeptShatrStats female;
  const _DepartmentPerf({required this.name, required this.male, required this.female});
}

enum _ShatrFilter { all, male, female }

/// حالة الإنجاز حسب نوع الإجراء - قسم مستعاد من التصميم الأول (بطلب سليمان
/// صراحةً: يجيب "في أي نوع من الطلبات يوجد التأخير؟" بخلاف أداء الأقسام
/// العلمية الذي يجيب "أين يوجد التأخير؟"). عنوان عادي متناسق مع بقية عناوين
/// اللوحة بدل الشريط الأخضر الكبير السابق.
class _ActionTypeStats {
  final String label;
  final int completed;
  final int processing;
  final int notStarted;
  const _ActionTypeStats({required this.label, required this.completed, required this.processing, required this.notStarted});

  int get total => completed + processing + notStarted;
  double get rate => total == 0 ? 0 : completed / total;
}

/// نفس محتوى قسم "حالة الإنجاز حسب نوع الإجراء" السابق، بلا حاوية/عنوان
/// خاصَّين به بعد أن رُفع ليشترك بنفس فلتر "متابعة سير العمل" (شطر/قسم/حالة)
/// بلا تكرار الفلتر (سليمان 2026-08-21).
class _ActionTypeStatsRow extends StatelessWidget {
  final List<_ActionTypeStats> stats;
  const _ActionTypeStatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 560) {
        return Column(children: [for (final t in stats) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ActionTypeCard(stats: t))]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i != 0) const SizedBox(width: 10),
            Expanded(child: _ActionTypeCard(stats: stats[i])),
          ],
        ],
      );
    });
  }
}

class _ActionTypeCard extends StatelessWidget {
  final _ActionTypeStats stats;
  const _ActionTypeCard({required this.stats});

  Color get _color => stats.rate >= 0.6
      ? AppColors.green
      : stats.rate >= 0.4
          ? AppColors.gold
          : AppColors.errorRed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _MiniDonut(percent: stats.rate, color: _color, size: 39, strokeWidth: 5, centerText: '${(stats.rate * 100).round()}%'),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${stats.label} — ${stats.total} طلبًا', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${stats.completed} مكتمل • ${stats.processing} قيد المعالجة • ${stats.notStarted} لم يبدأ',
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// درجة أهمية الحالة (تُستخدم لتلوين وتصنيف الحالات ضمن "تحتاج تدخل إدارة
/// الوحدة" - لا علاقة لها بالدور المسؤول، فقط بحالة الطلب نفسه).
enum _CaseSeverity { urgent, overdue, review }

class _ManagementCase {
  final String shatr; // 'male' | 'female'
  final String department;
  final String student;
  final String type;
  final String status;
  final String reason;
  final String waiting;
  final _CaseSeverity severity;
  const _ManagementCase({
    required this.shatr,
    required this.department,
    required this.student,
    required this.type,
    required this.status,
    required this.reason,
    required this.waiting,
    required this.severity,
  });
}

/// شبكة رئيسية: تحتاج تدخل إدارة الوحدة (70%) + النشاطات والتنبيهات (30%) -
/// بلا فرض تساوي الارتفاع (كل قسم بارتفاعه الطبيعي، بطلب سليمان صراحةً).
class _MainGrid extends StatelessWidget {
  final _DashboardData data;
  const _MainGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 1000;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ManagementAttentionSection(data: data),
            const SizedBox(height: 14),
            const _ActivityFeedSection(),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: _ManagementAttentionSection(data: data)),
          const SizedBox(width: 14),
          const Expanded(flex: 3, child: _ActivityFeedSection()),
        ],
      );
    });
  }
}

/// "تحتاج تدخل إدارة الوحدة" - هرم تدرّجي (الشطر ← القسم العلمي ← تفاصيل
/// الحالة) بدل عرض أسماء الطلبة مباشرة بالصفحة الرئيسية (بطلب سليمان
/// صراحةً: Dashboard يعرض الصورة الإدارية العامة، وتفاصيل الحالات الفردية
/// تظهر فقط بعد الدخول للقسم العلمي).
class _ManagementAttentionSection extends StatefulWidget {
  final _DashboardData data;
  const _ManagementAttentionSection({required this.data});

  @override
  State<_ManagementAttentionSection> createState() => _ManagementAttentionSectionState();
}

class _ManagementAttentionSectionState extends State<_ManagementAttentionSection> {
  // شطر الطلاب محدَّد افتراضيًا (لا يُترك الشطران مغلقين) - حتى يظهر
  // المستوى الثاني (الأقسام العلمية) فورًا بدل مساحة فارغة كبيرة (سليمان
  // 2026-08-19).
  String _shatr = 'male';
  String? _department;

  List<_ManagementCase> get _cases => widget.data.managementCases;
  List<_ManagementCase> get _casesInShatr => _cases.where((c) => c.shatr == _shatr).toList();
  List<_ManagementCase> get _casesInDept => _casesInShatr.where((c) => c.department == _department).toList();

  String _severityLabel(_CaseSeverity s) => switch (s) {
        _CaseSeverity.urgent => 'عاجلة',
        _CaseSeverity.overdue => 'متأخرة',
        _CaseSeverity.review => 'مراجعة',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Badge عدد الحالات مُلاصِق للعنوان مباشرةً - لا يُستخدَم trailing
          // العام (_SectionTitle) الذي كان يدفعه لأقصى الطرف الآخر بعيدًا عن
          // العنوان (سليمان 2026-08-19: "معلومتان مرتبطتان يجب أن تكونا
          // متقاربتين").
          Row(
            children: [
              Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              const Icon(Icons.report_gmailerrorred_outlined, size: 19, color: AppColors.greenDark),
              const SizedBox(width: 7),
              const Text('تحتاج تدخل إدارة الوحدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppColors.greenDark)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.errorRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text('عدد الحالات: ${_cases.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.errorRed)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildShatrTabs(),
          const SizedBox(height: 8),
          if (_department != null) ...[
            _buildBreadcrumb(),
            const SizedBox(height: 8),
          ],
          if (_cases.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('لا توجد حالات تحتاج تدخل إدارة الوحدة حاليًا', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
              ),
            )
          else if (_department == null)
            _buildDepartmentLevel()
          else
            _buildCaseLevel(),
        ],
      ),
    );
  }

  /// شريحتان صغيرتان (Segmented Control) بدل بطاقتين كبيرتين - توفّر مساحة
  /// كبيرة كانت تظهر فارغة أسفلهما (سليمان 2026-08-19).
  Widget _buildShatrTabs() {
    final male = _cases.where((c) => c.shatr == 'male').length;
    final female = _cases.where((c) => c.shatr == 'female').length;

    Widget tab(String label, String value, int count) {
      final selected = _shatr == value;
      return InkWell(
        onTap: () => setState(() {
          _shatr = value;
          _department = null;
        }),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          decoration: BoxDecoration(color: selected ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(7)),
          child: Text(
            '$label  $count',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade700),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      tab('شطر الطلاب', 'male', male),
      const SizedBox(width: 6),
      tab('شطر الطالبات', 'female', female),
    ]);
  }

  Widget _buildBreadcrumb() {
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
      _crumb(_shatr == 'male' ? 'شطر الطلاب' : 'شطر الطالبات', onTap: () => setState(() => _department = null)),
      Icon(Icons.chevron_left, size: 14, color: Colors.grey.shade400),
      _crumb(_department!, isCurrent: true),
    ]);
  }

  Widget _crumb(String label, {VoidCallback? onTap, bool isCurrent = false}) {
    final text = Text(
      label,
      style: TextStyle(fontSize: 11.5, fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600, color: isCurrent ? AppColors.greenDark : Colors.grey.shade500),
    );
    if (onTap == null || isCurrent) return text;
    return InkWell(onTap: onTap, child: text);
  }

  /// Compact Structured Grid بدل صف بمعلومتين في طرفيه - عمود لكل تصنيف
  /// (عاجلة/متأخرة/مراجعة) بدل نص حر متفرق (سليمان 2026-08-19).
  Widget _buildDepartmentLevel() {
    final cases = _casesInShatr;
    // ترتيب الأقسام العلمية دائمًا حسب ترتيب [_kCanonicalDepartmentOrder]
    // المعتمد (الإدارة، المحاسبة، التسويق، الاقتصاد والتمويل، نظم المعلومات
    // الإدارية) - لا حسب ترتيب ظهورها العرضي بقائمة الحالات (سليمان
    // 2026-08-19: "نبدأ بالإدارة وننتهي بنظم المعلومات").
    final departments = cases.map((c) => c.department).toSet().toList()
      ..sort((a, b) => _kCanonicalDepartmentOrder.indexOf(a).compareTo(_kCanonicalDepartmentOrder.indexOf(b)));
    if (departments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('لا توجد حالات بهذا الشطر حاليًا', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeptGridHeader(),
        const Divider(height: 8, thickness: 1),
        for (final dep in departments) _buildDeptRow(dep, cases.where((c) => c.department == dep).toList()),
      ],
    );
  }

  Widget _buildDeptGridHeader() {
    TextStyle style = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Expanded(flex: 3, child: SizedBox()),
          Expanded(flex: 2, child: Text('عاجلة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('متأخرة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('مراجعة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.center, style: style)),
          const SizedBox(width: 19),
        ],
      ),
    );
  }

  Widget _buildDeptRow(String dep, List<_ManagementCase> cases) {
    final urgent = cases.where((c) => c.severity == _CaseSeverity.urgent).length;
    final overdue = cases.where((c) => c.severity == _CaseSeverity.overdue).length;
    final review = cases.where((c) => c.severity == _CaseSeverity.review).length;

    Widget cell(int n, Color color) => Expanded(
          flex: 2,
          child: Text(n == 0 ? '—' : '$n', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: n == 0 ? Colors.grey.shade400 : color)),
        );

    return InkWell(
      onTap: () => setState(() => _department = dep),
      borderRadius: BorderRadius.circular(8),
      hoverColor: AppColors.green.withValues(alpha: 0.05),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(minHeight: 38),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(dep, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5))),
            cell(urgent, AppColors.errorRed),
            cell(overdue, AppColors.gold),
            cell(review, const Color(0xFF2563EB)),
            Expanded(flex: 2, child: Text('${cases.length}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.greenDark))),
            SizedBox(width: 19, child: Icon(Icons.chevron_left, size: 15, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _buildCaseLevel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final c in _casesInDept) _ManagementCaseRow(item: c, severityLabel: _severityLabel(c.severity))],
    );
  }
}

class _ManagementCaseRow extends StatelessWidget {
  final _ManagementCase item;
  final String severityLabel;
  const _ManagementCaseRow({required this.item, required this.severityLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(item.student, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                      child: Text(item.status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.errorRed)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${item.type} · ${item.reason}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(item.waiting, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  minimumSize: const Size(0, 26),
                  foregroundColor: AppColors.green,
                  side: const BorderSide(color: AppColors.green),
                ),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('عرض تفاصيل حالة "${item.student}"')),
                ),
                child: const Text('عرض', style: TextStyle(fontSize: 10.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _FeedTab { alerts, activity }

/// النشاطات والتنبيهات - كانت تعرض بيانات وهمية (Mock) ثابتة بالكود؛ حُذفت
/// (سليمان 2026-08-21: يتناقض بصريًا مع صندوق "تحتاج تدخل إدارة الوحدة"
/// المجاور حين يعرض هو "0" حقيقية وهذا القسم "5 تنبيهات" مزيَّفة - غير
/// احترافي). تُعرَض الآن حالة "قيد التطوير" صريحة بدل ذلك، لحين توفّر سجل
/// حركات لحظي حقيقي (متى/من/ماذا فعل) - قاعدة البيانات تخزّن الحالة الأخيرة
/// لكل تذكرة فقط حاليًا، لا تاريخ التغييرات عليها. بقية أقسام اللوحة كلها
/// مربوطة ببيانات حقيقية. التبويبان ("التنبيهات"/"آخر النشاطات") أُبقيا
/// لأن التصميم نفسه لا يزال صالحًا فور توفّر مصدر بيانات حقيقي.
class _ActivityFeedSection extends StatefulWidget {
  const _ActivityFeedSection();

  @override
  State<_ActivityFeedSection> createState() => _ActivityFeedSectionState();
}

class _ActivityFeedSectionState extends State<_ActivityFeedSection> {
  _FeedTab _tab = _FeedTab.alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabStrip(),
          const SizedBox(height: 16),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.hourglass_empty_rounded, size: 28, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'قيد التطوير - ستُفعَّل عند توفّر سجل حركات لحظي',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
    Widget tab(String label, _FeedTab value) {
      final selected = _tab == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.green : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade700)),
          ),
        ),
      );
    }

    return Row(children: [
      tab('التنبيهات', _FeedTab.alerts),
      const SizedBox(width: 6),
      tab('آخر النشاطات', _FeedTab.activity),
    ]);
  }
}

