import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'academic_services_hub_screen.dart';
import 'admin_workspace_screen.dart';
import 'advising_hub_screen.dart';
import 'change_password_dialog.dart';
import 'college_roster_admin_screen.dart';
import 'mobile_bottom_nav_bar.dart';
import 'reports_hub_screen.dart';

/// الشاشة الرئيسية الجوّالة لحساب الإدارة الكامل بعد الدخول - بطاقة ترحيب +
/// شريط تنقّل سفلي (بأسلوب النسخة القديمة التي فضّلها سليمان صراحةً، صور
/// أرسلها 2026-08-16: "المزيد/التقارير/إدارة الطلبات/الرئيسية") بدل شبكة
/// خدمات ثابتة فقط كما كانت سابقًا - المرحلة 2 من خطة إعادة بناء تطبيق
/// الجوال (نموذج مرجعي لدور الإدارة أولًا قبل تعميمه على بقية الأدوار).
///
/// تبويبا "التقارير" و"إدارة الطلبات" ينقلان لشاشتي الموقع الحاليتين
/// (`ReportsHubScreen`/`AdvisingHubScreen`) مباشرة - بلا إعادة بناء منطقهما،
/// فقط بوابة تنقّل جوّالة جديدة حولهما. "المزيد" يفتح قائمة سفلية لبقية
/// الأقسام (لوحة الإدارة الكاملة بتصميمها العريض، خدمات أكاديمية،
/// المنسوبين - آخر اثنين حصريًا للمدير العام) + تغيير كلمة المرور وتسجيل
/// الخروج.
///
/// تُعرض فقط لحساب الإدارة الكامل - بقية الأدوار تُوجَّه لوجهتها مباشرة من
/// [MobileAdvisingRoot] نفسه (لا تصل لهذه الشاشة أصلًا)، فلا حاجة لفحص أدوار
/// أخرى هنا.
class MobileAdvisingHomeScreen extends StatelessWidget {
  const MobileAdvisingHomeScreen({
    super.key,
    required this.email,
    required this.uid,
    required this.isFullAdmin,
    required this.isSuperAdmin,
    required this.isCollegeCoordinator,
    required this.isViewer,
  });

  final String? email;
  final String uid;
  final bool isFullAdmin;
  final bool isSuperAdmin;
  final bool isCollegeCoordinator;
  final bool isViewer;

  void _openMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined, color: AppColors.greenDark),
              title: const Text('لوحة الإدارة الكاملة'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminWorkspaceScreen()));
              },
            ),
            if (isSuperAdmin)
              ListTile(
                leading: const Icon(Icons.school_outlined, color: AppColors.green),
                title: const Text('خدمات أكاديمية'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AcademicServicesHubScreen()));
                },
              ),
            if (isSuperAdmin)
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: AppColors.goldLight),
                title: const Text('المنسوبين'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CollegeRosterAdminScreen()));
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: AppColors.greenDark),
              title: const Text('تغيير كلمة المرور'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showChangePasswordDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل خروج'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                FirebaseAuth.instance.signOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(0xFFE7EFEA),
                  child: Icon(Icons.person_outline, color: AppColors.greenDark),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isSuperAdmin ? 'المدير العام' : 'إدارة الوحدة',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.greenDark),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.greenDark, AppColors.green],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Text('👋', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'أهلاً بك',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'نتمنى لك يومًا موفقًا - تصفّح خدماتك من هنا',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MobileBottomNavBar(
        currentIndex: 0,
        onMore: () => _openMoreSheet(context),
        tabs: [
          MobileNavTab(icon: Icons.home_outlined, label: 'الرئيسية', onTap: () {}),
          MobileNavTab(
            icon: Icons.fact_check_outlined,
            label: 'إدارة الطلبات',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdvisingHubScreen())),
          ),
          MobileNavTab(
            icon: Icons.assessment_outlined,
            label: 'التقارير',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsHubScreen())),
          ),
        ],
      ),
    );
  }
}
