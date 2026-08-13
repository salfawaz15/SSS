import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../data/academic_department_names.dart';
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
import '../utils/name_display.dart';
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

/// صفحة "متابعة حالات الإرشاد" - قلب مشروع وحدة الإرشاد الأكاديمي: تدمج ثلاثة
/// تقارير من المنظومة الداخلية (بيانات الطلبة الأكاديمية + طلاب تابعين لمرشد
/// + طلاب غير تابعين لمرشد) مع بيانات منسوبي الكلية الموجودة أصلاً بالتطبيق
/// (عبء الإرشاد يُقرأ تلقائيًا من هناك، بلا أي إدخال يدوي جديد هنا) لاستنتاج
/// كل حالات الإرشاد التي تحتاج متابعة أو تصحيح.
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
  final _base = _UploadSlot();
  final _assigned = _UploadSlot();
  final _unassigned = _UploadSlot();
  final _health = _UploadSlot();
  final _mismatch = _UploadSlot();
  List<AdvisingCaseRecord> _basePreviousMale = [];
  List<AdvisingCaseRecord> _basePreviousFemale = [];

  Map<String, CollegeRosterMember> _facultyByKey = {};
  List<String> _departments = [];

  /// خريطة اسم المرشد المطبَّع ← شطره، من قائمة منسوبي الكلية - تُستخدم
  /// لاستنتاج شطر الطالب تلقائيًا في تقارير ربط المرشد التي لا تحوي عمود
  /// "الجنس" ولا عنوان صفحة يفرّق الشطرين (انظر توثيق [AdvisingReportParserService.parse]).
  Map<String, String> _advisorShatrByName = {};

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
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.base),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.base),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.base),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.base),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.assigned),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.assigned),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.assigned),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.assigned),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.unassigned),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.unassigned),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.unassigned),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.unassigned),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.health),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.health),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.health),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.health),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.basePrevious),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.basePrevious),
        AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.mismatch),
        AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.mismatch),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.mismatch),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.mismatch),
        CollegeRosterRepository.load(),
      ]);
      if (!mounted) return;
      final roster = results[22] as List<CollegeRosterMember>;
      setState(() {
        _base.male = results[0] as List<AdvisingCaseRecord>;
        _base.female = results[1] as List<AdvisingCaseRecord>;
        _base.maleDate = results[2] as DateTime?;
        _base.femaleDate = results[3] as DateTime?;
        _assigned.male = results[4] as List<AdvisingCaseRecord>;
        _assigned.female = results[5] as List<AdvisingCaseRecord>;
        _assigned.maleDate = results[6] as DateTime?;
        _assigned.femaleDate = results[7] as DateTime?;
        _unassigned.male = results[8] as List<AdvisingCaseRecord>;
        _unassigned.female = results[9] as List<AdvisingCaseRecord>;
        _unassigned.maleDate = results[10] as DateTime?;
        _unassigned.femaleDate = results[11] as DateTime?;
        _health.male = results[12] as List<AdvisingCaseRecord>;
        _health.female = results[13] as List<AdvisingCaseRecord>;
        _health.maleDate = results[14] as DateTime?;
        _health.femaleDate = results[15] as DateTime?;
        _basePreviousMale = results[16] as List<AdvisingCaseRecord>;
        _basePreviousFemale = results[17] as List<AdvisingCaseRecord>;
        _mismatch.male = results[18] as List<AdvisingCaseRecord>;
        _mismatch.female = results[19] as List<AdvisingCaseRecord>;
        _mismatch.maleDate = results[20] as DateTime?;
        _mismatch.femaleDate = results[21] as DateTime?;
        _facultyByKey = {
          for (final m in roster) AdvisingCaseAnalyzer.nameKey(displayName(m.name)): m,
        };
        _advisorShatrByName = {
          for (final m in roster)
            if (_shatrLabelFromFreeText(m.shatr) != null)
              normalizeAdvisorNameForMatch(m.name): _shatrLabelFromFreeText(m.shatr)!,
        };
        // فلتر القسم هنا لفرز الطلاب حسب قسمهم العلمي فقط - لا معنى لظهور
        // جهات الإداريين (مكتب العميد، مركز الخدمات...) بينها، فالطلاب لا
        // ينتمون لأي منها أصلاً.
        _departments = roster
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

  /// خاص بتقرير "طلاب تابعين لمرشد" عبر PDF فقط: سليمان بدأ يدمج بملف واحد
  /// كلية إدارة الأعمال كاملة + كلية الحاسبات كاملة (2026-08-13، لضمان شمول
  /// طلاب د. طارق حلمي المسندين إليه رغم كونه إداريًا بكلية أخرى - انظر
  /// [[project_tariq_helmy_secondment]] بالذاكرة) بدل ملف مفلتَر لكليتنا فقط
  /// كسابقًا. تُبقي فقط صفوف "التخصص" المطابقة لأحد الأقسام الخمسة المعروفة
  /// لكليتنا (`isKnownBachelorDepartment`) - فطلاب كلية الحاسبات بغير تخصص
  /// "نظم المعلومات الإدارية" (علوم حاسب، هندسة برمجيات...) يُستبعَدون تلقائيًا،
  /// بينما طلاب طارق حلمي (تخصصهم "نظم المعلومات الإدارية" فعليًا) يمرّون
  /// بلا أي علم استثناء يدوي. بلا أثر على ملف كليتنا وحدها (كل صفوفه أصلًا
  /// من الأقسام الخمسة المعروفة).
  List<AdvisingCaseRecord> _filterToOurCollegeDepartments(
    List<AdvisingCaseRecord> records,
    Map<String, int> exclusionCounts,
  ) {
    final kept = <AdvisingCaseRecord>[];
    for (final r in records) {
      if (isKnownBachelorDepartment(normalizeDepartmentName(r.department))) {
        kept.add(r);
      } else {
        final rawDept = r.department.trim();
        exclusionCounts.update(
          'تخصص خارج كليتنا (${rawDept.isEmpty ? "فارغ" : rawDept})',
          (v) => v + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return kept;
  }

  Future<void> _uploadForKind(
    AdvisingReportKind kind,
    _UploadSlot slot,
    String reportLabel, {
    bool requireDepartment = true,
  }) async {
    // "طلاب تابعين لمرشد" فقط يُقبَل PDF مباشرةً (التقرير الرسمي كما يخرج من
    // المنظومة، دون تحويله يدويًا إلى Word أولًا كبقية التقارير).
    final acceptsPdf = kind == AdvisingReportKind.assigned;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: acceptsPdf ? ['docx', 'pdf'] : ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;
    final isPdf = (result.files.single.extension ?? '').toLowerCase() == 'pdf';

    setState(() => slot.uploading = true);

    try {
      List<AdvisingCaseRecord> records;
      List<String> unresolvedShatrRows = const [];
      var exclusionCounts = <String, int>{};
      try {
        if (isPdf) {
          final r = await AdvisingReportPdfParserService.parseInBackground(bytes, advisorShatrByName: _advisorShatrByName);
          exclusionCounts = r.exclusionCounts;
          records = kind == AdvisingReportKind.assigned
              ? _filterToOurCollegeDepartments(r.records, exclusionCounts)
              : r.records;
          unresolvedShatrRows = r.unresolvedShatrRows;
        } else {
          exclusionCounts = <String, int>{};
          final parsed = AdvisingReportParserService.parse(
            bytes,
            requireDepartment: requireDepartment,
            advisorShatrByName: _advisorShatrByName,
            isHealthReport: kind == AdvisingReportKind.health,
            exclusionCounts: exclusionCounts,
          );
          records = kind == AdvisingReportKind.assigned
              ? _filterToOurCollegeDepartments(parsed, exclusionCounts)
              : parsed;
        }
      } on ShatrRequiredException {
        // الملف لا يحوي عمود "الجنس" فلا يمكن فرزه تلقائيًا - يُطلَب من
        // المستخدم تحديد الشطر الذي يمثّله الملف بالكامل مرة واحدة فقط.
        if (!mounted) return;
        final chosen = await showDialog<Shatr>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تحديد الشطر'),
            content: Text('ملف "$reportLabel" هذا لا يحتوي عمود "الجنس" فلا يمكن فرزه تلقائيًا - '
                'حدّد الشطر الذي يمثّله هذا الملف بالكامل.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, Shatr.male), child: const Text('شطر الطلاب')),
              TextButton(onPressed: () => Navigator.pop(context, Shatr.female), child: const Text('شطر الطالبات')),
            ],
          ),
        );
        if (chosen == null) return;
        if (isPdf) {
          final r = await AdvisingReportPdfParserService.parseInBackground(bytes, shatr: chosen);
          exclusionCounts = r.exclusionCounts;
          records = kind == AdvisingReportKind.assigned
              ? _filterToOurCollegeDepartments(r.records, exclusionCounts)
              : r.records;
          unresolvedShatrRows = r.unresolvedShatrRows;
        } else {
          exclusionCounts = <String, int>{};
          final parsed = AdvisingReportParserService.parse(
            bytes,
            shatr: chosen,
            requireDepartment: requireDepartment,
            isHealthReport: kind == AdvisingReportKind.health,
            exclusionCounts: exclusionCounts,
          );
          records = kind == AdvisingReportKind.assigned
              ? _filterToOurCollegeDepartments(parsed, exclusionCounts)
              : parsed;
        }
      }

      // بعض الصفوف قد يتعذّر تحديد شطرها مباشرةً (الحالة الشائعة: مرشد الصف
      // غير موجود بملف منسوبي الكلية فلا تُعرَف صفته منه) - لم تُستبعَد، بل
      // أُضيفت لكلا الشطرين وتُفلتَر تلقائيًا للشطر الصحيح عند الدمج ببيانات
      // الطلبة (انظر التعليق بـadvising_report_parser_service.dart)، فتظهر
      // تحت "طلاب على غير مرشدهم" لا "بلا مرشد". هذا التنبيه للعلم فقط.
      if (unresolvedShatrRows.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${unresolvedShatrRows.length} حالة بمرشد غير موثَّق'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Text(
                  'الحالات التالية لها مرشد غير موجود بملف منسوبي الكلية (أو بلا اسم مرشد أصلًا) '
                  'فتعذّر تحديد شطرها من اسم مرشدها - ستظهر تحت "طلاب على غير مرشدهم" '
                  'حتى يُتحقَّق من مرشدها ويُضاف/يُصحَّح بملف منسوبي الكلية:\n\n'
                  '${unresolvedShatrRows.join('\n')}',
                ),
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا')),
            ],
          ),
        );
      }

      final male = records.where((r) => r.shatr == Shatr.male.label).toList();
      final female = records.where((r) => r.shatr == Shatr.female.label).toList();

      // ملف فارغ (بلا أي جدول) حالة طبيعية متوقَّعة لبعض التقارير (مثال:
      // "مرشدين ليس لهم طلاب" حين لا توجد حالة واحدة) - لا يُرفض، فقط يُعتمد
      // كقائمة فارغة بعد تأكيد صريح.
      final totalExcluded = exclusionCounts.values.fold<int>(0, (a, b) => a + b);
      final exclusionLines =
          exclusionCounts.entries.map((e) => '- ${e.key}: ${e.value}').join('\n');

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد اعتماد التقرير'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                records.isEmpty
                    ? 'الملف لا يحتوي أي بيانات (تقرير فارغ) - $reportLabel.\n\n'
                        'سيُعتمد كقائمة فارغة لكلا الشطرين. هل تريد الاعتماد؟'
                    : 'تم استخراج ${male.length} سجل لشطر الطلاب و${female.length} سجل لشطر الطالبات '
                        '(${records.length} إجمالًا) - $reportLabel.\n\n'
                        '${totalExcluded > 0 ? 'استُبعد $totalExcluded صف من الملف الخام قبل الاعتماد:\n$exclusionLines\n\n' : ''}'
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

      Future<void> saveShatr(Shatr shatr, List<AdvisingCaseRecord> shatrRecords) async {
        // قبل استبدال "بيانات الطلبة" (القاعدة) تحديدًا: احفظ النسخة الحالية
        // كنسخة سابقة أولاً - مصدر "النطاق السابق" للمعدل في المقارنة القادمة.
        if (kind == AdvisingReportKind.base) {
          await AdvisingReportRepository.promoteBaseToPrevious(shatr);
        }
        await AdvisingReportRepository.save(shatr, shatrRecords, kind: kind);
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
        SnackBar(content: Text('تم اعتماد $reportLabel بنجاح (${records.length} سجل).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر قراءة الملف: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => slot.uploading = false);
    }
  }

  /// إجمالي حالات الإرشاد المحلَّلة عبر الشطرين وكل الأقسام (بلا أي فلتر
  /// واجهة) - كل طالب نشط يقع في واحدة فقط من الحالات الثلاث الرئيسية (على
  /// مرشده/بلا مرشد/على غير مرشده - انظر [AdvisingCaseAnalyzer.analyze])
  /// بالإضافة للمفصولين المستبعَدين من التحليل الرئيسي، فمجموع الأربعة يجب
  /// أن يطابق منطقيًا إجمالي "بيانات الطلبة الأكاديمية" المرفوعة إن كانت
  /// شاملة فعلًا لكل طلاب الكلية - يُستخدَم كبطاقة تحقّق مقابل ذلك الرقم.
  ({int male, int female}) get _totalAdvisingCasesAnalyzed {
    final maleAnalysis = AdvisingCaseAnalyzer.analyze(students: _mergedFor(Shatr.male), facultyByNameKey: _facultyByKey);
    final femaleAnalysis = AdvisingCaseAnalyzer.analyze(students: _mergedFor(Shatr.female), facultyByNameKey: _facultyByKey);
    int sumOf(AdvisingCaseAnalysis a) =>
        a.studentsCorrectlyAssigned.length + a.studentsWithoutAdvisor.length + a.studentsWithWrongDeptAdvisor.length + a.dismissedStudents.length;
    return (male: sumOf(maleAnalysis), female: sumOf(femaleAnalysis));
  }

  /// دمج بيانات ربط المرشد (طلاب تابعين لمرشد) والحالة الصحية مع القاعدة،
  /// لكل شطر على حدة.
  List<AdvisingCaseRecord> _mergedFor(Shatr shatr) {
    final base = shatr == Shatr.male ? _base.male : _base.female;
    final assigned = shatr == Shatr.male ? _assigned.male : _assigned.female;
    final mismatch = shatr == Shatr.male ? _mismatch.male : _mismatch.female;
    final health = shatr == Shatr.male ? _health.male : _health.female;
    final previous = shatr == Shatr.male ? _basePreviousMale : _basePreviousFemale;
    final withAdvisors = AdvisingCaseAnalyzer.mergeAdvisorLinks(base, assigned);
    final withMismatchGaps = AdvisingCaseAnalyzer.mergeGapsFromMismatchReport(withAdvisors, mismatch);
    final withHealth = AdvisingCaseAnalyzer.mergeHealthConditions(withMismatchGaps, health);
    return AdvisingCaseAnalyzer.mergePreviousGpa(withHealth, previous);
  }

  /// نطاق الطلاب الحالي بعد تطبيق فلترَي الشطر والقسم - مرتَّب حسب الشطر ثم
  /// القسم كما طُلب صراحةً.
  List<AdvisingCaseRecord> get _scopedStudents {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _mergedFor(Shatr.male);
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _mergedFor(Shatr.female);
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

  /// التحليل يُبنى لكل شطر على حدة دومًا (حتى مع اختيار "كل الشطرين") لأن
  /// معايير التوازن والمطابقة (منسوبو الكلية) مرتبطة بشطر واحد لكل عضو -
  /// ثم تُدمَج النتائج مرتَّبة.
  AdvisingCaseAnalysis get _analysis {
    final male = _shatrFilter == Shatr.female.label
        ? const <AdvisingCaseRecord>[]
        : _mergedFor(Shatr.male).where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter).toList();
    final female = _shatrFilter == Shatr.male.label
        ? const <AdvisingCaseRecord>[]
        : _mergedFor(Shatr.female).where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter).toList();

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

  /// تسوية تقرير "طلاب على غير مرشدهم" الرسمي (كما وصل من الجامعة، دون
  /// تصحيح) مقابل ملف منسوبي الكلية المصحَّح - يفصل الحالات الحقيقية عن
  /// استثناءات الانتداب المعروفة (حنان/طارق وأمثالهما) تلقائيًا.
  OfficialMismatchReconciliation get _officialMismatchReconciliation {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _mismatch.male;
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _mismatch.female;
    final baseMale = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _base.male;
    final baseFemale = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _base.female;

    final r = AdvisingCaseAnalyzer.reconcileOfficialMismatchReport(
      officialMismatchReport: [...male, ...female],
      base: [...baseMale, ...baseFemale],
      facultyByNameKey: _facultyByKey,
    );
    bool inDept(MismatchedAdvisorCase c) => _deptFilter == _kAllDepartments || c.student.department == _deptFilter;
    return OfficialMismatchReconciliation(
      confirmed: r.confirmed.where(inDept).toList(),
      excusedBySecondment: r.excusedBySecondment.where(inDept).toList(),
    );
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
                      _buildValidationSummary(),
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

  /// بطاقتا تحقّق مقارَنة: عدد "بيانات الطلبة الأكاديمية" المرفوعة فعليًا
  /// (بتفصيل طلاب/طالبات) مقابل إجمالي حالات الإرشاد المحلَّلة من نفس
  /// البيانات (على مرشدهم + بلا مرشد + على غير مرشدهم + مفصولون) - يجب أن
  /// يتطابق الرقمان منطقيًا إن كان الملف المرفوع شاملاً فعلًا لكل طلاب
  /// الكلية؛ فرق بينهما مؤشر مباشر على نقص ببيانات المصدر لا خلل بالتحليل.
  Widget _buildValidationSummary() {
    final baseMale = _base.male.length;
    final baseFemale = _base.female.length;
    final baseTotal = baseMale + baseFemale;
    final analyzed = _totalAdvisingCasesAnalyzed;
    final analyzedTotal = analyzed.male + analyzed.female;
    final matches = baseTotal == analyzedTotal;

    Widget box({required String title, required int total, required String breakdown, required IconData icon}) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.green, size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$total', style: AppTextStyles.h2(color: AppColors.greenDark)),
                Text(title, style: AppTextStyles.caption()),
                Text(breakdown, style: AppTextStyles.caption()),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: matches ? Colors.white : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: matches ? AppColors.green.withValues(alpha: 0.25) : Colors.orange.shade300),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          box(
            title: 'بيانات الطلبة الأكاديمية المرفوعة',
            total: baseTotal,
            breakdown: 'طلاب $baseMale - طالبات $baseFemale',
            icon: Icons.upload_file_outlined,
          ),
          box(
            title: 'إجمالي حالات الإرشاد المحلَّلة',
            total: analyzedTotal,
            breakdown: 'طلاب ${analyzed.male} - طالبات ${analyzed.female}',
            icon: Icons.summarize_outlined,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(matches ? Icons.check_circle : Icons.error_outline, color: matches ? AppColors.green : Colors.orange.shade800),
              const SizedBox(width: 6),
              Text(
                matches ? 'الرقمان متطابقان' : 'فرق ${(baseTotal - analyzedTotal).abs()} - راجع اكتمال ملف "بيانات الطلبة الأكاديمية"',
                style: TextStyle(fontWeight: FontWeight.bold, color: matches ? AppColors.greenDark : Colors.orange.shade800),
              ),
            ],
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
              label: 'بيانات الطلبة الأكاديمية',
              uploading: _base.uploading,
              maleDate: _base.maleDate,
              femaleDate: _base.femaleDate,
              fmt: fmt,
              onPressed: () => _uploadForKind(AdvisingReportKind.base, _base, 'بيانات الطلبة الأكاديمية'),
              onClear: () => _clearKindBoth(AdvisingReportKind.base, 'بيانات الطلبة الأكاديمية'),
            ),
            const SizedBox(width: 10),
            _uploadTile(
              label: 'طلاب تابعين لمرشد',
              uploading: _assigned.uploading,
              maleDate: _assigned.maleDate,
              femaleDate: _assigned.femaleDate,
              fmt: fmt,
              color: AppColors.gold,
              onPressed: () => _uploadForKind(AdvisingReportKind.assigned, _assigned, 'طلاب تابعين لمرشد', requireDepartment: false),
              onClear: () => _clearKindBoth(AdvisingReportKind.assigned, 'طلاب تابعين لمرشد'),
            ),
            const SizedBox(width: 10),
            _uploadTile(
              label: 'طلاب غير تابعين لمرشد',
              uploading: _unassigned.uploading,
              maleDate: _unassigned.maleDate,
              femaleDate: _unassigned.femaleDate,
              fmt: fmt,
              color: Colors.grey.shade600,
              onPressed: () =>
                  _uploadForKind(AdvisingReportKind.unassigned, _unassigned, 'طلاب غير تابعين لمرشد', requireDepartment: false),
              onClear: () => _clearKindBoth(AdvisingReportKind.unassigned, 'طلاب غير تابعين لمرشد'),
            ),
            const SizedBox(width: 10),
            _uploadTile(
              label: 'الحالة الصحية للطلبة',
              uploading: _health.uploading,
              maleDate: _health.maleDate,
              femaleDate: _health.femaleDate,
              fmt: fmt,
              color: Colors.purple.shade700,
              onPressed: () => _uploadForKind(AdvisingReportKind.health, _health, 'الحالة الصحية للطلبة'),
              onClear: () => _clearKindBoth(AdvisingReportKind.health, 'الحالة الصحية للطلبة'),
            ),
            const SizedBox(width: 10),
            _uploadTile(
              label: 'طلاب على غير مرشدهم',
              uploading: _mismatch.uploading,
              maleDate: _mismatch.maleDate,
              femaleDate: _mismatch.femaleDate,
              fmt: fmt,
              color: Colors.brown.shade600,
              onPressed: () => _uploadForKind(AdvisingReportKind.mismatch, _mismatch, 'طلاب على غير مرشدهم', requireDepartment: false),
              onClear: () => _clearKindBoth(AdvisingReportKind.mismatch, 'طلاب على غير مرشدهم'),
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
    final cards = [
      (
        'طلاب على مرشدهم',
        Icons.verified_user_outlined,
        a.studentsCorrectlyAssigned.length,
        () => _showStudentsDialog('طلاب على مرشدهم', a.studentsCorrectlyAssigned),
      ),
      (
        'طلاب بلا مرشد',
        Icons.person_off_outlined,
        a.studentsWithoutAdvisor.length,
        () => _showStudentsDialog('طلاب بلا مرشد', a.studentsWithoutAdvisor),
      ),
      (
        'طلاب على غير مرشدهم',
        Icons.compare_arrows_outlined,
        a.studentsWithWrongDeptAdvisor.length,
        () => _showMismatchDialog(a.studentsWithWrongDeptAdvisor),
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
        if (_showAll && (a.exemptAdvisorsNoIssue.isNotEmpty || _officialMismatchReconciliation.excusedBySecondment.isNotEmpty)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (a.exemptAdvisorsNoIssue.isNotEmpty)
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
              if (_officialMismatchReconciliation.excusedBySecondment.isNotEmpty)
                InkWell(
                  onTap: () => _showMismatchDialog(
                    _officialMismatchReconciliation.excusedBySecondment,
                    title: 'حالات انتداب مستثناة تلقائيًا (تُحتسب ضمن العبء الفعلي)',
                    gray: true,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    width: 300,
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
                              Text('${_officialMismatchReconciliation.excusedBySecondment.length}',
                                  style: AppTextStyles.h3(color: Colors.grey.shade700)),
                              Text('حالات انتداب مستثناة تلقائيًا (طبيعي)', style: AppTextStyles.caption()),
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

  /// قسم 2 من 2: "النتائج والإحصائيات" - أرقام النطاقات (المعدل)، إجمالي
  /// ذوي الإعاقة، الطلاب المفصولون أكاديميًا، وكشف كل الطلاب في النطاق
  /// الحالي - نتائج للاطلاع لا تحتاج إجراء تصحيح فوري.
  Widget _buildResultsSection() {
    final a = _analysis;
    final cards = [
      (
        'طلاب بحاجة متابعة (المعدل)',
        Icons.warning_amber_outlined,
        a.atRiskStudents.length,
        () => _showStudentsDialog('طلاب بحاجة متابعة أكاديمية', a.atRiskStudents),
      ),
      (
        'إجمالي حالات ذوي الإعاقة (طلاب ${a.healthCaseStudents.where((s) => s.shatr == Shatr.male.label).length} / '
            'طالبات ${a.healthCaseStudents.where((s) => s.shatr == Shatr.female.label).length})',
        Icons.accessible_outlined,
        a.healthCaseStudents.length,
        () => _showStudentsDialog('كل حالات ذوي الإعاقة', a.healthCaseStudents),
      ),
      (
        'طلاب مفصولون أكاديميًا',
        Icons.block_outlined,
        a.dismissedStudents.length,
        () => _showStudentsDialog('طلاب مفصولون أكاديميًا', a.dismissedStudents),
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
  void _showMismatchDialog(List<MismatchedAdvisorCase> cases, {String title = 'طلاب على غير مرشدهم', bool gray = false}) {
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
          child: ListView(
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
