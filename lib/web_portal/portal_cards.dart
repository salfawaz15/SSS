import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// بطاقتان موحَّدتان يُعاد استخدامهما بكل صفحات البوابة (العامة والإدارة)
/// بدل تكرار نفس التصميم بملفات منفصلة - كانتا مكرَّرتين حرفيًا بين
/// `public_landing_screen.dart` و`admin_workspace_screen.dart` (لاحظنا هذا
/// عمليًا حين طلب سليمان تبديل موضع الأيقونة واحتجنا تعديل ملفين لنفس
/// النتيجة). توحيدهما هنا يضمن أن أي تعديل مستقبلي بموضع/حجم الأيقونة يصير
/// بمكان واحد فقط.
///
/// قاعدة ثابتة لحجم الأيقونات بكل البوابة (بطلب سليمان 2026-08-07): 22 لكل
/// بطاقة صغيرة/إجراء ضمن شبكة، و28 للبطاقات الرئيسية والعناصر العائمة
/// (كالشارة العائمة لتحميل تطبيق الأندرويد).
const double kPortalCardIconSizeSmall = 22;
const double kPortalCardIconSizeLarge = 28;

/// بطاقة "أيقونة أعلاها + عنوان تحتها" بخلفية صلبة ملوّنة - اعتمدها سليمان
/// صراحةً (2026-08-09) كالحجم/الإخراج الصحيح ("تسكين المقررات الدراسية"،
/// "الجدول الدراسي"، "المنسوبين" كانت أمثلته المرجعية) بعد أن كانت خاصة
/// بـ`admin_workspace_screen.dart` باسم `_QuickActionCard` - وُحِّدت هنا
/// لإعادة استخدامها بأي صفحة أخرى (مثل تبويبات صفحة منسّق القسم) بلا تكرار.
class PortalIconTileCard extends StatelessWidget {
  const PortalIconTileCard({
    super.key,
    required this.icon,
    required this.title,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: kPortalCardIconSizeSmall),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: foreground, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة إحصاء "رقم بارز + بلوك أيقونة ملوّن" - الأيقونة دائمًا يمين البطاقة
/// (بطلب سليمان 2026-08-07) والنص يسارها. تُستخدم لعرض الأرقام/الإحصائيات
/// فقط (لا إجراء عند الضغط).
class PortalStatCard extends StatelessWidget {
  const PortalStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 60,
            height: double.infinity,
            color: accentColor,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: kPortalCardIconSizeLarge),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.greenDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة إجراء (اضغط لتنتقل) موحَّدة - أيقونة يمين + عنوان ووصف مختصر
/// اختياري + سهم اتجاه يسار، داخل تدرّج لوني. تحل محل كل أنماط "بطاقة
/// إجراء" السابقة المتفرّقة (كروت لوحة الإدارة بأيقونة أعلى، كروت التقارير
/// بتدرّج) بقالب واحد ثابت.
class PortalActionCard extends StatelessWidget {
  const PortalActionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: kPortalCardIconSizeSmall),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
