import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/course_catalog.dart';
import '../models/course_section_record.dart';
import '../services/advising_report_repository.dart';
import '../services/advising_schedule_repository.dart';
import '../services/advisor_correction_service.dart';
import '../services/course_schedule_change_repository.dart';
import '../services/course_schedule_diff_service.dart';
import '../services/course_schedule_repository.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/outside_course_repository.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';
import 'upload_dialogs.dart';
import 'upload_flows.dart';

/// صفحة مركزية واحدة لكل الملفات التي مصدرها المنظومة الداخلية للجامعة
/// حصرًا (وليس Microsoft Forms أو الموقع نفسه) - بطلب سليمان صراحةً
/// (2026-08-17). صفحة **رفع فقط** بلا أي إحصائيات/تحليلات/تقارير (ستكون
/// بصفحة مستقلة لاحقًا) - سليمان صراحةً: "الصفحة تكون مخصصة للرفع فقط".
///
/// **المقررات الدراسية**: خانة رفع واحدة فقط (لا فصل طلاب/طالبات) - يستخرج
/// شطر كل شعبة تلقائيًا من حقل "المقر" داخل الملف نفسه
/// ([DocxScheduleParserService.parseSectionsWithShatr]) بدل الاعتماد على
/// ملفين منفصلين مسبقًا. الثلاثة الأخرى (كل الكليات/ذوو الإعاقة/مواعيد
/// الإرشاد) كانت أصلاً بخانة واحدة تفرز داخليًا حسب الشطر - منطقها مُستخرَج
/// بالكامل في `upload_flows.dart` (مصدر واحد يخدم هذه الصفحة وصفحاتها
/// الأصلية معًا).
///
/// **التصميم**: بطاقات بيضاء بحواف دائرية وحدود ذهبية فاتحة، شبكة 2×2 على
/// الحاسوب (عمود واحد على الجوال) بحيث تظهر الأربع دفعة واحدة بلا تمرير
/// طويل، منطقة رفع واضحة بالضغط لاختيار الملف، وتاريخ "آخر رفع" فقط بصيغة
/// عربية واضحة - بلا اسم/نوع/امتداد ملف أو أي تفاصيل تقنية - سليمان صراحةً
/// (2026-08-17).
///
/// **صلاحية الوصول حاليًا**: حساب المدير العام (super_admin) فقط، بنفس
/// تقييد "خدمات أكاديمية"/"المنسوبين" المجاورين لها بالشريط.
class UploadHubScreen extends StatefulWidget {
  const UploadHubScreen({super.key});

  @override
  State<UploadHubScreen> createState() => _UploadHubScreenState();
}

class _UploadHubScreenState extends State<UploadHubScreen> {
  DateTime? _maleExportDate;
  DateTime? _femaleExportDate;
  bool _uploadingCourses = false;

  DateTime? _allCollegesMaleDate;
  DateTime? _allCollegesFemaleDate;
  DateTime? _healthMaleDate;
  DateTime? _healthFemaleDate;
  DateTime? _scheduleLatestDate;
  int _scheduleUploadedCount = 0;
  bool _loadingDates = true;

