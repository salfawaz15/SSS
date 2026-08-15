import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'portal_header.dart';

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
/// مسار"). حاليًا Placeholder فقط - الوظائف الفعلية (حالات الظروف الخاصة
/// والدعم النفسي المنقولتان من صفحة منسّق القسم، إرشاد شامل كل الأقسام،
/// تقرير خاص بالمسار) تُبنى لاحقًا بعد اعتماد تدفّق الدخول الجديد بالكامل.
class TrackCoordinatorWorkspaceScreen extends StatelessWidget {
  final String track;

  const TrackCoordinatorWorkspaceScreen({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final label = _trackLabels[track] ?? track;
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
              'الصفحة قيد البناء - ستضم قريبًا حالات الظروف الخاصة والدعم النفسي والاجتماعي، '
              'الإرشاد الأكاديمي الشامل لكل الأقسام، والتقرير الخاص بمسارك.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
