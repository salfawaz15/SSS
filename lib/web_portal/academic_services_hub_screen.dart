import 'package:flutter/material.dart';

import '../data/faculty_sort_order.dart';
import '../models/college_roster_member.dart';
import '../models/course_section_record.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_repository.dart' show CourseScheduleRepository, Shatr;
import '../theme/dashboard_tokens.dart';
import '../theme/filter_pills.dart';
import '../utils/name_display.dart';
import 'admin_nav.dart';
import 'course_schedule_admin_screen.dart';
import 'portal_header.dart';

/// صفحة وسيطة تجمع "تسكين المقررات الدراسية" و"الجدول الدراسي" بضغطة واحدة
/// من الشريط العلوي - حصرية لحساب المدير العام (نفس تقييد وصولهما الأصلي
/// بلوحة الإدارة)، بطلب سليمان صراحةً (2026-08-07).
///
/// أُعيد تصميمها (2026-08-20) بهوية `DashTokens` الموحَّدة (المستخرجة من لوحة
/// "الحذف والإضافة") - نفس قالب لوحة الإرشاد: شريط KPI بشريط أعلى ملوَّن +
/// بطاقات إجراء بيضاء، بدل البلاطات الملوَّنة السابقة.
class AcademicServicesHubScreen extends StatefulWidget {
  const AcademicServicesHubScreen({super.key});

  @override
  State<AcademicServicesHubScreen> createState() => _AcademicServicesHubScreenState();
}

class _AcademicServicesHubScreenState extends State<AcademicServicesHubScreen> {
  bool _loadingStats = true;
  int _totalCourses = 0;
  int _facultyCount = 0;
  int _scheduledSections = 0;
  int _unscheduledSections = 0;
  List<CourseSectionRecord> _unscheduledList = const [];
  List<CourseSectionRecord> _maleRecords = const [];
  List<CourseSectionRecord> _femaleRecords = const [];
  Map<String, CollegeRosterMember> _rosterByName = const {};

  // فلتر "أعلى الأعباء التدريسية" - شطر/قسم/الكل (سليمان 2026-08-23)، بنفس
  // هوية الفلاتر الموحَّدة لكل الموقع [FilterResetChip]/[FilterPillDropdown].
  Shatr? _shatrFilter;
  String? _deptFilter;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final results = await Future.wait([
        CourseScheduleRepository.loadSchedule(Shatr.male),
        CourseScheduleRepository.loadSchedule(Shatr.female),
        CollegeRosterRepository.load(),
      ]);
      if (!mounted) return;

      final maleRecords = results[0] as List<CourseSectionRecord>;
      final femaleRecords = results[1] as List<CourseSectionRecord>;
      final roster = results[2] as List<CollegeRosterMember>;
      final rosterByName = {
        for (final m in roster) _normalizeNameKey(displayName(m.name)): m,
      };

      final all = <CourseSectionRecord>[...maleRecords, ...femaleRecords];
      final facultyNames = <String>{
        for (final r in all) ...[
          if ((r.instructorName ?? '').trim().isNotEmpty) r.instructorName!.trim(),
          if ((r.practicalInstructorName ?? '').trim().isNotEmpty) r.practicalInstructorName!.trim(),
        ],
      };
      final courseCodes = <String>{for (final r in all) r.courseCode};
      // "شعبة مسكَّنة" = أُسنِد لها عضو هيئة تدريس فعليًا (نظري أو عملي) -
      // "تسكين" هنا يعني إسناد محاضر للشعبة، لا وجود موعد بالجدول (الموعد
      // موجود أصلاً بملف الحويّة المستورَد لكل الشعب بلا استثناء، فكان
      // الاعتماد عليه يُظهر صفرًا دائمًا لعدد الشعب غير المسكَّنة رغم وجود
      // شعب فعلية بلا محاضر - سليمان 2026-08-09).
      final scheduled = all.where((r) => (r.instructorName ?? '').trim().isNotEmpty).length;
      final unscheduled = all.where((r) => (r.instructorName ?? '').trim().isEmpty).toList()
        ..sort((a, b) => a.courseCode.compareTo(b.courseCode));

