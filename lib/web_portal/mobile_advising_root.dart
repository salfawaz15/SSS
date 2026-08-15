import 'package:flutter/material.dart';

import 'app_update_banner.dart';
import 'mobile_home_screen.dart';
import 'portal_login_screen.dart';
import 'portal_role_gate.dart';

/// نقطة الدخول لتطبيق "CBA Advising" على الجوال - **أُعيد بناؤها بالكامل من
/// الصفر** (2026-08-16) بعد أن كشف اختبار سليمان الحي أن دفع شاشات الموقع
/// العريضة (`AdminWorkspaceScreen`, `CoordinatorWorkspaceScreen`,
/// `AdvisingHubScreen`...) مباشرة على الجوال ينتج صفحات مكسورة فعليًا -
/// هذه الشاشات مبنية حصرًا لعرض حاسوب ولم تُختبَر على عرض جوال ضيق من قبل.
///
/// كل الأدوار السبعة تُعرَض الآن بنفس [MobileHomeScreen] الجوّالة الأصيلة
/// الواحدة (بلا أي دفع لشاشات الويب العريضة) - بطلب سليمان الصريح: "يبدأ
/// بالصفحة الرئيسية فقط". الوجهات الحقيقية (تقارير/إدارة طلبات/...) ستُبنى
/// جوّالة أصيلة من الصفر واحدة تلو الأخرى بجلسات قادمة، لا نوافذ لعرض شاشات
/// الحاسوب كما كانت التجربة السابقة.
class MobileAdvisingRoot extends StatelessWidget {
  const MobileAdvisingRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalRoleGate(
      loginBuilder: (context) => const PortalLoginScreen(),
      builder: (context, resolved) => AppUpdateBanner(
        child: MobileHomeScreen(role: resolved.role),
      ),
    );
  }
}
