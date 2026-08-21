import 'package:flutter/material.dart';

import '../data/academic_department_names.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/report_data_service.dart' show TicketAdvisorOutcome, ticketOutcomeForField;
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
          if (!ticketsSnap.hasData) {
            return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
          }
          final data = _DashboardData.compute(ticketsSnap.data!);
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
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
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

  const _DashboardData({required this.tickets});

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

  /// أين إجراء واحد الآن بمسار سير العمل - يعتمد فقط على نصوص الحالة الثلاث
  /// (بلا توقيت، بعد إلغاء مفهوم "التأخر" الزمني - سليمان 2026-08-21: منسّق
  /// الكلية جهة تنفيذية بلا مهلة، والمقياس الحقيقي هو "هل عُمل على الحالة
  /// إطلاقًا" لا "كم استغرقت").
  static _Stage _stageOf(Map<String, dynamic> action) {
    final advisorStatus = (action['advisor_status'] ?? '').toString();
    final coordinatorStatus = (action['coordinator_status'] ?? '').toString();
    final collegeStatus = (action['college_status'] ?? '').toString();

    if (collegeStatus == _kCompletedMarker) return _Stage.closed;
    if (coordinatorStatus == _kCompletedMarker) return _Stage.collegeReview;
    if (advisorStatus == _kAdvisorCompletedMarker || advisorStatus == _kCompletedMarker) return _Stage.deptReview;
    return _Stage.advisor;
  }

  factory _DashboardData.compute(List<Map<String, dynamic>> tickets) => _DashboardData(tickets: tickets);
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
  // عدد الطلاب الذين تخطّى المرشد حالتهم كليًا (لم يعمل على أي إجراء لها) لكن
  // أُنجز لاحقًا عند منسّق القسم أو منسّق الكلية - المؤشر الفعلي المهم لإدارة
  // الوحدة (سليمان 2026-08-21: "دوري متابعة الحالات التي لم يتم عليها أي
  // إجراء" - لا "المتأخرة" بالوقت، فمنسّق الكلية بلا مهلة زمنية أصلًا).
  final int advisorSkippedCount;
  const _KpiStats({required this.totalRequests, required this.totalCompleted, required this.advisorSkippedCount});
}

/// نفس مؤشر "الإغلاق النهائي" الأصلي لكن قابل لإعادة الحساب على أي مجموعة
/// تذاكر مُفلترة - يعتمد فقط على نصوص الحالة (`_DashboardData._stageOf`)
/// بلا حاجة لتوقيت التنزيل، بعد إلغاء مفهوم "التأخر الزمني" (سليمان
/// 2026-08-21: منسّق الكلية بلا مهلة، فلا معنى موضوعيًا لحساب تأخر بالساعات).
_KpiStats _computeKpiStats(List<Map<String, dynamic>> tickets) {
  var total = 0, completed = 0;
  var advisorSkipped = 0;
  for (final ticket in tickets) {
    final actions = (ticket['actions'] as List?) ?? const [];
    for (final raw in actions) {
      final action = Map<String, dynamic>.from(raw as Map);
      total++;
      if (_DashboardData._stageOf(action) == _Stage.closed) completed++;
    }
    if (_advisorSkippedTicket(ticket)) advisorSkipped++;
  }
  return _KpiStats(totalRequests: total, totalCompleted: completed, advisorSkippedCount: advisorSkipped);
}

/// هل تخطَّى الطالب مرحلة المرشد كليًا؟ - المرشد لم يعمل على أي من إجراءات
/// هذا الطالب إطلاقًا، لكن منسّق القسم أو منسّق الكلية أنجز شيئًا منها -
/// يعني المرشد بالاسم (`ticket['advisor']`) هو من يحتاج متابعة، لا "التأخر".
bool _advisorSkippedTicket(Map<String, dynamic> ticket) {
  if (ticketOutcomeForField(ticket, 'advisor_status') != TicketAdvisorOutcome.notStarted) return false;
  return ticketOutcomeForField(ticket, 'coordinator_status') != TicketAdvisorOutcome.notStarted ||
      ticketOutcomeForField(ticket, 'college_status') != TicketAdvisorOutcome.notStarted;
}

