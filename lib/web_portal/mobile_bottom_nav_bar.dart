import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// عنصر تبويب واحد بشريط التنقّل السفلي الجوّالة.
class MobileNavTab {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const MobileNavTab({required this.icon, required this.label, required this.onTap});
}

/// شريط تنقّل سفلي جوّال بأسلوب النسخة القديمة التي فضّلها سليمان (صور
/// أرسلها 2026-08-16): خلفية بيضاء، أيقونة + تسمية لكل تبويب، والتبويب
/// النشط يحمل مؤشّر Pill بخلفية خضراء فاتحة ونصًا أخضر داكنًا غامقًا، بقية
/// التبويبات رمادية. حتى 4 تبويبات تُمرَّر مباشرة (`tabs`) + تبويب اختياري
/// أخير ثابت "المزيد" (`onMore`) لبقية الأقسام غير الظاهرة كتبويب مباشر -
/// يُستخدَم بأي شاشة جوّال جذرية (`Scaffold.bottomNavigationBar`).
class MobileBottomNavBar extends StatelessWidget {
  final List<MobileNavTab> tabs;
  final int currentIndex;
  final VoidCallback? onMore;

  const MobileBottomNavBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          // ترتيب القائمة أدناه يحدّد الترتيب البصري من اليمين لليسار (RTL):
          // أول عنصر بالقائمة = أقصى اليمين. التبويبات (بدءًا بـ"الرئيسية")
          // تُمرَّر أولًا فتظهر يمينًا، و"المزيد" أخيرًا فيظهر أقصى اليسار -
          // بنفس ترتيب صور سليمان المرجعية (المزيد/التقارير/إدارة الطلبات/
          // الرئيسية من اليسار لليمين).
          children: [
            for (var i = 0; i < tabs.length; i++)
              _NavTabButton(
                icon: tabs[i].icon,
                label: tabs[i].label,
                selected: i == currentIndex,
                onTap: tabs[i].onTap,
              ),
            if (onMore != null)
              _NavTabButton(icon: Icons.more_horiz, label: 'المزيد', selected: false, onTap: onMore!),
          ],
        ),
      ),
    );
  }
}

class _NavTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTabButton({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE7EFEA) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: selected ? AppColors.greenDark : Colors.grey.shade500),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.greenDark : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
