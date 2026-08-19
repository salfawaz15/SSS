import 'package:flutter/material.dart';

import 'admin_executive_dashboard_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'inactivity_auto_logout.dart';
import 'portal_role_gate.dart';
import 'staff_number_login_screen.dart';
import 'track_coordinator_workspace_screen.dart';
import 'unit_coordinator_workspace_screen.dart';
import 'viewer_reports_screen.dart';

/// اسم مسار [PortalRoot] عند دفعه بـ`Navigator.push` (من الصفحة العامة أو
/// شاشة الدخول السرية) - يُستخدم لاحقًا للرجوع إليه تحديدًا بـ`popUntil` من
/// أي صفحة إدارة فرعية (بدل الافتراض الخاطئ أن أول صفحة بالمكدّس = لوحة
/// الإدارة، وهو غير صحيح عند الدخول العادي لأن الصفحة العامة تبقى تحته).
const String kPortalRootRouteName = '/portal-root';

/// نقطة دخول بوابة الويب: يوجّه حسب حالة تسجيل الدخول إلى شاشة الدخول، أو
/// لوحة الإدارة، أو شاشة المنسّق - عبر [PortalRoleGate] (منطق حسم الدور
/// المشترك مع `MobileAdvisingRoot`، انظر portal_role_gate.dart).
class PortalRoot extends StatelessWidget {
  const PortalRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalRoleGate(
      loginBuilder: (context) => const StaffNumberLoginScreen(),
      builder: (context, resolved) => InactivityAutoLogout(
        child: switch (resolved.role) {
          PortalRole.superAdmin || PortalRole.admin => const AdminExecutiveDashboardScreen(),
          PortalRole.ameen => const ViewerReportsScreen(),
          PortalRole.unitCoordinator => const UnitCoordinatorWorkspaceScreen(),
          PortalRole.collegeCoordinator => CollegeCoordinatorWorkspaceScreen(uid: resolved.uid),
          PortalRole.deptCoordinator => CoordinatorWorkspaceScreen(uid: resolved.uid),
          PortalRole.trackCoordinator => TrackCoordinatorWorkspaceScreen(track: resolved.track ?? ''),
          PortalRole.unknown =>
            const Scaffold(body: Center(child: Text('دور غير معروف بحسابك - تواصل مع الإدارة'))),
        },
      ),
    );
  }
}
