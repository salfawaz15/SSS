import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/advising_case_analyzer.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'advising_workspace.dart';
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
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.overview, isSuperAdmin: isSuperAdmin),
          Expanded(
            child: Container(
              color: DashTokens.pageBg,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AdvisingPageHeader(
                          breadcrumbTrail: 'نظرة عامة',
                          title: 'نظرة عامة على الإرشاد',
                          description: 'أرقام حيّة من آخر بيانات إرشاد مرفوعة والخدمات السريعة لكل شاشات الإرشاد',
                          icon: Icons.query_stats_outlined,
                        ),
                        const SizedBox(height: 20),
                        const DashSectionHeader(title: 'أرقام ومؤشرات الإرشاد', icon: Icons.bar_chart_outlined),
                        const SizedBox(height: 12),
                        _buildMetricsGrid(context),
                        const SizedBox(height: 28),
                        const DashSectionHeader(title: 'الخدمات السريعة', icon: Icons.dashboard_customize_outlined),
                        const SizedBox(height: 12),
                        _buildActionsGrid(context, isSuperAdmin: isSuperAdmin),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context) {
    final total = _studentsWithAdvisor + _studentsWithoutAdvisor;
    final coveragePct = total == 0 ? 100 : ((_studentsWithAdvisor / total) * 100).round();

    final tiles = [
      (
        label: 'مرشدون لديهم طلبة',
        value: _loadingStats ? '...' : '$_advisorsWithStudents',
        note: 'من إجمالي المرشدين',
        icon: Icons.groups_outlined,
        color: DashTokens.green900,
      ),
      (
        label: 'مرشدون دون طلبة',
        value: _loadingStats ? '...' : '$_advisorsWithoutStudents',
        note: 'معفَون أو بلا حالات',
        icon: Icons.person_off_outlined,
        color: DashTokens.gold600,
      ),
      (
        label: 'الطلبة لديهم مرشد',
        value: _loadingStats ? '...' : '$_studentsWithAdvisor',
        note: 'من إجمالي الطلبة',
        icon: Icons.school_outlined,
        color: DashTokens.success,
      ),
      (
        label: 'طلبة بلا مرشد',
        value: _loadingStats ? '...' : '$_studentsWithoutAdvisor',
        note: _studentsWithoutAdvisor > 0 ? 'يحتاجون تسكينًا' : 'لا يوجد حاليًا',
        icon: Icons.person_search_outlined,
        color: (_loadingStats || _studentsWithoutAdvisor == 0) ? DashTokens.success : DashTokens.danger,
      ),
      (
        label: 'التغطية الإرشادية',
        value: _loadingStats ? '...' : '$coveragePct%',
        note: '$_studentsWithAdvisor لديهم مرشد',
        icon: Icons.donut_large_outlined,
        color: (_loadingStats || coveragePct >= 100) ? DashTokens.success : DashTokens.gold600,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 1200 ? 5 : (w >= 800 ? 3 : (w >= 520 ? 2 : 1));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 115,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, i) {
            final t = tiles[i];
            return AdvisingMetricCard(label: t.label, value: t.value, note: t.note, icon: t.icon, accent: t.color);
          },
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
          onTap: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdvisingCasesAdminScreen()),
          ),
        ),
      if (isSuperAdmin)
        (
          icon: Icons.person_search_outlined,
          title: 'بحث عن مرشد وقائمة طلابه',
          subtitle: 'ابحث باسم أو رقم المرشد لعرض كل طلابه دفعة واحدة',
          accent: DashTokens.green900,
          onTap: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdvisorStudentsLookupScreen()),
          ),
        ),
      (
        icon: Icons.volunteer_activism_outlined,
        title: 'متابعة حالات الظروف الخاصة',
        subtitle: 'متابعة الحالات المسجَّلة ذات الظروف الخاصة',
        accent: DashTokens.gold600,
        onTap: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.favorite_border,
        title: 'متابعة حالات الدعم النفسي والاجتماعي',
        subtitle: 'متابعة طلبات الدعم النفسي والاجتماعي للطلبة',
        accent: DashTokens.success,
        onTap: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.schedule_outlined,
        title: 'توزيع فترات الإرشاد',
        subtitle: 'جدول فترات الإرشاد الرسمي لكل قسم وشطر',
        accent: DashTokens.gold500,
        onTap: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdvisingScheduleAdminScreen()),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 1350 ? tiles.length : (w >= 850 ? 3 : (w >= 520 ? 2 : 1));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 108,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, i) {
            final t = tiles[i];
            return DashActionCard(icon: t.icon, title: t.title, subtitle: t.subtitle, accent: t.accent, onTap: t.onTap);
          },
        );
      },
    );
  }
}
