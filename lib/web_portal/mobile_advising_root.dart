import 'package:flutter/material.dart';

import 'app_update_banner.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'mobile_advising_home_screen.dart';
import 'portal_login_screen.dart';
import 'portal_role_gate.dart';
import 'track_coordinator_workspace_screen.dart';
import 'unit_coordinator_workspace_screen.dart';
import 'viewer_reports_screen.dart';

/// نقطة الدخول لتطبيق "CBA Advising" على الجوال (نكهة advising، انظر
/// main_advising_app.dart) - بديل جوّال أصلي عن [PortalRoot] (المخصَّص
/// للموقع)، لكن بنفس منطق حسم الدور بالضبط عبر [PortalRoleGate] (سليمان
/// 2026-08-16: كان هذا الملف يفحص فقط الأعلام القديمة فيُخطئ توجيه أي حساب
/// من نظام الأدوار الجديد - منسّق قسم/مسار/وحدة، أمين - على الجوال).
///
/// دخول مباشر (بلا الصفحة التعريفية الطويلة [PublicLandingScreen] - لا حاجة
/// لها لمستخدم التطبيق، هو أصلًا موظف بالوحدة). حساب الإدارة الكامل فقط له
/// شاشة رئيسية جوّالة أصلية (`MobileAdvisingHomeScreen` - شبكة خدمات)؛ بقية
/// الأدوار (لها وجهة واحدة) تُنقَل إليها مباشرة بلا شبكة وسيطة لا فائدة منها
/// - نفس الشاشات المستخدمة بالويب حاليًا (إعادة تصميم الغلاف الجوّالة الكامل
/// مرحلة لاحقة منفصلة، انظر خطة "إعادة بناء تطبيق الجوال").
class MobileAdvisingRoot extends StatelessWidget {
  const MobileAdvisingRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalRoleGate(
      loginBuilder: (context) => const PortalLoginScreen(),
      builder: (context, resolved) => AppUpdateBanner(
        child: switch (resolved.role) {
          PortalRole.superAdmin || PortalRole.admin => MobileAdvisingHomeScreen(
              email: resolved.email,
              uid: resolved.uid,
              isFullAdmin: true,
              isSuperAdmin: resolved.role == PortalRole.superAdmin,
              isCollegeCoordinator: false,
              isViewer: false,
            ),
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
