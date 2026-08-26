import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/hardship_case.dart';
import '../services/advising_case_analyzer.dart';
import '../services/hardship_case_service.dart';
import '../services/support_case_service.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
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
/// **أُعيدت هيكلتها بالكامل (سليمان 2026-08-22)** من صفحة روابط ("الخدمات
/// السريعة" كانت تكرّر شريط التنقّل أعلاها) إلى لقطة تنفيذية حقيقية بأربعة
/// أقسام - وافق سليمان على مسودة تصميم مرئية (Design Canvas) قبل هذا
/// التنفيذ: أرقام ومؤشرات الإرشاد (+ تفريع ذوو الإعاقة) ← تنبيهات تحتاج
/// معالجة ← الحالات والمتابعة ← توزيع عادل بين المرشدين. الأرقام تُحسَب من
/// نفس منطق التحليل المستخدم فعليًا بـ"متابعة حالات الإرشاد"
/// ([AdvisingCaseAnalyzer]) بلا أي حساب جديد.
class AdvisingHubScreen extends StatefulWidget {
  const AdvisingHubScreen({super.key});

  @override
  State<AdvisingHubScreen> createState() => _AdvisingHubScreenState();
}

class _AdvisingHubScreenState extends State<AdvisingHubScreen> {
  bool _loadingStats = true;

  int _totalActiveStudents = 0;
  int _correctlyAssigned = 0;
  int _wrongDeptCount = 0;
  int _withoutAdvisorCount = 0;
  int _totalAdvisors = 0;

  // نفس الأرقام أعلاه مفصَّلة حسب الشطر - لعرض تفصيل صغير تحت كل رقم كبير
  // (بطلب سليمان صراحةً 2026-08-24)، بلا أي تغيير بالمصدر أو حساب الإجمالي.
  int _totalActiveMale = 0;
  int _totalActiveFemale = 0;
  int _correctMale = 0;
  int _correctFemale = 0;
  int _needsCorrectionMale = 0;
  int _needsCorrectionFemale = 0;
  int _advisorsMale = 0;
  int _advisorsFemale = 0;

  int _disabilityCorrect = 0;
  int _disabilityWrong = 0;

  int _externalAdvisorsWithOurStudents = 0;
  int _quotaImbalanceCount = 0;

