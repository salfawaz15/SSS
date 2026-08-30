import 'package:flutter/material.dart';

import '../../../services/advising_overview_stats_service.dart';
import '../../../services/report_data_service.dart';
import '../../../services/ticket_action_stats_service.dart';
import '../../../services/ticket_workflow_stats_service.dart';
import '../../../utils/name_display.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/mobile_alert_banner.dart';
import '../../widgets/mobile_empty_state.dart';
import '../../widgets/mobile_error_state.dart';
import '../../widgets/mobile_kpi_card.dart';
import '../../widgets/mobile_loading_state.dart';
import '../../widgets/mobile_status_row.dart';
import '../../widgets/mobile_workflow_summary_card.dart';
import '../../widgets/portal_app_bar_logo.dart';
import 'admin_summary_data_controller.dart';

/// حد أقصى لعرض المحتوى على الشاشات العريضة (تابلت) - بلا هذا الحد كانت
/// بطاقات `MobileKpiCard`/`MobileWorkflowSummaryCard` (نسب عرض/ارتفاع ثابتة)
/// تتمدد بعرض هائل مع محتوى صغير بداخلها فراغًا كبيرًا غير مستغَل يبدو "غير
/// احترافي" (سليمان صراحةً 2026-08-26، لقطة فعلية من جهاز تابلت). على الجوال
/// العادي هذا الحد لا يُفعَّل إطلاقًا (العرض دائمًا أقل منه).
Widget _capWideScreen(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child));

/// لوحة إدارة مختصرة بتبويبين فرعيين - بطلب سليمان صراحةً (2026-08-23):
/// لوحة الإدارة بالموقع تنقسم فعليًا لقسمين (الحذف والإضافة/الإرشاد)،
/// فتبويب "لوحة الإدارة" الجوّالي يحاكي نفس التقسيم بمفتاح تبديل علوي بدل
/// خلط القسمين بصفحة واحدة.
class AdminSummaryScreen extends StatelessWidget {
  const AdminSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: kPortalAppBarLeadingWidth,
          leading: const PortalAppBarLogo(),
          title: const Text('لوحة الإدارة'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الحذف والإضافة'),
              Tab(text: 'الإرشاد'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DeleteAddTab(),
            _AdvisingTab(),
          ],
        ),
      ),
    );
  }
}

/// قسم "الإرشاد" الفرعي - نفس مصدر البيانات المستخدَم بالرئيسية
/// (`AdvisingOverviewStatsService`) بلا تكرار حساب، لكن بتفصيل أعمق يناسب
/// صفحة التفصيل: بطاقة "الكل" الخامسة مُعادة هنا (حُذفت من الرئيسية عمدًا
/// لأنها لمحة سريعة)، وجدولا توزيع حسب القسم العلمي (طلاب/طالبات).
class _AdvisingTab extends StatefulWidget {
  const _AdvisingTab();

  @override
  State<_AdvisingTab> createState() => _AdvisingTabState();
}

class _AdvisingTabState extends State<_AdvisingTab> {
  late Future<AdvisingOverviewStats> _statsFuture = AdvisingOverviewStatsService.load();
  late Future<List<AdvisingDepartmentBreakdown>> _breakdownFuture = AdvisingOverviewStatsService.loadDepartmentBreakdown();

