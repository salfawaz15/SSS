/// عضو واحد في تشكيل وحدة الإرشاد الأكاديمي والخريجين - مصدره ورقة عمل
/// مستقلة "تشكيل الوحدة" داخل ملف منسوبي الكلية الرسمي (منفصلة تمامًا عن
/// ورقتَي "منسوبو الكلية"/"الإداريين" حتى لا يتأثر منصب أي منسوب آخر). تُقرأ
/// هذه الورقة وتُخزَّن في مجموعة Firestore عامة القراءة منفصلة، لتغذية صفحة
/// "تواصل معنا" وقسم "أعضاء الوحدة" في الموقع العام تلقائيًا بأحدث تشكيل.
class UnitCommitteeMember {
  final String name;
  final String department;
  final String role;
  final String email;

  const UnitCommitteeMember({
    required this.name,
    required this.department,
    required this.role,
    required this.email,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'department': department,
        'role': role,
        'email': email,
      };

  factory UnitCommitteeMember.fromJson(Map<String, dynamic> json) => UnitCommitteeMember(
        name: json['name'] as String? ?? '',
        department: json['department'] as String? ?? '',
        role: json['role'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}