  int _minLoad = 0;
  int _maxLoad = 0;
  double _avgDeviationPct = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  /// يحسب كل أرقام الأقسام 1/2/4 من نفس مصدر "متابعة حالات الإرشاد"
  /// ([AdvisingCaseAnalyzer.loadCollegeScopedStudents]) - القوائم المفلتَرة
  /// (male/female) لـ[analyze] (المعيار المعتمَد: نفس التخصص فقط)، والقوائم
  /// الخام (allCollegesMaleRaw/FemaleRaw) لـ[classifyAllColleges] (تحتاجها
  /// فقط "مرشدون خارج الكلية").
  Future<void> _loadStats() async {
    try {
      final loaded = await AdvisingCaseAnalyzer.loadCollegeScopedStudents();
      if (!mounted) return;

      final maleAnalysis = AdvisingCaseAnalyzer.analyze(students: loaded.male, facultyByNameKey: loaded.facultyByKey);
      final femaleAnalysis = AdvisingCaseAnalyzer.analyze(students: loaded.female, facultyByNameKey: loaded.facultyByKey);
      final maleClassification = AdvisingCaseAnalyzer.classifyAllColleges(
        academicRecords: loaded.academicMaleRaw,
        allCollegeRecords: loaded.allCollegesMaleRaw,
        allCollegeRecordsPrevious: loaded.allCollegesMalePrevious,
        facultyByNameKey: loaded.facultyByKey,
      );
      final femaleClassification = AdvisingCaseAnalyzer.classifyAllColleges(
        academicRecords: loaded.academicFemaleRaw,
        allCollegeRecords: loaded.allCollegesFemaleRaw,
        allCollegeRecordsPrevious: loaded.allCollegesFemalePrevious,
        facultyByNameKey: loaded.facultyByKey,
      );

      final analyses = [maleAnalysis, femaleAnalysis];
      final quota = [...maleAnalysis.quotaReport, ...femaleAnalysis.quotaReport];
      final loads = quota.map((q) => q.actualCount).toList()..sort();
      final deviations = quota.where((q) => q.fairShare > 0).map((q) => (q.actualCount - q.fairShare).abs() / q.fairShare);
      final avgDeviation = deviations.isEmpty ? 0.0 : deviations.reduce((a, b) => a + b) / deviations.length;

      if (!mounted) return;
      setState(() {
        _totalActiveStudents = analyses.fold(0, (s, a) => s + a.studentsCorrectlyAssigned.length + a.studentsWithWrongDeptAdvisor.length + a.studentsWithoutAdvisor.length);
        _correctlyAssigned = analyses.fold(0, (s, a) => s + a.studentsCorrectlyAssigned.length);
        _wrongDeptCount = analyses.fold(0, (s, a) => s + a.studentsWithWrongDeptAdvisor.length);
        _withoutAdvisorCount = analyses.fold(0, (s, a) => s + a.studentsWithoutAdvisor.length);
        _totalAdvisors = analyses.fold(0, (s, a) => s + a.quotaReport.length);

        _totalActiveMale = maleAnalysis.studentsCorrectlyAssigned.length + maleAnalysis.studentsWithWrongDeptAdvisor.length + maleAnalysis.studentsWithoutAdvisor.length;
        _totalActiveFemale = femaleAnalysis.studentsCorrectlyAssigned.length + femaleAnalysis.studentsWithWrongDeptAdvisor.length + femaleAnalysis.studentsWithoutAdvisor.length;
        _correctMale = maleAnalysis.studentsCorrectlyAssigned.length;
        _correctFemale = femaleAnalysis.studentsCorrectlyAssigned.length;
        _needsCorrectionMale = maleAnalysis.studentsWithWrongDeptAdvisor.length + maleAnalysis.studentsWithoutAdvisor.length;
        _needsCorrectionFemale = femaleAnalysis.studentsWithWrongDeptAdvisor.length + femaleAnalysis.studentsWithoutAdvisor.length;
        _advisorsMale = maleAnalysis.quotaReport.length;
        _advisorsFemale = femaleAnalysis.quotaReport.length;

        _disabilityCorrect = analyses.fold(0, (s, a) => s + a.studentsCorrectlyAssigned.where((r) => r.hasHealthCondition).length);
        _disabilityWrong = analyses.fold(
          0,
          (s, a) =>
              s +
              a.studentsWithWrongDeptAdvisor.where((m) => m.student.hasHealthCondition).length +
              a.studentsWithoutAdvisor.where((r) => r.hasHealthCondition).length,
        );

        _externalAdvisorsWithOurStudents = maleClassification.externalAdvisorsWithOurStudents.length + femaleClassification.externalAdvisorsWithOurStudents.length;
        _quotaImbalanceCount = quota.where((q) => q.status != QuotaStatus.balanced).length;

        _minLoad = loads.isEmpty ? 0 : loads.first;
        _maxLoad = loads.isEmpty ? 0 : loads.last;
        _avgDeviationPct = avgDeviation * 100;

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
                          description: 'لقطة تنفيذية مختصرة لحالة منظومة الإرشاد الأكاديمي الآن',
                          icon: Icons.query_stats_outlined,
                        ),
                        const SizedBox(height: 16),
                        const DashSectionHeader(title: 'أرقام ومؤشرات الإرشاد', icon: Icons.bar_chart_outlined),
                        const SizedBox(height: 10),
                        _buildMetricsGrid(context),
                        const SizedBox(height: 6),
                        _buildDisabilitySubBranch(context),
                        const SizedBox(height: 18),
                        const DashSectionHeader(title: 'تنبيهات تحتاج معالجة', icon: Icons.warning_amber_rounded),
                        const SizedBox(height: 10),
                        _buildAlerts(context),
                        const SizedBox(height: 18),
                        const DashSectionHeader(title: 'الحالات والمتابعة', icon: Icons.fact_check_outlined),
                        const SizedBox(height: 10),
                        _buildCasesSummary(context),
                        const SizedBox(height: 18),
                        const DashSectionHeader(title: 'توزيع عادل بين المرشدين', icon: Icons.groups_outlined),
                        const SizedBox(height: 10),
                        _buildFairDistribution(context),
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
    // floor لا round - سليمان 2026-08-22: "8739 من أصل 8742" (99.97%) كانت
    // تظهر 100% بالتقريب العادي رغم وجود 3 حالات فعليًا غير مكتملة، وهذا
    // مضلِّل. floor يضمن ألا تظهر 100% إلا عند الاكتمال الحقيقي التام. يُحسَب
    // الآن لمنزلة عشرية واحدة لا رقمًا صحيحًا (سليمان 2026-08-26): بأعداد
    // كبيرة (آلاف الطلبة) فرق بسيط كـ6 طلاب بلا مرشد كان يُسقِط النسبة من
    // "99.9%" إلى "99%" بالتقريب الصحيح - فرق ضخم بصريًا لمشكلة صغيرة فعليًا.
    String coverageLabel(int correct, int total) {
      if (total == 0) return '100';
      final pct = (correct / total * 100 * 10).floor() / 10;
      return pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    }

    final coveragePctLabel = coverageLabel(_correctlyAssigned, _totalActiveStudents);
    final isFullCoverage = _totalActiveStudents > 0 && _correctlyAssigned == _totalActiveStudents;
    final needsCorrection = _wrongDeptCount + _withoutAdvisorCount;
    final needsCorrectionMale = _needsCorrectionMale;
    final needsCorrectionFemale = _needsCorrectionFemale;
    final coveragePctMaleLabel = coverageLabel(_correctMale, _totalActiveMale);
    final coveragePctFemaleLabel = coverageLabel(_correctFemale, _totalActiveFemale);

    // تفصيل صغير (طلاب - طالبات) تحت كل رقم كبير بالشبكة - بطلب سليمان
    // صراحةً 2026-08-24، يُطبَّق على كل البطاقات لا "إجمالي الطلبة" فقط.
    String breakdownOf(int male, int female) => '$male طلاب - $female طالبات';

    final tiles = [
      (
        label: 'إجمالي الطلبة',
        value: _loadingStats ? '...' : '$_totalActiveStudents',
        breakdown: _loadingStats ? null : breakdownOf(_totalActiveMale, _totalActiveFemale),
        note: 'الطلبة النشطون فقط (بلا مفصولين)',
        icon: Icons.groups_outlined,
        color: DashTokens.green900,
      ),
      (
        label: 'لديهم مرشد صحيح',
        value: _loadingStats ? '...' : '$_correctlyAssigned',
        breakdown: _loadingStats ? null : breakdownOf(_correctMale, _correctFemale),
        note: 'من نفس تخصصهم العلمي',
        icon: Icons.verified_outlined,
        color: DashTokens.success,
      ),
      (
        label: 'تحتاج تصحيح إسناد',
        value: _loadingStats ? '...' : '$needsCorrection',
        breakdown: _loadingStats ? null : breakdownOf(needsCorrectionMale, needsCorrectionFemale),
        note: 'على غير مرشدهم / بلا مرشد',
        icon: Icons.error_outline,
        color: (_loadingStats || needsCorrection == 0) ? DashTokens.success : DashTokens.danger,
      ),
      (
        label: 'إجمالي المرشدين',
        value: _loadingStats ? '...' : '$_totalAdvisors',
        breakdown: _loadingStats ? null : breakdownOf(_advisorsMale, _advisorsFemale),
        note: 'مرشدًا أكاديميًا فعّالًا',
        icon: Icons.school_outlined,
        color: DashTokens.gold600,
      ),
      (
        label: 'نسبة التغطية الإرشادية',
        value: _loadingStats ? '...' : '$coveragePctLabel%',
        breakdown: _loadingStats ? null : 'طلاب $coveragePctMaleLabel% - طالبات $coveragePctFemaleLabel%',
        note: '$_correctlyAssigned من أصل $_totalActiveStudents',
        icon: Icons.donut_large_outlined,
        color: (_loadingStats || isFullCoverage) ? DashTokens.success : DashTokens.gold600,
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
            // 119 لا 115 - كانت البطاقات تُظهر "BOTTOM OVERFLOWED BY 1.00
            // PIXELS" فعليًا (تأكَّد حيًّا) لأن ارتفاع الخلية كان أضيق بكسل
            // واحد من محتوى AdvisingMetricCard الفعلي (سليمان 2026-08-22).
            // 136 بعد إضافة سطر التفصيل (طلاب/طالبات) تحت الرقم الكبير -
            // نفس فارق الـ17 بكسل المضاف لـ`minHeight` بالبطاقة نفسها.
            mainAxisExtent: 136,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, i) {
            final t = tiles[i];
            return AdvisingMetricCard(label: t.label, value: t.value, breakdown: t.breakdown, note: t.note, icon: t.icon, accent: t.color);
          },
        );
      },
    );
  }

