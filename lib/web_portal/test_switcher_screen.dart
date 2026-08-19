import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_executive_dashboard_screen.dart';
import 'admin_workspace_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'portal_header.dart';
import 'track_coordinator_workspace_screen.dart';
import 'unit_coordinator_workspace_screen.dart';
import 'viewer_reports_screen.dart';

const _departments = <String>[
  'قسم الادارة',
  'قسم المحاسبة',
  'قسم التسويق',
  'قسم الاقتصاد و التمويل',
  'قسم نظم المعلومات الادارية',
];
const _shatrs = <String>['شطر الطلاب', 'شطر الطالبات'];
const _tracks = <String, String>{
  'academic_advising': 'الإرشاد الأكاديمي',
  'student_care': 'الرعاية الطلابية',
  'data_quality': 'البيانات والجودة والتطوير',
  'graduates': 'الخريجين',
  'gifted': 'الموهوبين والتفوق الأكاديمي',
};

/// شاشة "تجربة الصفحات" - لحساب المدير العام حصرًا (بطلب سليمان صراحةً
/// 2026-08-15: "أحتاج حساب ماستر يجعلني أجرّب كل الصفحات"). تفتح أي صفحة
/// عمل بالبوابة مباشرة للمعاينة، بلا حاجة لإنشاء حساب حقيقي منفصل لكل دور.
///
/// لمنسّق الكلية/القسم تحديدًا: الشاشتان الحقيقيتان تقرآن الشطر/القسم من
/// وثيقة Firestore الخاصة بمعرّف الحساب الحالي (uid) لا من معامل مباشر - لذا
/// تكتب هذه الشاشة أولًا نفس الوثيقة لحساب المدير العام نفسه بالقيم
/// المُختارة (مسموح له بالكتابة أصلًا Firestore rules) ثم تفتح الشاشة
/// الحقيقية بلا أي تكرار لمنطقها.
///
/// **ملاحظة للمرحلة القادمة**: `buildAdminNavItems` يُظهر بعض الأزرار
/// (خدمات أكاديمية/المنسوبين) فقط لحساب `salfawaz@...internal` القديم -
/// حسابات المدير العام الجديدة (بالمنسوب) لن تراها حتى يُحدَّث ذلك الفحص
/// ليقرأ الدور من Custom Claim أيضًا.
class TestSwitcherScreen extends StatelessWidget {
  const TestSwitcherScreen({super.key});

  Future<void> _openCollegeCoordinator(BuildContext context, String shatr) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('college_coordinator_accounts').doc(uid).set({'shatr': shatr});
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollegeCoordinatorWorkspaceScreen(uid: uid)));
    }
  }

  Future<void> _openDeptCoordinator(BuildContext context, String department, String shatr) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('coordinator_accounts').doc(uid).set({
      'department': department,
      'shatr': shatr,
    });
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoordinatorWorkspaceScreen(uid: uid)));
    }
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'تجربة الصفحات',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'اختر أي صفحة لمعاينتها مباشرة - للمدير العام فقط، لأغراض الاختبار.',
            style: TextStyle(color: AppColors.greenDark, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'الإدارة والعرض',
            icon: Icons.admin_panel_settings_outlined,
            children: [
              _TestTile(label: 'لوحة الإدارة (تبويب الحذف والإضافة)', onTap: () => _open(context, const AdminWorkspaceScreen())),
              _TestTile(label: 'لوحة الإدارة الرئيسية', onTap: () => _open(context, const AdminExecutiveDashboardScreen())),
              _TestTile(label: 'عرض فقط (أمين/سكرتير)', onTap: () => _open(context, const ViewerReportsScreen())),
              _TestTile(label: 'منسّق الوحدة للشؤون الإدارية', onTap: () => _open(context, const UnitCoordinatorWorkspaceScreen())),
            ],
          ),
          _Section(
            title: 'منسّقو الكلية للشؤون الأكاديمية',
            icon: Icons.school_outlined,
            children: [
              for (final shatr in _shatrs)
                _TestTile(label: shatr, onTap: () => _openCollegeCoordinator(context, shatr)),
            ],
          ),
          _Section(
            title: 'منسّقو الأقسام العلمية',
            icon: Icons.grid_view_outlined,
            children: [
              for (final dept in _departments)
                for (final shatr in _shatrs)
                  _TestTile(label: '$dept - $shatr', onTap: () => _openDeptCoordinator(context, dept, shatr)),
            ],
          ),
          _Section(
            title: 'منسّقو المسارات النوعية',
            icon: Icons.explore_outlined,
            children: [
              for (final entry in _tracks.entries)
                _TestTile(
                  label: entry.value,
                  onTap: () => _open(context, TrackCoordinatorWorkspaceScreen(track: entry.key)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _TestTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TestTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(label),
    );
  }
}
