import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'portal_footer.dart';

/// عنصر تنقّل واحد في الشريط العلوي للبوابة (نفس فكرة تبويبات الصفحة
/// العامة `_NavBar` في public_landing_screen.dart، لكن لأقسام البوابة
/// الداخلية بدل صفحات الموقع التعريفي).
class PortalNavItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  const PortalNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
}

/// شارة الهوية - نفس صورة الشعار المعتمدة بالضبط في الشريط العلوي للصفحة
/// العامة (`assets/images/full_logo_green.png`، خلفية خضراء + TU بحلقة
/// ذهبية + اسم الكلية والوحدة) بلا إعادة بنائها يدويًا بخط/تنسيق مختلف،
/// حتى تكون بصمة الهوية مطابقة 100% سواء قبل تسجيل الدخول أو داخل البوابة.
class _PortalBrandBadge extends StatelessWidget {
  const _PortalBrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Image.asset(
        'assets/images/full_logo_green.png',
        height: 40,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Text('TU', style: AppTextStyles.caption(color: Colors.white)),
      ),
    );
  }
}

/// الشريط العلوي الموحّد لكل صفحات البوابة الداخلية: خط تمييز رفيع بلون
/// الهوية، ثم شريط أبيض يحمل شارة الهوية أولًا (تظهر دائمًا مهما كانت
/// الصفحة)، وتبويبات تنقّل اختيارية لأقسام البوابة الرئيسية (تتكيّف حسب
/// الدور: مدير/منسّق/عرض)، وإجراءات مساعدة (بحث/إشعارات/قائمة المزيد) على
/// الطرف الآخر. يحلّ محل بناء كل شاشة لشريط هوية/AppBar خاص بها من الصفر.
class PortalHeader extends StatelessWidget implements PreferredSizeWidget {
  final List<PortalNavItem> navItems;
  final List<Widget>? trailing;
  final bool showBackButton;
  final String? fallbackTitle;

  const PortalHeader({
    super.key,
    this.navItems = const [],
    this.trailing,
    this.showBackButton = false,
    this.fallbackTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 4, color: AppColors.greenDark),
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              Widget navButton(PortalNavItem item) {
                return TextButton.icon(
                  onPressed: item.onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: item.selected ? AppColors.green : Colors.grey.shade700,
                  ),
                  icon: Icon(item.icon, size: 17),
                  label: Text(
                    item.label,
                    style: TextStyle(fontWeight: item.selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5),
                  ),
                );
              }

              final backButton = showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.green),
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : const SizedBox.shrink();

              if (isWide) {
                return Row(
                  children: [
                    backButton,
                    const _PortalBrandBadge(),
                    const SizedBox(width: 18),
                    if (navItems.isNotEmpty)
                      ...navItems.map(navButton)
                    else if (fallbackTitle != null)
                      Text(fallbackTitle!, style: AppTextStyles.h3()),
                    const Spacer(),
                    ...?trailing,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [backButton, const _PortalBrandBadge()]),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...?trailing,
                      if (navItems.isNotEmpty)
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.menu, color: AppColors.green),
                          tooltip: 'أقسام البوابة',
                          itemBuilder: (context) => [
                            for (var i = 0; i < navItems.length; i++)
                              PopupMenuItem(
                                value: i,
                                child: Row(
                                  children: [
                                    Icon(navItems[i].icon, size: 18, color: AppColors.green),
                                    const SizedBox(width: 10),
                                    Text(navItems[i].label),
                                  ],
                                ),
                              ),
                          ],
                          onSelected: (i) => navItems[i].onTap(),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(4 + 52);
}

/// إطار صفحة موحّد لكل شاشات البوابة الداخلية: `PortalHeader` (شارة الهوية
/// دائمًا + تبويبات تنقّل اختيارية) أعلى الصفحة بلا استثناء، ثم صف
/// تبويبات فرعية اختياري (`bottom`، مثل TabBar صفحة معيّنة)، ثم المحتوى،
/// ثم تذييل الحقوق `PortalFooterBar` أسفل الصفحة.
class PortalScaffold extends StatelessWidget {
  final String title;
  final List<PortalNavItem> navItems;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showBackButton;
  final Widget body;
  final Widget? floatingActionButton;

  const PortalScaffold({
    super.key,
    required this.title,
    required this.body,
    this.navItems = const [],
    this.actions,
    this.bottom,
    this.showBackButton = true,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final header = PortalHeader(
      navItems: navItems,
      trailing: actions,
      showBackButton: showBackButton,
      fallbackTitle: navItems.isEmpty ? title : null,
    );
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(header.preferredSize.height + bottomHeight),
        child: Column(
          children: [
            header,
            ?bottom,
          ],
        ),
      ),
      bottomNavigationBar: const PortalFooterBar(),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}