  /// تفريع ذوو الإعاقة - تصنيف فرعي ضمن نفس إجمالي الطلبة أعلاه (سليمان
  /// 2026-08-22: "منطقيًا طلبة ذوي الإعاقة هم من الطلبة، إجمالي الطلبة")،
  /// لا فئة موازية مستقلة. يعتمد على عمود "الحالة الصحية" بتقرير بيانات
  /// الطلبة الأكاديمية ([AdvisingCaseRecord.hasHealthCondition]).
  Widget _buildDisabilitySubBranch(BuildContext context) {
    Widget miniCard(String label, int value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: DashTokens.cardBg,
            border: Border.all(color: const Color(0xFFC9CFCC)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: DashTokens.textSecondary))),
              Text(_loadingStats ? '...' : '$value', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessible_outlined, size: 13, color: DashTokens.textMuted),
              const SizedBox(width: 6),
              Text('تفريع: ذوو الإعاقة (ضمن إجمالي الطلبة أعلاه)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: DashTokens.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              miniCard('طلبة إعاقة لديهم مرشد صحيح', _disabilityCorrect, DashTokens.success),
              const SizedBox(width: 12),
              miniCard('طلبة إعاقة على غير مرشدهم', _disabilityWrong, DashTokens.danger),
              const Spacer(flex: 3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlerts(BuildContext context) {
    final items = [
      (label: 'طلاب على غير مرشدهم', value: _wrongDeptCount, critical: true),
      (label: 'طلاب بلا مرشد', value: _withoutAdvisorCount, critical: true),
      (label: 'مرشدون خارج الكلية لهم طلبتنا', value: _externalAdvisorsWithOurStudents, critical: false),
      (label: 'مرشدون خارج التوازن العادل', value: _quotaImbalanceCount, critical: false),
    ];

    return Container(
      decoration: BoxDecoration(color: DashTokens.cardBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _alertRow(items[i].label, items[i].value, items[i].critical),
            if (i != items.length - 1) Container(height: 1, color: DashTokens.border, margin: const EdgeInsets.symmetric(vertical: 2)),
          ],
        ],
      ),
    );
  }

