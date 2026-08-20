import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/advising_case_analyzer.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'advisor_students_lookup_screen.dart';
import 'hardship_cases_admin_screen.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';
import 'support_cases_admin_screen.dart';

/// صفحة وسيطة تجمع كل ما يخص الإرشاد بضغطة واحدة من الشريط العلوي - بدل
/// تبويب مستقل لكل قسم (حالات الظروف الخاصة/الدعم النفسي/متابعة الإرشاد) كما
/// كان سابقًا، بطلب سليمان صراحةً (2026-08-07) لتبسيط الشريط العلوي.
/// "متابعة حالات الإرشاد" حصرية لحساب المدير العام (نفس تقييدها الأصلي بلوحة
/// الإدارة) - الظروف الخاصة والدعم النفسي متاحان لكل حسابات الإدارة.
///
/// أُعيد تصميمها (2026-08-20) بهوية `DashTokens` الموحَّدة (المستخرجة من
/// لوحة "الحذف والإضافة") بدل البطاقات الملوَّنة السابقة: شريط KPI بشريط
/// أعلى ملوَّن + دائرة تغطية إرشادية + شبكة إجراءات ببطاقات بيضاء - بطلب
/// سليمان الصريح: "اجعل الهوية واحدة... واملأ الصفحة بلا فراغات بيضاء".
/// الأرقام تُحسَب من نفس منطق التحليل المستخدم فعليًا في
/// [AdvisingCasesAdminScreen] (عبر [AdvisingCaseAnalyzer]) بلا أي حساب جديد.
class AdvisingHubScreen extends StatefulWidget {
  const AdvisingHubScreen({super.key});

  @override
  State<AdvisingHubScreen> createState() => _AdvisingHubScreenState();
}

