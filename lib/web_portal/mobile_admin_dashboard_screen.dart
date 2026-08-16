import 'package:flutter/material.dart';

import '../services/advising_case_analyzer.dart';
import '../theme/app_theme.dart';
import 'portal_cards.dart';

/// لوحة الإدارة الجوّالة الأصيلة لحساب المدير العام (`salfawaz`) - **إعادة
/// بناء من الصفر** (2026-08-16، بطلب سليمان: "اعمل ما يكون مناسب بحيث تحتوي
/// كل الصلاحيات") بدل فتح `AdminWorkspaceScreen` العريضة (ثبت فشلها على
/// الجوال سابقًا هذه الجلسة). إحصائيات حية من نفس مصدر `AdvisingHubScreen`
/// بالضبط (`AdvisingCaseAnalyzer`، بلا إعادة حساب أي منطق)، ثم شبكة إجراءات
/// لبقية أقسام الإدارة - كل قسم غير مبني بعد يعرض "قيد التطوير" بدل شاشة
/// الويب العريضة المكسورة.
class MobileAdminDashboardScreen extends StatefulWidget {
  const MobileAdminDashboardScreen({super.key});

  @override
  State<MobileAdminDashboardScreen> createState() => _MobileAdminDashboardScreenState();
}

class _MobileAdminDashboardScreenState extends State<MobileAdminDashboardScreen> {
  bool _loading = true;
  int _advisorsWithStudents = 0;
  int _advisorsWithoutStudents = 0;
  int _studentsWithAdvisor = 0;
  int _studentsWithoutAdvisor = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final loaded = await AdvisingCaseAnalyzer.loadCollegeScopedStudents();
      if (!mounted) return;

      final maleAnalysis = AdvisingCaseAnalyzer.analyze(students: loaded.male, facultyByNameKey: loaded.facultyByKey);
      final femaleAnalysis = AdvisingCaseAnalyzer.analyze(students: loaded.female, facultyByNameKey: loaded.facultyByKey);

      int advisorsWithStudents(AdvisingCaseAnalysis a) => a.quotaReport.length - a.advisorsWithNoStudents.length;
      int studentsWithAdvisor(AdvisingCaseAnalysis a) => a.studentsCorrectlyAssigned.length + a.studentsWithWrongDeptAdvisor.length;

      setState(() {
        _advisorsWithStudents = advisorsWithStudents(maleAnalysis) + advisorsWithStudents(femaleAnalysis);
        _advisorsWithoutStudents = maleAnalysis.advisorsWithNoStudents.length + femaleAnalysis.advisorsWithNoStudents.length;
        _studentsWithAdvisor = studentsWithAdvisor(maleAnalysis) + studentsWithAdvisor(femaleAnalysis);
        _studentsWithoutAdvisor = maleAnalysis.studentsWithoutAdvisor.length + femaleAnalysis.studentsWithoutAdvisor.length;
        _loading = false;
      });
    } catch (_) {
      // لا تُفشِل عرض الصفحة إن تعذّر حساب الإحصائيات (مثلاً قبل رفع أي
      // تقرير) - تبقى الأرقام صفرًا وتختفي مؤشر التحميل فقط.
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label - قيد التطوير، قريبًا بإذن الله')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (
        icon: Icons.groups_outlined,
        label: 'مرشدون لديهم طلاب',
        value: _loading ? '...' : '$_advisorsWithStudents',
        color: AppColors.greenDark,
      ),
      (
        icon: Icons.person_off_outlined,
        label: 'مرشدون بدون طلاب',
        value: _loading ? '...' : '$_advisorsWithoutStudents',
        color: AppColors.gold,
      ),
      (
        icon: Icons.school_outlined,
        label: 'طلاب لهم مرشد',
        value: _loading ? '...' : '$_studentsWithAdvisor',
        color: AppColors.green,
      ),
      (
        icon: Icons.person_search_outlined,
        label: 'طلاب بلا مرشد',
        value: _loading ? '...' : '$_studentsWithoutAdvisor',
        color: Colors.redAccent,
      ),
    ];

    final actions = <({IconData icon, String label, Color color})>[
      (icon: Icons.fact_check_outlined, label: 'لوحة الإرشاد', color: AppColors.gold),
      (icon: Icons.assessment_outlined, label: 'تقارير', color: AppColors.green),
      (icon: Icons.school_outlined, label: 'خدمات أكاديمية', color: AppColors.greenDark),
      (icon: Icons.badge_outlined, label: 'المنسوبين', color: AppColors.goldLight),
      (icon: Icons.groups_2_outlined, label: 'الحسابات وكلمات المرور', color: AppColors.green),
      (icon: Icons.science_outlined, label: 'تجربة الصفحات', color: AppColors.gold),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: AppColors.greenDark,
        foregroundColor: Colors.white,
        title: const Text('لوحة الإدارة'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('إحصائيات سريعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark)),
          const SizedBox(height: 12),
          for (final t in tiles) ...[
            PortalStatCard(icon: t.icon, value: t.value, label: t.label, accentColor: t.color),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          const Text('الأقسام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              for (final a in actions)
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _showComingSoon(a.label),
                    child: Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: a.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: Icon(a.icon, color: a.color, size: 20),
                          ),
                          const Spacer(),
                          Text(a.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
