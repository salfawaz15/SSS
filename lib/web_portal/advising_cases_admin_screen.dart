import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/advising_case_record.dart';
import '../models/college_roster_member.dart';
import '../services/advising_case_analyzer.dart';
import '../services/advising_case_excel_service.dart';
import '../services/advising_case_pdf_service.dart';
import '../services/advising_report_repository.dart';
import '../services/advisor_movement_repository.dart';
import '../services/web_download.dart';
import '../services/course_schedule_repository.dart' show Shatr, ShatrLabel;
import '../theme/app_theme.dart';
import '../theme/dashboard_tokens.dart';
import '../theme/filter_pills.dart';
import '../utils/name_display.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';
import 'upload_dialogs.dart';

const String _kAllShatr = 'كل الشطرين';
const String _kAllDepartments = 'كل الأقسام';
const String _kAllAdvisors = 'كل المرشدين';

/// حد أقصى للصفوف المعروضة فعليًا داخل أي `DataTable` بهذه الشاشة - يُبنى
/// **كل** صفوفه دفعة واحدة قبل الرسم (لا تحميل كسول)، فتجمّد الصفحة فعليًا
/// (لاحظه سليمان 2026-08-14) لو تجاوز عدد الصفوف بضعة آلاف - كما يحدث الآن
/// مع "طلاب على مرشدهم" لملف "كل الكليات" (الجامعة كاملة). التصدير (Excel/
/// PDF) يبقى **بلا أي حد** - يشمل كل السجلات دومًا، هذا الحد للعرض المرئي فقط.
const int _kMaxTableRows = 300;

/// صفحة "متابعة حالات الإرشاد" - قلب مشروع وحدة الإرشاد الأكاديمي.
///
/// أُعيدت هيكلتها (2026-08-14) بطلب سليمان صراحةً: "بيانات الطلبة الأكاديمية"
/// (المعدل/الساعات) يصعب الحصول عليها حاليًا خلال فترة الحذف والإضافة، فجُمِّد
/// رفعها من هذه الشاشة مؤقتًا (تبقى الخدمات/البيانات القديمة في المشروع بلا
/// حذف، لحين توفّر الملف). الأولوية الآن: توزيع الطلبة على المرشدين، عبر ملف
/// أسبوعي واحد "كل الكليات" (تقرير "طلاب تابعين لمرشد" الرسمي **غير مفلتَر**
/// لكليتنا، يشمل الجامعة كاملة) + ملف ثانٍ لذوي الإعاقة - أيقونتا رفع فقط.
/// انظر [AdvisingCaseAnalyzer.classifyAllColleges] للتصنيفات الأربعة الجديدة
/// و[AdvisingCaseAnalyzer.detectAdvisorMovements] لتقرير "حركات الإرشاد".
class AdvisingCasesAdminScreen extends StatefulWidget {
  const AdvisingCasesAdminScreen({super.key});

  @override
  State<AdvisingCasesAdminScreen> createState() => _AdvisingCasesAdminScreenState();
}

class _UploadSlot {
  List<AdvisingCaseRecord> male = [];
  List<AdvisingCaseRecord> female = [];
  DateTime? maleDate;
  DateTime? femaleDate;
  bool uploading = false;
}

class _AdvisingCasesAdminScreenState extends State<AdvisingCasesAdminScreen> {
  // 12 قسمًا منطقيًا - كانت أشرطة تبويب أفقية (TabBar) تفيض عن عرض الشاشة
  // بمظهر غير احترافي كما لاحظ سليمان صراحةً (2026-08-14)؛ استُبدلت بقائمة
  // منسدلة واحدة ("عرض") توضع أول الفلاتر (قبل "الشطر") بنفس تصميم بقية
  // فلاتر الشريط - أخف بصريًا وقابلة للتوسّع مستقبلاً بلا فيضان أفقي.
  int _sectionIndex = 0;
  final _allColleges = _UploadSlot();
  final _health = _UploadSlot();

  // نتاج AdvisingCaseAnalyzer.loadCollegeScopedStudents - تُخزَّن هنا بعد كل
  // تحميل بدل استدعائها مباشرة بالـbuild.
  List<AdvisingCaseRecord> _scopedMale = [];
  List<AdvisingCaseRecord> _scopedFemale = [];
  List<AdvisingCaseRecord> _allCollegesMaleRaw = [];
  List<AdvisingCaseRecord> _allCollegesFemaleRaw = [];
  List<AdvisingCaseRecord> _academicMaleRaw = [];
  List<AdvisingCaseRecord> _academicFemaleRaw = [];

  // سجل حركات الإرشاد الدائم/التراكمي (كل الرفعات، لا آخر رفعتين فقط) - انظر
  // [AdvisorMovementRepository].
  List<AdvisorMovementLogEntry> _movementsLog = [];

  Map<String, CollegeRosterMember> _facultyByKey = {};
  List<String> _departments = [];

  bool _loading = true;

  String _shatrFilter = _kAllShatr;
  String _deptFilter = _kAllDepartments;
  String _advisorFilter = _kAllAdvisors;
  final _studentSearchCtrl = TextEditingController();
  final _advisorSearchCtrl = TextEditingController();