class _AdvisingHubScreenState extends State<AdvisingHubScreen> {
  bool _loadingStats = true;
  int _advisorsWithStudents = 0;
  int _advisorsWithoutStudents = 0;
  int _studentsWithAdvisor = 0;
  int _studentsWithoutAdvisor = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  /// يحسب إحصائيات الإرشاد من نفس مصدر [AdvisingCasesAdminScreen] الحالي
  /// (تقرير "كل الكليات" + ذوو الإعاقة + منسوبي الكلية) عبر
  /// [AdvisingCaseAnalyzer.loadCollegeScopedStudents] المشترك - بلا إعادة
  /// تنفيذ أي منطق تحميل/دمج جديد هنا.
  Future<void> _loadStats() async {
    try {
      final loaded = await AdvisingCaseAnalyzer.loadCollegeScopedStudents();
      if (!mounted) return;

      final maleAnalysis = AdvisingCaseAnalyzer.analyze(students: loaded.male, facultyByNameKey: loaded.facultyByKey);
      final femaleAnalysis = AdvisingCaseAnalyzer.analyze(students: loaded.female, facultyByNameKey: loaded.facultyByKey);

      int advisorsWithStudents(AdvisingCaseAnalysis a) => a.quotaReport.length - a.advisorsWithNoStudents.length;
      int studentsWithAdvisor(AdvisingCaseAnalysis a) => a.studentsCorrectlyAssigned.length + a.studentsWithWrongDeptAdvisor.length;

      if (!mounted) return;
      setState(() {
        _advisorsWithStudents = advisorsWithStudents(maleAnalysis) + advisorsWithStudents(femaleAnalysis);
        _advisorsWithoutStudents = maleAnalysis.advisorsWithNoStudents.length + femaleAnalysis.advisorsWithNoStudents.length;
        _studentsWithAdvisor = studentsWithAdvisor(maleAnalysis) + studentsWithAdvisor(femaleAnalysis);
        _studentsWithoutAdvisor = maleAnalysis.studentsWithoutAdvisor.length + femaleAnalysis.studentsWithoutAdvisor.length;
        _loadingStats = false;
      });
    } catch (_) {
      // لا تُفشِل عرض الصفحة إن تعذّر حساب الإحصائيات (مثلاً قبل رفع أي
      // تقرير) - تبقى الأرقام صفرًا وتختفي مؤشر التحميل فقط.
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'لوحة الإرشاد',
      navItems: buildAdminNavItems(context, current: 'advising-hub'),
      body: Container(
        color: DashTokens.pageBg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DashSectionHeader(
                    title: 'نظرة عامة على الإرشاد',
                    subtitle: 'أرقام حيّة من آخر بيانات إرشاد مرفوعة',
                    icon: Icons.query_stats_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildOverviewRow(context),
                  const SizedBox(height: 20),
                  const DashSectionHeader(title: 'الخدمات السريعة', icon: Icons.dashboard_customize_outlined),
                  const SizedBox(height: 12),
                  _buildActionsGrid(context, isSuperAdmin: isSuperAdmin),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewRow(BuildContext context) {
    final tiles = [
      (
        label: 'مرشدون لديهم طلاب',
        value: _loadingStats ? '...' : '$_advisorsWithStudents',
        note: 'من إجمالي المرشدين',
        icon: Icons.groups_outlined,
        color: DashTokens.green900,
      ),
      (
        label: 'مرشدون بدون طلاب',
        value: _loadingStats ? '...' : '$_advisorsWithoutStudents',
        note: 'معفَون أو بلا حالات',
        icon: Icons.person_off_outlined,
        color: DashTokens.gold600,
      ),
      (
        label: 'طلاب لهم مرشد',
        value: _loadingStats ? '...' : '$_studentsWithAdvisor',
        note: 'من إجمالي الطلبة',
        icon: Icons.school_outlined,
        color: DashTokens.success,
      ),
      (
        label: 'طلاب بلا مرشد',
        value: _loadingStats ? '...' : '$_studentsWithoutAdvisor',
        note: 'يحتاجون تسكينًا',
        icon: Icons.person_search_outlined,
        color: DashTokens.danger,
      ),
    ];

    final coverageCard = DashCardShell(
      title: 'التغطية الإرشادية',
      subtitle: 'نسبة الطلبة المسنَدين لمرشد',
      icon: Icons.donut_large_outlined,
      child: _CoverageGauge(withAdvisor: _studentsWithAdvisor, withoutAdvisor: _studentsWithoutAdvisor, loading: _loadingStats),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        final kpiGrid = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: isNarrow ? 500 : 260,
            mainAxisExtent: 92,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, i) {
            final t = tiles[i];
            return DashKpiCard(label: t.label, value: t.value, note: t.note, icon: t.icon, accent: t.color);
          },
        );
        if (isNarrow) {
          return Column(children: [kpiGrid, const SizedBox(height: 12), coverageCard]);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 160, child: kpiGrid),
              const SizedBox(width: 12),
              Expanded(flex: 100, child: coverageCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionsGrid(BuildContext context, {required bool isSuperAdmin}) {
    final tiles = <({IconData icon, String title, String subtitle, Color accent, VoidCallback onTap})>[
      if (isSuperAdmin)
        (
          icon: Icons.fact_check_outlined,
          title: 'متابعة حالات الإرشاد',
          subtitle: 'كشف بيانات الطلبة، النصاب، إعادة التوزيع، والتقارير التفصيلية',
          accent: DashTokens.green900,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdvisingCasesAdminScreen()),
          ),
        ),
      if (isSuperAdmin)
        (
          icon: Icons.person_search_outlined,
          title: 'بحث عن مرشد وقائمة طلابه',
          subtitle: 'ابحث باسم أو رقم المرشد لعرض كل طلابه دفعة واحدة',
          accent: DashTokens.green900,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdvisorStudentsLookupScreen()),
          ),
        ),
      (
        icon: Icons.volunteer_activism_outlined,
        title: 'متابعة حالات الظروف الخاصة',
        subtitle: 'متابعة الحالات المسجَّلة ذات الظروف الخاصة',
        accent: DashTokens.gold600,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.favorite_border,
        title: 'متابعة حالات الدعم النفسي والاجتماعي',
        subtitle: 'متابعة طلبات الدعم النفسي والاجتماعي للطلبة',
        accent: DashTokens.success,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.schedule_outlined,
        title: 'توزيع فترات الإرشاد',
        subtitle: 'جدول فترات الإرشاد الرسمي لكل قسم وشطر',
        accent: DashTokens.gold500,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdvisingScheduleAdminScreen()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 108,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, i) {
        final t = tiles[i];
        return DashActionCard(icon: t.icon, title: t.title, subtitle: t.subtitle, accent: t.accent, onTap: t.onTap);
      },
    );
  }
}

/// دائرة "التغطية الإرشادية" (نسبة الطلبة المسنَدين لمرشد) - بنفس أسلوب
/// `_StatusGauge` بلوحة الحذف والإضافة حرفيًا.
class _CoverageGauge extends StatelessWidget {
  final int withAdvisor;
  final int withoutAdvisor;
  final bool loading;

  const _CoverageGauge({required this.withAdvisor, required this.withoutAdvisor, required this.loading});

  @override
  Widget build(BuildContext context) {
    final total = withAdvisor + withoutAdvisor == 0 ? 1 : withAdvisor + withoutAdvisor;
    final pct = loading ? 0 : ((withAdvisor / total) * 100).round();

    return Column(
      children: [
        SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 38,
                  sections: [
                    if (withAdvisor > 0) PieChartSectionData(value: withAdvisor.toDouble(), color: DashTokens.success, showTitle: false, radius: 16),
                    if (withoutAdvisor > 0) PieChartSectionData(value: withoutAdvisor.toDouble(), color: DashTokens.danger, showTitle: false, radius: 16),
                    if (withAdvisor == 0 && withoutAdvisor == 0)
                      PieChartSectionData(value: 1, color: DashTokens.track, showTitle: false, radius: 16),
                  ],
                ),
              ),
              Text(loading ? '...' : '$pct%', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _legendLine('لهم مرشد', withAdvisor, DashTokens.success),
        const SizedBox(height: 4),
        _legendLine('بلا مرشد', withoutAdvisor, DashTokens.danger),
      ],
    );
  }

  Widget _legendLine(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ', style: const TextStyle(fontSize: 11, color: DashTokens.textSecondary)),
        Text('$value', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
