import '../data/academic_department_names.dart';
import '../models/college_roster_member.dart';
import 'advisor_name_matching.dart';

/// حالات انتداب حقيقية موثَّقة صراحةً (سليمان): مسجَّلتان/مسجَّل رسميًا بقسم
/// بملف منسوبي الكلية لكن يعملان فعليًا بقسم آخر - القسم الفعلي هنا يتغلّب
/// دائمًا على القسم الرسمي بالملف عند تحديد "أي قسم يخص ملف/تقرير هذا العضو".
const knownSecondments = {
  'حنان عامر': 'قسم الاقتصاد و التمويل',
  'طارق حلمي': 'قسم نظم المعلومات الادارية',
};

/// يحدّد القسم الحقيقي (الفعلي، لا الرسمي بالضرورة) لمرشد بالاسم: أولوية
/// لحالات الانتداب الموثَّقة صراحةً، ثم ملف منسوبي الكلية الرسمي (المصدر
/// الشامل والموثوق لبقية الحالات) - يُستخدم بدل الاعتماد على قسم الطالب
/// المذكور بالتذكرة نفسها عند تحديد "أي قسم يخص ملف/تقرير هذا المرشد
/// تحديدًا"، لأن قسم الطالب قد يخالف قسم مرشده الفعلي (خطأ إدخال بنموذج
/// Microsoft Forms أو إشراف عابر للأقسام) - سليمان صراحةً (2026-08-31): حالات
/// مؤكَّدة (عدنان يعقوب، براء الحازمي، زكية العوفي) كل واحد منها له تذكرة
/// واحدة شاردة بقسم غير قسمه الحقيقي، فكانت ملفاته الفعلية (لا فقط التقرير)
/// تذهب لمنسّق قسم لا علاقة له به - هذا يُصحَّح جذريًا هنا مرة واحدة لكل
/// الاستخدامات (توزيع ملفات المرشدين وتقرير الأعضاء المقصّرين معًا).
String? resolveAdvisorDepartment(String advisorName, List<CollegeRosterMember> collegeRoster) {
  final trimmed = advisorName.trim();
  if (trimmed.isEmpty) return null;
  final normalized = normalizeAdvisorNameForMatch(trimmed);
  for (final entry in knownSecondments.entries) {
    if (normalized.contains(normalizeAdvisorNameForMatch(entry.key))) {
      return entry.value;
    }
  }
  for (final m in collegeRoster) {
    if (normalizeAdvisorNameForMatch(m.name) == normalized) {
      return m.department;
    }
  }
  return null;
}

/// يعيد تجميع التذاكر حسب "شطر|قسم المرشد الحقيقي" (لا قسم الطالب بالتذكرة
/// نفسها) - لأغراض توزيع ملف/تقرير كل مرشد على قسمه الصحيح فقط؛ الاستخدامات
/// الأخرى بالموقع (إحصاءات الطلاب، ذوي الإعاقة، تصعيد المنسّق) تبقى بقسم
/// الطالب كما هي لأنها تخص القسم كصاحب الحالة إجرائيًا لا المرشد شخصيًا.
/// عند تعذّر تحديد قسم المرشد الحقيقي (غير موجود بملف منسوبي الكلية) تبقى
/// التذكرة بقسم الطالب كما هي (أفضل تقدير متاح، بلا فقدان أي حالة).
Map<String, List<Map<String, dynamic>>> groupTicketsByAdvisorRealDepartment(
  List<Map<String, dynamic>> tickets,
  List<CollegeRosterMember> collegeRoster,
) {
  final canonicalToRawDept = <String, String>{};
  for (final t in tickets) {
    final raw = (t['department'] ?? '').toString();
    if (raw.isEmpty) continue;
    canonicalToRawDept.putIfAbsent(normalizeDepartmentName(raw), () => raw);
  }
  final result = <String, List<Map<String, dynamic>>>{};
  for (final t in tickets) {
    final shatr = (t['shatr'] ?? '').toString();
    final ticketDepartment = (t['department'] ?? '').toString();
    final advisor = (t['advisor'] ?? '').toString();
    final resolved = resolveAdvisorDepartment(advisor, collegeRoster);
    final department = resolved == null
        ? ticketDepartment
        : (canonicalToRawDept[normalizeDepartmentName(resolved)] ?? ticketDepartment);
    result.putIfAbsent('$shatr|$department', () => []).add(t);
  }
  return result;
}
