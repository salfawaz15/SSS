import '../services/excel_parser_service.dart';

/// يربط بين (الشطر، القسم) الظاهرين للمستخدم وبين حسابات Firebase Auth
/// الداخلية الثابتة المُنشأة مسبقًا لكل قسم (11 حساب: إدارة + 10 أقسام).
class PortalAccounts {
  static const String domain = 'sss-advising-tu.internal';
  static const String adminEmail = 'admin@$domain';

  /// حساب المدير العام (صلاحيات كاملة مطابقة لحساب الإدارة تمامًا) - حساب
  /// إضافي شخصي بصلاحيات كاملة على البوابة.
  static const String superAdminEmail = 'salfawaz@$domain';

  /// حساب "منسّق الوحدة" - دور تقني جاهز بانتظار القرار الرسمي، بلا ربطه
  /// بأي شخص فعلي بعد. بريد ثابت واحد فقط (لا تفريع شطر/قسم مثل منسّقي
  /// الأقسام) لأن صلاحياته تقتصر على رفع الملفات فقط عبر شاشة واحدة مخصَّصة
  /// (انظر UnitCoordinatorWorkspaceScreen)، بلا أي عرض تقارير أو بيانات.
  static const String unitCoordinatorEmail = 'unit-coordinator@$domain';

  static bool isUnitCoordinator(String? email) => email == unitCoordinatorEmail;

  /// حسابا عرض التقارير فقط (بلا صلاحية رفع/تنزيل ملفات الأقسام) - تابعان
  /// لدخول الإدارة لكن بصلاحيات أقل (استطلاع وطباعة التقارير حصرًا).
  static const Map<String, String> viewerEmails = {
    'أمين الوحدة': 'ameen@$domain',
    'سكرتير الوحدة': 'secretary@$domain',
  };

  /// كل خيارات "دخول الإدارة" الظاهرة في قائمة الدخول العادية (الصلاحية
  /// الكاملة + صلاحيات العرض فقط + منسّق الوحدة) - حساب المدير العام
  /// (salfawaz) غير مُدرَج هنا عمدًا؛ له صفحة دخول مخفية منفصلة (انظر
  /// hidden_admin_login_screen.dart). ترتيب هرمي: منسّق الوحدة (دور إداري
  /// بصلاحية رفع ملفات فقط) يأتي بعد أمين الوحدة (دور أكاديمي) لا قبله -
  /// لا يمكن أن يكون الإداري أعلى من الأكاديمي بالترتيب (سليمان).
  static Map<String, String> get adminRoleEmails => {
    'إدارة وحدة الإرشاد الأكاديمي': adminEmail,
    'أمين الوحدة': viewerEmails['أمين الوحدة']!,
    'منسّق الوحدة': unitCoordinatorEmail,
    'سكرتير الوحدة': viewerEmails['سكرتير الوحدة']!,
  };

  /// صلاحيات كاملة (إدارة + المدير العام) بنفس المستوى تمامًا.
  static bool isFullAdmin(String? email) => email == adminEmail || email == superAdminEmail;

  /// حسابا منسّق/ة الكلية (المستوى الثالث في مسار التصعيد، بعد المرشد
  /// ومنسّق القسم) - يريان كل أقسام شطرهما مجتمعة، لا قسمًا واحدًا. حسابان
  /// فعليّان: عادل علي محمد حسن (شطر الطلاب)، هبة الله عبدالصبور أمين حسن
  /// (شطر الطالبات - منصب منفصل تمامًا عن كونها أمينة قسم التسويق).
  static Map<String, String> get collegeCoordinatorEmails => {
    ExcelParserService.shatrMale: 'college-coordinator-male@$domain',
    ExcelParserService.shatrFemale: 'college-coordinator-female@$domain',
  };

  static bool isCollegeCoordinator(String? email) =>
      collegeCoordinatorEmails.values.contains(email);

  static const Map<String, String> _departmentKeys = {
    'قسم الادارة': 'idara',
    'قسم المحاسبة': 'accounting',
    'قسم التسويق': 'marketing',
    'قسم الاقتصاد و التمويل': 'economy',
    'قسم نظم المعلومات الادارية': 'mis',
  };

  static const Map<String, String> _shatrKeys = {
    ExcelParserService.shatrMale: 'male',
    ExcelParserService.shatrFemale: 'female',
  };

  /// يحوّل (الشطر، القسم) إلى البريد الداخلي الثابت المطابق، أو null إن لم يُعرَف.
  static String? coordinatorEmail(String shatr, String department) {
    final deptKey = _departmentKeys[department];
    final shatrKey = _shatrKeys[shatr];
    if (deptKey == null || shatrKey == null) return null;
    return '$deptKey-$shatrKey@$domain';
  }
}