/// نفس فكرة [_advisorSkippedTicket] لمنسّق القسم - لم يعمل على أي إجراء
/// إطلاقًا، لكن منسّق الكلية أنجز شيئًا منها بدلًا عنه.
bool _coordinatorSkippedTicket(Map<String, dynamic> ticket) {
  if (ticketOutcomeForField(ticket, 'coordinator_status') != TicketAdvisorOutcome.notStarted) return false;
  return ticketOutcomeForField(ticket, 'college_status') != TicketAdvisorOutcome.notStarted;
}

/// سجل مساءلة مرشد واحد بالاسم - كم طالبًا تخطّى المرشد حالته كليًا فأُنجزت
/// عند منسّق القسم/الكلية بدلًا عنه (سليمان 2026-08-21: هذا دور إدارة
/// الوحدة الفعلي - متابعة من لم يعمل، لا من "تأخّر" بالوقت).
class _AdvisorAccountability {
  final String advisorName;
  final String department;
  final String shatrLabel;
  final int skippedCount;
  const _AdvisorAccountability({
    required this.advisorName,
    required this.department,
    required this.shatrLabel,
    required this.skippedCount,
  });
}

/// نفس الفكرة لمنسّق القسم - بلا اسم (لا يوجد حقل بالتذكرة يحدّد اسم منسّق
/// القسم تحديدًا، بخلاف المرشد)، فتُجمَّع فقط بمستوى قسم-شطر.
class _CoordinatorAccountability {
  final String department;
  final String shatrLabel;
  final int skippedCount;
  const _CoordinatorAccountability({required this.department, required this.shatrLabel, required this.skippedCount});
}

String _shatrDisplayLabel(String shatrRaw) => shatrRaw == ExcelParserService.shatrMale ? 'شطر الطلاب' : 'شطر الطالبات';

