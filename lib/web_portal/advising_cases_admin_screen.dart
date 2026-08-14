import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/advising_case_record.dart';
import '../models/college_roster_member.dart';
import '../services/advising_case_analyzer.dart';
import '../services/advising_case_excel_service.dart';
import '../services/advising_case_pdf_service.dart';
import '../services/advising_report_parser_service.dart';
import '../services/advising_report_pdf_parser_service.dart';
import '../services/advising_report_repository.dart';
import '../services/advisor_name_matching.dart';
import '../services/college_roster_repository.dart';
import '../services/web_download.dart';
import '../services/course_schedule_repository.dart' show Shatr, ShatrLabel;
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

const String _kAllShatr = 'كل الشطرين';
const String _kAllDepartments = 'كل الأقسام';

/// عمود "الشطر" في ملف منسوبي الكلية نص حر تكتبه العمادة (لا قيمة ثابتة
/// مضمونة) - نتحقق من الكلمة المفتاحية بدل المطابقة التامة، والفحص عن
/// "طالبات" أولًا لأنها تحتوي حروف "طلاب" لكن بترتيب مختلف فلا تلتبس بها.
String? _shatrLabelFromFreeText(String raw) {
  if (raw.contains('طالبات')) return Shatr.female.label;
  if (raw.contains('طلاب')) return Shatr.male.label;
  return null;
}

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

