import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../services/advisor_movement_repository.dart';
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
const String _kAllAdvisors = 'كل المرشدين';

/// حد أقصى للصفوف المعروضة فعليًا داخل أي `DataTable` بهذه الشاشة - يُبنى
/// **كل** صفوفه دفعة واحدة قبل الرسم (لا تحميل كسول)، فتجمّد الصفحة فعليًا
/// (لاحظه سليمان 2026-08-14) لو تجاوز عدد الصفوف بضعة آلاف - كما يحدث الآن
/// مع "طلاب على مرشدهم" لملف "كل الكليات" (الجامعة كاملة). التصدير (Excel/
/// PDF) يبقى **بلا أي حد** - يشمل كل السجلات دومًا، هذا الحد للعرض المرئي فقط.
const int _kMaxTableRows = 300;

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
  // 12 تبويبًا (بدل تبويبين + بطاقات تفتح نوافذ) بطلب سليمان صراحةً
  // (2026-08-14): كل تصنيف يصبح تبويبًا مستقلاً، والقائمة تظهر مضمَّنة تحته
  // مباشرة، وفلاتر الشطر/القسم/المرشد/البحث أعلى التبويبات تؤثر عليها جميعًا.
  late final TabController _sectionTab = TabController(length: 12, vsync: this);
  final _allColleges = _UploadSlot();
  final _health = _UploadSlot();

  // نتاج AdvisingCaseAnalyzer.loadCollegeScopedStudents - تُخزَّن هنا بعد كل
  // تحميل بدل استدعائها مباشرة بالـbuild.
  List<AdvisingCaseRecord> _scopedMale = [];
  List<AdvisingCaseRecord> _scopedFemale = [];
  List<AdvisingCaseRecord> _allCollegesMaleRaw = [];
  List<AdvisingCaseRecord> _allCollegesFemaleRaw = [];

  // سجل حركات الإرشاد الدائم/التراكمي (كل الرفعات، لا آخر رفعتين فقط) - انظر
  // [AdvisorMovementRepository].
  List<AdvisorMovementLogEntry> _movementsLog = [];

  Map<String, CollegeRosterMember> _facultyByKey = {};
  List<String> _departments = [];

  bool _loading = true;

  String _shatrFilter = _kAllShatr;
  String _deptFilter = _kAllDepartments;
  String _advisorFilter = _kAllAdvisors;
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
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '$title\n$details'));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ نص الخطأ')));
              }
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('نسخ'),
          ),
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

      // يقارن هذه الرفعة بما هو مخزَّن حاليًا (آخر رفعة سابقة) **قبل** استبداله،
      // ويضيف أي حركة مكتشَفة لسجل دائم/تراكمي (لا يُستبدَل أبدًا) - بطلب
      // سليمان صراحةً (2026-08-14): "لو عشر مرات تظهر الحركات" لا مقارنة آخر
      // رفعتين فقط. انظر [AdvisorMovementRepository].
      Future<void> saveShatr(Shatr shatr, List<AdvisingCaseRecord> shatrRecords) async {
        final previouslyStored = await AdvisingReportRepository.load(shatr, kind: AdvisingReportKind.allColleges);
        final movements = AdvisingCaseAnalyzer.detectAdvisorMovements(previous: previouslyStored, current: shatrRecords);

        await AdvisingReportRepository.promoteAllCollegesToPrevious(shatr);
        await AdvisingReportRepository.save(shatr, shatrRecords, kind: AdvisingReportKind.allColleges);

        if (movements.isNotEmpty) {
          await AdvisorMovementRepository.appendMovements([
            for (final m in movements)
              AdvisorMovementLogEntry(
                studentId: m.student.studentId,
                studentName: m.student.studentName,
                department: m.student.department,
                shatr: m.student.shatr,
                fromAdvisorNameRaw: m.fromAdvisorNameRaw,
                toAdvisorNameRaw: m.toAdvisorNameRaw,
              ),
          ]);
        }
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

  /// أسماء المرشدين المرشَّحة لقائمة الفلترة - مقصورة على قسم [_deptFilter]
  /// المختار حاليًا (بلا اعتماد على الشطر) كما طُلب صراحةً (2026-08-14):
  /// "يُضاف اسم المرشد من خلال القسم". تُبنى من `advisorNameRaw` كما وردت
  /// فعليًا بسجلات الطلاب (لا من ملف منسوبي الكلية) لضمان تطابق حرفي مع
  /// المطابقة عبر [_advisorMatches] (قد يختلف شكل الاسم بين المصدرين قليلًا)،
  /// لكن **مقصورة فقط على مرشدين موجودين فعليًا بملف منسوبي الكلية** - سليمان
  /// لاحظ (2026-08-14) ظهور اسم "إيمان عبدالعزيز أحمد جان طاشكندي" رغم عدم
  /// وجودها عضوة بالكلية إطلاقًا (مرشدة من خارج الكلية أُسنِد لها طالب من
  /// قسمنا سهوًا بالمنظومة) - أسماء كهذه تبقى تظهر في تبويب "مرشد خارجي ←
  /// طلابنا" المخصَّص لها، لكن لا تُقترَح كخيار بقائمة الفلترة العامة.
  List<String> get _advisorFilterOptions {
    final male = _shatrFilter == Shatr.female.label ? const <AdvisingCaseRecord>[] : _scopedMale;
    final female = _shatrFilter == Shatr.male.label ? const <AdvisingCaseRecord>[] : _scopedFemale;
    final names = [...male, ...female]
        .where((s) => _deptFilter == _kAllDepartments || s.department == _deptFilter)
        .map((s) => s.advisorNameRaw.trim())
        .where((n) => n.isNotEmpty && _facultyByKey.containsKey(AdvisingCaseAnalyzer.nameKey(displayName(n))))
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

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Widget Function())>[
      ('على مرشدهم', _tabCorrectlyAssigned),
      ('بلا مرشد', _tabWithoutAdvisor),
      ('على غير مرشدهم', _tabWrongAdvisor),
      ('مرشد خارجي ← طلابنا', _tabExternalAdvisors),
      ('مرشدنا ← طلاب خارجيون', _tabExternalStudents),
      ('معفَون ولهم طلاب', _tabExemptWithStudents),
      ('مرشدون بلا طلاب', _tabAdvisorsNoStudents),
      ('تقرير النصاب', _tabQuota),
      ('إعادة التوزيع', _tabTransfer),
      ('حالات صحية غير موزَّعة', _tabHealthMismatch),
      ('ذوو الإعاقة', _tabHealthCases),
      ('حركات الإرشاد', _tabMovements),
    ];
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
                    isScrollable: true,
                    labelColor: AppColors.green,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: AppColors.green,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [for (final t in tabs) Tab(text: t.$1)],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _sectionTab,
                    children: [
                      for (final t in tabs)
                        ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [t.$2()]),
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
    try {
      await AdvisingReportRepository.clear(Shatr.male, kind: kind);
      await AdvisingReportRepository.clear(Shatr.female, kind: kind);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تفريغ $label بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('تعذّر التفريغ', '$e');
    }
  }

  /// شريط الفلترة (شطر/قسم/مرشد/بحث) - يظهر أعلى التبويبات الاثني عشر ويؤثر
  /// عليها جميعًا فورًا، كما طُلب صراحةً (2026-08-14). قائمة المرشد تُعاد
  /// بناؤها تلقائيًا (عبر `key`) كلما تغيّر القسم لأنها مقصورة عليه.
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
            onSelected: (v) => setState(() {
              _shatrFilter = v ?? _kAllShatr;
              _advisorFilter = _kAllAdvisors;
            }),
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
            onSelected: (v) => setState(() {
              _deptFilter = v ?? _kAllDepartments;
              _advisorFilter = _kAllAdvisors;
            }),
          ),
        ),
        SizedBox(
          key: ValueKey('$_deptFilter|$_shatrFilter'),
          width: 240,
          child: DropdownMenu<String>(
            label: const Text('المرشد'),
            initialSelection: _advisorFilter,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: _kAllAdvisors, label: _kAllAdvisors),
              ..._advisorFilterOptions.map((a) => DropdownMenuEntry(value: a, label: a)),
            ],
            onSelected: (v) => setState(() => _advisorFilter = v ?? _kAllAdvisors),
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
      ],
    );
  }

  // ------------------------------- فلاتر مشتركة -------------------------------

  bool _deptMatches(String department) => _deptFilter == _kAllDepartments || department == _deptFilter;

  bool _advisorMatches(String advisorName) =>
      _advisorFilter == _kAllAdvisors ||
      AdvisingCaseAnalyzer.nameKey(advisorName) == AdvisingCaseAnalyzer.nameKey(_advisorFilter);

  bool _matchesSearch(String name, String id) {
    final q = _searchCtrl.text.trim();
    return q.isEmpty || name.contains(q) || id.contains(q);
  }

  // ------------------------------- 12 تبويبًا -------------------------------
  // كل دالة تبني قائمة صفوف نصية (بعد تطبيق فلاتر القسم/المرشد) ثم تمررها
  // لـ[_buildPanel] المشتركة (عنوان + عدّاد + تصدير Excel/PDF + جدول). الشطر
  // مُطبَّق مسبقًا عند بناء `_classification`/`_analysis`/`_movementsLog`.

  Widget _tabCorrectlyAssigned() {
    final list = _classification.studentsCorrectlyAssigned
        .where((s) => _deptMatches(s.department) && _advisorMatches(s.advisorNameRaw) && _matchesSearch(s.studentName, s.studentId))
        .toList();
    return _buildPanel(
      title: 'طلاب على مرشدهم',
      headers: const ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد'],
      rows: [
        for (final s in list) [s.studentName, s.studentId, s.department, s.shatr, s.advisorNameRaw.ifEmptyDash()],
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

  Widget _tabWrongAdvisor() {
    final list = _classification.studentsWithWrongDeptAdvisor
        .where((c) =>
            _deptMatches(c.student.department) &&
            _advisorMatches(c.student.advisorNameRaw) &&
            _matchesSearch(c.student.studentName, c.student.studentId))
        .toList();
    return _buildPanel(
      title: 'طلاب على غير مرشدهم',
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد الحالي', 'قسم المرشد المسجَّل'],
      rows: [
        for (final c in list)
          [
            c.student.studentName,
            c.student.studentId,
            c.student.department,
            c.student.shatr,
            c.student.advisorNameRaw.ifEmptyDash(),
            c.advisor?.department ?? 'غير موجود بملف منسوبي الكلية',
          ],
      ],
      emptyMessage: 'لا يوجد طلبة على غير مرشدهم',
    );
  }

  Widget _tabExternalAdvisors() {
    final list = _classification.externalAdvisorsWithOurStudents
        .where((s) => _deptMatches(s.department) && _advisorMatches(s.advisorNameRaw) && _matchesSearch(s.studentName, s.studentId))
        .toList();
    return _buildPanel(
      title: 'مرشدون من خارج الكلية يرشدون طلبة من داخل الكلية',
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد (من خارج الكلية)', 'رقم منسوب المرشد'],
      rows: [
        for (final s in list)
          [s.studentName, s.studentId, s.department, s.shatr, s.advisorNameRaw.ifEmptyDash(), s.advisorId.ifEmptyDash()],
      ],
    );
  }

  Widget _tabExternalStudents() {
    final list = _classification.ourAdvisorsWithExternalStudents
        .where((s) => _deptMatches(s.department) && _advisorMatches(s.advisorNameRaw) && _matchesSearch(s.studentName, s.studentId))
        .toList();
    return _buildPanel(
      title: 'مرشدون من داخل الكلية يرشدون طلبة من خارج الكلية',
      headers: const ['الطالب', 'الرقم الجامعي', 'التخصص (خارج كليتنا)', 'الشطر', 'المرشد'],
      rows: [
        for (final s in list) [s.studentName, s.studentId, s.department, s.shatr, s.advisorNameRaw.ifEmptyDash()],
      ],
    );
  }

  Widget _tabExemptWithStudents() {
    final cases = _analysis.exemptAdvisorsWithStudents
        .where((c) => _deptMatches(c.advisor.department) && _advisorMatches(c.advisor.name))
        .toList();
    return _buildPanel(
      title: 'مرشدون معفَون ولديهم طلاب',
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'المرشد المعفى', 'قسم المرشد'],
      rows: [
        for (final c in cases)
          for (final s in c.students) [s.studentName, s.studentId, s.department, c.advisor.name, c.advisor.department],
      ],
    );
  }

  Widget _tabAdvisorsNoStudents() {
    final list = _analysis.advisorsWithNoStudents
        .where((m) => _deptMatches(m.department) && _advisorMatches(m.name))
        .toList();
    return _buildPanel(
      title: 'مرشدون بلا طلاب',
      headers: const ['الاسم', 'رقم المنسوب', 'القسم', 'الشطر', 'السبب'],
      rows: [for (final m in list) [m.name, m.staffNumber.ifEmptyDash(), m.department, m.shatr, m.advisingReason]],
    );
  }

  Widget _tabQuota() {
    final list = _analysis.quotaReport
        .where((q) => _deptMatches(q.advisor.department) && _advisorMatches(q.advisor.name))
        .toList();
    return _buildPanel(
      title: 'تقرير النصاب (فوق/دون الحصة العادلة)',
      headers: const ['المرشد', 'القسم', 'العدد الحالي', 'الحصة العادلة', 'الحالة'],
      rows: [
        for (final q in list)
          [q.advisor.name, q.advisor.department, '${q.actualCount}', '${q.fairShare.round()}', _quotaStatusLabel(q.status)],
      ],
    );
  }

  Widget _tabTransfer() {
    final list = _analysis.transferSuggestions
        .where((t) => _deptMatches(t.student.department) && _advisorMatches(t.fromAdvisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'تقرير إعادة التوزيع',
      headers: const ['الطالب', 'رقمه', 'تخصصه', 'المرشد السابق', 'رقمه', 'المرشد الموصى به', 'رقمه'],
      rows: [
        for (final t in list)
          [
            t.student.studentName,
            t.student.studentId,
            t.student.department,
            t.fromAdvisorNameRaw,
            t.fromAdvisor?.staffNumber.ifEmptyDash() ?? '—',
            t.toAdvisor?.name ?? 'يلزم قرار يدوي',
            t.toAdvisor?.staffNumber.ifEmptyDash() ?? '—',
          ],
      ],
    );
  }

  Widget _tabHealthMismatch() {
    final list = _analysis.healthCasesNotWithAmin
        .where((h) => _deptMatches(h.student.department) &&
            _advisorMatches(h.currentAdvisor?.name ?? h.student.advisorNameRaw))
        .toList();
    return _buildPanel(
      title: 'حالات صحية غير موزَّعة بشكل صحيح',
      headers: const ['الطالب', 'رقمه', 'تخصصه', 'الحالة الصحية', 'المرشد الحالي', 'المرشد المفترض'],
      rows: [
        for (final h in list)
          [
            h.student.studentName,
            h.student.studentId,
            h.student.department,
            h.student.healthCondition,
            h.currentAdvisor?.name ?? (h.student.hasAdvisor ? h.student.advisorNameRaw : 'بلا مرشد'),
            h.departmentAmin?.name ?? 'غير معروف',
          ],
      ],
    );
  }

  Widget _tabHealthCases() {
    final list = _analysis.healthCaseStudents
        .where((s) => _deptMatches(s.department) && _advisorMatches(s.advisorNameRaw) && _matchesSearch(s.studentName, s.studentId))
        .toList();
    return _buildPanel(
      title: 'إجمالي حالات ذوي الإعاقة',
      headers: const ['الاسم', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد', 'الحالة الصحية'],
      rows: [
        for (final s in list)
          [s.studentName, s.studentId, s.department, s.shatr, s.advisorNameRaw.ifEmptyDash(), s.healthCondition],
      ],
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
            _matchesSearch(m.studentName, m.studentId))
        .toList();
    return _buildPanel(
      title: 'حركات الإرشاد (كل الرفعات)',
      headers: const ['الطالب', 'الرقم الجامعي', 'القسم', 'الشطر', 'المرشد الحالي', 'المرشد السابق', 'تاريخ الاكتشاف'],
      rows: [
        for (final m in list)
          [
            m.studentName,
            m.studentId,
            m.department,
            m.shatr,
            m.toAdvisorNameRaw.ifEmptyDash(),
            m.fromAdvisorNameRaw.ifEmptyDash(),
            m.detectedAt != null ? fmt.format(m.detectedAt!) : '—',
          ],
      ],
      emptyMessage: 'لا توجد حركات إرشاد مسجَّلة بعد',
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
              Expanded(child: Text('$title ($count)', style: AppTextStyles.h3(color: AppColors.greenDark))),
              TextButton.icon(
                onPressed: hasData ? () => _exportExcel(title, headers, rows) : null,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Excel'),
              ),
              TextButton.icon(
                onPressed: hasData
                    ? () async {
                        final bytes = await AdvisingCasePdfService.build(title: title, headers: headers, rows: rows);
                        await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
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

  /// جدول عام من نصوص جاهزة (بلا نوع بيانات محدَّد) - يُبنى مرة واحدة فقط
  /// لكل التبويبات الاثني عشر بدل تكرار كود `DataTable` لكل نوع سجل. يُقلَّص
  /// للعرض المرئي فقط عند تجاوز [_kMaxTableRows] (التصدير يبقى كاملاً دومًا).
  Widget _dataTableFromRows(List<String> columns, List<List<String>> allRows, {required String emptyMessage}) {
    if (allRows.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(emptyMessage, style: TextStyle(color: Colors.grey.shade600))));
    }
    final truncated = allRows.length > _kMaxTableRows;
    final visible = truncated ? allRows.sublist(0, _kMaxTableRows) : allRows;
    return Column(
      children: [
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'يُعرض هنا أول $_kMaxTableRows من ${allRows.length} سجلًا فقط - '
              'استخدم Excel أو PDF أعلاه لعرض/طباعة كل السجلات.',
              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.green),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: [for (final c in columns) DataColumn(label: Center(child: Text(c)))],
              rows: [
                for (var i = 0; i < visible.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                    cells: [for (final v in visible[i]) DataCell(Center(child: Text(v)))],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _exportExcel(String title, List<String> headers, List<List<String>> rows) {
    final bytes = AdvisingCaseExcelService.build(title: title, headers: headers, rows: rows);
    downloadBytes(bytes, '$title.xlsx');
  }
}

extension on String {
  String ifEmptyDash() => trim().isEmpty ? '—' : this;
}
