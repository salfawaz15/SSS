import 'package:flutter/material.dart';

import 'app_theme.dart';

/// شريحة "الكل" (إعادة تعيين كل الفلاتر دفعة واحدة) - الهوية الموحَّدة
/// لكل فلاتر الموقع (سليمان 2026-08-22: "يجب أن تكون في أي مكان فيه فلتر
/// مهما كان"). مرجع مشترك بدل تكرار نفس التعريف الخاص (private) بكل ملف.
class FilterResetChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const FilterResetChip({super.key, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: active ? AppColors.greenDark : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
        child: Text('الكل', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700)),
      ),
    );
  }
}

/// شريحة فلتر دائرية (قائمة منسدلة داخل شريحة خضراء داكنة عند التفعيل،
/// رمادية فاتحة عند عدمه) - الهوية الموحَّدة لكل فلاتر الموقع.
class FilterPillDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const FilterPillDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: active ? AppColors.greenDark : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isDense: true,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700),
          icon: Icon(Icons.expand_more, size: 16, color: active ? Colors.white : Colors.grey.shade600),
          dropdownColor: Colors.white,
          // نص الشريحة المغلقة أبيض دائمًا عند التفعيل (خلفية خضراء داكنة) -
          // بلا selectedItemBuilder يظهر لون العنصر الثابت (أسود) فوق الخلفية
          // الداكنة فيصبح غير مقروء (سليمان لاحظه فعليًا 2026-08-22).
          selectedItemBuilder: (context) => [
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 10.5)),
            for (final item in items)
              Text(itemLabel(item), style: TextStyle(color: active ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 10.5)),
          ],
          items: [
            DropdownMenuItem(value: null, child: Text(label, style: const TextStyle(color: Colors.black87))),
            for (final item in items) DropdownMenuItem(value: item, child: Text(itemLabel(item), style: const TextStyle(color: Colors.black87))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// حاوية شريط الفلتر الموحَّدة (صندوق أبيض بحدّ رمادي خفيف) - تُغلِّف
/// [FilterResetChip] وشرائح [FilterPillDropdown] معًا.
class FilterBarShell extends StatelessWidget {
  final List<Widget> children;
  const FilterBarShell({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
