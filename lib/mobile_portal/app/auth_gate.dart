import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../screens/login/portal_login_screen.dart';
import '../theme/portal_theme.dart';
import 'portal_shell.dart';

/// بوابة الدخول - تفتح مباشرة على "الرئيسية" إن كانت هناك جلسة صالحة، أو
/// شاشة الدخول أولًا إن لم تكن هناك جلسة (القسم 6) - خلافًا للتطبيق الجوّالي
/// القديم (CBA Advising) الذي يعرض الرئيسية العامة دائمًا بلا دخول إجباري.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: authService.authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.green)),
          );
        }
        if (snapshot.data == null) {
          return const PortalLoginScreen();
        }
        return const PortalShell();
      },
    );
  }
}
