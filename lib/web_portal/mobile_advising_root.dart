import 'package:flutter/material.dart';

import 'app_update_banner.dart';
import 'mobile_home_screen.dart';

/// نقطة الدخول لتطبيق "CBA Advising" على الجوال - **أُعيد بناؤها بالكامل من
/// الصفر** (2026-08-16) بعد أن كشف اختبار سليمان الحي أن دفع شاشات الموقع
/// العريضة (`AdminWorkspaceScreen`, `CoordinatorWorkspaceScreen`,
/// `AdvisingHubScreen`...) مباشرة على الجوال ينتج صفحات مكسورة فعليًا -
/// هذه الشاشات مبنية حصرًا لعرض حاسوب ولم تُختبَر على عرض جوال ضيق من قبل.
///
/// **بلا أي بوابة دخول عند هذه النقطة** - بطلب سليمان الصريح: "طبيعي عندما
/// أدخل الموقع يفتح على الصفحة الرئيسية، كذلك التطبيق - بعدها لي الخيار أن
/// أبقى بالصفحة الرئيسية أو أذهب لتسجيل الدخول". [MobileHomeScreen] صفحة
/// عامة (لا تفحص حالة الدخول إطلاقًا) - تسجيل الدخول/حسم الدور يحدث فقط عند
/// ضغط أيقونة الحساب من داخلها (`mobile_account_screen.dart`، يستخدم
/// `PortalRoleGate` هناك حصرًا).
class MobileAdvisingRoot extends StatelessWidget {
  const MobileAdvisingRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppUpdateBanner(child: MobileHomeScreen());
  }
}
