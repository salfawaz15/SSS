import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_workspace_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'inactivity_auto_logout.dart';
import 'portal_accounts.dart';
import 'portal_login_screen.dart';
import 'unit_coordinator_workspace_screen.dart';
import 'viewer_reports_screen.dart';

/// اسم مسار [PortalRoot] عند دفعه بـ`Navigator.push` (من الصفحة العامة أو
/// شاشة الدخول السرية) - يُستخدم لاحقًا للرجوع إليه تحديدًا بـ`popUntil` من
/// أي صفحة إدارة فرعية (بدل الافتراض الخاطئ أن أول صفحة بالمكدّس = لوحة
/// الإدارة، وهو غير صحيح عند الدخول العادي لأن الصفحة العامة تبقى تحته).
const String kPortalRootRouteName = '/portal-root';

/// نقطة دخول بوابة الويب: يوجّه حسب حالة تسجيل الدخول إلى شاشة الدخول، أو
/// لوحة الإدارة، أو شاشة المنسّق - حسب البريد الداخلي لحساب Firebase Auth.
class PortalRoot extends StatelessWidget {
  const PortalRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const PortalLoginScreen();
        }

        return InactivityAutoLogout(
          child: Builder(
            builder: (context) {
              if (PortalAccounts.isFullAdmin(user.email)) {
                return const AdminWorkspaceScreen();
              }

              if (PortalAccounts.viewerEmails.values.contains(user.email)) {
                return const ViewerReportsScreen();
              }

              if (PortalAccounts.isCollegeCoordinator(user.email)) {
                return CollegeCoordinatorWorkspaceScreen(uid: user.uid);
              }

              // منسّق الوحدة: دور تقني جاهز بانتظار القرار الرسمي، بصلاحية رفع
              // الملفات فقط - يُفحَص قبل "المنسّق الافتراضي" أدناه حتى لا يقع
              // خطأً ضمن منسّق قسم عادي (لا مستند coordinator_accounts له أصلاً).
              if (PortalAccounts.isUnitCoordinator(user.email)) {
                return const UnitCoordinatorWorkspaceScreen();
              }

              return CoordinatorWorkspaceScreen(uid: user.uid);
            },
          ),
        );
      },
    );
  }
}
