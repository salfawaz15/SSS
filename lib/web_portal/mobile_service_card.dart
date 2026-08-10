import 'package:flutter/material.dart';

/// بطاقة خدمة صغيرة موحّدة لشبكات الخدمات على الجوال (أيقونة دائرية 42×42 +
/// عنوان) - مستخرجة من `mobile_advising_home_screen.dart` لتُستخدَم بنفس
/// الحجم في أي صفحة شبكة خدمات أخرى على الجوال (مثال: `academic_services_
/// hub_screen.dart`) بدل تكرار التصميم أو استخدام `PortalActionCard` الكبيرة
/// المصمَّمة أصلاً لعرض الحاسوب - سليمان لاحظ عدم اتساق حجم الأيقونات بين
/// الصفحتين على الجوال (2026-08-09).
class MobileServiceItem {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const MobileServiceItem({required this.icon, required this.color, required this.label, required this.onTap});
}

class MobileServiceCard extends StatelessWidget {
  const MobileServiceCard({super.key, required this.service});

  final MobileServiceItem service;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: service.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: service.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(service.icon, color: service.color, size: 22),
                ),
                const Spacer(),
                Text(service.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
