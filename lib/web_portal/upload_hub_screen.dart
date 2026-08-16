import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/course_catalog.dart';
import '../services/advising_report_repository.dart';
import '../services/advising_schedule_repository.dart';
import '../services/course_schedule_repository.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/outside_course_repository.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'portal_header.dart';

/// صفحة مركزية واحدة لكل الملفات التي مصدرها المنظومة الداخلية للجامعة
/// حصرًا (وليس Microsoft Forms أو الموقع نفسه) - بطلب سليمان صراحةً
/// (2026-08-17) بعد أن لاحظ أن أزرار الرفع المتناثرة داخل صفحات بيانات
/// كثيفة أصلاً (تسكين المقررات، حالات الإرشاد، مواعيد الإرشاد) تُشعر
/// المستخدم بالازدحام. كل صفحة أصلية تبقي فقط ملاحظة "آخر رفع: تاريخ" بلا
/// زر - الرفع الفعلي انتقل هنا بالكامل.
///
/// "رفع المقررات الدراسية" وحده مبنيّ هنا بمنطقه الكامل (كان معزولاً وبسيطًا
/// أصلاً). الثلاثة الباقية (كل الكليات/ذوي الإعاقة/مواعيد الإرشاد) منطقها
/// متشابك بشدة مع صفحاتها الأصلية (مطابقة أسماء، كشف تعارضات، تتبّع حركات
/// مرشدين) - نقلها بالكامل كان يعني خطر خطأ ميكانيكي على بيانات أكاديمية
/// حقيقية أثناء النقل، فسليمان فضّل تصغير المخاطرة: تبقى هذه الثلاثة تُرفَع
/// فعليًا من صفحاتها الأصلية، وهذه الصفحة توفّر فقط اختصارًا مباشرًا إليها
/// مع عرض تاريخ آخر رفع لكل منها.
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

  /// رفع موحَّد لملف "الحويّة" الشامل لشطر واحد - يستخرج منه دفعة واحدة كلا
  /// العنصرين معًا: (أ) جدول شعب كليتنا الخاصة (شعب "المستفيد" منها كلية
  /// إدارة الأعمال وكودها ليس ضمن قائمة "مواد خارج الكلية")، و(ب) قائمة
  /// "مواد خارج الكلية" المعتمَدة لهذا الفصل (شرطها: كودها بقائمة الخطة +
  /// شعبة فعلية مستفيدها كليتنا).
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
        throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف "الحويّة" الشامل الصحيح بصيغة Word (.docx).');
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

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الاعتماد'),
          content: Text(
            'من إجمالي ${sections.length} سطر بالملف لـ ${shatr.label}'
            '${exportDate != null ? ' (تاريخ السحب: ${DateFormat('yyyy/MM/dd').format(exportDate)})' : ''}:\n\n'
            '• ${ownRecords.length} شعبة لجدول كليتنا الخاص.\n'
            '• ${outsideOptions.length} مادة من قائمة "خارج الكلية" (من أصل ${CourseCatalog.outsideCollegeCourses.length}).\n\n'
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
      await _loadDates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد جدول ${shatr.label} (${ownRecords.length} شعبة) ومواد خارج الكلية (${outsideOptions.length} مادة) بنجاح.')),
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

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd');
    return PortalScaffold(
      title: 'رفع ملفات المنظومة الداخلية',
      navItems: buildAdminNavItems(context, current: 'upload-hub'),
      body: _loadingDates
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الملفات الأربعة هنا مصدرها المنظومة الداخلية الرسمية للجامعة (EduGate) حصرًا - '
                        'لا علاقة لها بنموذج Microsoft Forms ولا بملفات الموقع الداخلية.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      _sectionCard(
                        title: 'المقررات الدراسية (الحويّة)',
                        subtitle: 'يستخرج تلقائيًا جدول شعب كليتنا + قائمة مواد خارج الكلية معًا من نفس الملف.',
                        icon: Icons.table_chart_outlined,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            _uploadButton(
                              label: 'رفع المقررات الدراسية - طلاب',
                              uploading: _uploadingMale,
                              date: _maleExportDate,
                              fmt: fmt,
                              onPressed: () => _uploadCourses(Shatr.male),
                            ),
                            _uploadButton(
                              label: 'رفع المقررات الدراسية - طالبات',
                              uploading: _uploadingFemale,
                              date: _femaleExportDate,
                              fmt: fmt,
                              onPressed: () => _uploadCourses(Shatr.female),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'حالات الإرشاد - كل الكليات',
                        subtitle: 'تقرير "طلاب على غير مرشدهم" الرسمي لكل الجامعة.',
                        icon: Icons.groups_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _dateLine('شطر الطلاب', _allCollegesMaleDate, fmt),
                            _dateLine('شطر الطالبات', _allCollegesFemaleDate, fmt),
                            const SizedBox(height: 8),
                            _goToPageButton('الانتقال لصفحة الرفع'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'طلبة ذوو الإعاقة',
                        subtitle: 'ملف حالات ذوي الإعاقة الرسمي.',
                        icon: Icons.accessible_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _dateLine('شطر الطلاب', _healthMaleDate, fmt),
                            _dateLine('شطر الطالبات', _healthFemaleDate, fmt),
                            const SizedBox(height: 8),
                            _goToPageButton('الانتقال لصفحة الرفع'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'جدول مواعيد الإرشاد لكل مرشد',
                        subtitle: 'حتى 10 ملفات دفعة واحدة، كل ملف يحدَّد قسمه/شطره من محتواه.',
                        icon: Icons.event_available_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _dateLine('آخر رفع (أي قسم/شطر)', _scheduleLatestDate, fmt),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const AdvisingScheduleAdminScreen()),
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('الانتقال لصفحة الرفع'),
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: BorderSide(color: AppColors.green)),
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

  Widget _goToPageButton(String label) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AdvisingCasesAdminScreen()),
      ),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: BorderSide(color: AppColors.green)),
    );
  }

  Widget _dateLine(String label, DateTime? date, DateFormat fmt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label - آخر رفع: ${date != null ? fmt.format(date) : 'لم يُرفع بعد'}',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
      ),
    );
  }

  Widget _uploadButton({
    required String label,
    required bool uploading,
    required DateTime? date,
    required DateFormat fmt,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: uploading ? null : onPressed,
          icon: uploading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_file, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
        ),
        const SizedBox(height: 4),
        Text(
          date != null ? 'آخر رفع: ${fmt.format(date)}' : 'لم يُرفع بعد',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.h3(color: AppColors.greenDark)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