  Widget _alertRow(String label, int value, bool critical) {
    final isZero = value == 0;
    final bg = isZero ? Colors.transparent : (critical ? DashTokens.dangerSoft : DashTokens.warningSoft);
    final valueColor = isZero ? const Color(0xFFB7BEBB) : (critical ? DashTokens.danger : const Color(0xFF8A6A0E));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: isZero ? 8 : 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isZero ? 12 : 13, fontWeight: isZero ? FontWeight.w400 : FontWeight.w600, color: isZero ? const Color(0xFFB7BEBB) : DashTokens.textPrimary)),
          Text(_loadingStats ? '...' : '$value', style: TextStyle(fontSize: isZero ? 13 : 16, fontWeight: FontWeight.w700, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildCasesSummary(BuildContext context) {
    return StreamBuilder<List<HardshipCase>>(
      stream: HardshipCaseService.watchAllCases(),
      builder: (context, hardshipSnap) {
        return StreamBuilder<List<HardshipCase>>(
          stream: SupportCaseService.watchAllCases(),
          builder: (context, supportSnap) {
            final hardship = hardshipSnap.data ?? const <HardshipCase>[];
            final support = supportSnap.data ?? const <HardshipCase>[];
            final hardshipNeedsFollowUp = hardship.where((c) => c.status == HardshipStatus.needsOngoingFollowUp).length;
            final supportNew = support.where((c) => c.status == HardshipStatus.newCase).length;
            final supportNeedsFollowUp = support.where((c) => c.status == HardshipStatus.needsOngoingFollowUp).length;

            return LayoutBuilder(builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final cards = [
                _CaseSummaryCard(
                  icon: Icons.volunteer_activism_outlined,
                  iconColor: DashTokens.gold600,
                  title: 'الظروف الخاصة',
                  stats: [(value: '${hardship.length}', label: 'إجمالي الحالات', color: DashTokens.textPrimary), (value: '$hardshipNeedsFollowUp', label: 'تحتاج متابعة', color: DashTokens.danger)],
                  onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen())),
                ),
                _CaseSummaryCard(
                  icon: Icons.favorite_border,
                  iconColor: DashTokens.success,
                  title: 'الدعم النفسي والاجتماعي',
                  stats: [
                    (value: '${support.length}', label: 'إجمالي الحالات', color: DashTokens.textPrimary),
                    (value: '$supportNew', label: 'جديدة', color: const Color(0xFF8A6A0E)),
                    (value: '$supportNeedsFollowUp', label: 'متابعة مستمرة', color: DashTokens.danger),
                  ],
                  onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen())),
                ),
              ];
              if (isNarrow) return Column(children: [cards[0], const SizedBox(height: 12), cards[1]]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[0]), const SizedBox(width: 14), Expanded(child: cards[1])]);
            });
          },
        );
      },
    );
  }

  Widget _buildFairDistribution(BuildContext context) {
    final deviation = _avgDeviationPct.round();
    final isBalanced = deviation <= 20;
    return Container(
      decoration: BoxDecoration(color: DashTokens.cardBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: LayoutBuilder(builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final children = [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('نطاق عدد الطلبة لكل مرشد', style: TextStyle(fontSize: 11.5, color: DashTokens.textSecondary)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(_loadingStats ? '...' : '$_minLoad', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                  const Text('  —  ', style: TextStyle(fontSize: 12, color: DashTokens.textMuted)),
                  Text(_loadingStats ? '...' : '$_maxLoad', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                  const SizedBox(width: 6),
                  const Text('طالبًا', style: TextStyle(fontSize: 11.5, color: DashTokens.textMuted)),
                ],
              ),
            ],
          ),
          Container(width: isNarrow ? double.infinity : 1, height: isNarrow ? 1 : 40, color: DashTokens.border, margin: isNarrow ? const EdgeInsets.symmetric(vertical: 14) : const EdgeInsets.symmetric(horizontal: 32)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الانحراف عن المتوسط العادل', style: TextStyle(fontSize: 11.5, color: DashTokens.textSecondary)),
                    Text(_loadingStats ? '...' : '$deviation%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isBalanced ? const Color(0xFF8A6A0E) : DashTokens.danger)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(children: [
                    Container(height: 6, color: DashTokens.track),
                    FractionallySizedBox(widthFactor: (deviation / 100).clamp(0.0, 1.0), child: Container(height: 6, color: isBalanced ? DashTokens.gold600 : DashTokens.danger)),
                  ]),
                ),
              ],
            ),
          ),
          if (isNarrow) const SizedBox(height: 14) else const SizedBox(width: 32),
        ];
        // نص لا Expanded - يُستخدَم Container بلا ارتفاع ثابت داخل
        // SingleChildScrollView (ارتفاع غير مُقيَّد)، وExpanded داخل Column
        // بارتفاع غير مُقيَّد يرمي استثناء "incoming height constraints are
        // unbounded" حقيقيًا (تأكَّد حيًّا عبر فحص متصفح فعلي على عرض 390px -
        // سليمان 2026-08-22: كان يُسقط رسم لوحة الإرشاد بالكامل على الجوال).
        // Column(stretch) يمدّد النص بعرض كامل دون الحاجة لـExpanded أصلًا.
        final noteText = Text(
          isBalanced
              ? 'التوزيع ضمن نطاق مقبول حاليًا؛ لا توجد حالة تركّز حالات على مرشد واحد تستدعي تدخلًا فوريًا.'
              : 'التوزيع يتجاوز النطاق المقبول - يُنصَح بمراجعة تقرير النصاب لمعرفة المرشدين الأكثر انحرافًا.',
          style: const TextStyle(fontSize: 11.5, color: DashTokens.textSecondary, height: 1.7),
        );
        if (isNarrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...children, noteText]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [...children, Expanded(child: noteText)]);
      }),
    );
  }
}

/// بطاقة ملخّص حالات قابلة للنقر (الظروف الخاصة/الدعم النفسي) - بلا أي
/// أسماء طلبة، أرقام إجمالية فقط (سليمان 2026-08-22: "لا تُعرض أسماء الطلبة
/// بنظرة عامة").
class _CaseSummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<({String value, String label, Color color})> stats;
  final VoidCallback onTap;

  const _CaseSummaryCard({required this.icon, required this.iconColor, required this.title, required this.stats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DashTokens.cardBg,
      borderRadius: BorderRadius.circular(DashTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DashTokens.textPrimary))),
                  const Icon(Icons.north_east, size: 15, color: DashTokens.textMuted),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final s in stats) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: s.color, height: 1)),
                        const SizedBox(height: 4),
                        Text(s.label, style: const TextStyle(fontSize: 11, color: DashTokens.textMuted)),
                      ],
                    ),
                    if (s != stats.last) const SizedBox(width: 28),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