  Future<void> _reload() async {
    setState(() {
      _statsFuture = AdvisingOverviewStatsService.load();
      _breakdownFuture = AdvisingOverviewStatsService.loadDepartmentBreakdown();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: _capWideScreen(ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('مؤشرات رئيسية لحالات الإرشاد', style: AppTextStyles.h3()),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<AdvisingOverviewStats>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return MobileErrorState(onRetry: _reload);
              }
              if (!snapshot.hasData) {
                return const MobileLoadingState();
              }
              final a = snapshot.data!;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 2.8,
                children: [
                  MobileKpiCard(
                    label: 'طلبة على غير مرشدهم',
                    value: '${a.wrongAdvisor}',
                    note: 'منهم ${a.wrongAdvisorWithDisability} من ذوي الإعاقة',
                    icon: Icons.sync_problem_outlined,
                    accentColor: AppColors.gold,
                  ),
                  MobileKpiCard(
                    label: 'طلبة بلا مرشد',
                    value: '${a.withoutAdvisor}',
                    icon: Icons.person_off_outlined,
                    accentColor: AppColors.errorRed,
                  ),
                  MobileKpiCard(
                    label: 'طلبة تابعين لمرشد – ذوي الإعاقة',
                    value: '${a.assignedWithDisability}',
                    icon: Icons.accessible_outlined,
                    accentColor: AppColors.green,
                  ),
                  MobileKpiCard(
                    label: 'طلبة تابعين لمرشد',
                    value: '${a.assigned}',
                    icon: Icons.school_outlined,
                    accentColor: AppColors.greenDark,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('التوزيع حسب القسم العلمي', style: AppTextStyles.h3()),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<List<AdvisingDepartmentBreakdown>>(
            future: _breakdownFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return MobileErrorState(onRetry: _reload);
              }
              if (!snapshot.hasData) {
                return const MobileLoadingState();
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const MobileEmptyState(message: 'لا توجد بيانات إرشاد بعد', icon: Icons.apartment_outlined);
              }
              return Column(
                children: [
                  _AdvisingDepartmentTable(
                    title: 'شطر الطلاب',
                    rows: rows.where((r) => r.shatr.contains('طلاب') && !r.shatr.contains('طالبات')).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _AdvisingDepartmentTable(
                    title: 'شطر الطالبات',
                    rows: rows.where((r) => r.shatr.contains('طالبات')).toList(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      )),
    );
  }
}

/// جدول توزيع قسم علمي واحد بشطر واحد - عمودان (تابعين لمرشد/على غير
/// مرشدهم) بدل شريط تقدّم (لا نسبة إنجاز هنا، بل عدّ مباشر لكل تصنيف).
class _AdvisingDepartmentTable extends StatelessWidget {
  final String title;
  final List<AdvisingDepartmentBreakdown> rows;
  const _AdvisingDepartmentTable({required this.title, required this.rows});

  static String _shortDepartmentName(String raw) => raw.replaceFirst('قسم ', '').trim();

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Expanded(flex: 3, child: SizedBox()),
              Expanded(child: Center(child: Text('تابعين لمرشد', style: AppTextStyles.caption(color: Colors.black54)))),
              Expanded(child: Center(child: Text('على غير مرشدهم', style: AppTextStyles.caption(color: Colors.black54)))),
            ],
          ),
          const Divider(height: AppSpacing.md),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(_shortDepartmentName(row.department), style: AppTextStyles.body(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('${row.assigned}', style: AppTextStyles.body(color: AppColors.green).copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('${row.wrongAdvisor}', style: AppTextStyles.body(color: AppColors.gold).copyWith(fontWeight: FontWeight.w700)),
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

class _DeleteAddTab extends StatefulWidget {
  const _DeleteAddTab();

  @override
  State<_DeleteAddTab> createState() => _DeleteAddTabState();
}

class _DeleteAddTabState extends State<_DeleteAddTab> {
  final _stream = AdminSummaryDataController.watch();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminSummaryData>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MobileErrorState(onRetry: () => setState(() {}));
          }
          if (!snapshot.hasData) {
            return const MobileLoadingState();
          }
          final data = snapshot.data!;
          final rate = (data.report.overall.completionRate * 100).round();
          final departmentsWithCases = data.report.departments.where((d) => d.counts.total > 0).toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: _capWideScreen(ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                // أهم جزء بقسم "الحذف والإضافة" حسب سليمان صراحةً (2026-08-23):
                // حالة الحالات عند المرشد الأكاديمي تحديدًا - منجزة/لم يُعمَل
                // عليها/محوَّلة لمنسّق القسم (لم يُنفَّذها المرشد فانتقلت
                // للمستوى التالي).
                Text('حالة الحالات - المرشد الأكاديمي', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: MobileKpiCard(
                        label: 'منجزة',
                        value: '${data.advisorProgress.complete}',
                        icon: Icons.check_circle_outline,
                        accentColor: AppColors.green,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: MobileKpiCard(
                        label: 'لم يُعمَل عليها',
                        value: '${data.advisorProgress.notStarted}',
                        icon: Icons.hourglass_empty_rounded,
                        accentColor: PortalStatusColors.notStarted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: MobileKpiCard(
                        label: 'محوَّلة لمنسّق القسم',
                        value: '${data.advisorProgress.escalated}',
                        icon: Icons.move_up_outlined,
                        accentColor: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('نظرة عامة', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: MobileKpiCard(
                        label: 'إجمالي الحالات',
                        value: '${data.totalCases}',
                        icon: Icons.folder_copy_outlined,
                        accentColor: AppColors.greenDark,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: MobileKpiCard(
                        label: 'الأقسام النشطة',
                        value: '${data.activeDepartmentsCount}',
                        icon: Icons.apartment_rounded,
                        accentColor: AppColors.gold,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: MobileKpiCard(
                        label: 'نسبة الإنجاز',
                        value: '$rate%',
                        icon: Icons.trending_up_rounded,
                        accentColor: AppColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('حالة الإجراءات', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                _ActionTypeStatusSection(actionTypeStats: data.actionTypeStats),
                const SizedBox(height: AppSpacing.xl),
                Text('الإنجاز حسب القسم العلمي', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                if (departmentsWithCases.isEmpty)
                  const MobileEmptyState(message: 'لا توجد بيانات حالات بعد', icon: Icons.apartment_outlined)
                else ...[
                  _DepartmentShatrTable(
                    title: 'شطر الطلاب',
                    departments: departmentsWithCases.where((d) => d.shatr.contains('طلاب') && !d.shatr.contains('طالبات')).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DepartmentShatrTable(
                    title: 'شطر الطالبات',
                    departments: departmentsWithCases.where((d) => d.shatr.contains('طالبات')).toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text('عدد الحالات حسب القسم والشطر', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                if (departmentsWithCases.isEmpty)
                  const MobileEmptyState(message: 'لا توجد بيانات حالات بعد', icon: Icons.apartment_outlined)
                else ...[
                  _DepartmentCaseCountTable(
                    title: 'شطر الطلاب',
                    departments: departmentsWithCases.where((d) => d.shatr.contains('طلاب') && !d.shatr.contains('طالبات')).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DepartmentCaseCountTable(
                    title: 'شطر الطالبات',
                    departments: departmentsWithCases.where((d) => d.shatr.contains('طالبات')).toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text('عدد الحالات حسب العضو', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                _AdvisorCaseCountTable(report: data.report),
                const SizedBox(height: AppSpacing.xl),
                Text('حالات تحتاج انتباه', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                MobileAlertBanner(exceededCount: data.exceededCount),
                const SizedBox(height: AppSpacing.xl),
                Text('متابعة سير العمل', style: AppTextStyles.h3()),
                const SizedBox(height: AppSpacing.sm),
                _WorkflowSection(roleProgress: data.roleProgress),
                const SizedBox(height: AppSpacing.xl),
              ],
            )),
          );
        },
      );
  }
}

/// جدول إنجاز أقسام شطر واحد - جدولان منفصلان (طلاب/طالبات) بدل قائمة واحدة
/// مختلطة (سليمان 2026-08-23: "شكله غير احترافي")، مع حذف كلمة "قسم" و"شطر
/// ال..." من التسمية (كانت تُقصّ ولا تظهر كاملة على عرض جوال ضيق - يكتفى
/// باسم القسم المختصر: "الإدارة"، "المحاسبة"...).
class _DepartmentShatrTable extends StatelessWidget {
  final String title;
  final List<DepartmentReport> departments;
  const _DepartmentShatrTable({required this.title, required this.departments});

  static String _shortDepartmentName(String raw) => raw.replaceFirst('قسم ', '').trim();

  @override
  Widget build(BuildContext context) {
    if (departments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
          const Divider(height: AppSpacing.md),
          for (final dept in departments)
            MobileStatusRow(
              label: _shortDepartmentName(dept.department),
              progress: dept.counts.completionRate,
              labelFlex: 3,
            ),
        ],
      ),
    );
  }
}

/// جدول عدد الحالات (لا نسبة إنجاز) لكل قسم بشطر واحد - يجاوب مباشرة على
/// "كم حالة بكل قسم؟" بدل شريط تقدّم فقط.
class _DepartmentCaseCountTable extends StatelessWidget {
  final String title;
  final List<DepartmentReport> departments;
  const _DepartmentCaseCountTable({required this.title, required this.departments});

  static String _shortDepartmentName(String raw) => raw.replaceFirst('قسم ', '').trim();

  @override
  Widget build(BuildContext context) {
    if (departments.isEmpty) return const SizedBox.shrink();
    final sorted = [...departments]..sort((a, b) => b.counts.total.compareTo(a.counts.total));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
          const Divider(height: AppSpacing.md),
          for (final dept in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_shortDepartmentName(dept.department), style: AppTextStyles.body(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('${dept.counts.total}', style: AppTextStyles.body(color: AppColors.greenDark).copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// جدول عدد الحالات لكل عضو (مرشد أكاديمي) - كل أعضاء كل الأقسام والشطرين
/// بقائمة واحدة مرتَّبة تنازليًا حسب عدد الحالات.
class _AdvisorCaseCountTable extends StatelessWidget {
  final ReportData report;
  const _AdvisorCaseCountTable({required this.report});

  @override
  Widget build(BuildContext context) {
    final rows = <AdvisorProgress>[];
    for (final department in report.departments) {
      for (final advisor in department.advisors) {
        if (advisor.counts.total == 0) continue;
        rows.add(AdvisorProgress(
          shatr: department.shatr,
          department: department.department,
          advisorName: advisor.name,
          counts: advisor.counts,
        ));
      }
    }
    if (rows.isEmpty) {
      return const MobileEmptyState(message: 'لا توجد بيانات أعضاء بعد', icon: Icons.people_outline);
    }
    rows.sort((a, b) => b.counts.total.compareTo(a.counts.total));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(displayName(row.advisorName), style: AppTextStyles.body(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(row.department.replaceFirst('قسم ', '').trim(), style: AppTextStyles.caption(color: Colors.black54)),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${row.counts.total}', style: AppTextStyles.body(color: AppColors.greenDark).copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionTypeStatusSection extends StatelessWidget {
  final Map<String, ActionTypeStats> actionTypeStats;
  const _ActionTypeStatusSection({required this.actionTypeStats});

  @override
  Widget build(BuildContext context) {
    if (actionTypeStats.isEmpty) {
      return const MobileEmptyState(message: 'لا توجد بيانات إجراءات بعد', icon: Icons.assignment_outlined);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (final entry in actionTypeStats.entries)
            MobileStatusRow(label: entry.key, progress: entry.value.statusCounts.completionRate),
        ],
      ),
    );
  }
}

class _WorkflowSection extends StatelessWidget {
  final List<TicketRoleProgress> roleProgress;
  const _WorkflowSection({required this.roleProgress});

  @override
  Widget build(BuildContext context) {
    if (roleProgress.isEmpty) {
      return const MobileEmptyState(message: 'لا توجد بيانات سير عمل بعد', icon: Icons.timeline_outlined);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          const MobileWorkflowSummaryHeader(),
          const Divider(height: AppSpacing.md),
          for (final progress in roleProgress) MobileWorkflowSummaryCard(progress: progress),
        ],
      ),
    );
  }
}