List<_AdvisorAccountability> _computeAdvisorAccountability(List<Map<String, dynamic>> tickets) {
  final counts = <String, int>{};
  final meta = <String, ({String name, String dept, String shatr})>{};
  for (final ticket in tickets) {
    if (!_advisorSkippedTicket(ticket)) continue;
    final name = (ticket['advisor'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final dept = _DashboardData._displayDepartment((ticket['department'] ?? '').toString());
    final shatr = _shatrDisplayLabel((ticket['shatr'] ?? '').toString());
    final key = '$name|$dept|$shatr';
    counts[key] = (counts[key] ?? 0) + 1;
    meta[key] = (name: name, dept: dept, shatr: shatr);
  }
  final list = counts.entries.map((e) {
    final m = meta[e.key]!;
    return _AdvisorAccountability(advisorName: m.name, department: m.dept, shatrLabel: m.shatr, skippedCount: e.value);
  }).toList();
  list.sort((a, b) => b.skippedCount.compareTo(a.skippedCount));
  return list;
}

List<_CoordinatorAccountability> _computeCoordinatorAccountability(List<Map<String, dynamic>> tickets) {
  final counts = <String, int>{};
  final meta = <String, ({String dept, String shatr})>{};
  for (final ticket in tickets) {
    if (!_coordinatorSkippedTicket(ticket)) continue;
    final dept = _DashboardData._displayDepartment((ticket['department'] ?? '').toString());
    final shatr = _shatrDisplayLabel((ticket['shatr'] ?? '').toString());
    final key = '$dept|$shatr';
    counts[key] = (counts[key] ?? 0) + 1;
    meta[key] = (dept: dept, shatr: shatr);
  }
  final list = counts.entries.map((e) {
    final m = meta[e.key]!;
    return _CoordinatorAccountability(department: m.dept, shatrLabel: m.shatr, skippedCount: e.value);
  }).toList();
  list.sort((a, b) => b.skippedCount.compareTo(a.skippedCount));
  return list;
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

  /// نص وصف نطاق الفلتر الحالي - يُلحَق بنصوص بطاقات المؤشرات حتى لا يبقى
  /// أي رقم مبهمًا بلا سياق (سليمان 2026-08-21: "إذا كان الفلتر عام يظهر
  /// للكل أو حسب القسم وهكذا").
  String _filterScopeLabel() {
    final parts = <String>[];
    if (_department != null) parts.add(_department!.replaceFirst('قسم ', ''));
    if (_shatr != _ShatrFilter.all) parts.add(_shatr == _ShatrFilter.male ? 'شطر الطلاب' : 'شطر الطالبات');
    if (_priority == _PriorityFilter.disability) parts.add('ذوي الإعاقة');
    if (_priority == _PriorityFilter.graduate) parts.add('المتوقع تخرجهم');
    return parts.isEmpty ? 'كل الأقسام والشطرين' : parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTickets;
    final kpi = _computeKpiStats(filtered);
    final actionTypeStats = _computeActionTypeStats(filtered);
    final roleProgress = _computeRoleProgress(filtered);
    final advisorAccountability = _computeAdvisorAccountability(filtered);
    final coordinatorAccountability = _computeCoordinatorAccountability(filtered);
    final scopeLabel = _filterScopeLabel();

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
        _KpiRow(kpi: kpi, scopeLabel: scopeLabel),
        const SizedBox(height: 18),
        _ActionTypeSection(stats: actionTypeStats),
        const SizedBox(height: 18),
        _WorkflowSection(roleProgress: roleProgress),
        const SizedBox(height: 18),
        // TODO(معاينة مؤقتة سليمان 2026-08-21): بيانات وهمية لرؤية شكل الحالة
        // غير الفارغة فقط - أزلها وأعد `advisorAccountability`/`coordinatorAccountability`
        // الحقيقيتين قبل أي نشر.
        _MainGrid(
          advisorList: advisorAccountability.isNotEmpty
              ? advisorAccountability
              : const [
                  _AdvisorAccountability(advisorName: 'أ. نموذج تجريبي', department: 'قسم الإدارة', shatrLabel: 'شطر الطلاب', skippedCount: 3),
                  _AdvisorAccountability(advisorName: 'د. نموذج تجريبي 2', department: 'قسم المحاسبة', shatrLabel: 'شطر الطالبات', skippedCount: 1),
                ],
          coordinatorList: coordinatorAccountability.isNotEmpty
              ? coordinatorAccountability
              : const [
                  _CoordinatorAccountability(department: 'قسم التسويق', shatrLabel: 'شطر الطلاب', skippedCount: 2),
                ],
        ),
      ],
    );
  }
}

/// 4 بطاقات تشغيلية Compact - أصغر بنحو 20% من النسخة السابقة، مع مؤشر دائري
/// مصغَّر لبطاقة نسبة الإنجاز بدل أيقونة ثابتة.
class _KpiRow extends StatelessWidget {
  final _KpiStats kpi;
  final String scopeLabel;
  const _KpiRow({required this.kpi, required this.scopeLabel});

