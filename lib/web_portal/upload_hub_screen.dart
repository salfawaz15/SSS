import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/course_catalog.dart';
import '../models/course_section_record.dart';
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

  Future<void> _clearCourses() async {
    if (!await _confirmClear('جدول المقررات الدراسية (الشطرين)')) return;
    try {
      await CourseScheduleRepository.clear(Shatr.male);
      await CourseScheduleRepository.clear(Shatr.female);
      await OutsideCourseRepository.clear(Shatr.male);
      await OutsideCourseRepository.clear(Shatr.female);
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم تفريغ جدول المقررات بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر التفريغ', '$e');
    }
  }

  Future<void> _clearKindBoth(AdvisingReportKind kind, String label) async {
    if (!await _confirmClear(label)) return;
    try {
      await AdvisingReportRepository.clear(Shatr.male, kind: kind);
      await AdvisingReportRepository.clear(Shatr.female, kind: kind);
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم تفريغ $label بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر التفريغ', '$e');
    }
  }

  Future<void> _clearSchedule() async {
    if (!await _confirmClear('جدول مواعيد الإرشاد')) return;
    try {
      await AdvisingScheduleRepository.clearAll();
      await _loadDates();
      if (!mounted) return;
      _showSuccessSnackBar('تم تفريغ جدول مواعيد الإرشاد بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر التفريغ', '$e');
    }
  }

  Future<bool> _confirmClear(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفريغ $label'),
        content: const Text('سيُحذَف كل ما هو مخزَّن حاليًا لهذا العنصر. هل تريد المتابعة؟'),
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerBanner(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 780;
                          final coursesCard = _uploadCard(
                            icon: Icons.menu_book_outlined,
                            title: 'المقررات الدراسية',
                            subtitle: 'لاستخراج شعب المقررات الدراسية.',
                            uploading: _uploadingCourses,
                            dates: [
                              (label: 'آخر رفع - شطر الطلاب', date: _maleExportDate),
                              (label: 'آخر رفع - شطر الطالبات', date: _femaleExportDate),
                            ],
                            onPressed: _uploadCoursesCombined,
                            onClear: (_maleExportDate != null || _femaleExportDate != null) ? _clearCourses : null,
                          );
                          final casesCard = _uploadCard(
                            icon: Icons.groups_outlined,
                            title: 'حالات الإرشاد',
                            subtitle: 'رفع ملف حالات الإرشاد.',
                            uploading: _uploadingAllColleges,
                            dates: [
                              (label: 'آخر رفع - شطر الطلاب', date: _allCollegesMaleDate),
                              (label: 'آخر رفع - شطر الطالبات', date: _allCollegesFemaleDate),
                            ],
                            onPressed: () => runUploadAllColleges(
                              context: context,
                              setUploading: (v) => setState(() => _uploadingAllColleges = v),
                              onSuccess: () async {
                                await _loadDates();
                                if (mounted) _showSuccessSnackBar('تم رفع الملف بنجاح');
                              },
                            ),
                            onClear: (_allCollegesMaleDate != null || _allCollegesFemaleDate != null)
                                ? () => _clearKindBoth(AdvisingReportKind.allColleges, 'حالات الإرشاد')
                                : null,
                          );
                          final disabilityCard = _uploadCard(
                            icon: Icons.accessible_outlined,
                            title: 'طلبة ذوو الإعاقة',
                            subtitle: 'رفع الملف المعتمد لطلبة ذوي الإعاقة.',
                            uploading: _uploadingHealth,
                            dates: [
                              (label: 'آخر رفع - شطر الطلاب', date: _healthMaleDate),
                              (label: 'آخر رفع - شطر الطالبات', date: _healthFemaleDate),
                            ],
                            onPressed: () => runUploadHealth(
                              context: context,
                              setUploading: (v) => setState(() => _uploadingHealth = v),
                              onSuccess: () async {
                                await _loadDates();
                                if (mounted) _showSuccessSnackBar('تم رفع الملف بنجاح');
                              },
                            ),
                            onClear: (_healthMaleDate != null || _healthFemaleDate != null)
                                ? () => _clearKindBoth(AdvisingReportKind.health, 'طلبة ذوو الإعاقة')
                                : null,
                          );
                          final scheduleCard = _uploadCard(
                            icon: Icons.event_available_outlined,
                            title: 'جداول مواعيد الإرشاد',
                            subtitle: 'رفع جداول مواعيد الإرشاد (حتى 10 ملفات).',
                            uploading: _uploadingSchedule,
                            dates: [(label: 'آخر رفع', date: _scheduleLatestDate)],
                            buttonLabel: 'رفع الملفات',
                            dropzoneHint: 'اسحب الملفات هنا أو اضغط للاختيار',
                            onPressed: () => runUploadAdvisingSchedule(
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
  /// منطقة رفع بالضغط لاختيار الملف، ثم "آخر رفع" فقط + أزرار الرفع/التفريغ.
  /// بلا اسم/نوع/امتداد ملف أو أي خانة حالة تقنية - سليمان صراحةً 2026-08-17.
  Widget _uploadCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool uploading,
    required List<({String label, DateTime? date})> dates,
    required VoidCallback onPressed,
    required VoidCallback? onClear,
    String buttonLabel = 'رفع الملف',
    String dropzoneHint = 'اسحب الملف هنا أو اضغط للاختيار',
  }) {
    final fmt = DateFormat('d MMMM yyyy، h:mm a', 'ar');
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
          _dropzone(uploading: uploading, hint: dropzoneHint, onTap: uploading ? null : onPressed),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 42,
                child: FilledButton.icon(
                  onPressed: uploading ? null : onPressed,
                  icon: uploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file, size: 18),
                  label: Text(buttonLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.greenDark,
                    side: BorderSide(color: AppColors.gold, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
              ),
              if (onClear != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: 'تفريغ',
                    onPressed: onClear,
                    icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in dates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: RichText(
                          textAlign: TextAlign.end,
                          text: TextSpan(
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
                            children: [
                              TextSpan(text: '${dates.length > 1 ? d.label : 'آخر رفع'}: '),
                              TextSpan(
                                text: d.date != null ? fmt.format(d.date!) : 'لا يوجد رفع سابق',
                                style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// منطقة رفع بحدود متقطّعة تُضغَط لاختيار الملف - بلا سحب/إفلات حقيقي حاليًا
  /// (يحتاج مكتبة إضافية غير موجودة بالمشروع)، لكن بنفس الشكل البصري المطلوب.
  Widget _dropzone({required bool uploading, required String hint, required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: const Color(0xFFAAB6B0)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFCFB),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            children: [
              uploading
                  ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Icon(Icons.cloud_upload_outlined, size: 32, color: AppColors.green),
              const SizedBox(height: 6),
              Text(
                uploading ? 'جارٍ الرفع...' : hint,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF52615C), fontSize: 13.5),
              ),
            ],
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
