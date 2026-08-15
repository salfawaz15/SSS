import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_workspace_screen.dart';
import 'college_coordinator_workspace_screen.dart';
import 'coordinator_workspace_screen.dart';
import 'force_change_password_screen.dart';
import 'inactivity_auto_logout.dart';
import 'portal_accounts.dart';
import 'portal_login_screen.dart';
import 'track_coordinator_workspace_screen.dart';
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
          child: FutureBuilder<IdTokenResult>(
            // force refresh: true - دور الحساب (Custom Claim) قد يُعيَّن بعد
            // إنشاء الحساب مباشرة عبر أداة سطر الأوامر، والتوكن المحفوظ محليًا
            // (لو كانت هناك جلسة سابقة) لا يعرف عنه شيئًا قبل تحديثه صراحةً.
            future: user.getIdTokenResult(true),
            builder: (context, tokenSnapshot) {
              if (!tokenSnapshot.hasData) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final role = tokenSnapshot.data!.claims?['role'] as String?;

              // نظام الأدوار الجديد (Custom Claim على حساب فردي برقم منسوب) -
              // المرحلة 3 من إعادة هيكلة الدخول والصلاحيات (2026-08-15).
              if (role != null) {
                return _StaffAccountGate(
                  uid: user.uid,
                  role: role,
                  track: tokenSnapshot.data!.claims?['track'] as String?,
                );
              }

              // النظام القديم (حسابات أدوار مشتركة بالبريد الحرفي) - يبقى
              // يعمل أثناء فترة الانتقال، إلى أن تُنقَل كل الحسابات للنظام
              // الجديد وتُحذف هذه الحسابات المشتركة.
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

/// يفحص علم "يجب تغيير كلمة المرور" لحساب النظام الجديد، ثم يوجّه للصفحة
/// المناسبة حسب الدور (Custom Claim).
class _StaffAccountGate extends StatelessWidget {
  final String uid;
  final String role;
  final String? track;

  const _StaffAccountGate({required this.uid, required this.role, required this.track});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('portal_users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data!.data()?['mustChangePassword'] == true) {
          return const ForceChangePasswordScreen();
        }

        return switch (role) {
          'super_admin' || 'admin' => const AdminWorkspaceScreen(),
          'ameen' || 'secretary' => const ViewerReportsScreen(),
          'unit_coordinator' => const UnitCoordinatorWorkspaceScreen(),
          'college_coordinator' => CollegeCoordinatorWorkspaceScreen(uid: uid),
          'dept_coordinator' => CoordinatorWorkspaceScreen(uid: uid),
          'track_coordinator' => TrackCoordinatorWorkspaceScreen(track: track ?? ''),
          _ => const Scaffold(body: Center(child: Text('دور غير معروف بحسابك - تواصل مع الإدارة'))),
        };
      },
    );
  }
}