  @override
  Widget build(BuildContext context) {
    final total = kpi.totalRequests;
    final completed = kpi.totalCompleted;
    final rate = total == 0 ? 0 : (completed / total * 100).round();
    final pending = total - completed;
    final skipped = kpi.advisorSkippedCount;

    final cards = <Widget>[
      _KpiCard(
        title: 'طلبات تحتاج إجراء',
        value: '$pending',
        meta: 'من إجمالي $total طلبًا ($completed منها أُغلق نهائيًا) - $scopeLabel',
        icon: Icons.pending_actions_outlined,
        accent: AppColors.green,
      ),
      _KpiCard(
        title: 'طلاب تخطّى المرشد حالاتهم',
        value: '$skipped',
        meta: skipped == 0 ? 'لا توجد حالات تخطّت المرشد - $scopeLabel' : 'أُنجزت لاحقًا عند منسّق القسم ضمن $scopeLabel - راجع القائمة أدناه',
        icon: Icons.person_off_outlined,
        accent: AppColors.errorRed,
      ),
      _KpiCard(
        title: 'نسبة الإغلاق النهائي',
        value: '$rate%',
        meta: '$completed من أصل $total طلبًا - $scopeLabel',
        icon: Icons.donut_large_outlined,
        accent: AppColors.greenDark,
        donutPercent: rate / 100,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(title: 'الإغلاق الإداري النهائي', icon: Icons.fact_check_outlined),
          const SizedBox(height: 4),
          Text(
            'هذه الأرقام تقيس اكتمال إغلاق الحالة إداريًا بكل المستويات (مرشد ← منسّق قسم ← منسّق كلية) - '
            'لا تنفيذ المرشد وحده. لتفاصيل الإنجاز حسب كل دور راجع "متابعة سير العمل" أدناه.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth < 650 ? 1 : (constraints.maxWidth < 1100 ? 2 : 3);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in cards) SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns, child: c),
              ],
            );
          }),
        ],
      ),
    );
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
      constraints: const BoxConstraints(minHeight: 68),
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
          Row(
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
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                        const SizedBox(width: 8),
                        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
                  ],
                ),
              ),
            ],
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
    final active = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: active ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: active ? Colors.white : Colors.grey.shade600),
          dropdownColor: Colors.white,
          items: [
            const DropdownMenuItem(value: null, child: Text('القسم العلمي', style: TextStyle(color: Colors.black87))),
            for (final d in _kCanonicalDepartmentOrder)
              DropdownMenuItem(value: d, child: Text(d.replaceFirst('قسم ', ''), style: const TextStyle(color: Colors.black87))),
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
    final active = value != _ShatrFilter.all;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: active ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_ShatrFilter>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: active ? Colors.white : Colors.grey.shade600),
          dropdownColor: Colors.white,
          items: const [
            DropdownMenuItem(value: _ShatrFilter.all, child: Text('الشطر', style: TextStyle(color: Colors.black87))),
            DropdownMenuItem(value: _ShatrFilter.male, child: Text('الطلاب', style: TextStyle(color: Colors.black87))),
            DropdownMenuItem(value: _ShatrFilter.female, child: Text('الطالبات', style: TextStyle(color: Colors.black87))),
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
    final active = value != _PriorityFilter.all;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: active ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_PriorityFilter>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: active ? Colors.white : Colors.grey.shade600),
          dropdownColor: Colors.white,
          items: const [
            DropdownMenuItem(value: _PriorityFilter.all, child: Text('الحالة', style: TextStyle(color: Colors.black87))),
            DropdownMenuItem(value: _PriorityFilter.disability, child: Text('ذوي الإعاقة', style: TextStyle(color: Colors.black87))),
            DropdownMenuItem(value: _PriorityFilter.graduate, child: Text('المتوقع تخرجهم', style: TextStyle(color: Colors.black87))),
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

/// نفس هوية [_KpiCard] الأعلى بالضبط (حاوية بيضاء + إطار رمادي + لمسة ذهبية
/// + نفس أحجام الخطوط) - كانتا بتصميمين مختلفين تمامًا قبل التوحيد (سليمان
/// 2026-08-21: "لا يوجد شكل جمالي يناسب الهوية البصرية ولا توسيط للمحتوى").
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
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(width: 3, height: 30, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(3))),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MiniDonut(percent: stats.rate, color: _color, size: 46, strokeWidth: 5.5, centerText: '${(stats.rate * 100).round()}%'),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: Text('${stats.label} — ${stats.total} طلبًا', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                        const SizedBox(width: 8),
                        Text('${(stats.rate * 100).round()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${stats.completed} مكتمل • ${stats.processing} قيد المعالجة • ${stats.notStarted} لم يبدأ',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// مساءلة من لم يعمل - عرض كامل (بلا "النشاطات والتنبيهات" المجاورة، أُزيلت
/// مؤقتًا بطلب سليمان 2026-08-21 لأنها بلا فائدة فعلية حتى توفّر سجل حركات
/// لحظي حقيقي؛ الكود [_ActivityFeedSection] بقي بالملف لإعادتها لاحقًا).
class _MainGrid extends StatelessWidget {
  final List<_AdvisorAccountability> advisorList;
  final List<_CoordinatorAccountability> coordinatorList;
  const _MainGrid({required this.advisorList, required this.coordinatorList});

  @override
  Widget build(BuildContext context) {
    return _AccountabilitySection(advisorList: advisorList, coordinatorList: coordinatorList);
  }
}

/// "من لم يعمل على حالاته" - بديل "تحتاج تدخل إدارة الوحدة" القديم المبني
/// على وقت/إعاقة. القاعدة الحقيقية (سليمان 2026-08-21): "دوري متابعة
/// الحالات التي لم يتم عليها أي إجراء" - بالاسم للمرشد (تخطّاه القسم/الكلية
/// وأنجزا بدلًا عنه)، وبمستوى القسم للمنسّق (لا يوجد اسم منسّق بالتذكرة).
/// منسّق الكلية خارج أي مساءلة هنا عمدًا - بمجرد وصول الحالة إليه فهي
/// "منجزة" من منظور الوحدة بصرف النظر متى/كيف ينفّذها فعليًا.
class _AccountabilitySection extends StatelessWidget {
  final List<_AdvisorAccountability> advisorList;
  final List<_CoordinatorAccountability> coordinatorList;
  const _AccountabilitySection({required this.advisorList, required this.coordinatorList});

  @override
  Widget build(BuildContext context) {
    final totalSkipped = advisorList.fold<int>(0, (s, a) => s + a.skippedCount) + coordinatorList.fold<int>(0, (s, c) => s + c.skippedCount);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              const Icon(Icons.person_off_outlined, size: 19, color: AppColors.greenDark),
              const SizedBox(width: 7),
              const Text('من لم يعمل على حالاته', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppColors.greenDark)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.errorRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text('$totalSkipped حالة', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.errorRed)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'طلاب أُنجزت حالاتهم دون أن يعمل عليها المرشد/منسّق القسم إطلاقًا - أُنجزت لاحقًا عند من فوقه. '
            'منسّق الكلية غير مُتابَع هنا (جهة تنفيذية بلا مهلة زمنية).',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 14),
          if (totalSkipped == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('لا توجد حالات تخطّت المرشد أو منسّق القسم حاليًا', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
              ),
            )
          else
            // ارتفاع أقصى ثابت + تمرير داخلي - يمنع القسم من تمديد الصفحة كاملة
            // نزولًا عند وجود حالات كثيرة (بطلب سليمان 2026-08-21: "أشاهد كل
            // شيء دون تصغير الصفحة").
            SizedBox(
              height: 260,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (advisorList.isNotEmpty) ...[
                      Text('مرشدون تخطّتهم حالات', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      for (final a in advisorList) _AccountabilityRow(primary: a.advisorName, secondary: '${a.department} - ${a.shatrLabel}', count: a.skippedCount),
                    ],
                    if (advisorList.isNotEmpty && coordinatorList.isNotEmpty) const SizedBox(height: 16),
                    if (coordinatorList.isNotEmpty) ...[
                      Text('أقسام تخطّى منسّقوها حالات', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      for (final c in coordinatorList) _AccountabilityRow(primary: '${c.department} - ${c.shatrLabel}', secondary: 'منسّق القسم', count: c.skippedCount),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountabilityRow extends StatelessWidget {
  final String primary;
  final String secondary;
  final int count;
  const _AccountabilityRow({required this.primary, required this.secondary, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(primary, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(secondary, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.errorRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text('$count حالة', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.errorRed)),
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

