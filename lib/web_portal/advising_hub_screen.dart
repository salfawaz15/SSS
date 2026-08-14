import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/advising_case_analyzer.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'advisor_students_lookup_screen.dart';
import 'hardship_cases_admin_screen.dart';
import 'portal_accounts.dart';
import 'portal_cards.dart';
import 'portal_header.dart';
import 'support_cases_admin_screen.dart';

/// صفحة وسيطة تجمع كل ما يخص الإرشاد بضغطة واحدة من الشريط العلوي - بدل
/// تبويب مستقل لكل قسم (حالات الظروف الخاصة/الدعم النفسي/متابعة الإرشاد) كما
/// كان سابقًا، بطلب سليمان صراحةً (2026-08-07) لتبسيط الشريط العلوي.
/// "متابعة حالات الإرشاد" حصرية لحساب المدير العام (نفس تقييدها الأصلي بلوحة
/// الإدارة) - الظروف الخاصة والدعم النفسي متاحان لكل حسابات الإدارة.
///
/// أُعيد تصميمها (2026-08-08) بطلب سليمان: شريط إحصائيات أفقي أعلى الصفحة
/// (بنفس PortalStatCard المستخدم بلوحة الإدارة) يعرض عدد المرشدين
/// بطلاب/بدونهم وعدد الطلاب بمرشد/بدونه، ثم شبكة إجراءات 2×2 (بنفس
/// PortalActionCard) تضم أهم أربع صفحات إرشاد بدل القائمة الرأسية السابقة.
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
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail;

    return PortalScaffold(
      title: 'لوحة الإرشاد',
      navItems: buildAdminNavItems(context, current: 'advising-hub'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatsBar(context),
                const SizedBox(height: 20),
                _buildActionsGrid(context, isSuperAdmin: isSuperAdmin),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context) {
    final tiles = [
      (
        label: 'مرشدون لديهم طلاب',
        value: _loadingStats ? '...' : '$_advisorsWithStudents',
        icon: Icons.groups_outlined,
        color: AppColors.greenDark,
      ),
      (
        label: 'مرشدون بدون طلاب',
        value: _loadingStats ? '...' : '$_advisorsWithoutStudents',
        icon: Icons.person_off_outlined,
        color: AppColors.gold,
      ),
      (
        label: 'طلاب لهم مرشد',
        value: _loadingStats ? '...' : '$_studentsWithAdvisor',
        icon: Icons.school_outlined,
        color: AppColors.green,
      ),
      (
        label: 'طلاب بلا مرشد',
        value: _loadingStats ? '...' : '$_studentsWithoutAdvisor',
        icon: Icons.person_search_outlined,
        color: Colors.redAccent,
      ),
    ];

    final isNarrow = MediaQuery.of(context).size.width < 700;
    if (isNarrow) {
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            PortalStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accentColor: tiles[i].color),
            if (i < tiles.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            Expanded(child: PortalStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accentColor: tiles[i].color)),
            if (i < tiles.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsGrid(BuildContext context, {required bool isSuperAdmin}) {
    final tiles = <({IconData icon, String title, Color background, VoidCallback onTap})>[
      if (isSuperAdmin)
        (
          icon: Icons.fact_check_outlined,
          title: 'متابعة حالات الإرشاد',
          background: AppColors.greenDark,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdvisingCasesAdminScreen()),
          ),
        ),
      if (isSuperAdmin)
        (
          icon: Icons.person_search_outlined,
          title: 'بحث عن مرشد وقائمة طلابه',
          background: AppColors.greenDark,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdvisorStudentsLookupScreen()),
          ),
        ),
      (
        icon: Icons.volunteer_activism_outlined,
        title: 'متابعة حالات الظروف الخاصة',
        background: AppColors.gold,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.favorite_border,
        title: 'متابعة حالات الدعم النفسي والاجتماعي',
        background: AppColors.green,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.schedule_outlined,
        title: 'توزيع فترات الإرشاد',
        background: AppColors.goldLight,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdvisingScheduleAdminScreen()),
        ),
      ),
    ];

    // Wrap مع توسيط (بدل GridView التي تُلصِق الصفوف الناقصة على جهة واحدة
    // فقط بلا توسيط) - كانت الأيقونات تبدو غير متوسّطة بالصفحة رغم توسيط
    // الحاوية نفسها (سليمان 2026-08-09).
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final t in tiles)
          SizedBox(
            width: 200,
            height: 118,
            child: PortalIconTileCard(
              icon: t.icon,
              title: t.title,
              background: t.background,
              foreground: Colors.white,
              onTap: t.onTap,
            ),
          ),
      ],
    );
  }
}
