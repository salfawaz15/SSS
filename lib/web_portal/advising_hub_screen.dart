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
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

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
            _HubStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accent: tiles[i].color),
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
            Expanded(child: _HubStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accent: tiles[i].color)),
            if (i < tiles.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsGrid(BuildContext context, {required bool isSuperAdmin}) {
    final tiles = <({IconData icon, String title, String subtitle, Color accent, VoidCallback onTap})>[
      if (isSuperAdmin)
        (
          icon: Icons.fact_check_outlined,
          title: 'متابعة حالات الإرشاد',
          subtitle: 'كشف بيانات الطلبة، النصاب، إعادة التوزيع، والتقارير التفصيلية',
          accent: AppColors.greenDark,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdvisingCasesAdminScreen()),
          ),
        ),
      if (isSuperAdmin)
        (
          icon: Icons.person_search_outlined,
          title: 'بحث عن مرشد وقائمة طلابه',
          subtitle: 'ابحث باسم أو رقم المرشد لعرض كل طلابه دفعة واحدة',
          accent: AppColors.greenDark,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdvisorStudentsLookupScreen()),
          ),
        ),
      (
        icon: Icons.volunteer_activism_outlined,
        title: 'متابعة حالات الظروف الخاصة',
        subtitle: 'متابعة الحالات المسجَّلة ذات الظروف الخاصة',
        accent: AppColors.gold,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.favorite_border,
        title: 'متابعة حالات الدعم النفسي والاجتماعي',
        subtitle: 'متابعة طلبات الدعم النفسي والاجتماعي للطلبة',
        accent: AppColors.green,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen()),
        ),
      ),
      (
        icon: Icons.schedule_outlined,
        title: 'توزيع فترات الإرشاد',
        subtitle: 'جدول فترات الإرشاد الرسمي لكل قسم وشطر',
        accent: AppColors.goldLight,
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
        return _HubActionCard(icon: t.icon, title: t.title, subtitle: t.subtitle, accent: t.accent, onTap: t.onTap);
      },
    );
  }
}

/// بطاقة إحصائية بهوية "لوحة الإدارة" (بطاقة بيضاء + أيقونة بخلفية شفافة
/// 10%) - بدل [PortalStatCard] ذي البلوك اللوني الكامل، الذي لم يعد يطابق
/// الهوية المعتمدة حديثًا. بطلب سليمان الصريح (2026-08-20): هذه الصفحة كانت
/// "مختلفة تمامًا" عن لوحة الإدارة ولوحة الحذف والإضافة.
class _HubStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  const _HubStatCard({required this.icon, required this.value, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
            alignment: Alignment.center,
            child: Icon(icon, size: 23, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.greenDark, height: 1)),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة إجراء بنفس هوية `_ReportCard` (تقارير) و`_KpiCard` (لوحة الإدارة) -
/// بطاقة بيضاء بحدّ رمادي فاتح وأيقونة بخلفية شفافة 10%، بدل البلاطة الملوّنة
/// بالكامل السابقة.
class _HubActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _HubActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.greenDark)),
                    const SizedBox(height: 4),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