  @override
  void dispose() {
    _studentSearchCtrl.dispose();
    _advisorSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.health),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.health),
      ]);
      final loaded = await AdvisingCaseAnalyzer.loadCollegeScopedStudents();
      final movements = await AdvisorMovementRepository.loadAll();
      if (!mounted) return;
      setState(() {
        _allColleges.maleDate = results[0];
        _allColleges.femaleDate = results[1];
        _health.maleDate = results[2];
        _health.femaleDate = results[3];
        _scopedMale = loaded.male;
        _scopedFemale = loaded.female;
        _allCollegesMaleRaw = loaded.allCollegesMaleRaw;
        _allCollegesFemaleRaw = loaded.allCollegesFemaleRaw;
        _academicMaleRaw = loaded.academicMaleRaw;
        _academicFemaleRaw = loaded.academicFemaleRaw;
        _movementsLog = movements;
        _facultyByKey = loaded.facultyByKey;
        // فلتر القسم هنا لفرز الطلاب حسب قسمهم العلمي فقط - لا معنى لظهور
        // جهات الإداريين (مكتب العميد، مركز الخدمات...) بينها، فالطلاب لا
        // ينتمون لأي منها أصلاً.
        _departments = _facultyByKey.values
            .where((m) => m.type == CollegeMemberType.faculty)
            .map((m) => m.department)
            .toSet()
            .toList()
          ..sort();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحميل بيانات الصفحة: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// أسماء المرشدين المرشَّحة لقائمة الفلترة - **كل مرشد موجود فعليًا بقاعدة
  /// البيانات (ملف "كل الكليات")، حتى لو كان من خارج كليتنا تمامًا** - بطلب
  /// سليمان الصريح (2026-08-14): "خانة المرشد فيها بحث على أي مرشد موجود في
  /// قاعدة البيانات حتى لو كان من خارج الكلية". كانت مقصورة سابقًا على من
  /// يطابق اسمه عضوًا بملف منسوبي الكلية فقط، فتعذّر الفلترة على مرشدين
  /// ظاهرين بتبويبي "مرشد خارجي ← طلابنا"/"مرشدنا ← طلاب خارجيون" تحديدًا
  /// (هم بالتعريف من خارج ملف منسوبينا). تُبنى من السجلات الخام غير
  /// المفلتَرة (`_allCollegesMaleRaw`/`_allCollegesFemaleRaw`) لا المفلتَرة
  /// لكليتنا فقط، مع إبقاء ربطها بفلتر القسم/الشطر كسابقًا.
  List<String> get _advisorFilterOptions {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _allCollegesMaleRaw;
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _allCollegesFemaleRaw;
    final names = [...male, ...female]
        .where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter)
        .map((s) => s.advisorNameRaw.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return names;
  }

  static int _shatrOrder(String shatr) => shatr == Shatr.male.label ? 0 : 1;

  static const List<String> _departmentDisplayOrder = [
    'قسم الادارة',
    'قسم المحاسبة',
    'قسم التسويق',
    'قسم الاقتصاد و التمويل',
    'قسم نظم المعلومات الادارية',
  ];

  static int _departmentOrder(String department) {
    final i = _departmentDisplayOrder.indexOf(department);
    return i == -1 ? _departmentDisplayOrder.length : i;
  }

  /// التحليل (نصاب/توازن/إعادة توزيع/مرشدون معفَون...) يُبنى من سجلات كليتنا
  /// المفلتَرة (`_scopedMale`/`_scopedFemale`) - **بلا أي تغيير جوهري** بمنطق
  /// [AdvisingCaseAnalyzer.analyze] نفسه، فقط تغيّر مصدر تغذيته.
  AdvisingCaseAnalysis get _analysis {
    final male = _shatrFilter == Shatr.female.label
        ? const <AdvisingCaseRecord>[]
        : _scopedMale.where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter).toList();
    final female = _shatrFilter == Shatr.male.label
        ? const <AdvisingCaseRecord>[]
        : _scopedFemale.where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter).toList();

    final a = AdvisingCaseAnalyzer.analyze(students: male, facultyByNameKey: _facultyByKey);
    final b = AdvisingCaseAnalyzer.analyze(students: female, facultyByNameKey: _facultyByKey);

    // ترتيب موحَّد حسب الشطر أولاً ثم القسم - كما طُلب صراحةً - على كل قوائم
    // التحليل، وليس فقط جدول الطلاب. مقارنة مركّبة (شطر ثم قسم) بدل الاعتماد
    // على استقرار الترتيب، لأن الدمج بين قائمتي الشطرين لا يضمن تجميعهما.
    int cmp(String shatrX, String deptX, String shatrY, String deptY) {
      final c = _shatrOrder(shatrX).compareTo(_shatrOrder(shatrY));
      return c != 0 ? c : _departmentOrder(deptX).compareTo(_departmentOrder(deptY));
    }

    // حالات النطاق (المعدل) تحديدًا تُرتَّب بمستوى ثالث إضافي: العضو
    // (المرشد) - حسب الشطر ثم القسم ثم اسم المرشد - كما طُلب صراحةً.
    int cmpWithMember(String shatrX, String deptX, String memberX, String shatrY, String deptY, String memberY) {
      final c = cmp(shatrX, deptX, shatrY, deptY);
      return c != 0 ? c : memberX.compareTo(memberY);
    }

    return AdvisingCaseAnalysis(
      studentsCorrectlyAssigned: [...a.studentsCorrectlyAssigned, ...b.studentsCorrectlyAssigned]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      studentsWithoutAdvisor: [...a.studentsWithoutAdvisor, ...b.studentsWithoutAdvisor]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      studentsWithWrongDeptAdvisor: [...a.studentsWithWrongDeptAdvisor, ...b.studentsWithWrongDeptAdvisor]
        ..sort((x, y) => cmpWithMember(x.student.shatr, x.student.department, x.student.advisorNameRaw,
            y.student.shatr, y.student.department, y.student.advisorNameRaw)),
      exemptAdvisorsWithStudents: [...a.exemptAdvisorsWithStudents, ...b.exemptAdvisorsWithStudents]
        ..sort((x, y) => cmp(x.advisor.shatr, x.advisor.department, y.advisor.shatr, y.advisor.department)),
      advisorsWithNoStudents: [...a.advisorsWithNoStudents, ...b.advisorsWithNoStudents]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      overloadedAdvisors: [...a.overloadedAdvisors, ...b.overloadedAdvisors]
        ..sort((x, y) => cmp(x.advisor.shatr, x.advisor.department, y.advisor.shatr, y.advisor.department)),
      quotaReport: [...a.quotaReport, ...b.quotaReport]
        ..sort((x, y) => cmp(x.advisor.shatr, x.advisor.department, y.advisor.shatr, y.advisor.department)),
      atRiskStudents: [...a.atRiskStudents, ...b.atRiskStudents]
        ..sort((x, y) => cmpWithMember(
            x.shatr, x.department, x.advisorNameRaw, y.shatr, y.department, y.advisorNameRaw)),
      dismissedStudents: [...a.dismissedStudents, ...b.dismissedStudents]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      exemptAdvisorsNoIssue: [...a.exemptAdvisorsNoIssue, ...b.exemptAdvisorsNoIssue]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      transferSuggestions: [...a.transferSuggestions, ...b.transferSuggestions]
        ..sort((x, y) => cmp(x.student.shatr, x.student.department, y.student.shatr, y.student.department)),
      healthCasesNotWithAmin: [...a.healthCasesNotWithAmin, ...b.healthCasesNotWithAmin]
        ..sort((x, y) => cmp(x.student.shatr, x.student.department, y.student.shatr, y.student.department)),
      healthCaseStudents: [...a.healthCaseStudents, ...b.healthCaseStudents]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      healthCasesWithAmin: [...a.healthCasesWithAmin, ...b.healthCasesWithAmin]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
      advisorStatistics: [...a.advisorStatistics, ...b.advisorStatistics]
        ..sort((x, y) => cmp(x.shatr, x.department, y.shatr, y.department)),
    );
  }

  /// التصنيفات الأربعة الجديدة (على مرشدهم/على غير مرشدهم/مرشد خارجي لطالب
  /// داخلي/مرشد داخلي لطالب خارجي) - من السجلات الخام غير المفلتَرة (كل
  /// الكليات) حتى تظهر حالات المرشدين من خارج كليتنا، بخلاف [_analysis] الذي
  /// يُبنى من السجلات المفلتَرة لكليتنا فقط.
  CollegeAdvisingClassification get _classification {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _allCollegesMaleRaw;
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _allCollegesFemaleRaw;
    final academicMale = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _academicMaleRaw;
    final academicFemale = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _academicFemaleRaw;
    final c = AdvisingCaseAnalyzer.classifyAllColleges(
      academicRecords: [...academicMale, ...academicFemale],
      allCollegeRecords: [...male, ...female],
      facultyByNameKey: _facultyByKey,
    );

    // ترتيب موحَّد حسب الشطر ثم اسم الطالب - كانت هذه القوائم الأربع (خلافًا
    // لبقية جداول الشاشة) تُعرَض بترتيب الملف الخام بلا أي فرز، فيظهر الرقم
    // الجامعي عشوائيًا كما رصد سليمان (2026-08-14).
    int cmp(String shatrX, String nameX, String shatrY, String nameY) {
      final s = _shatrOrder(shatrX).compareTo(_shatrOrder(shatrY));
      return s != 0 ? s : nameX.compareTo(nameY);
    }

    return CollegeAdvisingClassification(
      studentsCorrectlyAssigned: [...c.studentsCorrectlyAssigned]
        ..sort((x, y) => cmp(x.shatr, x.studentName, y.shatr, y.studentName)),
      studentsWithWrongDeptAdvisor: [...c.studentsWithWrongDeptAdvisor]
        ..sort((x, y) => cmp(x.student.shatr, x.student.studentName, y.student.shatr, y.student.studentName)),
      externalAdvisorsWithOurStudents: [...c.externalAdvisorsWithOurStudents]
        ..sort((x, y) => cmp(x.shatr, x.studentName, y.shatr, y.studentName)),
      ourAdvisorsWithExternalStudents: [...c.ourAdvisorsWithExternalStudents]
        ..sort((x, y) => cmp(x.shatr, x.studentName, y.shatr, y.studentName)),
      studentsWithoutAdvisor: [...c.studentsWithoutAdvisor]
        ..sort((x, y) => cmp(x.shatr, x.studentName, y.shatr, y.studentName)),
      dismissedStudents: c.dismissedStudents,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ترتيب وتسميات التبويبات بالضبط كما حدَّدها سليمان صراحةً (2026-08-15).
    final tabs = <(String, Widget Function())>[
      ('الكل', _tabAllStudents),
      ('طلبة تابعين لمرشد', _tabCorrectlyAssigned),
      ('طلبة تابعين لمرشد – ذوي الإعاقة', _tabHealthCases),
      ('طلبة بلا مرشد', _tabWithoutAdvisor),
      ('طلبة على غير مرشدهم', _tabWrongAdvisor),
      ('طلبة على غير مرشدهم – ذوي الإعاقة', _tabHealthMismatch),
      ('مرشدون خارج الكلية ← طلابنا', _tabExternalAdvisors),
      ('مرشدون داخل الكلية ← طلاب خارج الكلية', _tabExternalStudents),
      ('مرشدون معفون ولهم نصاب', _tabExemptWithStudents),
      ('مرشدون بلا نصاب', _tabAdvisorsNoStudents),
      ('تقرير نصاب الإرشاد', _tabQuota),
      ('خطة إعادة التوزيع العادل', _tabTransfer),
      ('إحصائيات الإرشاد', _tabAdvisorStatistics),
      ('حركات الإرشاد', _tabMovements),
      ('الطلبة المستجدون', _tabNewStudents),
    ];
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'متابعة حالات الإرشاد',
      navItems: buildAdminNavItems(context, current: 'advising-cases'),
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.cases, isSuperAdmin: isSuperAdmin),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildCompactHeader(),
                                const SizedBox(height: 10),
                                _buildStatsGrid(tabs),
                                const SizedBox(height: 10),
                                _buildFilterBar(),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              children: [tabs[_sectionIndex].$2()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// تفريغ سجل "حركات الإرشاد" التراكمي بالكامل - بطلب سليمان الصريح
  /// (2026-08-15)، لم يكن له زر تفريغ أصلاً (خلافًا لبقية التقارير) لأنه سجل
  /// مُشتَق تلقائيًا لا رفعة مباشرة، لكن يحتاجه أيضًا لتسهيل إعادة الاختبار.
  Future<void> _clearMovements() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ حركات الإرشاد'),
        content: const Text(
            'سيُحذَف كل سجل حركات الإرشاد التراكمي بالكامل (كل الرفعات منذ البداية). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('تفريغ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdvisorMovementRepository.clear();
      final movements = await AdvisorMovementRepository.loadAll();
      if (!mounted) return;
      setState(() => _movementsLog = movements);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفريغ حركات الإرشاد بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر التفريغ', '$e');
    }
  }

  /// رأس مخصَّص لهذه الصفحة فقط (لا يمسّ [AdvisingPageHeader] المشترك مع
  /// بقية صفحات الإرشاد) - العنوان والوصف بجانب بعضهما بـ`Wrap` بدل تكديسهما
  /// رأسيًا، فيظهران بسطر واحد على Desktop وينزل الوصف تلقائيًا لسطر ثانٍ
  /// عند ضيق الشاشة (سليمان 2026-08-23: "اعتماد نهائي" - رفع المؤشرات
  /// والجدول للأعلى بتقليل الارتفاع الرأسي لرأس الصفحة فقط).
  Widget _buildCompactHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdvisingBreadcrumb(trail: 'متابعة حالات الإرشاد'),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.fact_check_outlined, size: 20, color: DashTokens.green900),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('متابعة حالات الإرشاد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                  const SizedBox(width: 10),
                  Text(
                    'كشف بيانات الطلبة، النصاب، إعادة التوزيع، والتقارير التفصيلية.',
                    style: TextStyle(fontSize: 11.5, color: DashTokens.textSecondary.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// شبكة إحصائيات (10 بطاقات: 5 أعلى + 5 أسفل) بنفس تصميم [PortalStatCard]
  /// المستخدم بلوحة الإرشاد. بطاقة واحدة لكل تبويب من التبويبات الأربعة عشر
  /// كلها (بعد حذف قائمة "عرض" المنسدلة صار هذا الشريط الوسيلة الوحيدة
  /// للوصول لأي تبويب - سليمان 2026-08-20). كل بطاقة قابلة للنقر فتُبدّل قسم
  /// العرض مباشرة.
  Widget _buildStatsGrid(List<(String, Widget Function())> tabs) {
    final counts = <int>[
      _classification.studentsCorrectlyAssigned.length +
          _classification.studentsWithoutAdvisor.length +
          _classification.studentsWithWrongDeptAdvisor.length +
          _classification.externalAdvisorsWithOurStudents.length +
          _classification.ourAdvisorsWithExternalStudents.length,
      _classification.studentsCorrectlyAssigned.length,
      _analysis.healthCasesWithAmin.length,
      _classification.studentsWithoutAdvisor.length,
      _classification.studentsWithWrongDeptAdvisor.length,
      _analysis.healthCasesNotWithAmin.length,
      _classification.externalAdvisorsWithOurStudents.length,
      _classification.ourAdvisorsWithExternalStudents.length,
      _analysis.exemptAdvisorsWithStudents.length,
      _analysis.advisorsWithNoStudents.length,
      _analysis.quotaReport.length,
      _analysis.transferSuggestions.length,
      _analysis.advisorStatistics.fold<int>(0, (sum, b) => sum + b.totalAdvisors),
      _movementsLog.length,
      _classification.newStudents.length,
    ];
    const icons = <IconData>[
      Icons.groups_outlined,
      Icons.school_outlined,
      Icons.accessible_outlined,
      Icons.person_search_outlined,
      Icons.sync_problem_outlined,
      Icons.accessible_forward_outlined,
      Icons.login_outlined,
      Icons.logout_outlined,
      Icons.no_accounts_outlined,
      Icons.person_off_outlined,
      Icons.pie_chart_outline,
      Icons.published_with_changes_outlined,
      Icons.bar_chart_outlined,
      Icons.history_outlined,
      Icons.fiber_new_outlined,
    ];
    final colors = <Color>[
      AppColors.greenDark,
      AppColors.green,
      Colors.teal.shade700,
      Colors.redAccent,
      Colors.deepOrange,
      Colors.purple.shade700,
      AppColors.gold,
      Colors.indigo,
      Colors.blueGrey,
      Colors.brown,
      Colors.cyan.shade700,
      Colors.pink.shade700,
      Colors.lime.shade800,
      Colors.blueGrey.shade400,
      Colors.orange.shade700,
    ];

    // 14 بطاقة (لكل التبويبات الأربعة عشر - كانت 10 فقط قبل ذلك) - سليمان لاحظ
    // صراحةً (2026-08-20) أن أربعة تبويبات ("تقرير نصاب الإرشاد"، "خطة إعادة
    // التوزيع العادل"، "إحصائيات الإرشاد"، "حركات الإرشاد") صارت غير قابلة
    // للوصول إطلاقًا بعد حذف قائمة "عرض" المنسدلة التي كانت الوسيلة الوحيدة
    // للوصول إليها.
    //
    // مفصولة بصريًا (2026-08-21) لـ5 مؤشرات أساسية (أول 5 تبويبات بترتيب
    // سليمان نفسه - الأهم تشغيليًا: الكل/تابعين لمرشد/ذوي إعاقة/بلا مرشد/على
    // غير مرشدهم) بوزن أقوى، والباقي مؤشرات تشغيلية ثانوية بحجم أصغر - بدل
    // حائط 14 بطاقة متساوية الوزن.
    // بطاقة "طلبة على غير مرشدهم – ذوي الإعاقة" (index 5) لم تعد بطاقة
    // مستقلة (سليمان 2026-08-23: "فئة فرعية من طلبة على غير مرشدهم، لا تحتاج
    // بطاقة مستقلة") - رقمها يظهر كملاحظة ديناميكية داخل بطاقة "طلبة على غير
    // مرشدهم" (index 4) بدلًا من ذلك. التبويب نفسه (`_tabHealthMismatch`)
    // ومعادلة عدّه (`counts[5]`) بقيا كما هما بلا أي حذف من الكود أو الحسابات
    // - فقط استُبعِد من شبكة البطاقات.
    Widget tile(int i, {required bool compact, String? note}) => _CompactStatTile(
          icon: icons[i],
          value: '${counts[i]}',
          label: tabs[i].$1,
          note: note,
          color: colors[i],
          selected: _sectionIndex == i,
          compact: compact,
          onTap: () => setState(() {
            _sectionIndex = i;
            _resetTablePage();
          }),
        );

    const primaryIndices = [0, 1, 2, 3, 4];
    const secondaryIndices = [6, 7, 8, 9, 10, 11, 12, 13, 14];

    Widget grid({required List<int> indices, required bool compact, required int Function(double width) columnsFor}) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cols = columnsFor(constraints.maxWidth).clamp(1, indices.length);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: indices.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisExtent: compact ? 56 : 72,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, i) {
              final idx = indices[i];
              final note = switch (idx) {
                0 => 'المستهدفون بالإرشاد: ${_classification.targetedStudentsCount}',
                4 => 'منهم ${counts[5]} من ذوي الإعاقة',
                _ => null,
              };
              return tile(idx, compact: compact, note: note);
            },
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('مؤشرات أساسية', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        grid(
          indices: primaryIndices,
          compact: false,
          columnsFor: (w) => w >= 1150 ? 5 : (w >= 700 ? 3 : (w >= 460 ? 2 : 1)),
        ),
        const SizedBox(height: 10),
        Text('مؤشرات تشغيلية', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        grid(
          indices: secondaryIndices,
          compact: true,
          columnsFor: (w) => w >= 900 ? 4 : (w >= 520 ? 2 : 1),
        ),
      ],
    );
  }

  /// شريط الفلترة (شطر/قسم/مرشد/بحث) - يظهر أعلى التبويبات الاثني عشر ويؤثر
  /// عليها جميعًا فورًا، كما طُلب صراحةً (2026-08-14). قائمة المرشد تُعاد
  /// بناؤها تلقائيًا (عبر `key`) كلما تغيّر القسم لأنها مقصورة عليه.
  Widget _buildFilterBar() {
    final hasFilter = _shatrFilter != _kAllShatr || _deptFilter != _kAllDepartments || _advisorFilter != _kAllAdvisors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterResetChip(
            active: !hasFilter,
            onTap: () => setState(() {
              _shatrFilter = _kAllShatr;
              _deptFilter = _kAllDepartments;
              _advisorFilter = _kAllAdvisors;
              _resetTablePage();
            }),
          ),
          FilterPillDropdown<String>(
            label: 'الشطر',
            value: _shatrFilter == _kAllShatr ? null : _shatrFilter,
            items: [Shatr.male.label, Shatr.female.label],
            itemLabel: (v) => v,
            onChanged: (v) => setState(() {
              _shatrFilter = v ?? _kAllShatr;
              _advisorFilter = _kAllAdvisors;
              _resetTablePage();
            }),
          ),
          FilterPillDropdown<String>(
            label: 'القسم',
            value: _deptFilter == _kAllDepartments ? null : _deptFilter,
            items: _departments,
            itemLabel: (v) => v,
            onChanged: (v) => setState(() {
              _deptFilter = v ?? _kAllDepartments;
              _advisorFilter = _kAllAdvisors;
              _resetTablePage();
            }),
          ),
          FilterPillDropdown<String>(
            key: ValueKey('$_deptFilter|$_shatrFilter'),
            label: 'المرشد',
            value: _advisorFilter == _kAllAdvisors ? null : _advisorFilter,
            items: _advisorFilterOptions,
            itemLabel: displayName,
            onChanged: (v) => setState(() {
              _advisorFilter = v ?? _kAllAdvisors;
              _resetTablePage();
            }),
          ),
          SizedBox(
            width: 200,
            height: 32,
            child: TextField(
              controller: _studentSearchCtrl,
              style: const TextStyle(fontSize: 12.5, color: _FilterTokens.textPrimary, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'بحث باسم/رقم الطالب',
                hintStyle: TextStyle(fontSize: 12, color: _FilterTokens.textSecondary),
                prefixIcon: const Icon(Icons.search, size: 18, color: _FilterTokens.textSecondary),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.gold, width: 1.4)),
              ),
              onChanged: (_) => setState(() => _resetTablePage()),
            ),
          ),
          SizedBox(
            width: 200,
            height: 32,
            child: TextField(
              controller: _advisorSearchCtrl,
              style: const TextStyle(fontSize: 12.5, color: _FilterTokens.textPrimary, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'بحث باسم/رقم المرشد',
                hintStyle: TextStyle(fontSize: 12, color: _FilterTokens.textSecondary),
                prefixIcon: const Icon(Icons.person_search_outlined, size: 18, color: _FilterTokens.textSecondary),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.gold, width: 1.4)),
              ),
              onChanged: (_) => setState(() => _resetTablePage()),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------- فلاتر مشتركة -------------------------------

  bool _deptMatches(String department) => _deptFilter == _kAllDepartments || department == _deptFilter;

  bool _advisorMatches(String advisorName) =>
      _advisorFilter == _kAllAdvisors ||
      AdvisingCaseAnalyzer.nameKey(advisorName) == AdvisingCaseAnalyzer.nameKey(_advisorFilter);

  /// رقم منسوب المرشد من ملف منسوبي الكلية عبر اسمه - يُستخدم فقط لتوسيع
  /// خانة البحث لتشمل رقم المرشد أيضًا (لا اسمه فقط)، لأنه غير مخزَّن مباشرة
  /// على سجل الطالب نفسه.
  String _staffNumberFor(String advisorName) =>
      _facultyByKey[AdvisingCaseAnalyzer.nameKey(advisorName)]?.staffNumber ?? '';

  /// خانتا بحث منفصلتان (طالب/مرشد) بدل خانة موحَّدة سابقة - بطلب سليمان
  /// الصريح (2026-08-22): "لا يمكن البحث بالطالب والمرشد بنفس المكان"، أي
  /// كل خانة تُفلتر مجالها فقط، والنتيجة تُطابق الخانتين معًا (AND) حين
  /// تُملآن كلتاهما دفعة واحدة.
  /// توحيد صور الهمزة/التاء المربوطة قبل المقارنة - وإلا يفشل البحث بصمت لو
  /// كُتب الاستعلام بصورة مختلفة عن الصورة المخزَّنة لنفس الاسم (مثال: "احمد"
  /// المكتوبة بلا همزة لا تطابق "أحمد" المخزَّنة بها) - لاحظه سليمان صراحةً
  /// (2026-08-15): "لا أستطيع البحث باسم المرشد".
  static String _normalizeForSearch(String s) => s.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه');

  bool _matchesSearch(String name, String id, {String advisorName = '', String advisorId = ''}) {
    final studentQ = _normalizeForSearch(_studentSearchCtrl.text.trim());
    final advisorQ = _normalizeForSearch(_advisorSearchCtrl.text.trim());
    if (studentQ.isNotEmpty && !(_normalizeForSearch(name).contains(studentQ) || id.contains(studentQ))) return false;
    if (advisorQ.isNotEmpty &&
        !(_normalizeForSearch(advisorName).contains(advisorQ) ||
            advisorId.contains(advisorQ) ||
            (advisorName.isNotEmpty && _staffNumberFor(advisorName).contains(advisorQ)))) {
      return false;
    }
    return true;
  }

  // ------------------------------- 12 تبويبًا -------------------------------
  // كل دالة تبني قائمة صفوف نصية (بعد تطبيق فلاتر القسم/المرشد) ثم تمررها
  // لـ[_buildPanel] المشتركة (عنوان + عدّاد + تصدير Excel/PDF + جدول). الشطر
  // مُطبَّق مسبقًا عند بناء `_classification`/`_analysis`/`_movementsLog`.

  /// "الكل" - كل طلاب التصنيفات الأربعة + بلا مرشد مجتمعين بجدول واحد مع
  /// عمود "الوضع" يوضّح تصنيف كل طالب - بطلب سليمان الصريح (2026-08-15):
  /// خيار يعرض كل الطلاب بغض النظر عن وضعهم بدل التنقّل بين التبويبات.
  static String _gpaCell(AdvisingCaseRecord s) => s.gpa != null ? s.gpa!.toStringAsFixed(2) : '—';
  static String _completedHoursCell(AdvisingCaseRecord s) => s.completedHours?.toString() ?? '—';
  static String _remainingHoursCell(AdvisingCaseRecord s) => s.remainingHours?.toString() ?? '—';

  Widget _tabAllStudents() {
    final rows = <List<String>>[];
    for (final s in _classification.studentsCorrectlyAssigned) {
      if (_deptMatches(s.department) &&
          _advisorMatches(s.advisorNameRaw) &&
          _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw)) {
        rows.add([
          s.studentName,
          s.studentId,
          s.department,
          s.shatr,
          displayName(s.advisorNameRaw).ifEmptyDash(),
          'على مرشدهم',
          _gpaCell(s),
          _completedHoursCell(s),
          _remainingHoursCell(s),
        ]);
      }
    }
    for (final s in _classification.studentsWithoutAdvisor) {
      if (_deptMatches(s.department) && _advisorMatches(s.advisorNameRaw) && _matchesSearch(s.studentName, s.studentId)) {
        rows.add([s.studentName, s.studentId, s.department, s.shatr, '—', 'بلا مرشد', _gpaCell(s), _completedHoursCell(s), _remainingHoursCell(s)]);
      }
    }
    for (final c in _classification.studentsWithWrongDeptAdvisor) {
      if (_deptMatches(c.student.department) &&
          _advisorMatches(c.student.advisorNameRaw) &&
          _matchesSearch(c.student.studentName, c.student.studentId, advisorName: c.student.advisorNameRaw)) {
        rows.add([
          c.student.studentName,
          c.student.studentId,
          c.student.department,
          c.student.shatr,
          displayName(c.student.advisorNameRaw).ifEmptyDash(),
          'على غير مرشدهم',
          _gpaCell(c.student),
          _completedHoursCell(c.student),
          _remainingHoursCell(c.student),
        ]);
      }
    }
    for (final s in _classification.externalAdvisorsWithOurStudents) {
      if (_deptMatches(s.department) &&
          _advisorMatches(s.advisorNameRaw) &&
          _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw)) {
        rows.add([
          s.studentName,
          s.studentId,
          s.department,
          s.shatr,
          displayName(s.advisorNameRaw).ifEmptyDash(),
          'مرشد خارجي ← طلابنا',
          _gpaCell(s),
          _completedHoursCell(s),
          _remainingHoursCell(s),
        ]);
      }
    }
    for (final s in _classification.ourAdvisorsWithExternalStudents) {
      if (_deptMatches(s.department) &&
          _advisorMatches(s.advisorNameRaw) &&
          _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw)) {
        rows.add([
          s.studentName,
          s.studentId,
          s.department,
          s.shatr,
          displayName(s.advisorNameRaw).ifEmptyDash(),
          'مرشدنا ← طلاب خارجيون',
          _gpaCell(s),
          _completedHoursCell(s),
          _remainingHoursCell(s),
        ]);
      }
    }
    return _buildPanel(
      title: 'كل الطلاب',
      // أعمدة المعدل/الساعات المجتازة/المتبقية بطلب سليمان (2026-08-25) بعد
      // ربط رفع "بيانات الطلبة الأكاديمية" - null (تُعرض "—") لطالب لم يظهر
      // بعد بذلك الملف.
      headers: const ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد', 'الوضع', 'المعدل', 'الساعات المجتازة', 'الساعات المتبقية'],
      rows: rows,
    );
  }

  Widget _tabCorrectlyAssigned() {
    final list = _classification.studentsCorrectlyAssigned
        .where((s) => _deptMatches(s.department) &&
            _advisorMatches(s.advisorNameRaw) &&
            _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'طلاب على مرشدهم',
      headers: const ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد'],
      rows: [
        for (final s in list) [s.studentName, s.studentId, s.department, s.shatr, displayName(s.advisorNameRaw).ifEmptyDash()],
      ],
    );
  }

  Widget _tabWithoutAdvisor() {
    final list = _classification.studentsWithoutAdvisor
        .where((s) => _deptMatches(s.department) && _advisorMatches(s.advisorNameRaw) && _matchesSearch(s.studentName, s.studentId))
        .toList();
    return _buildPanel(
      title: 'طلاب بلا مرشد',
      headers: const ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر'],
      rows: [for (final s in list) [s.studentName, s.studentId, s.department, s.shatr]],
    );
  }

  /// الطلبة المستجدون (رقمهم يبدأ برمز سنة القبول الحالية) - مؤشر مستقل تمامًا
  /// عن "طلبة بلا مرشد"، بطلب سليمان صراحةً (2026-08-26): "الطالب المستجد غير
  /// ملزم بوجود مرشد أكاديمي؛ لذلك لا يجوز احتسابه ضمن مؤشر طلبة بلا مرشد".
  /// عمود "المرشد" هنا للعرض فقط (إن وُجد فعلاً بتقرير "كل الكليات") - وجوده
  /// لا يغيّر تصنيف الطالب (يبقى هنا حصرًا، لا يُحتسَب "على مرشدهم").
  Widget _tabNewStudents() {
    final list = _classification.newStudents
        .where((s) => _deptMatches(s.department) && _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'الطلبة المستجدون',
      headers: const ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد (إن وُجد)'],
      rows: [
        for (final s in list) [s.studentName, s.studentId, s.department, s.shatr, displayName(s.advisorNameRaw).ifEmptyDash()],
      ],
    );
  }

  Widget _tabWrongAdvisor() {
    final list = _classification.studentsWithWrongDeptAdvisor
        .where((c) =>
            _deptMatches(c.student.department) &&
            _advisorMatches(c.student.advisorNameRaw) &&
            _matchesSearch(c.student.studentName, c.student.studentId,
                advisorName: c.student.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'طلاب على غير مرشدهم',
      // رقم منسوب المرشد أُضيف بطلب سليمان صراحةً (2026-08-15): هذا الملف
      // يُرسَل لمسؤول الإرشاد بالقبول والتسجيل لتسكين الطلبة على مرشدهم
      // الصحيح - بلا رقم المنسوب لا يمكنه تحديد المرشد فعليًا (قد يتكرر
      // الاسم)، فيتعطّل العمل.
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد الحالي', 'رقم منسوب المرشد', 'قسم المرشد المسجَّل'],
      rows: [
        for (final c in list)
          [
            c.student.studentName,
            c.student.studentId,
            c.student.department,
            c.student.shatr,
            displayName(c.student.advisorNameRaw).ifEmptyDash(),
            c.advisor?.staffNumber.ifEmptyDash() ?? '-',
            c.advisor?.department ?? 'غير موجود بملف منسوبي الكلية',
          ],
      ],
      emptyMessage: 'لا يوجد طلبة على غير مرشدهم',
    );
  }

  Widget _tabExternalAdvisors() {
    final list = _classification.externalAdvisorsWithOurStudents
        .where((s) => _deptMatches(s.department) &&
            _advisorMatches(s.advisorNameRaw) &&
            _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw, advisorId: s.advisorId))
        .toList();
    return _buildPanel(
      title: 'مرشدون من خارج الكلية يرشدون طلبة من داخل الكلية',
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد (من خارج الكلية)', 'رقم منسوب المرشد'],
      rows: [
        for (final s in list)
          [s.studentName, s.studentId, s.department, s.shatr, displayName(s.advisorNameRaw).ifEmptyDash(), s.advisorId.ifEmptyDash()],
      ],
    );
  }

  Widget _tabExternalStudents() {
    final list = _classification.ourAdvisorsWithExternalStudents
        .where((s) => _deptMatches(s.department) &&
            _advisorMatches(s.advisorNameRaw) &&
            _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'مرشدون من داخل الكلية يرشدون طلبة من خارج الكلية',
      headers: const ['الطالب', 'الرقم الجامعي', 'التخصص (خارج كليتنا)', 'الشطر', 'المرشد'],
      rows: [
        for (final s in list) [s.studentName, s.studentId, s.department, s.shatr, displayName(s.advisorNameRaw).ifEmptyDash()],
      ],
    );
  }

  Widget _tabExemptWithStudents() {
    final cases = _analysis.exemptAdvisorsWithStudents
        .where((c) => _deptMatches(c.advisor.department) &&
            _advisorMatches(c.advisor.name) &&
            _matchesSearch(c.advisor.name, c.advisor.staffNumber))
        .toList();
    return _buildPanel(
      title: 'مرشدون معفَون ولديهم طلاب',
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'المرشد المعفى', 'قسم المرشد'],
      rows: [
        for (final c in cases)
          for (final s in c.students) [s.studentName, s.studentId, s.department, displayName(c.advisor.name), c.advisor.department],
      ],
    );
  }

  Widget _tabAdvisorsNoStudents() {
    final list = _analysis.advisorsWithNoStudents
        .where((m) => _deptMatches(m.department) &&
            _advisorMatches(m.name) &&
            _matchesSearch(m.name, m.staffNumber))
        .toList();
    return _buildPanel(
      title: 'مرشدون بلا طلاب',
      headers: const ['الاسم', 'رقم المنسوب', 'القسم', 'الشطر', 'السبب'],
      rows: [for (final m in list) [displayName(m.name), m.staffNumber.ifEmptyDash(), m.department, m.shatr, m.advisingReason]],
    );
  }

  static const _kAllQuotaStatuses = 'كل الحالات';
  static const List<String> _quotaStatusOptions = [_kAllQuotaStatuses, 'فوق النصاب', 'دون النصاب', 'متوازن'];
  String _quotaStatusFilter = _kAllQuotaStatuses;

  Widget _tabQuota() {
    final list = _analysis.quotaReport
        .where((q) => _deptMatches(q.advisor.department) &&
            _advisorMatches(q.advisor.name) &&
            _matchesSearch(q.advisor.name, q.advisor.staffNumber) &&
            (_quotaStatusFilter == _kAllQuotaStatuses || _quotaStatusLabel(q.status) == _quotaStatusFilter))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: DropdownMenu<String>(
            label: const Text('حالة النصاب'),
            initialSelection: _quotaStatusFilter,
            dropdownMenuEntries: _quotaStatusOptions.map((o) => DropdownMenuEntry(value: o, label: o)).toList(),
            onSelected: (v) => setState(() => _quotaStatusFilter = v ?? _kAllQuotaStatuses),
          ),
        ),
        const SizedBox(height: 14),
        _buildPanel(
          title: 'تقرير النصاب (فوق/دون الحصة العادلة)',
          headers: const ['المرشد', 'القسم', 'العدد الحالي', 'الحصة العادلة', 'الحالة'],
          rows: [
            for (final q in list)
              [displayName(q.advisor.name), q.advisor.department, '${q.actualCount}', '${q.fairShare.round()}', _quotaStatusLabel(q.status)],
          ],
        ),
      ],
    );
  }

  /// عدد الطلاب المنقولين بين كل زوج (من مرشد ← إلى مرشد) بدل سرد كل طالب
  /// بالاسم - كما طلب سليمان صراحةً (2026-08-14): المهم إحصائيًا فقط "كم
  /// طالب من مرشد أ ينتقل إلى مرشد ب" حتى تصح الموازنة، لا بيانات الطالب.
  Widget _tabTransfer() {
    final list = _analysis.transferSuggestions
        .where((t) => _deptMatches(t.student.department) &&
            _advisorMatches(t.fromAdvisorNameRaw) &&
            _matchesSearch(t.student.studentName, t.student.studentId, advisorName: t.fromAdvisorNameRaw))
        .toList();

    final counts = <String, int>{};
    final rowsByKey = <String, List<String>>{};
    for (final t in list) {
      final key = [
        t.student.department,
        t.fromAdvisorNameRaw,
        t.fromAdvisor?.staffNumber ?? '',
        t.toAdvisor?.name ?? 'يلزم قرار يدوي',
        t.toAdvisor?.staffNumber ?? '',
      ].join('|');
      counts[key] = (counts[key] ?? 0) + 1;
      rowsByKey[key] = [
        t.student.department,
        displayName(t.fromAdvisorNameRaw),
        t.fromAdvisor?.staffNumber.ifEmptyDash() ?? '—',
        t.toAdvisor != null ? displayName(t.toAdvisor!.name) : 'يلزم قرار يدوي',
        t.toAdvisor?.staffNumber.ifEmptyDash() ?? '—',
      ];
    }
    final keys = rowsByKey.keys.toList()
      ..sort((x, y) {
        final r = rowsByKey[x]![0].compareTo(rowsByKey[y]![0]);
        return r != 0 ? r : counts[y]!.compareTo(counts[x]!);
      });

    return _buildPanel(
      title: 'تقرير إعادة التوزيع - إحصائي (${list.length} طالب/ة)',
      headers: const ['القسم', 'المرشد السابق', 'رقمه', 'المرشد الموصى به', 'رقمه', 'عدد الطلاب المنقولين'],
      rows: [for (final k in keys) [...rowsByKey[k]!, '${counts[k]}']],
    );
  }

  /// جدول تفصيلي كامل - بطلب سليمان الصريح (2026-08-14): اسم الطالب/ة،
  /// رقمه الجامعي، تخصصه، المرشد الحالي (المخالف)، والمرشد المفترض حسب
  /// قاعدة أمين/منسّق القسم (انظر [[feedback_health_case_amin_coordinator_rule]])،
  /// ونوع الإعاقة - بدل قائمة الأسماء المجرَّدة سابقًا.
  Widget _tabHealthMismatch() {
    final list = _analysis.healthCasesNotWithAmin
        .where((h) => _deptMatches(h.student.department) &&
            _advisorMatches(h.currentAdvisor?.name ?? h.student.advisorNameRaw) &&
            _matchesSearch(h.student.studentName, h.student.studentId,
                advisorName: h.currentAdvisor?.name ?? h.student.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'طلبة ذوي الإعاقة على غير مرشدهم (${list.length})',
      // رقما منسوب المرشدَين (الحالي والمفترض) أُضيفا بطلب سليمان صراحةً
      // (2026-08-15) - نفس سبب تبويب "طلاب على غير مرشدهم": الملف يُرسَل
      // لمسؤول الإرشاد بالقبول والتسجيل لتسكين الطلبة على مرشدهم الصحيح.
      headers: const [
        'الاسم',
        'الرقم الجامعي',
        'التخصص',
        'نوع الإعاقة',
        'المرشد الحالي',
        'رقم منسوب المرشد الحالي',
        'المرشد المفترض',
        'رقم منسوب المرشد المفترض',
      ],
      rows: [
        for (final h in list)
          [
            h.student.studentName,
            h.student.studentId,
            h.student.department,
            h.student.healthCondition,
            h.currentAdvisor != null
                ? displayName(h.currentAdvisor!.name)
                : (h.student.hasAdvisor ? displayName(h.student.advisorNameRaw) : 'بلا مرشد'),
            h.currentAdvisor?.staffNumber.ifEmptyDash() ?? '-',
            h.departmentAmin != null ? displayName(h.departmentAmin!.name) : 'غير معروف',
            h.departmentAmin?.staffNumber.ifEmptyDash() ?? '-',
          ],
      ],
    );
  }

  /// جدول تفصيلي كامل لطلبة ذوي الإعاقة **الموزَّعين فعليًا حسب القاعدة
  /// المتَّفَق عليها** (لدى أمين القسم، أو منسّقه إن اختلف تخصص الأمين) -
  /// نفس أعمدة [_tabHealthMismatch] بالضبط ما عدا عمود "المرشد المفترض"
  /// (هنا مطابق فعليًا للمرشد الحالي فلا داعي لتكراره) - بطلب سليمان الصريح
  /// (2026-08-14).
  Widget _tabHealthCases() {
    final list = _analysis.healthCasesWithAmin
        .where((s) => _deptMatches(s.department) &&
            _advisorMatches(s.advisorNameRaw) &&
            _matchesSearch(s.studentName, s.studentId, advisorName: s.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'طلبة ذوي الإعاقة على مرشدهم (${list.length})',
      headers: const ['الاسم', 'الرقم الجامعي', 'التخصص', 'نوع الإعاقة', 'المرشد الحالي', 'رقم منسوب المرشد'],
      rows: [
        for (final s in list)
          [
            s.studentName,
            s.studentId,
            s.department,
            s.healthCondition,
            displayName(s.advisorNameRaw).ifEmptyDash(),
            _staffNumberFor(s.advisorNameRaw).ifEmptyDash(),
          ],
      ],
    );
  }

  /// "إحصائية المرشدين" - بيانات حيّة 100% من الموقع (نفس مصدر بقية
  /// التبويبات، `AdvisingCaseAnalyzer.analyze`) لا من أي ملف خارجي؛ ملف
  /// سليمان المرجعي استُخدم فقط لتصميم منهجية الحساب (الحصة العادلة/الوزن)
  /// لا كمصدر بيانات - بطلبه الصريح (2026-08-15) لا تُنسَخ كل أعمدته حرفيًا،
  /// بل تُختصَر لواجهة احترافية مفيدة. كتلة مستقلة لكل قسم/شطر (رأس ملخَّص +
  /// جدول)، مع فلتر إضافي خاص بهذا التبويب لنوع النصاب (فوق/دون النصاب مثلاً)
  /// إلى جانب فلاتر الشطر/القسم/المرشد/البحث المشتركة أعلى الصفحة.
  Widget _tabAdvisorStatistics() {
    bool rowMatches(AdvisorStatRow r) =>
        _advisorMatches(r.advisor.name) &&
        _matchesSearch(r.advisor.name, r.advisor.staffNumber) &&
        (_advisorStatsFilter == _kAllAdvisorStatuses || _advisorStatusOf(r) == _advisorStatsFilter);

    final blocks = _analysis.advisorStatistics.where((b) => _deptMatches(b.department)).toList();
    final filteredBlocks = [
      for (final b in blocks)
        (
          b,
          [
            for (final r in b.rows) if (rowMatches(r)) r,
          ]..sort((x, y) => y.diffFromTarget.compareTo(x.diffFromTarget)),
        ),
    ].where((e) => e.$2.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: DropdownMenu<String>(
            label: const Text('حالة النصاب'),
            initialSelection: _advisorStatsFilter,
            dropdownMenuEntries: _advisorStatusOptions.map((o) => DropdownMenuEntry(value: o, label: o)).toList(),
            onSelected: (v) => setState(() => _advisorStatsFilter = v ?? _kAllAdvisorStatuses),
          ),
        ),
        const SizedBox(height: 14),
        if (filteredBlocks.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Center(child: Text('لا توجد بيانات', style: TextStyle(color: Colors.grey.shade600))),
          )
        else
          for (final e in filteredBlocks) ...[
            _advisorStatsSummaryCard(e.$1),
            const SizedBox(height: 10),
            _buildPanel(
              title: '${e.$1.department} - ${e.$1.shatr}',
              headers: const ['م', 'اسم المرشد', 'رقم المرشد', 'نوع النصاب', 'العدد الحالي', 'النصاب المستهدف', 'الفرق', 'الحالة'],
              rows: [
                for (var i = 0; i < e.$2.length; i++)
                  [
                    '${i + 1}',
                    displayName(e.$2[i].advisor.name),
                    e.$2[i].advisor.staffNumber.ifEmptyDash(),
                    e.$2[i].quotaTypeLabel,
                    '${e.$2[i].actualCount}',
                    '${e.$2[i].target}',
                    '${e.$2[i].diffFromTarget}',
                    _advisorStatusOf(e.$2[i]),
                  ],
              ],
            ),
            const SizedBox(height: 20),
          ],
      ],
    );
  }

  /// حالة مختصرة لكل مرشد (تُستخدم للفلترة وعمود "الحالة") - "معفى وله طلاب"
  /// حالة شاذة تستحق تمييزًا خاصًا (تعني خللاً يحتاج مراجعة: عضو مُعفى لكنه
  /// لا يزال مسنَدًا له طلاب فعليًا بمنظومة الجامعة).
  static const _kAllAdvisorStatuses = 'كل الحالات';
  static const List<String> _advisorStatusOptions = [
    _kAllAdvisorStatuses,
    'فوق النصاب',
    'دون النصاب',
    'متوازن',
    'معفى/مجمَّد',
    'معفى وله طلاب (يحتاج مراجعة)',
  ];
  String _advisorStatusOf(AdvisorStatRow r) {
    if (r.weight == 0) return r.countInSystem > 0 ? 'معفى وله طلاب (يحتاج مراجعة)' : 'معفى/مجمَّد';
    if (r.diffFromTarget > 1) return 'فوق النصاب';
    if (r.diffFromTarget < -1) return 'دون النصاب';
    return 'متوازن';
  }

  String _advisorStatsFilter = _kAllAdvisorStatuses;

  Widget _advisorStatsSummaryCard(DepartmentAdvisorStats b) {
    Widget stat(String label, String value, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: (color ?? AppColors.green).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color ?? AppColors.greenDark)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${b.department} - ${b.shatr}', style: AppTextStyles.h3(color: AppColors.greenDark)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              stat('إجمالي المرشدين', '${b.totalAdvisors}'),
              stat('كامل النصاب', '${b.fullQuotaCount}'),
              stat('نصاب 50%', '${b.halfQuotaCount}'),
              stat('معفَون/مجمَّدون', '${b.exemptCount}'),
              stat('الوزن الفعلي للقسم', '${b.weightEquivalentAdvisors}'),
              stat('إجمالي الطلاب المسندين', '${b.totalActualCases}'),
              stat('النصاب العادل (كامل)', '${b.fairShareFull}'),
              stat('النصاب العادل (50%)', '${b.fairShareHalf}'),
              if (b.exemptCases > 0) stat('⚠ طلاب لدى معفَين', '${b.exemptCases}', color: Colors.red.shade700),
            ],
          ),
        ],
      ),
    );
  }

  /// حركات الإرشاد: سجل **تراكمي دائم** (كل الرفعات منذ البداية، لا آخر
  /// رفعتين فقط) - بطلب سليمان صراحةً (2026-08-14). يظهر مضمَّنًا بالصفحة (لا
  /// نافذة منبثقة)، والمرشد الحالي يسبق المرشد السابق في الأعمدة كما طلب.
  Widget _tabMovements() {
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    final list = _movementsLog
        .where((m) =>
            (_shatrFilter == _kAllShatr || m.shatr == _shatrFilter) &&
            _deptMatches(m.department) &&
            (_advisorMatches(m.toAdvisorNameRaw) || _advisorMatches(m.fromAdvisorNameRaw)) &&
            (_matchesSearch(m.studentName, m.studentId, advisorName: m.toAdvisorNameRaw) ||
                _matchesSearch(m.studentName, m.studentId, advisorName: m.fromAdvisorNameRaw)))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_movementsLog.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextButton.icon(
              onPressed: _clearMovements,
              icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700, size: 18),
              label: Text('تفريغ البيانات (للاختبار)', style: TextStyle(color: Colors.red.shade700)),
            ),
          ),
        _buildPanel(
          title: 'حركات الإرشاد (كل الرفعات)',
          headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد الحالي', 'المرشد السابق', 'تاريخ الاكتشاف'],
          rows: [
            for (final m in list)
              [
                m.studentName,
                m.studentId,
                m.department,
                m.shatr,
                displayName(m.toAdvisorNameRaw).ifEmptyDash(),
                displayName(m.fromAdvisorNameRaw).ifEmptyDash(),
                m.detectedAt != null ? fmt.format(m.detectedAt!) : '—',
              ],
          ],
          emptyMessage: 'لا توجد حركات إرشاد مسجَّلة بعد',
        ),
      ],
    );
  }

  // ------------------------------- عناصر مشتركة -------------------------------

  static String _quotaStatusLabel(QuotaStatus s) => switch (s) {
        QuotaStatus.over => 'فوق النصاب',
        QuotaStatus.under => 'دون النصاب',
        QuotaStatus.balanced => 'متوازن',
      };

  /// لوحة مشتركة لكل التبويبات الاثني عشر: عنوان + عدّاد + زرّا تصدير (Excel/
  /// PDF يُصدِّران [rows] **كاملة بلا أي حد**) + جدول العرض المرئي (يُقلَّص
  /// لأول [_kMaxTableRows] صف فقط عند تجاوزه - انظر توثيق الثابت أعلى الملف).
  Widget _buildPanel({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String emptyMessage = 'لا توجد بيانات',
  }) {
    final count = rows.length;
    final hasData = count > 0;
    // اسم الملف المصدَّر يصير اسم المرشد نفسه حين يكون فلتر "المرشد" محدَّدًا
    // بعضو واحد تحديدًا - بطلب سليمان الصريح (2026-08-15): "حين تنزيل ملف
    // إكسل طلبة على مرشدهم المفترض يُسمَّى الملف باسم العضو" - بدل عنوان
    // التبويب العام (غير مفيد حين يكون التصدير مقصورًا فعليًا على مرشد واحد).
    final fileBaseName = _advisorFilter == _kAllAdvisors ? title : _advisorFilter;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: AppColors.greenDark.withValues(alpha: 0.03), blurRadius: 5, offset: const Offset(0, 2)),
          BoxShadow(color: AppColors.greenDark.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('$title ($count)', style: AppTextStyles.h3(color: AppColors.greenDark))),
              TextButton.icon(
                onPressed: hasData ? () => _exportExcel(fileBaseName, headers, rows) : null,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Excel'),
              ),
              TextButton.icon(
                onPressed: hasData
                    ? () async {
                        final bytes = await AdvisingCasePdfService.build(title: title, headers: headers, rows: rows);
                        await Printing.sharePdf(bytes: bytes, filename: '$fileBaseName.pdf');
                      }
                    : null,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF/طباعة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _dataTableFromRows(headers, rows, emptyMessage: emptyMessage),
        ],
      ),
    );
  }

  /// فرز الجدول العام - بطلب سليمان الصريح (2026-08-15): الضغط على أي عمود
  /// برأس الجدول (الرقم الجامعي/التخصص/المرشد/أي عمود آخر) يفرز الصفوف به.
  /// عام بلا معرفة نوع العمود مسبقًا (يُستخدَم لكل التبويبات) - يقارن رقميًا
  /// إن أمكن تحويل القيمتين لرقم، وإلا نصيًا.
  int? _tableSortColumnIndex;
  bool _tableSortAscending = true;

  /// ترقيم صفحات احترافي بديل عن قصّ الصفوف بلا تنقّل - يعرض [_kPageSize]
  /// صفٍّ فقط في كل مرة (يحلّ أيضًا مشكلة تجميد `DataTable` عند آلاف
  /// الصفوف)، مع إتاحة كل الصفحات حتى [_kMaxTableRows] الأول (التصدير يبقى
  /// كاملاً دومًا بلا أي حد). تُصفَّر عند تغيير التبويب أو أي فلتر.
  static const int _kPageSize = 100;
  int _tablePage = 0;

  void _resetTablePage() => _tablePage = 0;

  /// جدول عام من نصوص جاهزة (بلا نوع بيانات محدَّد) - يُبنى مرة واحدة فقط
  /// لكل التبويبات الاثني عشر بدل تكرار كود `DataTable` لكل نوع سجل. يُقلَّص
  /// للعرض المرئي فقط عند تجاوز [_kMaxTableRows] (التصدير يبقى كاملاً دومًا).
  Widget _dataTableFromRows(List<String> columns, List<List<String>> allRows, {required String emptyMessage}) {
    if (allRows.isEmpty) {
      return AdvisingEmptyState(icon: Icons.inbox_outlined, title: 'لا توجد بيانات', description: emptyMessage);
    }
    var sortedRows = allRows;
    final sortIndex = _tableSortColumnIndex;
    if (sortIndex != null && sortIndex < columns.length) {
      sortedRows = [...allRows]
        ..sort((a, b) {
          final av = a[sortIndex];
          final bv = b[sortIndex];
          final an = num.tryParse(av);
          final bn = num.tryParse(bv);
          final cmp = (an != null && bn != null) ? an.compareTo(bn) : av.compareTo(bv);
          return _tableSortAscending ? cmp : -cmp;
        });
    }
    // حد أقصى [_kMaxTableRows] للبيانات المتاحة للعرض/التنقّل بالصفحات (يحمي
    // من تجميد `DataTable` مع آلاف الصفوف) - داخله ترقيم صفحات حقيقي بحجم
    // [_kPageSize] بدل قصّ صامت لأول 300 صف بلا تنقّل. التصدير (Excel/PDF)
    // يبقى بلا أي حد دومًا، يشمل كل السجلات.
    final capped = sortedRows.length > _kMaxTableRows ? sortedRows.sublist(0, _kMaxTableRows) : sortedRows;
    final totalPages = (capped.length / _kPageSize).ceil().clamp(1, 1 << 30);
    final page = _tablePage.clamp(0, totalPages - 1);
    final pageStart = page * _kPageSize;
    final pageEnd = (pageStart + _kPageSize).clamp(0, capped.length);
    final visible = capped.sublist(pageStart, pageEnd);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  capped.isEmpty
                      ? 'لا توجد سجلات'
                      : 'عرض ${pageStart + 1}–$pageEnd من ${allRows.length}${sortedRows.length > _kMaxTableRows ? ' (الحد الأقصى للعرض/التنقّل $_kMaxTableRows - استخدم Excel أو PDF أعلاه لكل السجلات)' : ''}',
                  style: const TextStyle(color: DashTokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              if (totalPages > 1) ...[
                IconButton(
                  tooltip: 'السابق',
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: page > 0 ? () => setState(() => _tablePage = page - 1) : null,
                ),
                Text('${page + 1} / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DashTokens.textSecondary)),
                IconButton(
                  tooltip: 'التالي',
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: page < totalPages - 1 ? () => setState(() => _tablePage = page + 1) : null,
                ),
              ],
            ],
          ),
        ),
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.transparent),
              headingTextStyle: TextStyle(color: AppColors.greenDark, fontWeight: FontWeight.w600, fontSize: 13),
              dividerThickness: 1,
              dataRowColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered) ? const Color(0xFFFAFCFB) : Colors.white,
              ),
              sortColumnIndex: sortIndex != null && sortIndex < columns.length ? sortIndex : null,
              sortAscending: _tableSortAscending,
              columns: [
                for (var i = 0; i < columns.length; i++)
                  DataColumn(
                    label: Expanded(child: Text(columns[i], textAlign: TextAlign.center)),
                    onSort: (colIndex, ascending) => setState(() {
                      _tableSortColumnIndex = colIndex;
                      _tableSortAscending = ascending;
                    }),
                  ),
              ],
              rows: [
                for (var i = 0; i < visible.length; i++)
                  DataRow(
                    cells: [for (final v in visible[i]) DataCell(Center(child: Text(v)))],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// أسماء أعمدة "المرشد" المحتملة عبر التبويبات الاثني عشر (كل تبويب يسمّي
  /// عمود المرشد بصيغة مختلفة قليلًا حسب سياقه - انظر رؤوس كل [_buildPanel]).
  static const List<String> _advisorColumnNames = [
    'المرشد',
    'اسم المرشد',
    'المرشد الحالي',
    'المرشد المعفى',
    'المرشد (من خارج الكلية)',
  ];

  /// فهرس عمود المرشد إن وُجد ضمن [headers] **وكان التجميع مفيدًا فعليًا**
  /// (أكثر من صف واحد لنفس المرشد بالمتوسط) - وإلا (كتبويب "تقرير النصاب"
  /// حيث كل مرشد صف واحد أصلًا) يبقى التصدير مسطَّحًا كالسابق بلا فائدة من
  /// كتلة عنوان لكل صف منفرد. بطلب سليمان الصريح 2026-08-25: تصدير كل
  /// التبويبات الاثني عشر بأسلوب "كتلة لكل مرشد" (عنوان ممتد بلون + عدد
  /// طلابه) بدل قائمة مسطَّحة مرتَّبة أبجديًا، مطابقةً لتقارير المنظومة
  /// الجامعية الأصلية.
  int? _groupColumnIndexFor(List<String> headers, List<List<String>> rows) {
    final idx = headers.indexWhere(_advisorColumnNames.contains);
    if (idx == -1 || rows.isEmpty) return null;
    final distinctValues = rows.map((r) => idx < r.length ? r[idx] : '').toSet().length;
    return distinctValues < rows.length ? idx : null;
  }

  void _exportExcel(String title, List<String> headers, List<List<String>> rows) {
    final bytes = AdvisingCaseExcelService.build(
      title: title,
      headers: headers,
      rows: rows,
      groupColumnIndex: _groupColumnIndexFor(headers, rows),
    );
    downloadBytes(bytes, '$title.xlsx');
  }
}

extension on String {
  String ifEmptyDash() => trim().isEmpty ? '—' : this;
}

/// بطاقة إحصائية مصغَّرة لشبكة "متابعة حالات الإرشاد" (10 بطاقات) - نفس
/// لغة تصميم [PortalStatCard] (أيقونة ملوَّنة + رقم + تسمية) لكن بحجم أصغر
/// بكثير (بلا ارتفاع مفروض) حتى تسع التسميات الطويلة بلا قصّ - سليمان لاحظ
/// صراحةً (2026-08-16) أن حجم البطاقات الأصلية (مصمَّمة أصلًا لأربع بطاقات
/// بصف واحد بلوحة الإرشاد) كان "ضخمًا جدًا" هنا مع عشر بطاقات فيصعب قراءة
/// التسميات أسفلها.
class _CompactStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
  final bool compact;
  // ملاحظة اختيارية صغيرة أسفل التسمية (مثال: "منهم 47 من ذوي الإعاقة") -
  // تُستخدَم لإظهار رقم فئة فرعية بلا حاجة لبطاقة مستقلة بشبكة المؤشرات
  // (سليمان 2026-08-23).
  final String? note;

  const _CompactStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
    this.compact = false,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = compact ? 26.0 : 30.0;
    final valueSize = compact ? 15.0 : 15.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? color.withValues(alpha: 0.06) : null,
            border: Border.all(color: selected ? color.withValues(alpha: 0.55) : Colors.grey.shade200, width: selected ? 1.4 : 1),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 6 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Icon(icon, color: Colors.white, size: compact ? 14 : 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: compact ? 10.5 : 9.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 8.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ألوان مقتبسة حرفيًا من هوية شريط فلاتر "إحصائيات طلبات الحذف والإضافة"
/// - تُستخدَم لحقل البحث النصي فقط (الفلاتر المنسدلة أصبحت [FilterPillDropdown]
/// المشتركة بـ`theme/filter_pills.dart`).
class _FilterTokens {
  static const textPrimary = Color(0xFF17352B);
  static const textSecondary = Color(0xFF66746F);
  static const border = Color(0xFFE4EAE7);
}
