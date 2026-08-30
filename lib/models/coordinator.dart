class Coordinator {
  /// اسم قسم اصطناعي (لا يطابق أي قسم علمي حقيقي) لتمييز صفّ منسّق/ة الكلية
  /// ضمن نفس مجموعة `coordinator_contacts` - المستوى الثالث بمسار التصعيد
  /// (مرشد ← منسّق قسم ← منسّق كلية)، يمثّل شطرًا كاملاً لا قسمًا واحدًا.
  static const String collegeMarker = 'الكلية';

  final String shatr;
  final String department;
  final String name;
  final String email;

  const Coordinator({
    required this.shatr,
    required this.department,
    required this.name,
    required this.email,
  });

  String get key => '$shatr|$department';

  Coordinator copyWith({String? name, String? email}) {
    return Coordinator(
      shatr: shatr,
      department: department,
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }

  Map<String, dynamic> toJson() => {
    'shatr': shatr,
    'department': department,
    'name': name,
    'email': email,
  };

  factory Coordinator.fromJson(Map<String, dynamic> json) => Coordinator(
    shatr: json['shatr'] as String? ?? '',
    department: json['department'] as String? ?? '',
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
  );
}
