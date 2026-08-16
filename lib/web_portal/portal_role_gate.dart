import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'force_change_password_screen.dart';
import 'portal_accounts.dart';

/// الدور المُحسَوم لحساب الدخول الحالي - نظام الأدوار الجديد (Custom Claim)
/// أو النظام القديم (بريد حرفي) على حدٍّ سواء، بمعرِّف موحَّد واحد يُستخدَم من
/// كل نقاط الدخول (الويب والجوال) بدل تكرار نفس منطق الفحص بكل نقطة على
/// حدة - كان هذا التكرار سبب علّة حقيقية: `mobile_advising_root.dart` كان
/// يفحص فقط الأعلام القديمة (`isFullAdmin`/`isViewer`/`isCollegeCoordinator`)
/// فيُخطئ توجيه أي حساب بنظام الأدوار الجديد (منسّق قسم/مسار/وحدة، أمين)
/// على الجوال تحديدًا (سليمان 2026-08-16).
enum PortalRole {
  superAdmin,
  admin,
  ameen,
  unitCoordinator,
  collegeCoordinator,
  deptCoordinator,
  trackCoordinator,
  unknown,
}

/// بيانات الدور المُحسَوم لحساب الدخول الحالي - تُمرَّر لدالة البناء
/// (`builder`) بـ[PortalRoleGate] لتقرّر أي شاشة تُعرض.
class PortalResolvedRole {
  final PortalRole role;
  final String uid;
  final String? email;
  final String? track;

  const PortalResolvedRole({required this.role, required this.uid, this.email, this.track});
}

/// يغلّف منطق تسجيل الدخول وحسم الدور بالكامل (حالة المصادقة، توكن Custom
/// Claim، فحص إجبار تغيير كلمة المرور، ثم التوافق الرجعي مع حسابات الأدوار
/// المشتركة القديمة بالبريد الحرفي) - مصدر وحيد للحقيقة يُستخدَم من
/// `PortalRoot` (الويب) و`MobileAdvisingRoot` (الجوال) معًا، فأي تحديث لمنطق
/// تحديد الدور يظهر أثره تلقائيًا بكلا الواجهتين بلا ازدواجية.
class PortalRoleGate extends StatelessWidget {
  final Widget Function(BuildContext context, PortalResolvedRole resolved) builder;
  final Widget Function(BuildContext context) loginBuilder;

  const PortalRoleGate({super.key, required this.builder, required this.loginBuilder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) return loginBuilder(context);

        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(true),
          builder: (context, tokenSnapshot) {
            if (!tokenSnapshot.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final claimRole = tokenSnapshot.data!.claims?['role'] as String?;
            PortalAccounts.currentClaimRole = claimRole;

            if (claimRole != null) {
              final track = tokenSnapshot.data!.claims?['track'] as String?;
              return _StaffAccountGate(
                uid: user.uid,
                claimRole: claimRole,
                track: track,
                builder: builder,
              );
            }

            return builder(context, _resolveLegacyRole(user));
          },
        );
      },
    );
  }

  /// يحسم الدور بلا أي بوابة UI (لا شاشة تحميل، لا فحص إجبار تغيير كلمة
  /// المرور) - يُستخدَم من صفحات لا تريد حجب نفسها بانتظار حسم الدور (مثال:
  /// `mobile_home_screen.dart` العامة، لتحديد عناصر الشريط السفلي المناسبة
  /// لدور المستخدم الحالي دون تعطيل عرض الصفحة نفسها). يرجع `null` لو
  /// المستخدم غير مسجَّل دخوله.
  static Future<PortalResolvedRole?> resolveSimple(User? user) async {
    if (user == null) return null;
    final token = await user.getIdTokenResult();
    final claimRole = token.claims?['role'] as String?;
    PortalAccounts.currentClaimRole = claimRole;

    if (claimRole == null) return _resolveLegacyRole(user);

    final track = token.claims?['track'] as String?;
    final role = switch (claimRole) {
      'super_admin' => PortalRole.superAdmin,
      'admin' => PortalRole.admin,
      'ameen' || 'secretary' => PortalRole.ameen,
      'unit_coordinator' => PortalRole.unitCoordinator,
      'college_coordinator' => PortalRole.collegeCoordinator,
      'dept_coordinator' => PortalRole.deptCoordinator,
      'track_coordinator' => PortalRole.trackCoordinator,
      _ => PortalRole.unknown,
    };
    return PortalResolvedRole(role: role, uid: user.uid, email: user.email, track: track);
  }

  static PortalResolvedRole _resolveLegacyRole(User user) {
    final email = user.email;
    if (PortalAccounts.isFullAdmin(email)) {
      return PortalResolvedRole(
        role: email == PortalAccounts.superAdminEmail ? PortalRole.superAdmin : PortalRole.admin,
        uid: user.uid,
        email: email,
      );
    }
    if (PortalAccounts.viewerEmails.values.contains(email)) {
      return PortalResolvedRole(role: PortalRole.ameen, uid: user.uid, email: email);
    }
    if (PortalAccounts.isCollegeCoordinator(email)) {
      return PortalResolvedRole(role: PortalRole.collegeCoordinator, uid: user.uid, email: email);
    }
    if (PortalAccounts.isUnitCoordinator(email)) {
      return PortalResolvedRole(role: PortalRole.unitCoordinator, uid: user.uid, email: email);
    }
    return PortalResolvedRole(role: PortalRole.deptCoordinator, uid: user.uid, email: email);
  }
}

class _StaffAccountGate extends StatelessWidget {
  final String uid;
  final String claimRole;
  final String? track;
  final Widget Function(BuildContext context, PortalResolvedRole resolved) builder;

  const _StaffAccountGate({
    required this.uid,
    required this.claimRole,
    required this.track,
    required this.builder,
  });

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

        final role = switch (claimRole) {
          'super_admin' => PortalRole.superAdmin,
          'admin' => PortalRole.admin,
          'ameen' || 'secretary' => PortalRole.ameen,
          'unit_coordinator' => PortalRole.unitCoordinator,
          'college_coordinator' => PortalRole.collegeCoordinator,
          'dept_coordinator' => PortalRole.deptCoordinator,
          'track_coordinator' => PortalRole.trackCoordinator,
          _ => PortalRole.unknown,
        };

        return builder(context, PortalResolvedRole(role: role, uid: uid, track: track));
      },
    );
  }
}
