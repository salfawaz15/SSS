import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'academic_services_hub_screen.dart';
import 'admin_workspace_screen.dart';
import 'advising_hub_screen.dart';
import 'change_password_dialog.dart';
import 'college_coordinator_workspace_screen.dart';
import 'college_roster_admin_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'mobile_service_card.dart';
import 'viewer_reports_screen.dart';

/// الشاشة الرئيسية الجوّالة الأصلية لتطبيق "CBA Advising" بعد الدخول - بطاقة
/// ترحيب + شبكة خدمات (بنفس روح الشاشة الرئيسية لتطبيق "سليمان" بطلب سليمان
/// صراحةً 2026-08-07)، بدل عرض `AdminWorkspaceScreen` (تصميم الموقع العريض)
/// مباشرة كما كان سابقًا.
///
/// الشبكة تظهر فقط لحساب الإدارة الكامل (أدوار متعدّدة تستحق شبكة اختيار) -
/// بقية الأدوار (منسّق قسم/منسّق كلية/عرض فقط) لها وجهة واحدة فيُنقَل إليها
/// مباشرة بلا شبكة وسيطة لا فائدة منها.
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

  @override
  Widget build(BuildContext context) {
    if (isViewer) return const ViewerReportsScreen();
    if (isCollegeCoordinator) return CollegeCoordinatorWorkspaceScreen(uid: uid);
    if (!isFullAdmin) return CoordinatorWorkspaceScreen(uid: uid);

    final services = <MobileServiceItem>[
      MobileServiceItem(
        icon: Icons.dashboard_outlined,
        color: AppColors.greenDark,
        label: 'لوحة الإدارة',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdminWorkspaceScreen()),
        ),
      ),
      MobileServiceItem(
        icon: Icons.fact_check_outlined,
        color: AppColors.gold,
        label: 'لوحة الإرشاد',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdvisingHubScreen()),
        ),
      ),
      if (isSuperAdmin)
        MobileServiceItem(
          icon: Icons.school_outlined,
          color: AppColors.green,
          label: 'خدمات أكاديمية',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AcademicServicesHubScreen()),
          ),
        ),
      if (isSuperAdmin)
        MobileServiceItem(
          icon: Icons.badge_outlined,
          color: AppColors.goldLight,
          label: 'المنسوبين',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CollegeRosterAdminScreen()),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
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
                IconButton(
                  tooltip: 'تغيير كلمة المرور',
                  icon: const Icon(Icons.lock_outline, color: AppColors.greenDark),
                  onPressed: () => showChangePasswordDialog(context),
                ),
                IconButton(
                  tooltip: 'تسجيل خروج',
                  icon: const Icon(Icons.logout, color: AppColors.greenDark),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
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
            const SizedBox(height: 26),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('الخدمات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.35,
              children: services.map((s) => MobileServiceCard(service: s)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