      setState(() {
        _totalCourses = courseCodes.length;
        _facultyCount = facultyNames.length;
        _scheduledSections = scheduled;
        _unscheduledSections = all.length - scheduled;
        _unscheduledList = unscheduled;
        _maleRecords = maleRecords;
        _femaleRecords = femaleRecords;
        _rosterByName = rosterByName;
        _loadingStats = false;
      });
    } catch (_) {
      // لا تُفشِل عرض الصفحة إن تعذّر حساب الإحصائيات (مثلاً قبل رفع أي
      // جدول دراسي بعد) - تبقى الأرقام صفرًا وتختفي مؤشر التحميل فقط.
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // نفس منطق تطبيع الاسم المعتمَد بـ`course_schedule_admin_screen.dart`
  // (`_rosterFor`) لمطابقة اختلافات الهمزة/التاء المربوطة بين ملف منسوبي
  // الكلية وملف الجدول الدراسي.
  String _normalizeNameKey(String s) => s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه');

  String _departmentFor(String instructorName) {
    final m = _rosterByName[_normalizeNameKey(displayName(instructorName))];
    final dept = m?.department ?? '';
    return dept.trim().isEmpty ? '' : FacultySortOrder.displayDepartment(dept);
  }

  List<String> get _departmentOptions {
    final set = <String>{
      for (final m in _rosterByName.values)
        if (m.department.trim().isNotEmpty) FacultySortOrder.displayDepartment(m.department),
    };
    final list = set.toList()..sort((a, b) => FacultySortOrder.departmentRank(a).compareTo(FacultySortOrder.departmentRank(b)));
    return list;
  }

  List<({String name, int count})> _computeTopLoad() {
    final records = switch (_shatrFilter) {
      Shatr.male => _maleRecords,
      Shatr.female => _femaleRecords,
      null => <CourseSectionRecord>[..._maleRecords, ..._femaleRecords],
    };
    final counts = <String, int>{};
    for (final r in records) {
      for (final name in [r.instructorName, r.practicalInstructorName]) {
        final n = (name ?? '').trim();
        if (n.isEmpty) continue;
        if (_deptFilter != null && _departmentFor(n) != _deptFilter) continue;
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final list = counts.entries.map((e) => (name: e.key, count: e.value)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'خدمات أكاديمية',
      navItems: buildAdminNavItems(context, current: 'academic-services'),
      body: Container(
        color: DashTokens.pageBg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DashSectionHeader(
                    title: 'نظرة عامة على الخدمات الأكاديمية',
                    subtitle: 'أرقام حيّة من آخر جدول دراسي مرفوع',
                    icon: Icons.query_stats_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildStatsBar(context),
                  const SizedBox(height: 20),
                  const DashSectionHeader(title: 'شعب تحتاج تسكين', icon: Icons.event_busy_outlined),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final unscheduled = _buildUnscheduledList(context);
                    final topLoad = _buildTopLoadFaculty(context, _computeTopLoad());
                    final topLoadHeader = Row(
                      children: [
                        const Expanded(child: DashSectionHeader(title: 'أعلى الأعباء التدريسية', icon: Icons.leaderboard_outlined)),
                        FilterBarShell(children: [
                          FilterResetChip(
                            active: _shatrFilter == null && _deptFilter == null,
                            onTap: () => setState(() {
                              _shatrFilter = null;
                              _deptFilter = null;
                            }),
                          ),
                          FilterPillDropdown<Shatr>(
                            label: 'الشطر',
                            value: _shatrFilter,
                            items: const [Shatr.male, Shatr.female],
                            itemLabel: (s) => s == Shatr.male ? 'شطر الطلاب' : 'شطر الطالبات',
                            onChanged: (v) => setState(() => _shatrFilter = v),
                          ),
                          FilterPillDropdown<String>(
                            label: 'القسم',
                            value: _deptFilter,
                            items: _departmentOptions,
                            itemLabel: (d) => d,
                            onChanged: (v) => setState(() => _deptFilter = v),
                          ),
                        ]),
                      ],
                    );
                    if (constraints.maxWidth < 900) {
                      return Column(children: [unscheduled, const SizedBox(height: 20), topLoadHeader, const SizedBox(height: 12), topLoad]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: unscheduled),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              topLoadHeader,
                              const SizedBox(height: 12),
                              topLoad,
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 20),
                  const DashSectionHeader(title: 'الخدمات السريعة', icon: Icons.dashboard_customize_outlined),
                  const SizedBox(height: 12),
                  _buildActionsGrid(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context) {
    final tiles = [
      (
        label: 'عدد مقررات الكلية',
        value: _loadingStats ? '...' : '$_totalCourses',
        note: 'مقررًا مسجَّلًا',
        icon: Icons.menu_book_outlined,
        color: DashTokens.green900,
      ),
      (
        label: 'أعضاء هيئة تدريس لديهم شعب',
        value: _loadingStats ? '...' : '$_facultyCount',
        note: 'عضو هيئة تدريس',
        icon: Icons.person_search_outlined,
        color: DashTokens.gold600,
      ),
      (
        label: 'شعب مسكَّنة',
        value: _loadingStats ? '...' : '$_scheduledSections',
        note: 'أُسنِد لها محاضر',
        icon: Icons.event_available_outlined,
        color: DashTokens.success,
      ),
      (
        label: 'شعب غير مسكَّنة',
        value: _loadingStats ? '...' : '$_unscheduledSections',
        note: 'بلا محاضر بعد',
        icon: Icons.event_busy_outlined,
        color: DashTokens.danger,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 92,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, i) {
        final t = tiles[i];
        return DashKpiCard(label: t.label, value: t.value, note: t.note, icon: t.icon, accent: t.color);
      },
    );
  }

  /// قائمة إجراء فعلية بدل حشو بصري فارغ (سليمان 2026-08-23: "فراغات بيضاء
  /// كبيرة رغم أهمية الصفحة") - تعرض أول 8 شعب بلا محاضر لتوجيه الانتباه
  /// مباشرة لما يحتاج عملًا، مع رابط لعرض الكل بصفحة التسكين الفعلية.
  Widget _buildUnscheduledList(BuildContext context) {
    if (_loadingStats) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
    }
    if (_unscheduledList.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: DashTokens.cardBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: DashTokens.success, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('لا توجد شعب متبقية بلا محاضر - كل الشعب مسكَّنة', style: TextStyle(fontSize: 13, color: DashTokens.textPrimary))),
          ],
        ),
      );
    }
    const previewCount = 8;
    final preview = _unscheduledList.take(previewCount).toList();
    final remaining = _unscheduledList.length - preview.length;

    return Container(
      decoration: BoxDecoration(color: DashTokens.cardBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < preview.length; i++) ...[
            _unscheduledRow(preview[i]),
            if (i != preview.length - 1) Container(height: 1, color: DashTokens.border, margin: const EdgeInsets.symmetric(vertical: 2)),
          ],
          Container(height: 1, color: DashTokens.border, margin: const EdgeInsets.symmetric(vertical: 2)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 0, singleTab: true)),
              ),
              icon: const Icon(Icons.arrow_left, size: 18),
              label: Text(remaining > 0 ? 'عرض الكل ($remaining أخرى)' : 'الذهاب لصفحة التسكين'),
              style: TextButton.styleFrom(foregroundColor: DashTokens.green900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unscheduledRow(CourseSectionRecord r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('شعبة ${r.theorySection}', style: const TextStyle(fontSize: 12, color: DashTokens.textSecondary)),
          Expanded(
            child: Text(
              '${r.courseName} (${r.courseCode})',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DashTokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// أعلى 5 أعضاء هيئة تدريس عبئًا (عدد الشعب المُسنَدة لهم نظريًا/عمليًا) -
  /// محتوى ثانٍ فعلي يملأ الفراغ الجانبي بجانب "شعب تحتاج تسكين" على
  /// الشاشات الواسعة (سليمان 2026-08-23: فراغات بيضاء كبيرة رغم أهمية
  /// الصفحة)، بنفس هوية القائمة (بلا بطاقة KPI جديدة أو تصميم منفصل).
  Widget _buildTopLoadFaculty(BuildContext context, List<({String name, int count})> topLoad) {
    if (_loadingStats) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
    }
    if (topLoad.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: DashTokens.cardBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: const Text('لا توجد بيانات مطابقة لهذا الفلتر', style: TextStyle(fontSize: 13, color: DashTokens.textSecondary)),
      );
    }
    return Container(
      decoration: BoxDecoration(color: DashTokens.cardBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(DashTokens.radiusLg)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < topLoad.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${topLoad[i].count} شعبة', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DashTokens.gold600)),
                  Expanded(
                    child: Text(
                      topLoad[i].name,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DashTokens.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            if (i != topLoad.length - 1) Container(height: 1, color: DashTokens.border, margin: const EdgeInsets.symmetric(vertical: 2)),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsGrid(BuildContext context) {
    final tiles = <({IconData icon, String title, String subtitle, Color accent, VoidCallback onTap})>[
      (
        icon: Icons.event_note_outlined,
        title: 'تسكين المقررات الدراسية',
        subtitle: 'تسكين شعب المقررات على المحاضرين وأوقات الحويّة',
        accent: DashTokens.green900,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 0, singleTab: true)),
        ),
      ),
      (
        icon: Icons.person_search_outlined,
        title: 'الجدول الدراسي',
        subtitle: 'عرض الجدول الدراسي الكامل حسب المحاضر أو الشعبة',
        accent: DashTokens.gold600,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 1, singleTab: true)),
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
