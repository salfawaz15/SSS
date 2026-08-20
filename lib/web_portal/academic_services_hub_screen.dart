import 'package:flutter/material.dart';

import '../models/course_section_record.dart';
import '../services/course_schedule_repository.dart' show CourseScheduleRepository, Shatr;
import '../theme/dashboard_tokens.dart';
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
      ]);
      if (!mounted) return;

      final all = <CourseSectionRecord>[...results[0], ...results[1]];
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

      setState(() {
        _totalCourses = courseCodes.length;
        _facultyCount = facultyNames.length;
        _scheduledSections = scheduled;
        _unscheduledSections = all.length - scheduled;
        _loadingStats = false;
      });
    } catch (_) {
      // لا تُفشِل عرض الصفحة إن تعذّر حساب الإحصائيات (مثلاً قبل رفع أي
      // جدول دراسي بعد) - تبقى الأرقام صفرًا وتختفي مؤشر التحميل فقط.
      if (mounted) setState(() => _loadingStats = false);
    }
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
              constraints: const BoxConstraints(maxWidth: 1400),
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
