/// سجل طالب واحد من تقرير "بيانات الطلبة الأكاديمية حسب الكلية والقسم"
/// (TAIF_REP260) بعد تحويله من PDF إلى Word ورفعه - المصدر الوحيد لبناء كل
/// حالات متابعة الإرشاد (طالب بلا مرشد، طالب على غير مرشده، توازن التوزيع...).
class AdvisingCaseRecord {
  final String studentId;
  final String studentName;
  final String department; // من عمود "التخصص" في تقارير المنظومة
  final String shatr; // 'شطر الطلاب' أو 'شطر الطالبات'
  final String advisorNameRaw; // كما ورد في تقرير الربط، بلا تطبيع
  final String advisorId; // "رقم المرشد" من تقرير "طلاب تابعين لمرشد" إن وُجد
  final String advisorDepartment; // "قسم المرشد" من نفس التقرير - للمقارنة مع department
  final double? gpa; // المعدل التراكمي من 4 - null إن لم يظهر بعد (مستجد مثلاً)

  /// نوع الحالة الصحية/الإعاقة من تقرير "الحالة الصحية للطلبة" إن وُجد (مثال:
  /// "معاق حركي"، "ضعف بصر شديد") - فارغ يعني لا حالة صحية مسجَّلة لهذا
  /// الطالب. طالب له حالة صحية يجب أن يُسند لأمين القسم (حالات خاصة فقط) لا
  /// لمرشد عادي.
  final String healthCondition;

  /// عمود "الحالة" في تقرير "بيانات الطلبة الأكاديمية" (منتظم/مفصول
  /// أكاديميًا/موقوف...) - حقل مستقل عن [healthCondition] (الذي مصدره تقرير
  /// آخر مختلف تمامًا: "الحالة الصحية للطلبة")، رغم تشابه الاسم، حتى لا
  /// يختلط مفهوم الحالة الدراسية بالحالة الصحية/الإعاقة.
  final String enrollmentStatus;

  /// المعدل من آخر رفعة سابقة قبل هذه (النطاق السابق) - null إن كانت هذه أول
  /// رفعة للطالب (لا يوجد نطاق سابق بعد، يظهر تلقائيًا من الفصل الذي يليه).
  final double? previousGpa;

  /// "ساعات الخطة" من تقرير "بيانات الطلبة الأكاديمية" - إجمالي ساعات خطة
  /// الطالب الدراسية (لا يتغيّر عادةً بين الرفعات). null إن لم تُرفع بيانات
  /// الطلبة الأكاديمية بعد لهذا الطالب.
  final int? planHours;

  /// "الساعات المتبقية" من نفس التقرير - يُحسَب منها [completedHours] تلقائيًا.
  final int? remainingHours;

  const AdvisingCaseRecord({
    required this.studentId,
    required this.studentName,
    required this.department,
    required this.shatr,
    required this.advisorNameRaw,
    this.advisorId = '',
    this.advisorDepartment = '',
    this.gpa,
    this.healthCondition = '',
    this.enrollmentStatus = '',
    this.previousGpa,
    this.planHours,
    this.remainingHours,
  });

  bool get hasAdvisor => advisorNameRaw.trim().isNotEmpty;
  bool get hasHealthCondition => healthCondition.trim().isNotEmpty;

  /// الساعات المجتازة = ساعات الخطة − الساعات المتبقية. null إن لم تتوفر
  /// بيانات الساعات لهذا الطالب بعد.
  int? get completedHours => (planHours != null && remainingHours != null) ? planHours! - remainingHours! : null;

  /// طالب مفصول أكاديميًا - يُستبعَد من كل قوائم متابعة الإرشاد العادية
  /// ويُعرَض في قائمة منفصلة (انظر [AdvisingCaseAnalyzer.analyze]).
  bool get isAcademicallyDismissed => enrollmentStatus.contains('مفصول');

  AdvisingCaseRecord copyWith({
    String? advisorNameRaw,
    String? advisorId,
    String? advisorDepartment,
    double? gpa,
    String? healthCondition,
    double? previousGpa,
    int? planHours,
    int? remainingHours,
  }) =>
      AdvisingCaseRecord(
        studentId: studentId,
        studentName: studentName,
        department: department,
        shatr: shatr,
        advisorNameRaw: advisorNameRaw ?? this.advisorNameRaw,
        advisorId: advisorId ?? this.advisorId,
        advisorDepartment: advisorDepartment ?? this.advisorDepartment,
        gpa: gpa ?? this.gpa,
        healthCondition: healthCondition ?? this.healthCondition,
        enrollmentStatus: enrollmentStatus,
        previousGpa: previousGpa ?? this.previousGpa,
        planHours: planHours ?? this.planHours,
        remainingHours: remainingHours ?? this.remainingHours,
      );

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'studentName': studentName,
        'department': department,
        'shatr': shatr,
        'advisorNameRaw': advisorNameRaw,
        'advisorId': advisorId,
        'advisorDepartment': advisorDepartment,
        'gpa': gpa,
        'healthCondition': healthCondition,
        'enrollmentStatus': enrollmentStatus,
        'previousGpa': previousGpa,
        'planHours': planHours,
        'remainingHours': remainingHours,
      };

  factory AdvisingCaseRecord.fromJson(Map<String, dynamic> json) => AdvisingCaseRecord(
        studentId: json['studentId'] as String? ?? '',
        studentName: json['studentName'] as String? ?? '',
        department: json['department'] as String? ?? '',
        shatr: json['shatr'] as String? ?? '',
        advisorNameRaw: json['advisorNameRaw'] as String? ?? '',
        advisorId: json['advisorId'] as String? ?? '',
        advisorDepartment: json['advisorDepartment'] as String? ?? '',
        gpa: (json['gpa'] as num?)?.toDouble(),
        healthCondition: json['healthCondition'] as String? ?? '',
        enrollmentStatus: json['enrollmentStatus'] as String? ?? '',
        previousGpa: (json['previousGpa'] as num?)?.toDouble(),
        planHours: (json['planHours'] as num?)?.toInt(),
        remainingHours: (json['remainingHours'] as num?)?.toInt(),
      );
}

/// تصنيف حالة الطالب أكاديميًا حسب سلّم لائحة جامعة الطائف (من 4).
enum GpaStatus { excellent, veryGood, good, pass, weak, unknown }

extension GpaStatusX on GpaStatus {
  String get label => switch (this) {
        GpaStatus.excellent => 'ممتاز',
        GpaStatus.veryGood => 'جيد جدًا',
        GpaStatus.good => 'جيد',
        GpaStatus.pass => 'مقبول',
        GpaStatus.weak => 'ضعيف',
        GpaStatus.unknown => '—',
      };

  /// هل تستدعي متابعة خاصة من المرشد (تنبيه)؟
  bool get needsAttention => this == GpaStatus.pass || this == GpaStatus.weak;

  bool get isCritical => this == GpaStatus.weak;
}

GpaStatus gpaStatusOf(double? gpa) {
  if (gpa == null) return GpaStatus.unknown;
  if (gpa >= 3.50) return GpaStatus.excellent;
  if (gpa >= 2.75) return GpaStatus.veryGood;
  if (gpa >= 1.75) return GpaStatus.good;
  if (gpa >= 1.00) return GpaStatus.pass;
  return GpaStatus.weak;
}
