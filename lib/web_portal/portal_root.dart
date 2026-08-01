import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_workspace_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'portal_accounts.dart';
import 'portal_login_screen.dart';
import 'viewer_reports_screen.dart';

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

        if (PortalAccounts.isFullAdmin(user.email)) {
          return const AdminWorkspaceScreen();
        }

        if (PortalAccounts.viewerEmails.values.contains(user.email)) {
          return const ViewerReportsScreen();
        }

        if (PortalAccounts.isCollegeCoordinator(user.email)) {
          return CollegeCoordinatorWorkspaceScreen(uid: user.uid);
        }

        return CoordinatorWorkspaceScreen(uid: user.uid);
      },
    );
  }
}
