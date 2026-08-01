/// سجل مرشد واحد ضمن قائمة "مرشدي القسم" الرسمية - تُستخدم لتوزيع حالات
/// منسّق القسم أو أي مرشد في إجازة (الحذف والإضافة) على بقية المرشدين خلال
/// فترة الحذف والإضافة (المرشد يبقى رسميًا في نظام الجامعة كما هو - هذا
/// توزيع عملي لعبء المعالجة فقط داخل بوابتنا).
class AdvisorRosterEntry {
  final String id;
  final String name;
  final String department;
  final String shatr;
  final bool isCoordinator;
  final bool isOnLeave;
  final String email;

  const AdvisorRosterEntry({
    required this.id,
    required this.name,
    required this.department,
    required this.shatr,
    required this.isCoordinator,
    this.isOnLeave = false,
    this.email = '',
  });

  factory AdvisorRosterEntry.fromJson(String id, Map<String, dynamic> json) => AdvisorRosterEntry(
    id: id,
    name: (json['name'] ?? '').toString(),
    department: (json['department'] ?? '').toString(),
    shatr: (json['shatr'] ?? '').toString(),
    isCoordinator: json['is_coordinator'] == true,
    isOnLeave: json['is_on_leave'] == true,
    email: (json['email'] ?? '').toString(),
  );
}
