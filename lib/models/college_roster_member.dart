import '../data/advising_load_rules.dart';

enum CollegeMemberType { faculty, admin }

/// سجل واحد لمنسوب كلية (عضو هيئة تدريس أو إداري) - مصدره ملف
/// "قالب_بيانات_منسوبي_الكلية_الرسمي.xlsx" المعتمد من عمادة الكلية.
/// عبء الإرشاد يُحسب وقت الاستيراد عبر [AdvisingLoadRules] ويُخزَّن جاهزًا
/// (وليس عمودًا في الملف المصدر) - انظر lib/data/advising_load_rules.dart.
class CollegeRosterMember {
  final CollegeMemberType type;
  final String name;
  final String email;
  final String phone;
  final String department;
  final String shatr;
  final String academicRank; // فارغ للإداريين
  final String position;
  final String position2;
  final String position3;

  /// نص حر يوضّح تفاصيل كل منصب معياري (مثال: المنصب "رئيس وحدة" وتوضيحه
  /// "وحدة الإرشاد الأكاديمي والخريجين") - وصفي فقط، لا يدخل في أي حساب
  /// برمجي (الإرشاد/النصاب)، ويُعرض مدمجًا مع المنصب في شاشة عرض المنسوبين.
  final String positionDetail;
  final String position2Detail;
  final String position3Detail;
  final String office;
  final String notes;

  /// عمود "حالة الموظف" الرسمي من ملف الكلية (مثال: "على رأس عمله"، "مبتعث
  /// خارجي"، "معار") - مصدر أوثق من تخمين الاستبعاد من نص المنصب وحده،
  /// يُدمَج مع نص المنصب عند التصنيف (انظر fromRaw أدناه).
  final String employeeStatus;
  final AdvisingLoad advisingLoad;
  final int? reducedToPercent;
  final String advisingReason;

  /// رقم المنسوب (رقم التوظيف) كما تكتبه العمادة - يُستخدم فقط للفصل بين
  /// عضوين من نفس الدرجة العلمية عند الترتيب (الأقدم/الأصغر رقمًا أولاً) -
  /// انظر lib/data/faculty_sort_order.dart.
  final String staffNumber;

  /// نص حر تكتبه العمادة صراحةً في عمود "نصاب الإرشاد" (سابقًا "ملاحظات
  /// تخفيض النصاب") - تصنيف عبء الإرشاد صراحةً (معفى/حالات خاصة/نسبة)، وهو
  /// **المرجع الحاسم الأول** لعبء الإرشاد قبل أي استنتاج من نص المنصب -
  /// انظر lib/data/advising_load_rules.dart. لا علاقة له بالنصاب التدريسي
  /// (انظر [teachingLoadHours] أدناه، حقل مستقل تمامًا لذلك الغرض).
  final String quotaReductionNote;

  /// النصاب التدريسي الفعلي المحسوب مسبقًا من العمادة نفسها في عمود "نصاب
  /// عضو هيئة التدريس" - **المرجع الحاسم الأول** للنصاب التدريسي، يتغلّب
  /// على أي استنتاج تلقائي من المنصب/الدرجة العلمية (lib/data/teaching_load_
  /// regulation.dart)، لأن قرار العمادة قد يخالف القاعدة العامة لحالات
  /// خاصة (مثال: عضو بمنصب "نائب رئيس وحدة" لكن نصابه الفعلي المعتمد لم
  /// يُخفَّض). null إن كان العمود فارغًا أو غير موجود في الملف المرفوع
  /// (بيانات قديمة قبل إضافة هذا العمود) - يُستكمَل حينها بالاستنتاج القديم.
  final int? teachingLoadHours;

  const CollegeRosterMember({
    required this.type,
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    required this.shatr,
    required this.academicRank,
    required this.position,
    required this.position2,
    required this.position3,
    this.positionDetail = '',
    this.position2Detail = '',
    this.position3Detail = '',
    required this.office,
    required this.notes,
    this.employeeStatus = '',
    required this.advisingLoad,
    required this.reducedToPercent,
    required this.advisingReason,
    required this.quotaReductionNote,
    this.teachingLoadHours,
    required this.staffNumber,
  });

  factory CollegeRosterMember.fromRaw({
    required CollegeMemberType type,
    required String name,
    required String email,
    required String phone,
    required String department,
    required String shatr,
    String academicRank = '',
    required String position,
    required String position2,
    required String position3,
    String positionDetail = '',
    String position2Detail = '',
    String position3Detail = '',
    required String office,
    required String notes,
    String employeeStatus = '',
    String quotaReductionNote = '',
    int? teachingLoadHours,
    String staffNumber = '',
  }) {
    // حالة الموظف تُدمَج مع نص المنصب عند التصنيف - "مبتعث خارجي"/"معار"
    // في عمود حالة الموظف يُعفي بنفس قوة ذكرها داخل عمود المنصب نفسه.
    final combined =
        [position, position2, position3, employeeStatus].where((p) => p.isNotEmpty).join('، ');
    final result = AdvisingLoadRules.classify(combined, advisingNote: quotaReductionNote, ownDepartment: department);
    return CollegeRosterMember(
      type: type,
      name: name,
      email: email,
      phone: phone,
      department: department,
      shatr: shatr,
      academicRank: academicRank,
      position: position,
      position2: position2,
      position3: position3,
      positionDetail: positionDetail,
      position2Detail: position2Detail,
      position3Detail: position3Detail,
      office: office,
      notes: notes,
      employeeStatus: employeeStatus,
      advisingLoad: result.load,
      reducedToPercent: result.reducedToPercent,
      advisingReason: result.reason,
      quotaReductionNote: quotaReductionNote,
      teachingLoadHours: teachingLoadHours,
      staffNumber: staffNumber,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'name': name,
        'email': email,
        'phone': phone,
        'department': department,
        'shatr': shatr,
        'academicRank': academicRank,
        'position': position,
        'position2': position2,
        'position3': position3,
        'positionDetail': positionDetail,
        'position2Detail': position2Detail,
        'position3Detail': position3Detail,
        'office': office,
        'notes': notes,
        'employeeStatus': employeeStatus,
        'advisingLoad': advisingLoad.name,
        'reducedToPercent': reducedToPercent,
        'advisingReason': advisingReason,
        'quotaReductionNote': quotaReductionNote,
        'teachingLoadHours': teachingLoadHours,
        'staffNumber': staffNumber,
      };

  factory CollegeRosterMember.fromJson(Map<String, dynamic> json) => CollegeRosterMember(
        type: CollegeMemberType.values.firstWhere((t) => t.name == json['type']),
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        department: json['department'] as String? ?? '',
        shatr: json['shatr'] as String? ?? '',
        academicRank: json['academicRank'] as String? ?? '',
        position: json['position'] as String? ?? '',
        position2: json['position2'] as String? ?? '',
        position3: json['position3'] as String? ?? '',
        positionDetail: json['positionDetail'] as String? ?? '',
        position2Detail: json['position2Detail'] as String? ?? '',
        position3Detail: json['position3Detail'] as String? ?? '',
        office: json['office'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        employeeStatus: json['employeeStatus'] as String? ?? '',
        advisingLoad: AdvisingLoad.values.firstWhere((l) => l.name == json['advisingLoad']),
        reducedToPercent: json['reducedToPercent'] as int?,
        advisingReason: json['advisingReason'] as String? ?? '',
        quotaReductionNote: json['quotaReductionNote'] as String? ?? '',
        teachingLoadHours: json['teachingLoadHours'] as int?,
        staffNumber: json['staffNumber'] as String? ?? '',
      );
}
