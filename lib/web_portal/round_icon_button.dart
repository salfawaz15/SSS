import 'package:flutter/material.dart';

/// زر دائري موحّد الشكل: خلفية داكنة صلبة بلون الإجراء ورمز أبيض فوقها
/// للوضوح (بدل خلفية فاتحة ورمز ملوّن) - مستخدَم في كل من لوحة الإدارة
/// وشاشة المنسّق حتى تتطابق أزرار الإجراءات (تفريغ/ذوي الإعاقة/تنزيل) بصريًا
/// في كل مكان بالبوابة.
class RoundIconButton extends StatelessWidget {
  final String tooltip;
  final Color color;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const RoundIconButton({
    super.key,
    required this.tooltip,
    required this.color,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.4),
          ),
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(icon, color: Colors.white, size: 20),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// صف أيقونة + نص لعناصر قائمة "المزيد" المنسدلة الموحَّدة (⋮) في شريط
/// أعلى كل شاشات البوابة (إدارة/منسّق/منسّق كلية) - تجمّع كل الإجراءات
/// الثانوية في قائمة واحدة بدل صف طويل من الأيقونات المتناثرة.
class PortalMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const PortalMenuRow({super.key, required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}
