/// أرقام مكاتب أعضاء هيئة التدريس - مصدرها ملف "جدول الإرشاد الأكاديمي"
/// (توزيع فترات الإرشاد)، وهو المصدر الوحيد المتوفر حاليًا لرقم المكتب.
/// يغطّي حاليًا فقط الأعضاء الذين ظهرت أسماؤهم في ذلك الجدول كمرشدين
/// أكاديميين؛ أي عضو آخر يبقى رقم مكتبه فارغًا حتى تتوفر بيانات إضافية.
///
/// المطابقة تتم عبر أجزاء مميّزة من الاسم (وليس الاسم الكامل بالضبط) لأن
/// الاسم في جدول الإرشاد مختصر (مثل "د. نواف الحميدي") بينما الاسم الكامل
/// في ملفات الجدول الدراسي أطول (مثل "نواف محسن عايض الحميدى").
class InstructorOffices {
  static const List<_OfficeEntry> _entries = [
    _OfficeEntry(['نواف', 'الحميدي'], '48'),
    _OfficeEntry(['محمد', 'الرفاعي'], 'مبنى 5000'),
    _OfficeEntry(['فهد', 'السعدي'], '51'),
    _OfficeEntry(['زياد', 'المطيري'], '59'),
    _OfficeEntry(['طارق', 'حلمي'], '50'),
    _OfficeEntry(['هتان', 'الشريف'], '58'),
    _OfficeEntry(['سليمان', 'الفواز'], '56'),
  ];

  static String? lookup(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return null;
    final normalized = _normalize(fullName);
    for (final entry in _entries) {
      if (entry.fragments.every((f) => normalized.contains(_normalize(f)))) {
        return entry.office;
      }
    }
    return null;
  }

  static String _normalize(String s) => s
      .replaceAll('ى', 'ي')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .trim();
}

class _OfficeEntry {
  final List<String> fragments;
  final String office;

  const _OfficeEntry(this.fragments, this.office);
}