  bool _uploadingAllColleges = false;
  bool _uploadingHealth = false;
  bool _uploadingSchedule = false;
  bool _uploadingFormsFile = false;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    setState(() => _loadingDates = true);
    try {
      final results = await Future.wait([
        CourseScheduleRepository.currentExportDate(Shatr.male),
        CourseScheduleRepository.currentExportDate(Shatr.female),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.health),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.health),
        AdvisingScheduleRepository.latestUploadDate(),
        AdvisingScheduleRepository.uploadedCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _maleExportDate = results[0] as DateTime?;
        _femaleExportDate = results[1] as DateTime?;
        _allCollegesMaleDate = results[2] as DateTime?;
        _allCollegesFemaleDate = results[3] as DateTime?;
        _healthMaleDate = results[4] as DateTime?;
        _healthFemaleDate = results[5] as DateTime?;
        _scheduleLatestDate = results[6] as DateTime?;
        _scheduleUploadedCount = results[7] as int;
      });
    } finally {
      if (mounted) setState(() => _loadingDates = false);
    }
  }

  /// رفع المقررات الدراسية بملف واحد يحوي الشطرين معًا - يحدَّد شطر كل شعبة
  /// تلقائيًا من حقل "المقر" ([DocxScheduleParserService.parseSectionsWithShatr])
  /// بدل الاعتماد على ملفين منفصلين مسبقًا، ثم يُحفَظ كل شطر بشكل مستقل تمامًا
  /// كما كان سابقًا (بلا أي تغيير بمنطق الحفظ/المقارنة نفسه) - سليمان صراحةً
  /// (2026-08-17) بعد تحقّق فعلي من دقة القراءة (0 فرق عن الرفع المنفصل).
  Future<void> _uploadCoursesCombined() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;
    // ملف .docx الحقيقي هو أرشيف ZIP يبدأ دائمًا بالتوقيع "PK" - إن لم يكن
    // كذلك فهو على الأغلب حُفظ فعليًا بصيغة .doc القديمة أو تالف.
    if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      if (!mounted) return;
      showUploadErrorDialog(
        context,
        'الملف ليس Word صالحًا',
        'الملف المختار لا يبدو ملف Word (.docx) حقيقيًا (قد يكون محفوظًا فعليًا بصيغة .doc القديمة أو تالفًا). '
            'تأكد عند التحويل من PDF أن تحفظه بصيغة "Word Document (.docx)" وليس "Word 97-2003 (.doc)"، ثم أعد المحاولة.',
      );
      return;
    }

    setState(() => _uploadingCourses = true);
    try {
      final sections = DocxScheduleParserService.parseSectionsWithShatr(bytes);
      if (sections.isEmpty) {
        throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف المقررات الدراسية الشامل الصحيح بصيغة Word (.docx).');
      }

      final ourSections = sections.where((s) => s.beneficiary.contains('كلية إدارة الأعمال')).toList();
      final outsideCodes = CourseCatalog.outsideCollegeCourses.map(CourseCatalog.outsideCourseCode).toSet();

      ({
        List<CourseSectionRecord> ownRecords,
        List<String> outsideOptions,
        List<CourseSectionRecord> outsideRecords,
      }) buildForShatr(Shatr shatr) {
        final shatrSections = ourSections.where((s) => s.shatr == shatr).toList();
        final ownRecords =
            shatrSections.where((s) => !outsideCodes.contains(s.record.courseCode)).map((s) => s.record).toList();
        final outsideSections = shatrSections.where((s) => outsideCodes.contains(s.record.courseCode)).toList();
        final offeredOutsideCodes = outsideSections.map((s) => s.record.courseCode).toSet();
        final outsideOptions = CourseCatalog.filterOutsideCoursesByOfferedCodes(offeredOutsideCodes);
        final outsideRecords = outsideSections.map((s) => s.record).toList()
          ..sort((a, b) {
            final c = a.courseCode.compareTo(b.courseCode);
            return c != 0 ? c : a.sequence.compareTo(b.sequence);
          });
        return (ownRecords: ownRecords, outsideOptions: outsideOptions, outsideRecords: outsideRecords);
      }

      final male = buildForShatr(Shatr.male);
      final female = buildForShatr(Shatr.female);

      if (male.ownRecords.isEmpty && female.ownRecords.isEmpty) {
        throw Exception(
          'لم يُعثر على أي شعبة "المستفيد" منها كلية إدارة الأعمال ضمن ${sections.length} سطر بالملف. '
          'تأكد أن الملف يحوي عمود "المستفيد" فعليًا وأن نص الكلية مطابق.',
        );
      }

      final previousMale = await CourseScheduleRepository.loadSchedule(Shatr.male);
      final previousFemale = await CourseScheduleRepository.loadSchedule(Shatr.female);
      final changesMale = CourseScheduleDiffService.diff(
        shatrLabel: Shatr.male.label,
        previous: previousMale,
        current: male.ownRecords,
      );
      final changesFemale = CourseScheduleDiffService.diff(
        shatrLabel: Shatr.female.label,
        previous: previousFemale,
        current: female.ownRecords,
      );

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الاعتماد'),
          content: Text(
            'من إجمالي ${sections.length} سطر بالملف:\n\n'
            '• ${male.ownRecords.length} شعبة لشطر الطلاب (${male.outsideOptions.length} مادة خارج الكلية).\n'
            '• ${female.ownRecords.length} شعبة لشطر الطالبات (${female.outsideOptions.length} مادة خارج الكلية).\n'
            'سيستبدل هذا آخر نسخة معتمدة للشطرين بالكامل. هل تريد الاعتماد؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      await CourseScheduleRepository.saveSchedule(Shatr.male, male.ownRecords);
      await CourseScheduleRepository.saveSchedule(Shatr.female, female.ownRecords);
      await OutsideCourseRepository.save(Shatr.male, male.outsideOptions, male.outsideRecords);
      await OutsideCourseRepository.save(Shatr.female, female.outsideOptions, female.outsideRecords);
      if (previousMale.isNotEmpty) await CourseScheduleChangeRepository.appendChanges(changesMale);
      if (previousFemale.isNotEmpty) await CourseScheduleChangeRepository.appendChanges(changesFemale);
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم رفع الملف بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر قراءة الملف', '$e');
    } finally {
      if (mounted) setState(() => _uploadingCourses = false);
    }
  }

  /// يسأل الأدمن أولًا: هل هذا أول رفع في دورة حذف وإضافة جديدة (يمسح كل
  /// شيء - بداية نظيفة)، أم رفعة يوم تالٍ من نفس الدورة (الاثنين/الثلاثاء -
  /// تصدير Microsoft Forms تراكمي، فيُضاف الجديد فقط بلا مسح أي شيء حتى لا
  /// يُفقَد عمل المرشدين/المنسّقين على حالات الأيام السابقة).
  Future<bool?> _confirmFormsUploadMode() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('اختر نوع الرفع'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('رفعة يوم تالٍ (إضافة فقط)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('رفع جديد (بداية دورة - يمسح القديم)'),
          ),
        ],
      ),
    );
  }

  /// رفع ملف طلبات الحذف/الإضافة (مصدره Microsoft Forms، لا المنظومة
  /// الداخلية - لذا بطاقة مستقلة مميَّزة بصريًا بدل الشبكة 2×2 العلوية).
  /// نُقل هنا حرفيًا من admin_workspace_screen.dart بلا أي تغيير بالمنطق -
  /// سليمان صراحةً 2026-08-19.
  Future<void> _pickAndUploadFormsFile() async {
    final isNewCycle = await _confirmFormsUploadMode();
    if (isNewCycle == null) return;

    setState(() => _uploadingFormsFile = true);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      setState(() => _uploadingFormsFile = false);
      return;
    }

    final Uint8List bytes = result.files.single.bytes!;
    final rawTickets = ExcelParserService.parseTickets(bytes);

    final advisingRecords = [
      ...await AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
      ...await AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
    ];
    final tickets = AdvisorCorrectionService.applyAdvisorCorrection(rawTickets, advisingRecords);

    String message;
    if (isNewCycle) {
      await FirestoreTicketService.replaceAllTickets(tickets);
      message = 'تم رفع ${tickets.length} حالة بنجاح (دورة جديدة)';
    } else {
      final addedCount = await FirestoreTicketService.addNewTickets(tickets);
      message = 'تمت إضافة $addedCount حالة جديدة (من أصل ${tickets.length} في الملف - '
          'الباقي موجود مسبقًا وتم تجاهله حفاظًا على عمل المرشدين/المنسّقين)';
    }

    if (!mounted) return;
    setState(() => _uploadingFormsFile = false);
    _showSuccessSnackBar(message);
  }

  Future<void> _clearCourses() async {
    if (!await _confirmClear('ملف المقررات الدراسية')) return;
    try {
      await CourseScheduleRepository.clear(Shatr.male);
      await CourseScheduleRepository.clear(Shatr.female);
      await OutsideCourseRepository.clear(Shatr.male);
      await OutsideCourseRepository.clear(Shatr.female);
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم مسح البيانات بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر مسح البيانات', '$e');
    }
  }

  Future<void> _clearKindBoth(AdvisingReportKind kind, String label) async {
    if (!await _confirmClear(label)) return;
    try {
      await AdvisingReportRepository.clear(Shatr.male, kind: kind);
      await AdvisingReportRepository.clear(Shatr.female, kind: kind);
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم مسح البيانات بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر مسح البيانات', '$e');
    }
  }

  Future<void> _clearSchedule() async {
    if (!await _confirmClear('جداول مواعيد الإرشاد')) return;
    try {
      await AdvisingScheduleRepository.clearAll();
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم مسح البيانات بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر مسح البيانات', '$e');
    }
  }

  /// حذف حقيقي للبيانات المستخرجة من قاعدة البيانات (لا مجرد "ملف") - إجراء
  /// خطير لا يُنفَّذ إلا بتأكيد صريح - سليمان صراحةً 2026-08-17: "الإجراء
  /// الأحمر لا يمثل حذف ملف فقط... حذف جميع البيانات المستخرجة من الملف
  /// الحالي والمخزَّنة داخل النظام".
  Future<bool> _confirmClear(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح البيانات الحالية؟'),
        content: Text(
          'سيؤدي هذا الإجراء إلى حذف جميع البيانات المستخرجة من $label الحالي من النظام. '
          'لا يمكن التراجع عن هذه العملية.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('نعم، مسح البيانات'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// أحدث تاريخ بين قيمتين (شطر الطلاب/الطالبات) - كل قسم أصبح يعتمد رفع ملف
  /// واحد يُحدَّث الشطرين معًا دفعة واحدة، فلا داعٍ لعرض تاريخين منفصلين
  /// بالواجهة - سليمان صراحةً 2026-08-17.
  DateTime? _latestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// رسالة نجاح مؤقتة تختفي تلقائيًا - بلا خانة حالة دائمة بالواجهة.
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'رفع ملفات المنظومة الداخلية',
      navItems: buildAdminNavItems(context, current: 'upload-hub'),
      body: _loadingDates
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              // Align(topCenter) بدل Center - يُلصق المحتوى بأعلى الصفحة فلا
              // يتوزّع الفراغ المتبقي أعلى وأسفل معًا، بل يتجمّع فراغًا طبيعيًا
              // واحدًا أسفل البطاقات فقط قبل الفوتر - سليمان صراحةً 2026-08-17.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerBanner(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                        child: _formsFileUploadBanner(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 780;
                          final coursesDate = _latestOf(_maleExportDate, _femaleExportDate);
                          final coursesCard = _uploadCard(
                            icon: Icons.menu_book_outlined,
                            title: 'المقررات الدراسية',
                            subtitle: 'لاستخراج شعب المقررات الدراسية',
                            uploading: _uploadingCourses,
                            date: coursesDate,
                            clearLabel: 'مسح البيانات الحالية',
                            onPressed: _uploadCoursesCombined,
                            onClear: coursesDate != null ? _clearCourses : null,
                          );
                          final casesDate = _latestOf(_allCollegesMaleDate, _allCollegesFemaleDate);
                          final casesCard = _uploadCard(
                            icon: Icons.groups_outlined,
                            title: 'حالات الإرشاد',
                            subtitle: 'رفع ملف حالات الإرشاد',
                            uploading: _uploadingAllColleges,
                            date: casesDate,
                            clearLabel: 'مسح البيانات الحالية',
                            onPressed: () => runUploadAllColleges(
                              context: context,
                              setUploading: (v) => setState(() => _uploadingAllColleges = v),
                              onSuccess: () async {
                                await _loadDates();
                                if (mounted) _showSuccessSnackBar('تم رفع الملف بنجاح');
                              },
                            ),
                            onClear: casesDate != null ? () => _clearKindBoth(AdvisingReportKind.allColleges, 'ملف حالات الإرشاد') : null,
                          );
                          final disabilityDate = _latestOf(_healthMaleDate, _healthFemaleDate);
                          final disabilityCard = _uploadCard(
                            icon: Icons.accessible_outlined,
                            title: 'طلبة ذوو الإعاقة',
                            subtitle: 'رفع بيانات طلبة ذوي الإعاقة',
                            uploading: _uploadingHealth,
                            date: disabilityDate,
                            clearLabel: 'مسح البيانات الحالية',
                            onPressed: () => runUploadHealth(
                              context: context,
                              setUploading: (v) => setState(() => _uploadingHealth = v),
                              onSuccess: () async {
                                await _loadDates();
                                if (mounted) _showSuccessSnackBar('تم رفع الملف بنجاح');
                              },
                            ),
                            onClear: disabilityDate != null ? () => _clearKindBoth(AdvisingReportKind.health, 'ملف طلبة ذوي الإعاقة') : null,
                          );
                          final scheduleMaxed = _scheduleUploadedCount >= 10;
                          final scheduleCard = _uploadCard(
                            icon: Icons.event_available_outlined,
                            title: 'جداول مواعيد الإرشاد',
                            subtitle: 'رفع جداول مواعيد الإرشاد (حتى 10 ملفات)',
                            uploading: _uploadingSchedule,
                            disabled: scheduleMaxed,
                            date: _scheduleLatestDate,
                            fileCounterText: '$_scheduleUploadedCount / 10 ملفات',
                            isMultiple: true,
                            clearLabel: 'مسح بيانات المواعيد',
                            onPressed: scheduleMaxed
                                ? null
                                : () => runUploadAdvisingSchedule(
                                      context: context,
                                      setUploading: (v) => setState(() => _uploadingSchedule = v),
                                      onSuccess: () async {
                                        await _loadDates();
                                        if (mounted) _showSuccessSnackBar('تم رفع الملفات بنجاح');
                                      },
                                    ),
                            onClear: _scheduleLatestDate != null ? _clearSchedule : null,
                          );

                          // شبكة 2×2: أعلى اليمين=المقررات، أعلى اليسار=حالات
                          // الإرشاد، أسفل اليمين=ذوو الإعاقة، أسفل اليسار=مواعيد
                          // الإرشاد - في RTL أول عنصر بالصف يظهر يمينًا.
                          if (!wide) {
                            return Column(children: [
                              coursesCard,
                              const SizedBox(height: 12),
                              casesCard,
                              const SizedBox(height: 12),
                              disabilityCard,
                              const SizedBox(height: 12),
                              scheduleCard,
                            ]);
                          }
                          return Column(
                            children: [
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: coursesCard),
                                    const SizedBox(width: 14),
                                    Expanded(child: casesCard),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: disabilityCard),
                                    const SizedBox(width: 14),
                                    Expanded(child: scheduleCard),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ==================== عناصر التصميم ====================

  /// رأس مصرَّف داكن بخط ذهبي وشارة ماسية، مع زخرفة أقواس ذهبية بزوايا الرأس.
  /// بطاقة مميَّزة بصريًا لرفع ملف طلبات الحذف/الإضافة - مصدرها مختلف عمدًا
  /// عن بقية بطاقات هذه الصفحة (Microsoft Forms لا المنظومة الداخلية)، لذا
  /// صُمِّمت بهوية مغايرة (تدرّج أخضر داكن + شارة ذهبية) بدل قالب البطاقة
  /// البيضاء الموحَّد، وبإشارة صريحة لمصدرها تحت العنوان - بطلب سليمان
  /// 2026-08-19 (نُقلت من لوحة الإدارة إلى هنا).
  Widget _formsFileUploadBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold, width: 1.4),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        final info = Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.assignment_outlined, color: AppColors.greenDark, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الملف الأساسي - طلبات الحذف والإضافة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.description_outlined, size: 13, color: AppColors.goldLight.withValues(alpha: 0.9)),
                      const SizedBox(width: 5),
                      Text('المصدر: نموذج Microsoft Forms', style: TextStyle(color: AppColors.goldLight.withValues(alpha: 0.9), fontSize: 11.5)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        final button = ElevatedButton.icon(
          onPressed: _uploadingFormsFile ? null : _pickAndUploadFormsFile,
          icon: _uploadingFormsFile
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.greenDark))
              : const Icon(Icons.upload_file, size: 18),
          label: Text(_uploadingFormsFile ? 'جارٍ الرفع...' : 'رفع الملف'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.greenDark,
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 14), button]);
        }
        return Row(children: [Expanded(child: info), const SizedBox(width: 16), button]);
      }),
    );
  }

  Widget _headerBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [AppColors.greenDark, AppColors.green],
              ),
              border: const Border(
                bottom: BorderSide(color: AppColors.gold, width: 3),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'رفع ملفات الإرشاد الأكاديمي',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'إدارة ملفات الرفع المعتمدة',
                  style: TextStyle(color: AppColors.goldLight, fontSize: 13),
                ),
              ],
            ),
          ),
          Positioned(top: -70, left: -70, child: _cornerArc()),
          Positioned(top: -70, right: -70, child: _cornerArc(flip: true)),
        ],
      ),
    );
  }

  Widget _cornerArc({bool flip = false}) {
    final ring = Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55), width: 2),
      ),
    );
    final ring2 = Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.goldLight.withValues(alpha: 0.35), width: 1),
      ),
    );
    return Transform.scale(
      scaleX: flip ? -1 : 1,
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(alignment: Alignment.center, children: [ring, ring2]),
      ),
    );
  }

  Widget _goldIconBadge(IconData icon, {double size = 46}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.goldLight),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.green, size: size * 0.46),
    );
  }

  /// بطاقة رفع موحَّدة لكل البطاقات الأربع: رأس (شارة+عنوان+وصف مختصر)،
  /// منطقة الرفع نفسها هي وسيلة الرفع الوحيدة (بلا زر منفصل مكرِّر لنفس
  /// الوظيفة) - نصّها يتغيّر حسب وجود بيانات سابقة من عدمه، ثم "آخر رفع"
  /// وزر أحمر واحد "مسح البيانات الحالية" (حذف حقيقي من قاعدة البيانات، لا
  /// مجرد إزالة اسم ملف) - سليمان صراحةً 2026-08-17.
  Widget _uploadCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool uploading,
    required DateTime? date,
    required VoidCallback? onPressed,
    required VoidCallback? onClear,
    required String clearLabel,
    bool isMultiple = false,
    String? fileCounterText,
    bool disabled = false,
  }) {
    final dateFmt = DateFormat('d MMMM yyyy', 'ar');
    final timeFmt = DateFormat('h:mm a', 'ar');
    final hasData = date != null;
    final mainText = disabled
        ? 'اكتمل الحد الأعلى (10 ملفات)'
        : isMultiple
            ? (hasData ? 'اضغط هنا لإضافة ملفات' : 'اضغط هنا لرفع الملفات')
            : (hasData ? 'اضغط هنا لرفع ملف بديل' : 'اضغط هنا لرفع الملف');
    final subText = isMultiple ? 'أو اسحب الملفات إلى هذه المنطقة' : 'أو اسحب الملف إلى هذه المنطقة';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.goldLight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _goldIconBadge(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.greenDark)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _dropzone(
            uploading: uploading,
            disabled: disabled,
            mainText: mainText,
            subText: subText,
            onTap: (uploading || disabled) ? null : onPressed,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                        children: [
                          const TextSpan(text: 'آخر رفع: '),
                          TextSpan(
                            text: hasData
                                ? '\u2068${dateFmt.format(date)}، ${timeFmt.format(date)}\u2069'
                                : 'لا توجد بيانات مرفوعة',
                            style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (fileCounterText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3FAF6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFD8C9)),
                        ),
                        child: Text(
                          fileCounterText,
                          style: const TextStyle(color: Color(0xFF176044), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              if (onClear != null) _clearDataButton(label: clearLabel, onPressed: onClear),
            ],
          ),
        ],
      ),
    );
  }

  /// منطقة رفع بحدود متقطّعة كاملة قابلة للضغط - هي وسيلة الرفع الوحيدة
  /// (بلا زر منفصل مكرِّر) - بلا سحب/إفلات حقيقي حاليًا (يحتاج مكتبة إضافية
  /// وتعديل منطق مشترك تخدم صفحات أخرى - سليمان صراحةً 2026-08-17 وافق على
  /// تأجيله لطلب منفصل)، لكن بنفس الشكل البصري المطلوب.
  Widget _dropzone({
    required bool uploading,
    required bool disabled,
    required String mainText,
    required String subText,
    required VoidCallback? onTap,
  }) {
    final borderColor = disabled ? Colors.grey.shade300 : const Color(0xFFAAB6B0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: borderColor),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFF3F4F2) : const Color(0xFFFBFCFB),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            children: [
              uploading
                  ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Icon(Icons.cloud_upload_outlined, size: 32, color: disabled ? Colors.grey.shade400 : AppColors.green),
              const SizedBox(height: 6),
              Text(
                uploading ? 'جارٍ الرفع...' : mainText,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: disabled ? Colors.grey.shade500 : const Color(0xFF52615C),
                  fontSize: 14,
                ),
              ),
              if (!uploading && !disabled) ...[
                const SizedBox(height: 3),
                Text(subText, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// زر "مسح البيانات الحالية" - خلفية حمراء فاتحة جدًا، حدّ أحمر خفيف، نص
  /// وأيقونة، يعكس لونه بالكامل عند Hover - سليمان صراحةً 2026-08-17: هذا
  /// الإجراء يحذف البيانات المستخرجة الفعلية من قاعدة البيانات، لا مجرد ملف.
  Widget _clearDataButton({required String label, required VoidCallback onPressed}) {
    return _HoverableClearButton(label: label, onPressed: onPressed);
  }
}

class _HoverableClearButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _HoverableClearButton({required this.label, required this.onPressed});

  @override
  State<_HoverableClearButton> createState() => _HoverableClearButtonState();
}

class _HoverableClearButtonState extends State<_HoverableClearButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: _hovering ? Colors.red.shade700 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _hovering ? Colors.red.shade700 : Colors.red.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_sweep_outlined, color: _hovering ? Colors.white : Colors.red.shade700, size: 16),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(color: _hovering ? Colors.white : Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// رسم حدّ متقطّع (Flutter لا يدعم BorderStyle.dashed مباشرة).
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(13));
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
