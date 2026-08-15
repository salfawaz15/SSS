import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/hardship_case_service.dart';
import '../services/support_case_service.dart';
import '../theme/app_theme.dart';
import 'portal_header.dart';
import 'track_case_list_view.dart';

const _trackLabels = <String, String>{
  'academic_advising': 'الإرشاد الأكاديمي',
  'student_care': 'الرعاية الطلابية',
  'data_quality': 'البيانات والجودة والتطوير',
  'graduates': 'الخريجين',
  'gifted': 'الموهوبين والتفوق الأكاديمي',
};

/// شاشة عمل عامة واحدة لكل "منسّقي المسارات النوعية" - قابلة لإعادة
/// الاستخدام لأي مسار حالي أو مستقبلي (المرحلة 3 من إعادة هيكلة الدخول
/// والصلاحيات، 2026-08-15، بطلب سليمان: "صفحة واحدة عامة بدل صفحة لكل
/// مسار"). "الرعاية الطلابية" وحدها فعّالة وظيفيًا الآن (حالات الظروف
/// الخاصة والدعم النفسي والاجتماعي عبر كل الأقسام - منقولتان من صفحة منسّق
/// القسم). بقية المسارات لا تزال Placeholder (الإرشاد الأكاديمي الشامل
/// معطَّل أصلًا حتى بصفحة منسّق القسم بانتظار بيانات كاملة - انظر
/// coordinator_advising_screen.dart؛ التقرير الخاص بكل مسار يُبنى لاحقًا).
class TrackCoordinatorWorkspaceScreen extends StatelessWidget {
  final String track;

  const TrackCoordinatorWorkspaceScreen({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final label = _trackLabels[track] ?? track;
    if (track == 'student_care') {
      return _StudentCareTrackScreen(label: label);
    }

    return PortalScaffold(
      title: 'منسّق مسار $label',
      showBackButton: false,
      actions: [
        TextButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: Icon(Icons.logout, color: Colors.red.shade700),
          label: Text('تسجيل الخروج', style: TextStyle(color: Colors.red.shade700)),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.explore_outlined, size: 56, color: AppColors.green),
            const SizedBox(height: 16),
            Text(
              'مرحبًا بمنسّق مسار $label',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.greenDark),
            ),
            const SizedBox(height: 12),
            Text(
              'الصفحة قيد البناء لهذا المسار.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentCareTrackScreen extends StatefulWidget {
  final String label;
  const _StudentCareTrackScreen({required this.label});

  @override
  State<_StudentCareTrackScreen> createState() => _StudentCareTrackScreenState();
}

class _StudentCareTrackScreenState extends State<_StudentCareTrackScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'منسّق مسار ${widget.label}',
      showBackButton: false,
      actions: [
        TextButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: Icon(Icons.logout, color: Colors.red.shade700),
          label: Text('تسجيل الخروج', style: TextStyle(color: Colors.red.shade700)),
        ),
      ],
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.green,
            tabs: const [
              Tab(text: 'حالات الظروف الخاصة', icon: Icon(Icons.volunteer_activism_outlined, size: 20)),
              Tab(text: 'الدعم النفسي والاجتماعي', icon: Icon(Icons.favorite_border, size: 20)),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                TrackCaseListView(
                  cases: HardshipCaseService.watchAllCases(),
                  addCase: HardshipCaseService.addCase,
                  addFollowUp: HardshipCaseService.addFollowUp,
                  emptyMessage: 'لا توجد حالات ظروف خاصة مسجَّلة بعد.',
                ),
                TrackCaseListView(
                  cases: SupportCaseService.watchAllCases(),
                  addCase: SupportCaseService.addCase,
                  addFollowUp: SupportCaseService.addFollowUp,
                  emptyMessage: 'لا توجد حالات دعم نفسي/اجتماعي مسجَّلة بعد.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
