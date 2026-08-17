import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/course_catalog.dart';
import '../models/course_schedule_change.dart';
import '../services/advising_report_repository.dart';
import '../services/advising_schedule_repository.dart';
import '../services/course_schedule_change_repository.dart';
import '../services/course_schedule_diff_service.dart';
import '../services/course_schedule_repository.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/outside_course_repository.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';
import 'upload_flows.dart';

/// صفحة مركزية واحدة لكل الملفات التي مصدرها المنظومة الداخلية للجامعة
/// حصرًا (وليس Microsoft Forms أو الموقع نفسه) - بطلب سليمان صراحةً
/// (2026-08-17) بعد أن لاحظ أن أزرار الرفع المتناثرة داخل صفحات بيانات
/// كثيفة أصلاً (تسكين المقررات، حالات الإرشاد، مواعيد الإرشاد) تُشعر
/// المستخدم بالازدحام. كل صفحة أصلية تبقي فقط ملاحظة "آخر رفع: تاريخ" بلا
/// زر - الرفع الفعلي انتقل هنا بالكامل.
///
/// الأربعة تعمل هنا برفع فعلي كامل - لا مجرد اختصار/تنقّل لصفحة أخرى. منطق
/// الثلاثة الأكثر تعقيدًا (كل الكليات/ذوي الإعاقة/مواعيد الإرشاد - مطابقة
/// أسماء، كشف تعارضات، تتبّع حركات مرشدين) مُستخرَج بالكامل في
/// `upload_flows.dart` كدوال مشتركة، تُستدعى من هنا **وأيضًا** من صفحاتها
/// الأصلية (بقيت أزرارها هناك كما هي بلا حذف) - مصدر منطق واحد فقط، فلا خطر
/// تباعد بين نسختين لنفس المنطق (طلب سليمان صراحةً 2026-08-17: "نقل كامل
/// بدون مخاطرة، يبقى كما هو بنفس الصفحة الأساسية وينقل إلى صفحة رفع الملفات").
///
/// **التصميم**: بطاقات ذهبية الحدود على خلفية بيضاء بهوية الوحدة البصرية،
/// برأس مصرَّف داكن مذيَّل بخط ذهبي وشارة ماسية - نفس تصميم مرجعي اعتمده
/// سليمان صراحةً (2026-08-17) بدل التصميم الأولي البدائي.
///
/// **صلاحية الوصول حاليًا**: حساب المدير العام (super_admin) فقط، بنفس
/// تقييد "خدمات أكاديمية"/"المنسوبين" المجاورين لها بالشريط. خطة مستقبلية
/// (لم تُنفَّذ بعد): منح نفس الصلاحية لمنسّق الوحدة للشؤون الإدارية أيضًا.
class UploadHubScreen extends StatefulWidget {
  const UploadHubScreen({super.key});

  @override
  State<UploadHubScreen> createState() => _UploadHubScreenState();
}

class _UploadHubScreenState extends State<UploadHubScreen> {
  DateTime? _maleExportDate;
  DateTime? _femaleExportDate;
  bool _uploadingMale = false;
  bool _uploadingFemale = false;

  DateTime? _allCollegesMaleDate;
  DateTime? _allCollegesFemaleDate;
  DateTime? _healthMaleDate;
  DateTime? _healthFemaleDate;
  DateTime? _scheduleLatestDate;
  bool _loadingDates = true;

