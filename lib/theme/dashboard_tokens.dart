import 'package:flutter/material.dart';

/// هوية بصرية موحّدة لكل لوحات الإحصائيات بالبوابة - مستخرجة حرفيًا من
/// التصميم المعتمَد فعليًا بلوحة "الحذف والإضافة" (`ticket_action_stats_panel`
/// - كان `_Tokens` هناك موثَّقًا كنظام مستقل عمدًا عن `AppColors` العام،
/// مقصورًا على تلك الصفحة فقط). سليمان طلب صراحةً (2026-08-20) توحيدها فعليًا
/// كهوية واحدة بدل بقائها استثناءً محليًا - هذا الملف هو المرجع المشترك بدل
/// تكرار القيم يدويًا بكل صفحة.
class DashTokens {
  static const green950 = Color(0xFF0B3B2E);
  static const green900 = Color(0xFF104836);
  static const green800 = Color(0xFF175B43);

  static const gold600 = Color(0xFFC79A2B);
  static const gold500 = Color(0xFFD5AA3B);

  static const success = Color(0xFF378542);
  static const successSoft = Color(0xFFEDF7EF);
  static const danger = Color(0xFFC2392F);
  static const dangerSoft = Color(0xFFFBEDEC);
  static const warning = Color(0xFFC79A2B);
  static const warningSoft = Color(0xFFFBF5E5);

  static const pageBg = Color(0xFFF4F7F5);
  static const cardBg = Colors.white;

  static const textPrimary = Color(0xFF17352B);
  static const textSecondary = Color(0xFF66746F);
  static const textMuted = Color(0xFF8A9691);

  static const border = Color(0xFFE4EAE7);
  static const track = Color(0xFFEDF0EE);

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: green950.withValues(alpha: 0.03), blurRadius: 5, offset: const Offset(0, 2)),
        BoxShadow(color: green950.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8)),
      ];
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
