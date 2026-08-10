import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_update_banner.dart';
import 'mobile_advising_home_screen.dart';
import 'portal_accounts.dart';
import 'portal_login_screen.dart';

/// نقطة الدخول لتطبيق "CBA Advising" على الجوال (نكهة advising، انظر
/// main_advising_app.dart) - بديل جوّال أصلي عن [PortalRoot] (المخصَّص
/// للموقع). [PortalRoot] كان يُستخدَم سابقًا هنا أيضًا فيعرض نفس شاشات
/// الويب مباشرة (`AdminWorkspaceScreen` بتخطيطها العريض) داخل التطبيق -
/// تبدو غير احترافية على شاشة جوال ضيقة وبعض أقسامها كانت تفشل بصمت
/// بنسخة Release (سليمان 2026-08-07، انظر لقطة الشاشة اللي أرسلها).
///
/// الفرق هنا: دخول مباشر (بلا الصفحة التعريفية الطويلة [PublicLandingScreen]
/// - لا حاجة لها لمستخدم التطبيق، هو أصلًا موظف بالوحدة)، وبعد الدخول شاشة
/// رئيسية جوّالة أصلية (`MobileAdvisingHomeScreen` - شبكة خدمات بأسلوب
/// تطبيق "سليمان") بدل عرض `AdminWorkspaceScreen` مباشرةً - أي خدمة تُفتح من
/// الشبكة تنتقل بعدها لنفس شاشات البوابة الحالية (لا تكرار أو إعادة بناء).
class MobileAdvisingRoot extends StatelessWidget {
  const MobileAdvisingRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) return const PortalLoginScreen();

        return AppUpdateBanner(
          child: MobileAdvisingHomeScreen(
            email: user.email,
            uid: user.uid,
            isFullAdmin: PortalAccounts.isFullAdmin(user.email),
            isSuperAdmin: user.email == PortalAccounts.superAdminEmail,
            isCollegeCoordinator: PortalAccounts.isCollegeCoordinator(user.email),
            isViewer: PortalAccounts.viewerEmails.values.contains(user.email),
          ),
        );
      },
    );
  }
}
