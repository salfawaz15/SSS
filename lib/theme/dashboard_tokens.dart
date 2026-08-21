import 'package:flutter/material.dart';

import 'app_theme.dart';

/// هوية بصرية موحّدة لكل لوحات الإحصائيات بالبوابة - أُعيد تعريفها لتستمَد
/// مباشرة من `AppColors` (هوية لوحة الإدارة والصفحة العامة) بدل نظام ألوان
/// مستقل خاص بها (سليمان 2026-08-22: "AppColors هي المرجع الوحيد لكل
/// البوابة" - كان هذا الملف نسخة من `_Tokens` بلوحة الحذف والإضافة، مختلفة
/// عمدًا عن AppColors، وقد عُمِّمت على 8 صفحات دون أن تُلاحَظ كهوية موازية
/// حتى قارنها سليمان بصفحة "التقارير" فوجدها باهتة رمادية). بلا ظل ولا زوايا
/// كبيرة - بطاقات مسطّحة بحدود رمادية خفيفة تطابق `_KpiCard` بلوحة الإدارة.
class DashTokens {
  static const green950 = AppColors.greenDark;
  static const green900 = AppColors.greenDark;
  static const green800 = AppColors.green;

  static const gold600 = AppColors.gold;
  static const gold500 = AppColors.goldLight;

  static const success = AppColors.green;
  static const successSoft = Color(0xFFEAF3EE);
  static const danger = AppColors.errorRed;
  static const dangerSoft = Color(0xFFF7E9E8);
  static const warning = AppColors.gold;
  static const warningSoft = Color(0xFFFBF3DE);

  static const pageBg = AppColors.background;
  static const cardBg = Colors.white;

  static const textPrimary = Color(0xFF17352B);
  static const textSecondary = Color(0xFF66746F);
  static const textMuted = Color(0xFF8A9691);

  static const border = Color(0xFFE0E0E0);
  static const track = Color(0xFFEDF0EE);

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 14.0;

  // بلا ظل - بطاقات مسطّحة بحدود فقط (تطابق بطاقات لوحة الإدارة).
  static List<BoxShadow> get cardShadow => const [];
}

/// بطاقة مؤشر رقمي (KPI) بشريط أعلى ملوَّن + أيقونة دائرية - نسخة قابلة
/// لإعادة الاستخدام حرفيًا من `_KpiCard` بلوحة الحذف والإضافة، بدل تكرارها
/// محليًا بكل صفحة.
class DashKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color accent;

  const DashKpiCard({super.key, required this.label, required this.value, required this.note, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        boxShadow: DashTokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 16,
            left: 16,
            child: Container(height: 3, decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 11.5, color: DashTokens.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: DashTokens.textPrimary, height: 1)),
                      const SizedBox(height: 4),
                      Text(note, style: const TextStyle(fontSize: 10, color: DashTokens.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// حاوية بطاقة بعنوان + أيقونة (Card Shell) - نسخة قابلة لإعادة الاستخدام
/// حرفيًا من `_CardShell` بلوحة الحذف والإضافة.
class DashCardShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  const DashCardShell({super.key, required this.title, this.subtitle, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        boxShadow: DashTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: DashTokens.green900),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                    if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 10.5, color: DashTokens.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// بطاقة إجراء (أيقونة + عنوان + وصف قصير) بنفس الهوية - بديل موحَّد لبطاقات
/// "تقارير" و"لوحة الإرشاد" و"الخدمات السريعة".
class DashActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const DashActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DashTokens.cardBg,
      borderRadius: BorderRadius.circular(DashTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: DashTokens.border),
            borderRadius: BorderRadius.circular(DashTokens.radiusLg),
            boxShadow: DashTokens.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                    const SizedBox(height: 4),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: DashTokens.textSecondary, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عنوان قسم صغير بأيقونة (بنفس أسلوب توليب لوحة الحذف والإضافة) - يُستخدَم
/// فوق كل مجموعة بطاقات لتمييزها بدل بدء المحتوى مباشرة بلا سياق.
class DashSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const DashSectionHeader({super.key, required this.title, this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: DashTokens.green900),
        const SizedBox(width: 7),
        Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Expanded(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: DashTokens.textMuted))),
        ],
      ],
    );
  }
}