  bool _uploadingAllColleges = false;
  bool _uploadingHealth = false;
  bool _uploadingSchedule = false;

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
      });
    } finally {
      if (mounted) setState(() => _loadingDates = false);
    }
  }

  /// رفع موحَّد لملف المقررات الدراسية الشامل لشطر واحد - يستخرج منه دفعة
  /// واحدة كلا العنصرين معًا: (أ) جدول شعب كليتنا الخاصة (شعب "المستفيد"
  /// منها كلية إدارة الأعمال وكودها ليس ضمن قائمة "مواد خارج الكلية")، و(ب)
  /// قائمة "مواد خارج الكلية" المعتمَدة لهذا الفصل (شرطها: كودها بقائمة
  /// الخطة + شعبة فعلية مستفيدها كليتنا).
  Future<void> _uploadCourses(Shatr shatr) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;

    setState(() {
      if (shatr == Shatr.male) {
        _uploadingMale = true;
      } else {
        _uploadingFemale = true;
      }
    });

    try {
      final sections = DocxScheduleParserService.parseSections(bytes);
      if (sections.isEmpty) {
        throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف المقررات الدراسية الشامل الصحيح بصيغة Word (.docx).');
      }

      final ourSections = sections.where((s) => s.beneficiary.contains('كلية إدارة الأعمال')).toList();
      final outsideCodes = CourseCatalog.outsideCollegeCourses.map(CourseCatalog.outsideCourseCode).toSet();

      final ownRecords = ourSections.where((s) => !outsideCodes.contains(s.record.courseCode)).map((s) => s.record).toList();
      final outsideSections = ourSections.where((s) => outsideCodes.contains(s.record.courseCode)).toList();
      final offeredOutsideCodes = outsideSections.map((s) => s.record.courseCode).toSet();
      final outsideOptions = CourseCatalog.filterOutsideCoursesByOfferedCodes(offeredOutsideCodes);
      final outsideRecords = outsideSections.map((s) => s.record).toList()
        ..sort((a, b) {
          final c = a.courseCode.compareTo(b.courseCode);
          return c != 0 ? c : a.sequence.compareTo(b.sequence);
        });

      if (ownRecords.isEmpty) {
        throw Exception(
          'لم يُعثر على أي شعبة "المستفيد" منها كلية إدارة الأعمال ضمن ${sections.length} سطر بالملف. '
          'تأكد أن الملف يحوي عمود "المستفيد" فعليًا وأن نص الكلية مطابق.',
        );
      }

      final exportDate = DocxScheduleParserService.extractExportDate(bytes);
      final currentExportDate = await CourseScheduleRepository.currentExportDate(shatr);
      if (exportDate != null && currentExportDate != null && !exportDate.isAfter(currentExportDate)) {
        final fmt = DateFormat('yyyy/MM/dd');
        throw Exception(
          'تاريخ سحب بيانات هذا الملف (${fmt.format(exportDate)}) ليس أحدث من تاريخ آخر نسخة معتمدة '
          '(${fmt.format(currentExportDate)}). تأكد من رفع أحدث ملف من المنظومة الداخلية.',
        );
      }

      // مقارنة النسخة الحالية المخزَّنة بالنسخة الجديدة **قبل** استبدالها -
      // تُبنى منها إضافات/حذوفات الشعب وتغييرات عضو هيئة التدريس، وتُحفَظ
      // كسجل تراكمي دائم (لا يُستبدَل أبدًا) لتقرير "التغييرات" - بطلب
      // سليمان صراحةً (2026-08-17). عدد الطلاب المسجَّلين لا يُقارَن أبدًا.
      final previousRecords = await CourseScheduleRepository.loadSchedule(shatr);
      final changes = CourseScheduleDiffService.diff(shatrLabel: shatr.label, previous: previousRecords, current: ownRecords);

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الاعتماد'),
          content: Text(
            'من إجمالي ${sections.length} سطر بالملف لـ ${shatr.label}'
            '${exportDate != null ? ' (تاريخ السحب: ${DateFormat('yyyy/MM/dd').format(exportDate)})' : ''}:\n\n'
            '• ${ownRecords.length} شعبة لجدول كليتنا الخاص.\n'
            '• ${outsideOptions.length} مادة من قائمة "خارج الكلية" (من أصل ${CourseCatalog.outsideCollegeCourses.length}).\n'
            '${previousRecords.isNotEmpty ? '• ${changes.length} تغيير مكتشَف عن النسخة السابقة (إضافة/حذف شعب أو تغيير محاضر).\n' : ''}\n'
            'سيستبدل هذا آخر نسخة معتمدة لكليهما لهذا الشطر بالكامل. هل تريد الاعتماد؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      await CourseScheduleRepository.saveSchedule(shatr, ownRecords, exportDate: exportDate);
      await OutsideCourseRepository.save(shatr, outsideOptions, outsideRecords);
      if (previousRecords.isNotEmpty) await CourseScheduleChangeRepository.appendChanges(changes);
      await _loadDates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم اعتماد جدول ${shatr.label} (${ownRecords.length} شعبة) ومواد خارج الكلية (${outsideOptions.length} مادة) بنجاح'
            '${previousRecords.isNotEmpty ? ' - ${changes.length} تغيير سُجِّل بالتقرير' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر قراءة الملف: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingMale = false;
          _uploadingFemale = false;
        });
      }
    }
  }

  /// زر تجريبي حصرًا (بلا حفظ أي بيانات) لاختبار دقة التصنيف التلقائي
  /// لشطر كل شعبة من حقل "المقر" في ملف Word شامل للشطرين معًا (محوَّل من
  /// ملف PDF واحد) - بطلب سليمان صراحةً (2026-08-17) قبل حذف صندوقَي رفع
  /// المقررات المنفصلين لكل شطر واستبدالهما بخانة رفع واحدة إن نجحت القراءة.
  Future<void> _uploadCoursesTrial() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;

    try {
      final sections = DocxScheduleParserService.parseSectionsWithShatr(bytes);
      if (sections.isEmpty) {
        throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف الحويّة الشامل الصحيح بصيغة Word (.docx).');
      }
      final ourSections = sections.where((s) => s.beneficiary.contains('كلية إدارة الأعمال')).toList();
      final maleCount = ourSections.where((s) => s.shatr == Shatr.male).length;
      final femaleCount = ourSections.where((s) => s.shatr == Shatr.female).length;
      final unknownCount = ourSections.where((s) => s.shatr == null).length;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('نتيجة التجربة (بلا حفظ)'),
          content: Text(
            'من إجمالي ${sections.length} سطر بالملف، ${ourSections.length} شعبة "المستفيد" منها كلية إدارة الأعمال:\n\n'
            '• $maleCount شعبة صُنِّفت شطر طلاب.\n'
            '• $femaleCount شعبة صُنِّفت شطر طالبات.\n'
            '${unknownCount > 0 ? '• $unknownCount شعبة تعذّر تحديد شطرها (راجع الملف).\n' : ''}\n'
            '${unknownCount == 0 && maleCount > 0 && femaleCount > 0 ? 'القراءة تبدو سليمة ✓' : 'راجع النتيجة قبل الاعتماد على هذا المسار.'}',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر قراءة الملف: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _clearKindBoth(AdvisingReportKind kind, String label) async {
    if (!await _confirmClear(label)) return;
    try {
      await AdvisingReportRepository.clear(Shatr.male, kind: kind);
      await AdvisingReportRepository.clear(Shatr.female, kind: kind);
      await _loadDates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تفريغ $label بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التفريغ: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _clearSchedule() async {
    if (!await _confirmClear('جدول مواعيد الإرشاد')) return;
    try {
      await AdvisingScheduleRepository.clearAll();
      await _loadDates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفريغ جدول مواعيد الإرشاد بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التفريغ: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  /// تقرير التغييرات التراكمي (كل رفعات المقررات الدراسية) - إضافة/حذف
  /// شعب وتغييرات عضو هيئة التدريس فقط، مرتَّبة الأحدث أولًا.
  Future<void> _showChangesReport() async {
    final changes = await CourseScheduleChangeRepository.loadAll();
    if (!mounted) return;
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تقرير التغييرات (${changes.length})'),
        content: SizedBox(
          width: 620,
          child: changes.isEmpty
              ? const Text('لا توجد تغييرات مسجَّلة بعد - تُضاف تلقائيًا بعد أول رفعة ثانية لنفس الشطر.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final c in changes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                switch (c.type) {
                                  CourseScheduleChangeType.added => Icons.add_circle_outline,
                                  CourseScheduleChangeType.removed => Icons.remove_circle_outline,
                                  CourseScheduleChangeType.instructorChanged => Icons.person_outline,
                                },
                                size: 18,
                                color: switch (c.type) {
                                  CourseScheduleChangeType.added => Colors.green.shade700,
                                  CourseScheduleChangeType.removed => Colors.red.shade700,
                                  CourseScheduleChangeType.instructorChanged => Colors.orange.shade800,
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.note, style: const TextStyle(fontSize: 12.5)),
                                    Text(
                                      '${c.shatr}${c.detectedAt != null ? ' - ${fmt.format(c.detectedAt!)}' : ''}',
                                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          if (changes.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                if (!await _confirmClear('تقرير التغييرات')) return;
                await CourseScheduleChangeRepository.clear();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700, size: 18),
              label: Text('تفريغ التقرير', style: TextStyle(color: Colors.red.shade700)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<bool> _confirmClear(String label) async {
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
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd');
    return PortalScaffold(
      title: 'رفع ملفات المنظومة الداخلية',
      navItems: buildAdminNavItems(context, current: 'upload-hub'),
      body: _loadingDates
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerBanner(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _cardShell(
                              icon: Icons.menu_book_outlined,
                              title: 'المقررات الدراسية',
                              subtitle: 'يستخرج تلقائيًا جدول شعب كليتنا + قائمة مواد خارج الكلية معًا من نفس الملف.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LayoutBuilder(builder: (context, constraints) {
                                    final narrow = constraints.maxWidth < 560;
                                    final maleBox = _uploadSlotBox(
                                      icon: Icons.man_outlined,
                                      title: 'رفع المقررات الدراسية - طلاب',
                                      uploading: _uploadingMale,
                                      dates: [(label: 'آخر رفع', date: _maleExportDate)],
                                      fmt: fmt,
                                      onPressed: () => _uploadCourses(Shatr.male),
                                      onClear: () async {
                                        if (!await _confirmClear('جدول الطلاب ومواد خارج الكلية - طلاب')) return;
                                        await CourseScheduleRepository.clear(Shatr.male);
                                        await OutsideCourseRepository.clear(Shatr.male);
                                        await _loadDates();
                                      },
                                    );
                                    final femaleBox = _uploadSlotBox(
                                      icon: Icons.woman_outlined,
                                      title: 'رفع المقررات الدراسية - طالبات',
                                      uploading: _uploadingFemale,
                                      dates: [(label: 'آخر رفع', date: _femaleExportDate)],
                                      fmt: fmt,
                                      onPressed: () => _uploadCourses(Shatr.female),
                                      onClear: () async {
                                        if (!await _confirmClear('جدول الطالبات ومواد خارج الكلية - طالبات')) return;
                                        await CourseScheduleRepository.clear(Shatr.female);
                                        await OutsideCourseRepository.clear(Shatr.female);
                                        await _loadDates();
                                      },
                                    );
                                    // الطلاب دائمًا قبل الطالبات (بطلب سليمان صراحةً) - في صف RTL
                                    // العنصر الأول بترتيب الأبناء يظهر يمينًا (أول ما يُقرأ)، فيجب
                                    // أن يكون صندوق الطلاب أول عنصر بالقائمة ليظهر يمينًا فعليًا.
                                    if (narrow) {
                                      return Column(children: [maleBox, const SizedBox(height: 12), femaleBox]);
                                    }
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: maleBox),
                                        const SizedBox(width: 14),
                                        Expanded(child: femaleBox),
                                      ],
                                    );
                                  }),
                                  const SizedBox(height: 14),
                                  _fullWidthOutlinedButton(
                                    icon: Icons.science_outlined,
                                    label: 'رفع المقررات الدراسية (للتجربة)',
                                    onPressed: _uploadCoursesTrial,
                                  ),
                                  const SizedBox(height: 14),
                                  _fullWidthOutlinedButton(
                                    icon: Icons.fact_check_outlined,
                                    label: 'عرض تقرير التغييرات (إضافة/حذف شعب، تغيير محاضرين)',
                                    onPressed: _showChangesReport,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _cardShell(
                              icon: Icons.groups_outlined,
                              title: 'حالات الإرشاد',
                              subtitle: 'تقرير "طلاب على غير مرشدهم" الرسمي لكل الجامعة.',
                              child: _uploadSlotBox(
                                icon: Icons.groups_outlined,
                                title: 'رفع حالات الإرشاد',
                                buttonLabel: 'رفع ملف "كل الكليات"',
                                uploading: _uploadingAllColleges,
                                dates: [
                                  (label: 'آخر رفع - شطر الطلاب', date: _allCollegesMaleDate),
                                  (label: 'آخر رفع - شطر الطالبات', date: _allCollegesFemaleDate),
                                ],
                                fmt: fmt,
                                onPressed: () => runUploadAllColleges(
                                  context: context,
                                  setUploading: (v) => setState(() => _uploadingAllColleges = v),
                                  onSuccess: _loadDates,
                                ),
                                onClear: (_allCollegesMaleDate != null || _allCollegesFemaleDate != null)
                                    ? () => _clearKindBoth(AdvisingReportKind.allColleges, 'رفع حالات الإرشاد')
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _cardShell(
                              icon: Icons.accessible_outlined,
                              title: 'طلبة ذوو الإعاقة',
                              subtitle: 'ملف حالات ذوي الإعاقة الرسمي.',
                              child: _uploadSlotBox(
                                icon: Icons.accessible_outlined,
                                title: 'رفع طلبة ذوي الإعاقة',
                                buttonLabel: 'رفع طلبة ذوي الإعاقة',
                                uploading: _uploadingHealth,
                                dates: [
                                  (label: 'آخر رفع - شطر الطلاب', date: _healthMaleDate),
                                  (label: 'آخر رفع - شطر الطالبات', date: _healthFemaleDate),
                                ],
                                fmt: fmt,
                                onPressed: () => runUploadHealth(
                                  context: context,
                                  setUploading: (v) => setState(() => _uploadingHealth = v),
                                  onSuccess: _loadDates,
                                ),
                                onClear: (_healthMaleDate != null || _healthFemaleDate != null)
                                    ? () => _clearKindBoth(AdvisingReportKind.health, 'رفع طلبة ذوي الإعاقة')
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _cardShell(
                              icon: Icons.event_available_outlined,
                              title: 'جدول مواعيد الإرشاد لكل مرشد',
                              subtitle: 'حتى 10 ملفات دفعة واحدة، كل ملف يحدَّد قسمه/شطره من محتواه.',
                              child: _uploadSlotBox(
                                icon: Icons.event_available_outlined,
                                title: 'رفع جدول مواعيد الإرشاد',
                                buttonLabel: 'رفع جدول مواعيد الإرشاد',
                                uploading: _uploadingSchedule,
                                dates: [(label: 'آخر رفع (أي قسم/شطر)', date: _scheduleLatestDate)],
                                fmt: fmt,
                                onPressed: () => runUploadAdvisingSchedule(
                                  context: context,
                                  setUploading: (v) => setState(() => _uploadingSchedule = v),
                                  onSuccess: _loadDates,
                                ),
                                onClear: _scheduleLatestDate != null ? _clearSchedule : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ==================== عناصر التصميم ====================

  /// رأس مصرَّف داكن بخط ذهبي وشارة ماسية - نفس التصميم المرجعي الذي اعتمده
  /// سليمان صراحةً بدل العنوان النصي البسيط الأولي.
  Widget _headerBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
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
                Text(
                  'رفع ملفات الإرشاد الأكاديمي',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 90, child: Divider(color: AppColors.gold.withValues(alpha: 0.6), thickness: 1)),
                    const SizedBox(width: 10),
                    Icon(Icons.circle, size: 5, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Text(
                      'إدارة رفع ملفات التقارير والبيانات الرسمية',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Icon(Icons.diamond_outlined, color: AppColors.gold, size: 14),
          ),
          Positioned(top: -70, left: -70, child: _cornerArc()),
          Positioned(top: -70, right: -70, child: _cornerArc(flip: true)),
        ],
      ),
    );
  }

  /// زخرفة القوس الذهبي بزوايا الرأس - نفس الشكل المرجعي الذي اعتمده سليمان
  /// صراحةً (منحنيات ذهبية متداخلة أعلى يمين ويسار الرأس).
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

  Widget _goldIconBadge(IconData icon, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.greenDark, size: size * 0.5),
    );
  }

  /// بطاقة قسم موحَّدة (حدود ذهبية، خلفية بيضاء، ظل خفيف) - رأسها شارة أيقونة
  /// ذهبية + عنوان/وصف، ومحتواها المُمرَّر بعدها.
  Widget _cardShell({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الشارة أولًا (أقصى اليمين في RTL) ثم العنوان ملتصقًا بها مباشرة
              // - كانت Expanded تسحب العنوان لعرض الصف كاملاً فتبتعد الشارة
              // لأقصى اليسار بفراغ كبير بينهما (سليمان صراحةً: دائرة برتقالية
              // حول الشارة المنعزلة).
              _goldIconBadge(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.greenDark)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  /// صندوق رفع موحَّد - نفس الشكل والألوان لكل بطاقات الرفع الأربعة بلا
  /// استثناء (شارة أيقونة، عنوان، زر اختيار ملف، فاصل، صفوف تواريخ) - كان
  /// لدى بطاقات "كل الكليات/ذوو الإعاقة/مواعيد الإرشاد" شكل مختلف تمامًا
  /// (صف ممدود بفراغ كبير) عن صندوقَي "طلاب/طالبات" فبدت الصفحة غير موحَّدة
  /// الهوية - سليمان صراحةً (2026-08-17): "لم تلتزم بنفس التصميم والطريقة".
  Widget _uploadSlotBox({
    required IconData icon,
    required String title,
    required bool uploading,
    required List<({String label, DateTime? date})> dates,
    required DateFormat fmt,
    required VoidCallback onPressed,
    required VoidCallback? onClear,
    String buttonLabel = 'اختر ملفًا للرفع',
  }) {
    final hasAnyDate = dates.any((d) => d.date != null);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // ترتيب القراءة الصحيح: الأيقونة أولًا (أقصى اليمين)، ثم النص
              // مباشرة بعدها - نفس التصميم المرجعي حيث زر التفريغ يظهر بجانب
              // زر الرفع بالأسفل وليس بجانب العنوان (سليمان صراحةً 2026-08-17
              // بعد مراجعة صورة التصميم المرجعي مباشرة).
              _goldIconBadge(icon, size: 36),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // قاعدة ثابتة بكل الموقع: زر التفريغ دائمًا يسار المستطيل (الزر
              // الرئيسي) - لذا الزر الرئيسي أولاً (يمينًا بـ RTL) وزر التفريغ
              // بعده (يسار الزر مباشرة) - سليمان صراحةً 2026-08-17.
              //
              // عرض ثابت (لا يمتد بعرض الصفحة) = نفس عرض شارة شعار الموقع
              // أعلى يمين الصفحة (764×148px بارتفاع عرض 40 = ~206px + حشوة
              // 20px ≈ 226px) - سليمان صراحةً 2026-08-17 بعد مقارنة صريحة.
              // الارتفاع يبقى كما هو (42px) بلا تغيير.
              SizedBox(
                width: 226,
                height: 42,
                child: FilledButton.icon(
                  onPressed: uploading ? null : onPressed,
                  icon: uploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file, size: 18),
                  label: Text(buttonLabel, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.greenDark,
                    side: BorderSide(color: AppColors.gold, width: 1.2),
                  ),
                ),
              ),
              if (hasAnyDate && onClear != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: 'تفريغ البيانات (للاختبار)',
                    onPressed: onClear,
                    icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 6),
          // العناصر متلاصقة كتلة واحدة يمينًا (بلا Spacer يمدّها لعرض الصندوق
          // كاملاً) - كانت تُنتج فراغًا أفقيًا كبيرًا جدًا بالصناديق الممتدة
          // عرض البطاقة كاملة (سليمان صراحةً 2026-08-17: "شاهد التشتت الكبير").
          for (final d in dates)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text('${d.label}: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                  Text(
                    d.date != null ? fmt.format(d.date!) : 'لم يُرفع بعد',
                    style: TextStyle(color: Colors.grey.shade800, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fullWidthOutlinedButton({required IconData icon, required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.greenDark,
          side: BorderSide(color: AppColors.gold),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
