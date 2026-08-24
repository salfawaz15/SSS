import 'package:flutter/material.dart';

import '../../theme/portal_theme.dart';

/// شاشة مؤقتة لتبويبات المرحلة التالية (متابعة/رفع ملفات/تنبيهات/المزيد) -
/// المرحلة الأولى من "بوابة الإرشاد" تشمل الرئيسية وتسجيل الدخول والتنقّل
/// السفلي فقط؛ باقي الشاشات تُبنى في مراحل تالية منفصلة بعد اعتماد كل مرحلة.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const ComingSoonScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: AppSpacing.md),
              Text('قيد التطوير - المرحلة التالية', style: AppTextStyles.body(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
