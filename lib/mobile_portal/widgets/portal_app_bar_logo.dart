import 'package:flutter/material.dart';

/// الشعار الرسمي النظيف (خلفية مُفرَّغة فعليًا) - نفس شعار شاشة الدخول
/// بالضبط، ثابت أعلى يمين كل شاشات التطبيق (باتجاه RTL) بطلب سليمان صراحةً
/// (2026-08-23). يُستخدَم دومًا مع `AppBar(leadingWidth: kPortalAppBarLeadingWidth, leading: const PortalAppBarLogo())`.
const kPortalAppBarLeadingWidth = 64.0;

class PortalAppBarLogo extends StatelessWidget {
  const PortalAppBarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Image.asset(
        'assets/images/unit_logo_clean_transparent_cropped.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
