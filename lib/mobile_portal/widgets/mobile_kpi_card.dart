import 'package:flutter/material.dart';

import '../theme/portal_theme.dart';

/// بطاقة مؤشر رئيسي واحد (KPI) - تخطيط أفقي مضغوط (أيقونة مربَّعة ملوَّنة
/// بخلفية صلبة + رقم + تسمية + ملاحظة اختيارية) بنفس نمط بطاقات الموقع
/// (`PortalStatCard`)، بدل تكديس رأسي كان يجعل الشبكة طويلة جدًا ويحتاج
/// تمريرًا (سليمان 2026-08-23: "حجمها كبير جدًا... لا بد من التمرير").
/// `highlighted`: حدّ مميَّز (بطاقة "الكل"/"إجمالي الحالات" بنهاية كل صف).
class MobileKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final IconData icon;
  final Color accentColor;
  final bool highlighted;

  const MobileKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.note,
    required this.icon,
    this.accentColor = AppColors.green,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: highlighted ? AppColors.greenDark : Colors.grey.shade200, width: highlighted ? 1.6 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: AppTextStyles.h1(color: AppColors.greenDark).copyWith(fontSize: 22),
                ),
                Text(
                  label,
                  style: AppTextStyles.caption(color: Colors.black54).copyWith(fontSize: 11.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (note != null)
                  Text(
                    note!,
                    style: AppTextStyles.caption(color: Colors.black38).copyWith(fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }
}