class _AdvisingCasesAdminScreenState extends State<AdvisingCasesAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _sectionTab = TabController(length: 2, vsync: this);
  final _allColleges = _UploadSlot();
  final _health = _UploadSlot();

  // نتاج AdvisingCaseAnalyzer.loadCollegeScopedStudents - تُخزَّن هنا بعد كل
  // تحميل بدل استدعائها مباشرة بالـbuild.
  List<AdvisingCaseRecord> _scopedMale = [];
  List<AdvisingCaseRecord> _scopedFemale = [];
  List<AdvisingCaseRecord> _allCollegesMaleRaw = [];
  List<AdvisingCaseRecord> _allCollegesFemaleRaw = [];
  List<AdvisingCaseRecord> _allCollegesMalePrevious = [];
  List<AdvisingCaseRecord> _allCollegesFemalePrevious = [];

  Map<String, CollegeRosterMember> _facultyByKey = {};
  List<String> _departments = [];

  bool _loading = true;
  bool _showAll = false;

  String _shatrFilter = _kAllShatr;
  String _deptFilter = _kAllDepartments;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sectionTab.dispose();
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
        _allCollegesMalePrevious = loaded.allCollegesMalePrevious;
        _allCollegesFemalePrevious = loaded.allCollegesFemalePrevious;
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

  /// حوار تحميل غير قابل للإغلاق يدويًا - يظهر أثناء معالجة الملف تحديدًا
  /// (لا طوال الرفع بالكامل) حتى لا يبدو للمستخدم أن الصفحة تجمَّدت بصمت.
  /// ملف "كل الكليات" PDF يغطي الجامعة كاملة (مئات الصفحات) فقد تستغرق
  /// معالجته دقائق - سليمان لاحظ ظهور تحذير "الصفحة لا تستجيب" من المتصفح
  /// أثناء الانتظار بلا أي مؤشر بالموقع نفسه يوضّح أن المعالجة مستمرة فعليًا
  /// (2026-08-14)، فأُضيف هذا الحوار الصريح بدل الاعتماد فقط على أيقونة
  /// صغيرة داخل الزر.
  void _showProcessingDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  void _hideProcessingDialog() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// حوار خطأ **لا يختفي تلقائيًا** (بخلاف SnackBar الذي كان يختفي بسرعة قبل
  /// أن يتمكن سليمان من قراءته/تصويره - 2026-08-14) والنص قابل للنسخ لتسهيل
  /// إرساله لتشخيص المشكلة.
  void _showErrorDialog(String title, String details) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: Colors.red.shade700)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: SelectableText(details)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _uploadAllColleges() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;

    setState(() => _allColleges.uploading = true);
    try {
      _showProcessingDialog(
        'جاري معالجة ملف "كل الكليات" - يغطي الجامعة كاملة فقد يستغرق عدة دقائق. '
        'الرجاء عدم إغلاق الصفحة أو تحديث المتصفح حتى الانتهاء.',
      );
      // يضمن رسم النافذة فعليًا على الشاشة قبل بدء المعالجة الثقيلة.
      // `endOfFrame` وحدها لم تكفِ فعليًا (لاحظ سليمان 2026-08-14 أنها لم
      // تظهر رغم إضافتها) - على الأرجح لأنها تنتظر جدولة الإطار داخليًا فقط
      // بلا ضمان رسم فعلي على شاشة المتصفح قبل حجب الخيط. `Future.delayed`
      // بمدة حقيقية تُنفَّذ عبر مؤقّت متصفح فعلي (لا مهمة دقيقة/microtask)،
      // فتضمن عودة السيطرة فعليًا لحلقة أحداث المتصفح (ورسم الإطار المعلَّق)
      // قبل استئناف الكود.
      await Future.delayed(const Duration(milliseconds: 300));

      // خريطة اسم المرشد المطبَّع ← شطره من ملف منسوبي الكلية - ملف "كل
      // الكليات" الرسمي **لا يحوي عمود "الجنس"** (نفس قيد تقرير "طلاب تابعين
      // لمرشد" الأصلي)، فيُستنتَج شطر كل صف من شطر مرشده. **قيد معروف**: يعمل
      // فقط لمرشدينا نحن (الموجودين بملف منسوبي الكلية) - مرشدون من كليات
      // أخرى لا يمكن تحديد شطرهم بهذه الطريقة، فتظهر صفوفهم استثناءً في كلا
      // الشطرين (نفس الحالة القديمة الموثَّقة بـ`advising_report_parser_service.dart`)
      // حتى يُتاح مصدر أفضل لتحديد شطرهم.
      final roster = await CollegeRosterRepository.load();
      final advisorShatrByName = {
        for (final m in roster)
          if (_shatrLabelFromFreeText(m.shatr) != null)
            normalizeAdvisorNameForMatch(m.name): _shatrLabelFromFreeText(m.shatr)!,
      };

      final AdvisingReportPdfParseResult r;
      try {
        r = await AdvisingReportPdfParserService.parseInBackground(bytes, advisorShatrByName: advisorShatrByName);
      } finally {
        _hideProcessingDialog();
      }
      final records = r.records;
      final male = records.where((r) => r.shatr == Shatr.male.label).toList();
      final female = records.where((r) => r.shatr == Shatr.female.label).toList();

      if (r.unresolvedShatrRows.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${r.unresolvedShatrRows.length} حالة بمرشد من خارج كليتنا (تعذّر تحديد شطره)'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Text(
                  'الحالات التالية مرشدها من خارج ملف منسوبي كليتنا (أو بلا اسم مرشد أصلًا) فتعذّر '
                  'تحديد شطرها - ستظهر مؤقتًا تحت كلا الشطرين معًا حتى يُتاح مصدر أفضل لتحديد شطر '
                  'مرشدي الكليات الأخرى:\n\n'
                  '${r.unresolvedShatrRows.join('\n')}',
                ),
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا')),
            ],
          ),
        );
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد اعتماد ملف "كل الكليات"'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                records.isEmpty
                    ? 'الملف لا يحتوي أي بيانات. سيُعتمد كقائمة فارغة لكلا الشطرين. هل تريد الاعتماد؟'
                    : 'تم استخراج ${male.length} سجل لشطر الطلاب و${female.length} سجل لشطر الطالبات '
                        '(${records.length} إجمالًا، كل كليات الجامعة).\n\n'
                        'سيستبدل هذا آخر رفعة معتمدة، وتُحفَظ النسخة الحالية تلقائيًا كنسخة سابقة '
                        'لبناء "تقرير حركات الإرشاد". هل تريد الاعتماد؟',
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      Future<void> saveShatr(Shatr shatr, List<AdvisingCaseRecord> shatrRecords) async {
        await AdvisingReportRepository.promoteAllCollegesToPrevious(shatr);
        await AdvisingReportRepository.save(shatr, shatrRecords, kind: AdvisingReportKind.allColleges);
      }

      if (records.isEmpty) {
        await saveShatr(Shatr.male, const []);
        await saveShatr(Shatr.female, const []);
      } else {
        if (male.isNotEmpty) await saveShatr(Shatr.male, male);
        if (female.isNotEmpty) await saveShatr(Shatr.female, female);
      }

      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد ملف "كل الكليات" بنجاح (${records.length} سجل).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('تعذّر إتمام العملية', '$e');
    } finally {
      if (mounted) setState(() => _allColleges.uploading = false);
    }
  }

  Future<void> _uploadHealth() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;

    setState(() => _health.uploading = true);
    try {
      _showProcessingDialog('جاري معالجة الملف...');
      await Future.delayed(const Duration(milliseconds: 300));
      List<AdvisingCaseRecord> records;
      var exclusionCounts = <String, int>{};
      try {
        try {
          records = AdvisingReportParserService.parse(
            bytes,
            requireDepartment: false,
            isHealthReport: true,
            exclusionCounts: exclusionCounts,
          );
        } finally {
          _hideProcessingDialog();
        }
      } on ShatrRequiredException {
        if (!mounted) return;
        final chosen = await showDialog<Shatr>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تحديد الشطر'),
            content: const Text('ملف "طلبة ذوي الإعاقة" هذا لا يحتوي عمود "الجنس" فلا يمكن فرزه تلقائيًا - '
                'حدّد الشطر الذي يمثّله هذا الملف بالكامل.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, Shatr.male), child: const Text('شطر الطلاب')),
              TextButton(onPressed: () => Navigator.pop(context, Shatr.female), child: const Text('شطر الطالبات')),
            ],
          ),
        );
        if (chosen == null) return;
        exclusionCounts = <String, int>{};
        records = AdvisingReportParserService.parse(
          bytes,
          shatr: chosen,
          requireDepartment: false,
          isHealthReport: true,
          exclusionCounts: exclusionCounts,
        );
      }

      final male = records.where((r) => r.shatr == Shatr.male.label).toList();
      final female = records.where((r) => r.shatr == Shatr.female.label).toList();

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد اعتماد ملف "طلبة ذوي الإعاقة"'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                records.isEmpty
                    ? 'الملف لا يحتوي أي بيانات. سيُعتمد كقائمة فارغة لكلا الشطرين. هل تريد الاعتماد؟'
                    : 'تم استخراج ${male.length} سجل لشطر الطلاب و${female.length} سجل لشطر الطالبات '
                        '(${records.length} إجمالًا).\n\n'
                        'سيستبدل هذا آخر نسخة معتمدة لكل شطر ظهر في الملف. هل تريد الاعتماد؟',
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      if (records.isEmpty) {
        await AdvisingReportRepository.save(Shatr.male, const [], kind: AdvisingReportKind.health);
        await AdvisingReportRepository.save(Shatr.female, const [], kind: AdvisingReportKind.health);
      } else {
        if (male.isNotEmpty) await AdvisingReportRepository.save(Shatr.male, male, kind: AdvisingReportKind.health);
        if (female.isNotEmpty) {
          await AdvisingReportRepository.save(Shatr.female, female, kind: AdvisingReportKind.health);
        }
      }

      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد ملف "طلبة ذوي الإعاقة" بنجاح (${records.length} سجل).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('تعذّر إتمام العملية', '$e');
    } finally {
      if (mounted) setState(() => _health.uploading = false);
    }
  }

  /// نطاق الطلاب الحالي بعد تطبيق فلترَي الشطر والقسم - مرتَّب حسب الشطر ثم
  /// القسم كما طُلب صراحةً.
  List<AdvisingCaseRecord> get _scopedStudents {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _scopedMale;
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _scopedFemale;
    final search = _searchCtrl.text.trim();
    return [...male, ...female]
        .where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter)
        .where((s) => search.isEmpty || s.studentName.contains(search) || s.studentId.contains(search))
        .toList()
      ..sort(_compareStudentsForDisplay);
  }

  /// ترتيب موحَّد لعرض الطلاب كما طُلب صراحةً: الشطر (الطلاب أولًا) ثم القسم
  /// (بترتيب الأقسام الخمسة الرسمي) ثم الرقم الجامعي تصاعديًا رقميًا (لا
  /// أبجديًا، وإلا سبق "9" الرقم "10").
  static int _compareStudentsForDisplay(AdvisingCaseRecord a, AdvisingCaseRecord b) {
    final s = _shatrOrder(a.shatr).compareTo(_shatrOrder(b.shatr));
    if (s != 0) return s;
    final d = _departmentOrder(a.department).compareTo(_departmentOrder(b.department));
    if (d != 0) return d;
    final idA = int.tryParse(a.studentId);
    final idB = int.tryParse(b.studentId);
    if (idA != null && idB != null) return idA.compareTo(idB);
    return a.studentId.compareTo(b.studentId);
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
    );
  }

  /// التصنيفات الأربعة الجديدة (على مرشدهم/على غير مرشدهم/مرشد خارجي لطالب
  /// داخلي/مرشد داخلي لطالب خارجي) - من السجلات الخام غير المفلتَرة (كل
  /// الكليات) حتى تظهر حالات المرشدين من خارج كليتنا، بخلاف [_analysis] الذي
  /// يُبنى من السجلات المفلتَرة لكليتنا فقط.
  CollegeAdvisingClassification get _classification {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _allCollegesMaleRaw;
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _allCollegesFemaleRaw;
    return AdvisingCaseAnalyzer.classifyAllColleges(
      allCollegeRecords: [...male, ...female],
      facultyByNameKey: _facultyByKey,
    );
  }

  /// حركات الإرشاد (تغيّر مرشد طالب بين آخر رفعتين لملف "كل الكليات").
  List<AdvisorMovement> get _advisorMovements {
    final currentMale = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _allCollegesMaleRaw;
    final currentFemale = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _allCollegesFemaleRaw;
    final previousMale = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _allCollegesMalePrevious;
    final previousFemale = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _allCollegesFemalePrevious;
    return [
      ...AdvisingCaseAnalyzer.detectAdvisorMovements(previous: previousMale, current: currentMale),
      ...AdvisingCaseAnalyzer.detectAdvisorMovements(previous: previousFemale, current: currentFemale),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'متابعة حالات الإرشاد',
      navItems: buildAdminNavItems(context, current: 'advising-cases'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      _buildUploadBar(),
                      const SizedBox(height: 16),
                      _buildFilterBar(),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
                  ),
                  child: TabBar(
                    controller: _sectionTab,
                    labelColor: AppColors.green,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: AppColors.green,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'ضبط عملية الإرشاد'),
                      Tab(text: 'النتائج والإحصائيات'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _sectionTab,
                    children: [
                      ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [_buildFixSection()]),
                      ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [_buildResultsSection()]),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildUploadBar() {
    final fmt = DateFormat('yyyy/MM/dd');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _uploadTile(
              label: 'رفع جميع الطلاب (كل الكليات)',
              uploading: _allColleges.uploading,
              maleDate: _allColleges.maleDate,
              femaleDate: _allColleges.femaleDate,
              fmt: fmt,
              onPressed: _uploadAllColleges,
              onClear: () => _clearKindBoth(AdvisingReportKind.allColleges, 'رفع جميع الطلاب (كل الكليات)'),
            ),
            const SizedBox(width: 10),
            _uploadTile(
              label: 'رفع طلبة ذوي الإعاقة',
              uploading: _health.uploading,
              maleDate: _health.maleDate,
              femaleDate: _health.femaleDate,
              fmt: fmt,
              color: Colors.purple.shade700,
              onPressed: _uploadHealth,
              onClear: () => _clearKindBoth(AdvisingReportKind.health, 'رفع طلبة ذوي الإعاقة'),
            ),
          ],
        ),
      ),
    );
  }

  /// خانة رفع موحَّدة لكلا الشطرين (ملف واحد يُفرز داخليًا) - تعرض تاريخ آخر
  /// رفع لكل شطر على حدة لأن البيانات تبقى مخزَّنة منفصلة، حتى مع رفعها معًا.
  Widget _uploadTile({
    required String label,
    required bool uploading,
    required DateTime? maleDate,
    required DateTime? femaleDate,
    required DateFormat fmt,
    required VoidCallback onPressed,
    Color? color,
    VoidCallback? onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: uploading ? null : onPressed,
                icon: uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file, size: 18),
                label: Text(label),
                style: FilledButton.styleFrom(backgroundColor: color ?? AppColors.green),
              ),
              if (onClear != null && (maleDate != null || femaleDate != null))
                IconButton(
                  tooltip: 'تفريغ البيانات (للاختبار)',
                  onPressed: onClear,
                  icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('طلاب: ${maleDate != null ? fmt.format(maleDate) : 'لم يُرفع بعد'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
          Text('طالبات: ${femaleDate != null ? fmt.format(femaleDate) : 'لم يُرفع بعد'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _clearKindBoth(AdvisingReportKind kind, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفريغ $label'),
        content: const Text('سيُحذَف كل ما هو مخزَّن حاليًا لهذا العنصر (لتسهيل إعادة اختبار الرفع). هل تريد المتابعة؟'),
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
    await AdvisingReportRepository.clear(Shatr.male, kind: kind);
    await AdvisingReportRepository.clear(Shatr.female, kind: kind);
    await _loadAll();
  }

  Widget _buildFilterBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 160,
          child: DropdownMenu<String>(
            label: const Text('الشطر'),
            initialSelection: _shatrFilter,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: _kAllShatr, label: _kAllShatr),
              DropdownMenuEntry(value: Shatr.male.label, label: Shatr.male.label),
              DropdownMenuEntry(value: Shatr.female.label, label: Shatr.female.label),
            ],
            onSelected: (v) => setState(() => _shatrFilter = v ?? _kAllShatr),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownMenu<String>(
            label: const Text('القسم'),
            initialSelection: _deptFilter,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: _kAllDepartments, label: _kAllDepartments),
              ..._departments.map((d) => DropdownMenuEntry(value: d, label: d)),
            ],
            onSelected: (v) => setState(() => _deptFilter = v ?? _kAllDepartments),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'بحث باسم أو رقم الطالب',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FilterChip(
          selected: _showAll,
          onSelected: (v) => setState(() => _showAll = v),
          avatar: Icon(Icons.visibility_outlined, size: 18, color: _showAll ? Colors.white : AppColors.green),
          label: const Text('إظهار الكل (شامل المعفَين)'),
          labelStyle: TextStyle(color: _showAll ? Colors.white : AppColors.green),
          selectedColor: AppColors.green,
          backgroundColor: AppColors.background,
          side: BorderSide(color: AppColors.green.withValues(alpha: 0.4)),
        ),
      ],
    );
  }

  /// قسم 1 من 2: "ضبط عملية الإرشاد" - كل عيوب التوزيع التي تحتاج معالجة
  /// فعلية (طلاب بلا مرشد/على غير مرشدهم، حالات صحية موزَّعة خطأ، مرشدون
  /// معفَون لديهم طلاب أو بلا طلاب رغم وجوب ذلك، تقرير النصاب) مع آلية
  /// إعادة توزيع (مرشده السابق ورقم منسوبه، والمرشد المقترح ورقم منسوبه).
  Widget _buildFixSection() {
    final a = _analysis;
    final c = _classification;
    final cards = [
      (
        'طلاب على مرشدهم',
        Icons.verified_user_outlined,
        c.studentsCorrectlyAssigned.length,
        () => _showStudentsDialog('طلاب على مرشدهم', c.studentsCorrectlyAssigned),
      ),
      (
        'طلاب بلا مرشد',
        Icons.person_off_outlined,
        c.studentsWithoutAdvisor.length,
        () => _showStudentsDialog('طلاب بلا مرشد', c.studentsWithoutAdvisor),
      ),
      (
        'طلاب على غير مرشدهم',
        Icons.compare_arrows_outlined,
        c.studentsWithWrongDeptAdvisor.length,
        () => _showMismatchDialog(c.studentsWithWrongDeptAdvisor, emptyMessage: 'لا يوجد طلبة على غير مرشدهم'),
      ),
      (
        'مرشدون من خارج الكلية يرشدون طلبة من داخل الكلية',
        Icons.arrow_circle_left_outlined,
        c.externalAdvisorsWithOurStudents.length,
        () => _showStudentsDialog('مرشدون من خارج الكلية يرشدون طلبة من داخل الكلية', c.externalAdvisorsWithOurStudents),
      ),
      (
        'مرشدون من داخل الكلية يرشدون طلبة من خارج الكلية',
        Icons.arrow_circle_right_outlined,
        c.ourAdvisorsWithExternalStudents.length,
        () => _showStudentsDialog('مرشدون من داخل الكلية يرشدون طلبة من خارج الكلية', c.ourAdvisorsWithExternalStudents),
      ),
      (
        'مرشدون معفَون ولديهم طلاب',
        Icons.report_gmailerrorred_outlined,
        a.exemptAdvisorsWithStudents.length,
        () => _showExemptWithStudentsDialog(a.exemptAdvisorsWithStudents),
      ),
      (
        'مرشدون بلا طلاب',
        Icons.person_search_outlined,
        a.advisorsWithNoStudents.length,
        () => _showAdvisorsDialog('مرشدون بلا طلاب', a.advisorsWithNoStudents),
      ),
      (
        'تقرير النصاب (فوق/دون الحصة العادلة)',
        Icons.balance_outlined,
        a.quotaReport.where((q) => q.status != QuotaStatus.balanced).length,
        () => _showQuotaReportDialog(a.quotaReport),
      ),
      (
        'تقرير إعادة التوزيع',
        Icons.swap_horiz_outlined,
        a.transferSuggestions.length,
        () => _showTransferDialog(a.transferSuggestions),
      ),
      (
        'حالات صحية غير موزَّعة بشكل صحيح',
        Icons.medical_services_outlined,
        a.healthCasesNotWithAmin.length,
        () => _showHealthMismatchDialog(a.healthCasesNotWithAmin),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCardsGrid(cards),
        if (_showAll && a.exemptAdvisorsNoIssue.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              InkWell(
                onTap: () => _showAdvisorsDialog('مرشدون معفَون من الإرشاد (طبيعي، لا خلل)', a.exemptAdvisorsNoIssue, gray: true),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey.shade600, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${a.exemptAdvisorsNoIssue.length}',
                                style: AppTextStyles.h3(color: Colors.grey.shade700)),
                            Text('مرشدون معفَون (طبيعي)', style: AppTextStyles.caption()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// قسم 2 من 2: "النتائج والإحصائيات" - حركات الإرشاد (تغيّر مرشد طالب بين
  /// آخر رفعتين)، إجمالي ذوي الإعاقة، وكشف كل الطلاب في النطاق الحالي. بطاقتا
  /// المعدل والمفصولين مُعطَّلتان مؤقتًا (تعتمدان على "بيانات الطلبة
  /// الأكاديمية" المجمَّدة حاليًا - انظر توثيق الشاشة أعلاه).
  Widget _buildResultsSection() {
    final movements = _advisorMovements;
    final a = _analysis;
    final cards = [
      (
        'حركات الإرشاد (تغيّر مرشد الطالب)',
        Icons.sync_alt_outlined,
        movements.length,
        () => _showMovementsDialog(movements),
      ),
      (
        'إجمالي حالات ذوي الإعاقة (طلاب ${a.healthCaseStudents.where((s) => s.shatr == Shatr.male.label).length} / '
            'طالبات ${a.healthCaseStudents.where((s) => s.shatr == Shatr.female.label).length})',
        Icons.accessible_outlined,
        a.healthCaseStudents.length,
        () => _showStudentsDialog('كل حالات ذوي الإعاقة', a.healthCaseStudents),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCardsGrid(cards),
        const SizedBox(height: 16),
        _buildAtRiskSection(),
      ],
    );
  }

  /// حوار "حركات الإرشاد": من المرشد ← إلى المرشد لكل طالب تغيّر مرشده بين
  /// آخر رفعتين لملف "كل الكليات" - طلب سليمان صراحةً (2026-08-14).
  void _showMovementsDialog(List<AdvisorMovement> movements) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حركات الإرشاد (${movements.length})'),
        content: SizedBox(
          width: 720,
          height: 480,
          child: movements.isEmpty
              ? Center(child: Text('لا توجد حركات إرشاد منذ آخر رفعتين', style: TextStyle(color: Colors.grey.shade600)))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(AppColors.green),
                    headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('الطالب')),
                      DataColumn(label: Text('الرقم الجامعي')),
                      DataColumn(label: Text('من مرشد')),
                      DataColumn(label: Text('إلى مرشد')),
                    ],
                    rows: [
                      for (var i = 0; i < movements.length; i++)
                        DataRow(
                          color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                          cells: [
                            DataCell(Text(movements[i].student.studentName)),
                            DataCell(Text(movements[i].student.studentId)),
                            DataCell(Text(movements[i].fromAdvisorNameRaw.isEmpty ? '—' : movements[i].fromAdvisorNameRaw)),
                            DataCell(Text(movements[i].toAdvisorNameRaw.isEmpty ? '—' : movements[i].toAdvisorNameRaw)),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: movements.isEmpty
                ? null
                : () => _exportExcel(
                      'حركات الإرشاد',
                      ['الطالب', 'الرقم الجامعي', 'من مرشد', 'إلى مرشد'],
                      movements
                          .map((m) => [m.student.studentName, m.student.studentId, m.fromAdvisorNameRaw, m.toAdvisorNameRaw])
                          .toList(),
                    ),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: movements.isEmpty
                ? null
                : () async {
                    final headers = ['الطالب', 'الرقم الجامعي', 'من مرشد', 'إلى مرشد'];
                    final rows = movements
                        .map((m) => [m.student.studentName, m.student.studentId, m.fromAdvisorNameRaw, m.toAdvisorNameRaw])
                        .toList();
                    final bytes = await AdvisingCasePdfService.build(title: 'حركات الإرشاد', headers: headers, rows: rows);
                    await Printing.sharePdf(bytes: bytes, filename: 'حركات_الإرشاد.pdf');
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF/طباعة'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildCardsGrid(List<(String, IconData, int, VoidCallback)> cards) {
    const crossAxisCount = 4;
    const spacing = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((c) {
            final (label, icon, count, onTap) = c;
            final alert = count > 0;
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                width: itemWidth,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: alert ? Colors.red.shade300 : AppColors.green.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: alert ? Colors.red.shade700 : AppColors.green, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$count', style: AppTextStyles.h2(color: alert ? Colors.red.shade700 : AppColors.greenDark)),
                          Text(label, style: AppTextStyles.caption(), maxLines: 2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAtRiskSection() {
    final students = _scopedStudents;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('كل الطلاب في النطاق الحالي (${students.length})', style: AppTextStyles.h3(color: AppColors.greenDark)),
              const Spacer(),
              TextButton.icon(
                onPressed: students.isEmpty
                    ? null
                    : () => _exportExcel('كشف بيانات الطلبة والحالة الأكاديمية', _studentsExportHeaders(),
                        _studentsExportRows(students)),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Excel'),
              ),
              TextButton.icon(
                onPressed: students.isEmpty ? null : () => _exportPdf('كشف بيانات الطلبة والحالة الأكاديمية', students),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF/طباعة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _studentsTable(
            students,
            showDepartment: _deptFilter == _kAllDepartments,
            showShatr: _shatrFilter == _kAllShatr,
          ),
        ],
      ),
    );
  }

  // ------------------------------- عناصر مشتركة -------------------------------

  Widget _gpaChip(double? gpa) {
    final status = gpaStatusOf(gpa);
    final color = switch (status) {
      GpaStatus.excellent || GpaStatus.veryGood => AppColors.green,
      GpaStatus.good => Colors.grey.shade700,
      GpaStatus.pass => Colors.orange.shade800,
      GpaStatus.weak => Colors.red.shade700,
      GpaStatus.unknown => Colors.grey.shade400,
    };
    final text = gpa == null ? '—' : '${gpa.toStringAsFixed(2)} (${status.label})';
    return Chip(
      label: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _studentsTable(
    List<AdvisingCaseRecord> students, {
    bool showDepartment = true,
    bool showShatr = true,
    bool showAdvisor = true,
  }) {
    if (students.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات')));
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.green),
          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          columns: [
            const DataColumn(label: Center(child: Text('الاسم'))),
            const DataColumn(label: Center(child: Text('الرقم الجامعي'))),
            if (showDepartment) const DataColumn(label: Center(child: Text('القسم'))),
            if (showShatr) const DataColumn(label: Center(child: Text('الشطر'))),
            if (showAdvisor) const DataColumn(label: Center(child: Text('المرشد'))),
            const DataColumn(label: Center(child: Text('النطاق السابق'))),
            const DataColumn(label: Center(child: Text('النطاق الحالي'))),
          ],
          rows: [
            for (var i = 0; i < students.length; i++)
              DataRow(
                color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                cells: [
                  DataCell(Center(child: Text(students[i].studentName))),
                  DataCell(Center(child: Text(students[i].studentId))),
                  if (showDepartment) DataCell(Center(child: Text(students[i].department))),
                  if (showShatr) DataCell(Center(child: Text(students[i].shatr))),
                  if (showAdvisor)
                    DataCell(Center(
                        child: Text(students[i].advisorNameRaw.isEmpty ? '—' : students[i].advisorNameRaw))),
                  DataCell(Center(child: _gpaChip(students[i].previousGpa))),
                  DataCell(Center(child: _gpaChip(students[i].gpa))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static List<String> _studentsExportHeaders() =>
      ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد', 'المعدل', 'الحالة الدراسية'];

  static List<List<String>> _studentsExportRows(List<AdvisingCaseRecord> students) => students
      .map((s) => [
            s.studentName,
            s.studentId,
            s.department,
            s.shatr,
            s.advisorNameRaw.isEmpty ? '—' : s.advisorNameRaw,
            s.gpa == null ? '—' : s.gpa!.toStringAsFixed(2),
            s.enrollmentStatus.isEmpty ? '—' : s.enrollmentStatus,
          ])
      .toList();

  Future<void> _exportPdf(String title, List<AdvisingCaseRecord> students) async {
    final bytes = await AdvisingCasePdfService.build(
      title: title,
      headers: _studentsExportHeaders(),
      rows: _studentsExportRows(students),
    );
    await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
  }

  void _exportExcel(String title, List<String> headers, List<List<String>> rows) {
    final bytes = AdvisingCaseExcelService.build(title: title, headers: headers, rows: rows);
    downloadBytes(bytes, '$title.xlsx');
  }

  void _showStudentsDialog(String title, List<AdvisingCaseRecord> students) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title (${students.length})'),
        content: SizedBox(width: 700, child: _studentsTable(students)),
        actions: [
          TextButton.icon(
            onPressed: students.isEmpty
                ? null
                : () => _exportExcel(title, _studentsExportHeaders(), _studentsExportRows(students)),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: students.isEmpty ? null : () => _exportPdf(title, students),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF/طباعة'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  /// مجمَّعة حسب المرشد (اسمه + رقم منسوبه المسجَّل في التقرير) بدل جدول
  /// مسطَّح - حتى يسهل معالجة كل مرشد على حدة (خصوصًا المرشدين غير الموجودين
  /// في ملف منسوبي الكلية، الذين يحتاجون تحققًا يدويًا من المنظومة الجامعية).
  void _showMismatchDialog(
    List<MismatchedAdvisorCase> cases, {
    String title = 'طلاب على غير مرشدهم',
    bool gray = false,
    String emptyMessage = 'لا توجد حالات',
  }) {
    final groups = <String, List<MismatchedAdvisorCase>>{};
    for (final c in cases) {
      final key = c.student.advisorNameRaw.isEmpty ? '(بلا اسم مرشد)' : c.student.advisorNameRaw;
      groups.putIfAbsent(key, () => []).add(c);
    }
    final advisorNames = groups.keys.toList()..sort();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title (${cases.length})'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: cases.isEmpty
              ? Center(child: Text(emptyMessage, style: TextStyle(color: Colors.grey.shade600)))
              : ListView(
            children: [
              for (final advisorName in advisorNames) ...[
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (gray ? Colors.grey.shade600 : AppColors.green).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 18, color: gray ? Colors.grey.shade700 : AppColors.greenDark),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'المرشد: $advisorName'
                          '${groups[advisorName]!.first.student.advisorId.isNotEmpty ? "  -  رقم المنسوب: ${groups[advisorName]!.first.student.advisorId}" : ""}'
                          '${groups[advisorName]!.first.advisor == null ? "  ⚠️ غير موجود في ملف منسوبي الكلية" : ""}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: groups[advisorName]!.first.advisor == null ? Colors.red.shade700 : null,
                          ),
                        ),
                      ),
                      Text('(${groups[advisorName]!.length})'),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 32,
                    dataRowMinHeight: 32,
                    dataRowMaxHeight: 36,
                    columns: const [
                      DataColumn(label: Text('الطالب')),
                      DataColumn(label: Text('الرقم الجامعي')),
                      DataColumn(label: Text('قسم الطالب')),
                      DataColumn(label: Text('الشطر')),
                    ],
                    rows: [
                      for (final c in groups[advisorName]!)
                        DataRow(cells: [
                          DataCell(Text(c.student.studentName)),
                          DataCell(Text(c.student.studentId)),
                          DataCell(Text(c.student.department)),
                          DataCell(Text(c.student.shatr)),
                        ]),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () => _exportExcel(title, _studentsExportHeaders(),
                    _studentsExportRows(cases.map((c) => c.student).toList())),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () => _exportPdf(
                      title,
                      cases.map((c) => c.student).toList(),
                    ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF/طباعة'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _showExemptWithStudentsDialog(List<ExemptAdvisorWithStudentsCase> cases) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('مرشدون معفَون ولديهم طلاب - يجب نقل طلابهم (${cases.length})'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in cases)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.advisor.name} - ${c.advisor.department} (معفى من الإرشاد)',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('لديه ${c.students.length} طالب يجب نقلهم', style: TextStyle(color: Colors.red.shade700)),
                          const SizedBox(height: 4),
                          Text(c.students.map((s) => s.studentName).join('، '), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () => _exportExcel(
                      'مرشدون معفَون ولديهم طلاب',
                      ['الطالب', 'الرقم الجامعي', 'القسم', 'المرشد المعفى', 'قسم المرشد'],
                      [
                        for (final c in cases)
                          for (final s in c.students)
                            [s.studentName, s.studentId, s.department, c.advisor.name, c.advisor.department],
                      ],
                    ),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _showAdvisorsDialog(String title, List<CollegeRosterMember> advisors, {bool gray = false}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title (${advisors.length})'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(gray ? Colors.grey.shade600 : AppColors.green),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('الاسم')),
                DataColumn(label: Text('القسم')),
                DataColumn(label: Text('الشطر')),
                DataColumn(label: Text('السبب')),
              ],
              rows: [
                for (var i = 0; i < advisors.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(gray
                        ? Colors.grey.shade100
                        : (i.isEven ? Colors.white : const Color(0xFFF7F5EF))),
                    cells: [
                      DataCell(Text(advisors[i].name, style: TextStyle(color: gray ? Colors.grey.shade700 : null))),
                      DataCell(Text(advisors[i].department, style: TextStyle(color: gray ? Colors.grey.shade700 : null))),
                      DataCell(Text(advisors[i].shatr, style: TextStyle(color: gray ? Colors.grey.shade700 : null))),
                      DataCell(Text(advisors[i].advisingReason,
                          style: TextStyle(color: gray ? Colors.grey.shade600 : null, fontSize: 12))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: advisors.isEmpty
                ? null
                : () => _exportExcel(
                      title,
                      ['الاسم', 'القسم', 'الشطر', 'السبب'],
                      advisors.map((a) => [a.name, a.department, a.shatr, a.advisingReason]).toList(),
                    ),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  static String _quotaStatusLabel(QuotaStatus s) => switch (s) {
        QuotaStatus.over => 'فوق النصاب',
        QuotaStatus.under => 'دون النصاب',
        QuotaStatus.balanced => 'متوازن',
      };

  static Color _quotaStatusColor(QuotaStatus s) => switch (s) {
        QuotaStatus.over => Colors.red.shade700,
        QuotaStatus.under => Colors.orange.shade800,
        QuotaStatus.balanced => Colors.grey.shade600,
      };

  /// تقرير النصاب الكامل لكل مرشدي النطاق الحالي - يشمل الفائضين والناقصين
  /// والمتوازنين معًا، بخلاف البطاقة السابقة التي كانت تقتصر على الفائضين.
  void _showQuotaReportDialog(List<AdvisorQuotaCase> cases) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تقرير النصاب (${cases.length} مرشد)'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.green),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('المرشد')),
                DataColumn(label: Text('القسم')),
                DataColumn(label: Text('العدد الحالي')),
                DataColumn(label: Text('الحصة العادلة')),
                DataColumn(label: Text('الحالة')),
              ],
              rows: [
                for (var i = 0; i < cases.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                    cells: [
                      DataCell(Text(cases[i].advisor.name)),
                      DataCell(Text(cases[i].advisor.department)),
                      DataCell(Text('${cases[i].actualCount}')),
                      DataCell(Text(cases[i].fairShare.toStringAsFixed(1))),
                      DataCell(Text(
                        _quotaStatusLabel(cases[i].status),
                        style: TextStyle(fontWeight: FontWeight.bold, color: _quotaStatusColor(cases[i].status)),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () => _exportExcel(
                      'تقرير النصاب',
                      ['المرشد', 'القسم', 'العدد الحالي', 'الحصة العادلة', 'الحالة'],
                      cases
                          .map((c) => [
                                c.advisor.name,
                                c.advisor.department,
                                '${c.actualCount}',
                                c.fairShare.toStringAsFixed(1),
                                _quotaStatusLabel(c.status),
                              ])
                          .toList(),
                    ),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () async {
                    final headers = ['المرشد', 'القسم', 'العدد الحالي', 'الحصة العادلة', 'الحالة'];
                    final rows = cases
                        .map((c) => [
                              c.advisor.name,
                              c.advisor.department,
                              '${c.actualCount}',
                              c.fairShare.toStringAsFixed(1),
                              _quotaStatusLabel(c.status),
                            ])
                        .toList();
                    final bytes = await AdvisingCasePdfService.build(title: 'تقرير النصاب', headers: headers, rows: rows);
                    await Printing.sharePdf(bytes: bytes, filename: 'تقرير_النصاب.pdf');
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF/طباعة'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _showTransferDialog(List<TransferSuggestion> suggestions) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تقرير إعادة التوزيع (${suggestions.length})'),
        content: SizedBox(
          width: 820,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.green),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('الطالب')),
                DataColumn(label: Text('رقمه')),
                DataColumn(label: Text('تخصصه')),
                DataColumn(label: Text('المرشد السابق')),
                DataColumn(label: Text('رقمه')),
                DataColumn(label: Text('المرشد الموصى به')),
                DataColumn(label: Text('رقمه')),
              ],
              rows: [
                for (var i = 0; i < suggestions.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                    cells: [
                      DataCell(Text(suggestions[i].student.studentName)),
                      DataCell(Text(suggestions[i].student.studentId)),
                      DataCell(Text(suggestions[i].student.department)),
                      DataCell(Text(suggestions[i].fromAdvisorNameRaw)),
                      DataCell(Text(suggestions[i].fromAdvisor?.staffNumber.ifEmptyDash() ?? '—')),
                      DataCell(Text(suggestions[i].toAdvisor?.name ?? 'لم يُحدَّد آليًا - يلزم قرار يدوي',
                          style: TextStyle(color: suggestions[i].toAdvisor == null ? Colors.red.shade700 : null))),
                      DataCell(Text(suggestions[i].toAdvisor?.staffNumber.ifEmptyDash() ?? '—')),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: suggestions.isEmpty
                ? null
                : () => _exportExcel(
                      'تقرير إعادة التوزيع',
                      ['الطالب', 'رقمه', 'تخصصه', 'المرشد السابق', 'رقمه', 'المرشد الموصى به', 'رقمه'],
                      suggestions
                          .map((s) => [
                                s.student.studentName,
                                s.student.studentId,
                                s.student.department,
                                s.fromAdvisorNameRaw,
                                s.fromAdvisor?.staffNumber.ifEmptyDash() ?? '—',
                                s.toAdvisor?.name ?? 'يلزم قرار يدوي',
                                s.toAdvisor?.staffNumber.ifEmptyDash() ?? '—',
                              ])
                          .toList(),
                    ),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: suggestions.isEmpty
                ? null
                : () async {
                    final headers = ['الطالب', 'رقمه', 'تخصصه', 'المرشد السابق', 'رقمه', 'المرشد الموصى به', 'رقمه'];
                    final rows = suggestions
                        .map((s) => [
                              s.student.studentName,
                              s.student.studentId,
                              s.student.department,
                              s.fromAdvisorNameRaw,
                              s.fromAdvisor?.staffNumber.ifEmptyDash() ?? '—',
                              s.toAdvisor?.name ?? 'يلزم قرار يدوي',
                              s.toAdvisor?.staffNumber.ifEmptyDash() ?? '—',
                            ])
                        .toList();
                    final bytes = await AdvisingCasePdfService.build(title: 'تقرير إعادة التوزيع', headers: headers, rows: rows);
                    await Printing.sharePdf(bytes: bytes, filename: 'تقرير_إعادة_التوزيع.pdf');
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF/طباعة'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _showHealthMismatchDialog(List<HealthCaseMismatch> cases) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حالات صحية غير موزَّعة بشكل صحيح (${cases.length})'),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.purple.shade700),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('الطالب')),
                DataColumn(label: Text('رقمه')),
                DataColumn(label: Text('تخصصه')),
                DataColumn(label: Text('الحالة الصحية')),
                DataColumn(label: Text('التوزيع')),
                DataColumn(label: Text('المرشد الحالي')),
                DataColumn(label: Text('رقمه')),
                DataColumn(label: Text('المرشد المفترض')),
                DataColumn(label: Text('رقمه')),
              ],
              rows: [
                for (var i = 0; i < cases.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                    cells: [
                      DataCell(Text(cases[i].student.studentName)),
                      DataCell(Text(cases[i].student.studentId)),
                      DataCell(Text(cases[i].student.department)),
                      DataCell(Text(cases[i].student.healthCondition)),
                      const DataCell(Text('خاطئ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                      DataCell(Text(cases[i].currentAdvisor?.name ??
                          (cases[i].student.hasAdvisor ? cases[i].student.advisorNameRaw : 'بلا مرشد'))),
                      DataCell(Text(cases[i].currentAdvisor?.staffNumber.ifEmptyDash() ?? '—')),
                      DataCell(Text(cases[i].departmentAmin?.name ?? 'غير معروف',
                          style: TextStyle(color: cases[i].departmentAmin == null ? Colors.red.shade700 : null))),
                      DataCell(Text(cases[i].departmentAmin?.staffNumber.ifEmptyDash() ?? '—')),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () => _exportExcel(
                      'حالات صحية غير موزَّعة بشكل صحيح',
                      [
                        'الطالب',
                        'رقمه',
                        'تخصصه',
                        'الحالة الصحية',
                        'التوزيع',
                        'المرشد الحالي',
                        'رقمه',
                        'المرشد المفترض',
                        'رقمه',
                      ],
                      cases
                          .map((c) => [
                                c.student.studentName,
                                c.student.studentId,
                                c.student.department,
                                c.student.healthCondition,
                                'خاطئ',
                                c.currentAdvisor?.name ??
                                    (c.student.hasAdvisor ? c.student.advisorNameRaw : 'بلا مرشد'),
                                c.currentAdvisor?.staffNumber.ifEmptyDash() ?? '—',
                                c.departmentAmin?.name ?? 'غير معروف',
                                c.departmentAmin?.staffNumber.ifEmptyDash() ?? '—',
                              ])
                          .toList(),
                    ),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: cases.isEmpty
                ? null
                : () async {
                    final headers = [
                      'الطالب',
                      'رقمه',
                      'تخصصه',
                      'الحالة الصحية',
                      'التوزيع',
                      'المرشد الحالي',
                      'رقمه',
                      'المرشد المفترض',
                      'رقمه',
                    ];
                    final rows = cases
                        .map((c) => [
                              c.student.studentName,
                              c.student.studentId,
                              c.student.department,
                              c.student.healthCondition,
                              'خاطئ',
                              c.currentAdvisor?.name ?? (c.student.hasAdvisor ? c.student.advisorNameRaw : 'بلا مرشد'),
                              c.currentAdvisor?.staffNumber.ifEmptyDash() ?? '—',
                              c.departmentAmin?.name ?? 'غير معروف',
                              c.departmentAmin?.staffNumber.ifEmptyDash() ?? '—',
                            ])
                        .toList();
                    final bytes = await AdvisingCasePdfService.build(
                        title: 'حالات صحية غير موزَّعة بشكل صحيح', headers: headers, rows: rows);
                    await Printing.sharePdf(bytes: bytes, filename: 'الحالات_الصحية.pdf');
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF/طباعة'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmptyDash() => isEmpty ? '—' : this;
}
