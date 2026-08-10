import 'package:flutter/material.dart';

import '../models/course_section_record.dart';
import '../services/course_schedule_repository.dart' show CourseScheduleRepository, Shatr;
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'course_schedule_admin_screen.dart';
import 'portal_cards.dart';
import 'portal_header.dart';

/// صفحة وسيطة تجمع "تسكين المقررات الدراسية" و"الجدول الدراسي" بضغطة واحدة
/// من الشريط العلوي - حصرية لحساب المدير العام (نفس تقييد وصولهما الأصلي
/// بلوحة الإدارة)، بطلب سليمان صراحةً (2026-08-07).
///
/// أُعيد تصميمها (2026-08-09) بنفس قالب لوحة الإرشاد: شريط إحصائيات علوي
/// (`PortalStatCard`) بأرقام فعلية من الجدول الدراسي المرفوع فعليًا لكلا
/// الشطرين، ثم شبكة أيقونات صغيرة (`PortalIconTileCard` - نفس حجم "تسكين
/// المقررات"/"الجدول الدراسي" المعتمد بلوحة الإدارة) بدل بطاقات التدرّج
/// الضخمة السابقة اللي كانت تترك فراغًا أبيض كبيرًا (سليمان). المحتوى محصور
/// بعرض أقصى 900 ومتوسّط بالصفحة بنفس أسلوب صفحتَي المنسّق والإرشاد.
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
                _buildActionsGrid(context),
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
        label: 'عدد مقررات الكلية',
        value: _loadingStats ? '...' : '$_totalCourses',
        icon: Icons.menu_book_outlined,
        color: AppColors.greenDark,
      ),
      (
        label: 'أعضاء هيئة تدريس لديهم شعب',
        value: _loadingStats ? '...' : '$_facultyCount',
        icon: Icons.person_search_outlined,
        color: AppColors.gold,
      ),
      (
        label: 'شعب مسكَّنة',
        value: _loadingStats ? '...' : '$_scheduledSections',
        icon: Icons.event_available_outlined,
        color: AppColors.green,
      ),
      (
        label: 'شعب غير مسكَّنة',
        value: _loadingStats ? '...' : '$_unscheduledSections',
        icon: Icons.event_busy_outlined,
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

  Widget _buildActionsGrid(BuildContext context) {
    final tiles = <({IconData icon, String title, Color background, VoidCallback onTap})>[
      (
        icon: Icons.event_note_outlined,
        title: 'تسكين المقررات الدراسية',
        background: AppColors.greenDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 0, singleTab: true)),
        ),
      ),
      (
        icon: Icons.person_search_outlined,
        title: 'الجدول الدراسي',
        background: AppColors.gold,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 1, singleTab: true)),
        ),
      ),
    ];

    // Wrap مع توسيط (بدل GridView) - نفس إصلاح لوحة الإرشاد (سليمان 2026-08-09).
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
