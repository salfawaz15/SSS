import 'package:flutter/material.dart';

/// شريط تذييل موحّد (نفس نص حقوق الملكية الموجود في الصفحة الرئيسية
/// العامة) يُضاف الآن في كل صفحات البوابة الداخلية (تسجيل الدخول، لوحة
/// الإدارة، شاشة المنسّق، شاشة العرض فقط) لضمان اتساق الهوية البصرية في
/// كل مكان بالموقع وليس فقط الصفحة الرئيسية.
class PortalFooterBar extends StatelessWidget implements PreferredSizeWidget {
  const PortalFooterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0E1F17),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'جميع الحقوق محفوظة لـ سليمان الفواز © 2026',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 13),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(38);
}
