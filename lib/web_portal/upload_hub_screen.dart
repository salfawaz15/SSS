import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/advisor_roster_entry.dart';
import '../models/college_roster_member.dart';
import '../models/course_section_record.dart';
import '../services/advising_report_repository.dart';
import '../services/advising_schedule_repository.dart';
import '../services/advisor_roster_service.dart';
import '../services/advisor_zip_service.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_repository.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/escalation_file_service.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/outside_course_repository.dart';
import '../services/processed_file_parser_service.dart';
import '../services/stage_download_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';
import 'round_icon_button.dart';
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
  int _maleCourseCount = 0;
  int _femaleCourseCount = 0;
  bool _uploadingCourses = false;

  DateTime? _rosterLastSavedAt;
  int _rosterFacultyCount = 0;
  int _rosterAdminCount = 0;
  bool _uploadingRoster = false;

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
  bool _downloadingFormsFile = false;
  bool _downloadingAllAdvisors = false;
  bool _downloadingAllStage2 = false;
  bool _downloadingAllStage3 = false;
  bool _clearingFormsFile = false;

  // ==================== رفع/تنزيل ملفات مراحل الحذف والإضافة ====================
  // (بطلب سليمان صراحةً 2026-08-20: توحيد كل رفع/تنزيل ملفات دورة الحذف
  // والإضافة بصفحة واحدة - "رفع وتنزيل الملفات" - بدل تشتّتها بين لوحة
  // الإدارة وقوائم "المزيد" المتفرّقة).
  List<AdvisorRosterEntry> _roster = [];
  bool _uploadingProcessedAll = false;
  bool _uploadingCoordinatorAll = false;
  bool _uploadingCollegeAll = false;
  DateTime? _processedAllLastUpload;
  DateTime? _coordinatorAllLastUpload;
  DateTime? _collegeAllLastUpload;
  final Set<String> _stageKeys = {}; // مفاتيح تحميل تنزيل/رفع لكل قسم-شطر أو شطر

  @override
  void initState() {
    super.initState();
    _loadDates();
    AdvisorRosterService.loadAll().then((r) {
      if (mounted) setState(() => _roster = r);
    });
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
        CourseScheduleRepository.loadSchedule(Shatr.male),
        CourseScheduleRepository.loadSchedule(Shatr.female),
        CollegeRosterRepository.currentLastSavedAt(),
        CollegeRosterRepository.load(),
      ]);
      if (!mounted) return;
      final roster = results[11] as List<CollegeRosterMember>;
      setState(() {
        _maleExportDate = results[0] as DateTime?;
        _femaleExportDate = results[1] as DateTime?;
        _allCollegesMaleDate = results[2] as DateTime?;
        _allCollegesFemaleDate = results[3] as DateTime?;
        _healthMaleDate = results[4] as DateTime?;
        _healthFemaleDate = results[5] as DateTime?;
        _scheduleLatestDate = results[6] as DateTime?;
        _scheduleUploadedCount = results[7] as int;
        _maleCourseCount = (results[8] as List<CourseSectionRecord>).length;
        _femaleCourseCount = (results[9] as List<CourseSectionRecord>).length;
        _rosterLastSavedAt = results[10] as DateTime?;
        _rosterFacultyCount = roster.where((m) => m.type == CollegeMemberType.faculty).length;
        _rosterAdminCount = roster.where((m) => m.type == CollegeMemberType.admin).length;
      });
    } finally {
      if (mounted) setState(() => _loadingDates = false);
    }
  }

  /// رفع المقررات الدراسية - منطق الاختيار/التحليل/الحفظ مُستخرَج بالكامل
  /// إلى [runUploadCourses] بـ`upload_flows.dart` (2026-08-23) ليُستدعى أيضًا
  /// من تطبيق "بوابة الإرشاد" الجوّالة بلا تكرار منطق - بلا أي تغيير بالسلوك
  /// هنا (نفس الحوارات/الرسائل بالضبط).
  Future<void> _uploadCoursesCombined() => runUploadCourses(
        context: context,
        setUploading: (v) => setState(() => _uploadingCourses = v),
        onSuccess: _loadDates,
        onMessage: _showSuccessSnackBar,
      );

  /// تنزيل ملف طلبات الحذف/الإضافة مضغوطًا (10 ملفات قسم/شطر) - مُستخرَج
  /// إلى [runDownloadFormsZip] (2026-08-23)، نفس ملاحظة `_uploadCoursesCombined`.
  Future<void> _downloadFormsFileZip() => runDownloadFormsZip(
        context: context,
        setDownloading: (v) => setState(() => _downloadingFormsFile = v),
        onMessage: _showSuccessSnackBar,
      );

  /// تنزيل ملف مضغوط رئيسي واحد بمجلدات متداخلة (شطر > قسم > ملف لكل مرشد)
  /// لكل الأقسام/الشطرين دفعة واحدة - [runDownloadAllAdvisorsZip] (2026-08-25).
  Future<void> _downloadAllAdvisorsZip() => runDownloadAllAdvisorsZip(
        context: context,
        setDownloading: (v) => setState(() => _downloadingAllAdvisors = v),
        onMessage: _showSuccessSnackBar,
      );

  /// تنزيل كل ملفات "مرحلة منسّق القسم" (10 ملفات) دفعة واحدة -
  /// [runDownloadAllStage2Zip] (2026-08-25).
  Future<void> _downloadAllStage2Zip() => runDownloadAllStage2Zip(
        context: context,
        setDownloading: (v) => setState(() => _downloadingAllStage2 = v),
        onMessage: _showSuccessSnackBar,
      );

  /// تنزيل ملفَي "مرحلة منسّق الكلية" (شطر الطلاب/الطالبات) دفعة واحدة -
  /// [runDownloadAllStage3Zip] (2026-08-25).
  Future<void> _downloadAllStage3Zip() => runDownloadAllStage3Zip(
        context: context,
        setDownloading: (v) => setState(() => _downloadingAllStage3 = v),
        onMessage: _showSuccessSnackBar,
      );

  /// رفع ملف طلبات الحذف/الإضافة (Microsoft Forms) - مُستخرَج إلى
  /// [runUploadForms] (2026-08-23)، نفس ملاحظة `_uploadCoursesCombined`.
  Future<void> _pickAndUploadFormsFile() => runUploadForms(
        context: context,
        setUploading: (v) => setState(() => _uploadingFormsFile = v),
        onSuccess: () {},
        onMessage: _showSuccessSnackBar,
      );

  /// إفراغ كل بيانات "الملف الأساسي - طلبات الحذف والإضافة" (مسح مجموعة
  /// `tickets` بالكامل) - إجراء مدمِّر يحذف عمل كل المرشدين/المنسّقين، لذا
  /// بتأكيد صريح قبل التنفيذ (بطلب سليمان صراحةً 2026-08-24: زر ثالث بجانب
  /// رفع/تنزيل الملف لتفريغ البيانات دون الحاجة لأداة سطر أوامر منفصلة).
  Future<void> _confirmAndClearFormsFile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إفراغ البيانات'),
        content: const Text(
          'سيُحذَف كل ما هو مرفوع حاليًا لـ"الملف الأساسي - طلبات الحذف والإضافة" (كل الحالات وحالة معالجتها) '
          'من كل الأقسام والشطرين بلا استثناء ولا رجعة. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إفراغ نهائيًا'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearingFormsFile = true);
    try {
      await FirestoreTicketService.clearAll();
      if (!mounted) return;
      _showSuccessSnackBar('تم إفراغ بيانات "الملف الأساسي" بنجاح');
    } catch (e) {
      if (!mounted) return;
      showUploadErrorDialog(context, 'تعذّر إفراغ البيانات', '$e');
    } finally {
      if (mounted) setState(() => _clearingFormsFile = false);
    }
  }

  /// رفع دفعي (10+ ملفات دفعة واحدة) لملفات معالجة عائدة من أي مرشد/منسّق
  /// قسم - يطابق كل صف بمفتاحه الخاص بصرف النظر عن قسمه/شطره
  /// (`mergeAllProcessedRows`)، فلا حاجة لاختيار قسم أو شطر يدويًا. إجراء
  /// وقائي/احتياطي بطلب سليمان صراحةً 2026-08-20.
  Future<void> _pickAndUploadProcessedFilesAll() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اختيار أي ملف - حاول مرة أخرى.')),
        );
      }
      return;
    }

    setState(() => _uploadingProcessedAll = true);
    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(file.bytes!));
      }
      if (allRows.isEmpty) {
        throw Exception('تعذّرت قراءة محتوى الملفات المختارة (قد تكون فارغة أو غير مدعومة).');
      }

      final mergeResult = await FirestoreTicketService.mergeAllProcessedRows(allRows).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال بالخادم (30 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى'),
      );

      if (!mounted) return;
      setState(() {
        _uploadingProcessedAll = false;
        _processedAllLastUpload = DateTime.now();
      });
      _showMergeResultSnackBar(mergeResult);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingProcessedAll = false);
      showUploadErrorDialog(context, 'تعذّر رفع ملفات المعالجة', '$e');
    }
  }

  /// نفس فكرة الرفع الدفعي الشامل أعلاه لكن كزرّ مستقل لملفات "منسّقي
  /// الأقسام" تحديدًا (بطلب سليمان صراحةً 2026-08-20: فصل الزرّين حتى لا
  /// يلتبس الأمر بين مرحلة المرشدين ومرحلة منسّقي الأقسام) - تُستخدَم نفس
  /// دالة الدمج الشاملة تمامًا (`mergeAllProcessedRows` لا تميّز بين
  /// المراحل، كل صف يحمل مفتاحه الخاص) بحالة/تتبّع منفصلَين فقط لوضوح
  /// الواجهة.
  Future<void> _pickAndUploadCoordinatorProcessedFilesAll() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اختيار أي ملف - حاول مرة أخرى.')),
        );
      }
      return;
    }

    setState(() => _uploadingCoordinatorAll = true);
    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(file.bytes!));
      }
      if (allRows.isEmpty) {
        throw Exception('تعذّرت قراءة محتوى الملفات المختارة (قد تكون فارغة أو غير مدعومة).');
      }

      final mergeResult = await FirestoreTicketService.mergeAllProcessedRows(allRows).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال بالخادم (30 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى'),
      );

      if (!mounted) return;
      setState(() {
        _uploadingCoordinatorAll = false;
        _coordinatorAllLastUpload = DateTime.now();
      });
      _showMergeResultSnackBar(mergeResult);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingCoordinatorAll = false);
      showUploadErrorDialog(context, 'تعذّر رفع ملفات المعالجة', '$e');
    }
  }

  /// نفس الفكرة لكن لملفات منسّق الكلية (تُجمِّع الأقسام الخمسة لشطر واحد) -
  /// نفس دالة الدمج الشاملة تعمل بلا تمييز لأن كل صف يحمل مفتاحه الخاص.
  Future<void> _pickAndUploadCollegeProcessedFilesAll() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اختيار أي ملف - حاول مرة أخرى.')),
        );
      }
      return;
    }

    setState(() => _uploadingCollegeAll = true);
    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(file.bytes!));
      }
      if (allRows.isEmpty) {
        throw Exception('تعذّرت قراءة محتوى الملفات المختارة (قد تكون فارغة أو غير مدعومة).');
      }

      final mergeResult = await FirestoreTicketService.mergeAllProcessedRows(allRows).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال بالخادم (30 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى'),
      );

      if (!mounted) return;
      setState(() {
        _uploadingCollegeAll = false;
        _collegeAllLastUpload = DateTime.now();
      });
      _showMergeResultSnackBar(mergeResult);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingCollegeAll = false);
      showUploadErrorDialog(context, 'تعذّر رفع ملفات منسّق الكلية', '$e');
    }
  }

  /// تنزيل ملف مضغوط بداخله ملف Excel منفصل لكل مرشد أكاديمي (مرحلة 1) لقسم/
  /// شطر واحد - نفس منطق `admin_workspace_screen.dart` بالضبط.
  Future<void> _downloadStage1(String key, List<Map<String, dynamic>> tickets) async {
    setState(() => _stageKeys.add(key));
    try {
      final zipBytes = AdvisorZipService.buildZip(tickets, roster: _roster);
      final parts = key.split('|');
      final shatrLabel = parts[0] == ExcelParserService.shatrMale ? 'male' : 'female';
      downloadBytes(zipBytes, '${parts.length > 1 ? parts[1] : 'قسم'}_$shatrLabel.zip');
      if (parts.length > 1) {
        unawaited(StageDownloadService.recordAdvisorDownload(shatr: parts[0], department: parts[1]));
      }
      if (mounted) _showSuccessSnackBar('تم تنزيل ملف القسم بنجاح');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر إنشاء ملف القسم: $e')));
      }
    } finally {
      if (mounted) setState(() => _stageKeys.remove(key));
    }
  }

  /// تنزيل ملف "مرحلة منسّق القسم" (كل حالات القسم مدمجة بملف واحد) - نفس
  /// ملف منسّق القسم بالضبط، متاح هنا مباشرة للتنزيل أو إعادة الرفع بعد
  /// اعتماده (سليمان صراحةً 2026-08-20).
  Future<void> _downloadStage2(String key, List<Map<String, dynamic>> tickets) async {
    final stage2Key = 'stage2|$key';
    setState(() => _stageKeys.add(stage2Key));
    try {
      final bytes = EscalationFileService.buildStage2File(tickets);
      final parts = key.split('|');
      final shatrLabel = parts[0] == ExcelParserService.shatrMale ? 'male' : 'female';
      downloadBytes(bytes, '${parts.length > 1 ? parts[1] : 'قسم'}_${shatrLabel}_مرحلة_المنسق.xlsx');
      if (parts.length > 1) {
        unawaited(StageDownloadService.recordCoordinatorDownload(shatr: parts[0], department: parts[1]));
      }
      if (mounted) _showSuccessSnackBar('تم تنزيل ملف مرحلة المنسّق بنجاح');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر إنشاء ملف مرحلة المنسّق: $e')));
      }
    } finally {
      if (mounted) setState(() => _stageKeys.remove(stage2Key));
    }
  }

  /// تنزيل ملف "مرحلة منسّق الكلية" لشطر كامل (الأقسام الخمسة مدمجة).
  Future<void> _downloadStage3(String shatr, List<Map<String, dynamic>> shatrTickets) async {
    final key = 'stage3|$shatr';
    setState(() => _stageKeys.add(key));
    try {
      final bytes = EscalationFileService.buildStage3File(shatrTickets);
      final shatrLabel = shatr == ExcelParserService.shatrMale ? 'male' : 'female';
      downloadBytes(bytes, 'منسق_الكلية_$shatrLabel.xlsx');
      if (mounted) _showSuccessSnackBar('تم تنزيل ملف منسّق الكلية بنجاح');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر إنشاء ملف منسّق الكلية: $e')));
      }
    } finally {
      if (mounted) setState(() => _stageKeys.remove(key));
    }
  }

  /// رفع ملف معالج معتمَد لقسم/شطر محدَّد تحديدًا (نيابةً عن منسّق القسم).
  Future<void> _uploadProcessedForDepartment(String shatr, String department) async {
    final key = 'upload|$shatr|$department';
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اختيار أي ملف - حاول مرة أخرى.')),
        );
      }
      return;
    }

    setState(() => _stageKeys.add(key));
    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(file.bytes!));
      }
      if (allRows.isEmpty) {
        throw Exception('تعذّرت قراءة محتوى الملف المختار.');
      }
      final mergeResult = await FirestoreTicketService.mergeProcessedRows(
        allRows,
        shatr: shatr,
        department: department,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال بالخادم (25 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى'),
      );
      if (mounted) {
        _showMergeResultSnackBar(mergeResult, prefix: 'تم الدمج نيابةً عن "$department - $shatr"');
      }
    } catch (e) {
      if (mounted) showUploadErrorDialog(context, 'تعذّر رفع الملف', '$e');
    } finally {
      if (mounted) setState(() => _stageKeys.remove(key));
    }
  }

  /// رفع ملف معالج معتمَد نيابةً عن منسّق الكلية (شطر كامل).
  Future<void> _uploadProcessedForShatr(String shatr) async {
    final key = 'uploadShatr|$shatr';
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اختيار أي ملف - حاول مرة أخرى.')),
        );
      }
      return;
    }

    setState(() => _stageKeys.add(key));
    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(file.bytes!));
      }
      if (allRows.isEmpty) {
        throw Exception('تعذّرت قراءة محتوى الملف المختار.');
      }
      final mergeResult = await FirestoreTicketService.mergeProcessedRowsForShatr(
        allRows,
        shatr: shatr,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال بالخادم (25 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى'),
      );
      if (mounted) {
        _showMergeResultSnackBar(mergeResult, prefix: 'تم الدمج نيابةً عن منسّق الكلية "$shatr"');
      }
    } catch (e) {
      if (mounted) showUploadErrorDialog(context, 'تعذّر رفع الملف', '$e');
    } finally {
      if (mounted) setState(() => _stageKeys.remove(key));
    }
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

  /// ملخّص نتيجة الدمج كنص - يضيف تنبيهًا لو رفض المرشد إجراءً ("لم يتم
  /// التنفيذ") بلا تحديد سبب، حتى لا يمر ذلك بصمت لمنسّق القسم/الكلية.
  String _mergeResultMessage(dynamic mergeResult, {String prefix = 'تم الدمج'}) {
    final base = '$prefix: ${mergeResult.matchedCount} حالة مطابَقة'
        '${mergeResult.unmatchedCount > 0 ? '، ${mergeResult.unmatchedCount} غير مطابَقة' : ''}';
    if (mergeResult.missingReasonCount > 0) {
      return '$base\nتنبيه: ${mergeResult.missingReasonCount} حالة اختار فيها المرشد "لم يتم التنفيذ" بلا تحديد السبب - يُرجى إعادتها له لتحديد السبب';
    }
    return base;
  }

  /// نفس [_showSuccessSnackBar] لكن بلون تنبيه (لا أخضر) ومدة أطول - تُستخدَم
  /// عند وجود حالات "لم يتم التنفيذ" بلا سبب محدَّد ضمن نتيجة الدمج.
  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }

  void _showMergeResultSnackBar(dynamic mergeResult, {String prefix = 'تم الدمج'}) {
    final message = _mergeResultMessage(mergeResult, prefix: prefix);
    if (mergeResult.missingReasonCount > 0) {
      _showWarningSnackBar(message);
    } else {
      _showSuccessSnackBar(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'رفع وتنزيل الملفات',
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
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerBanner(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                        child: _formsFileUploadBanner(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                        child: _processingStageSection(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        // القسم الثاني (المقررات الدراسية) والثالث (الإرشاد)
                        // جنبًا إلى جنب على الشاشات العريضة بدل التكديس
                        // الرأسي - يقلّل الارتفاع الكلي للصفحة (بطلب سليمان
                        // صراحةً 2026-08-20: "الهدف أن تكون الصفحة واحدة
                        // دون تمرير").
                        child: LayoutBuilder(builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 1100;
                          final boxes = [_coursesBanner(), _rosterBanner(), _advisingSection()];
                          if (!wide) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [for (final b in boxes) ...[b, const SizedBox(height: 14)]]..removeLast(),
                            );
                          }
                          return _EqualHeightRow(children: boxes);
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

  /// قسم مراحل معالجة الحذف والإضافة كاملًا: رفع دفعي شامل (مرشدين/منسّقي
  /// أقسام + منسّق كلية)، ثم جدول Compact لكل قسم علمي × شطر (تنزيل مرحلة
  /// المرشدين، تنزيل مرحلة المنسّق، رفع الملف المعتمَد)، وأخيرًا صف منسّق
  /// الكلية (تنزيل/رفع لكل شطر). كله Compact عمدًا (بلا Cards ضخمة) حتى
  /// يتسع أكبر قدر ممكن من الصفحة بلا تمرير طويل - بطلب سليمان صراحةً
  /// 2026-08-20.
  Widget _processingStageSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.goldLight), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 9),
              const Icon(Icons.sync_alt, size: 17, color: AppColors.greenDark),
              const SizedBox(width: 6),
              const Text('مراحل معالجة الحذف والإضافة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: AppColors.greenDark)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'إجراء وقائي/احتياطي - رفع أو تنزيل نيابةً عن أي مرشد/منسّق قسم/منسّق كلية عند الحاجة.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          // الجدول هو التسلسل الفعلي للمراحل بالضبط (سليمان 2026-08-20:
          // "طالما اسميتها مراحل يجب أن يكون الترتيب حسب المراحل") - لكل قسم
          // علمي بكل شطر: 1) تنزيل ملفات المرشدين 2) رفع معالجة المرشدين
          // 3) تنزيل ملف مرحلة منسّق القسم 4) رفع معالجة منسّق القسم.
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirestoreTicketService.watchAllTickets(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()));
              }
              final tickets = snapshot.data!;
              final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
              if (groups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('لا توجد بيانات مرفوعة بعد لعرض ملفات الأقسام', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                );
              }

              final maleEntries = groups.entries.where((e) => e.key.startsWith('${ExcelParserService.shatrMale}|')).toList();
              final femaleEntries = groups.entries.where((e) => e.key.startsWith('${ExcelParserService.shatrFemale}|')).toList();
              final maleAll = maleEntries.expand((e) => e.value).toList();
              final femaleAll = femaleEntries.expand((e) => e.value).toList();

              return LayoutBuilder(builder: (context, constraints) {
                final narrow = constraints.maxWidth < 900;
                final maleCol = _departmentColumn('شطر الطلاب', maleEntries, ExcelParserService.shatrMale, maleAll);
                final femaleCol = _departmentColumn('شطر الطالبات', femaleEntries, ExcelParserService.shatrFemale, femaleAll);
                return narrow
                    ? Column(children: [maleCol, const SizedBox(height: 12), femaleCol])
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: maleCol), const SizedBox(width: 14), Expanded(child: femaleCol)]);
              });
            },
          ),
        ],
      ),
    );
  }

  /// بطاقة رفع دفعي عمودية - شارة أيقونة ملوَّنة (لون مميّز لكل مرحلة) أعلاها
  /// وزر رفع بعرض كامل أسفلها - كانت مستخدَمة لثلاث بطاقات (مرشدون/منسّقو
  /// أقسام/منسّق كلية) قبل توحيدها بأيقونات شريط "الملف الأساسي" (سليمان
  /// صراحةً 2026-08-25) - أُبقيت الدالة نفسها (غير مستخدَمة حاليًا) تحسبًا
  /// لحاجة مستقبلية لعرض بطاقات بهذا الشكل.
  // ignore: unused_element
  Widget _bulkStageCard({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String subtitle,
    required bool uploading,
    required DateTime? lastUpload,
    required VoidCallback onPressed,
  }) {
    final timeFmt = DateFormat('h:mm a', 'ar');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(icon, color: accentColor, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: accentColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            lastUpload != null ? 'آخر رفعة: ${timeFmt.format(lastUpload)}' : 'لا توجد بيانات مرفوعة',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: uploading ? null : onPressed,
              icon: uploading
                  ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.greenDark))
                  : const Icon(Icons.upload_file, size: 15),
              label: Text(uploading ? 'جارٍ الرفع...' : 'رفع', style: const TextStyle(fontSize: 11.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.greenDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// عمود أقسام شطر واحد (5 صفوف) + صف منسّق الكلية لنفس الشطر أسفلها.
  Widget _departmentColumn(
    String shatrLabel,
    List<MapEntry<String, List<Map<String, dynamic>>>> entries,
    String shatrValue,
    List<Map<String, dynamic>> shatrAll,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(shatrLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.greenDark)),
        const SizedBox(height: 6),
        for (final e in entries) _departmentStageRow(e.key, e.value),
        const SizedBox(height: 4),
        _collegeStageRow(shatrValue, shatrLabel, shatrAll),
      ],
    );
  }

  /// صف Compact واحد لقسم علمي: اسم القسم + عدد الحالات + 3 أيقونات
  /// (تنزيل مرحلة المرشدين، تنزيل مرحلة المنسّق، رفع ملف معتمَد).
  Widget _departmentStageRow(String key, List<Map<String, dynamic>> tickets) {
    final parts = key.split('|');
    final shatr = parts[0];
    final department = parts.length > 1 ? parts[1] : '';
    final isDownloading1 = _stageKeys.contains(key);
    final isDownloading2 = _stageKeys.contains('stage2|$key');
    final isUploading = _stageKeys.contains('upload|$key');

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(9)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$department — ${tickets.length} حالة',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // ترتيب الأيقونات هو نفسه تسلسل المراحل الفعلي بالضبط (سليمان
          // 2026-08-20): 1) تنزيل المرشدين 2) رفع معالجتهم 3) تنزيل مرحلة
          // المنسّق 4) رفع معالجته - لا ترتيب تصميمي عشوائي.
          _miniIconButton(
            tooltip: '1) تنزيل ملفات المرشدين',
            icon: Icons.download_outlined,
            color: AppColors.green,
            isLoading: isDownloading1,
            onPressed: isDownloading1 ? null : () => _downloadStage1(key, tickets),
          ),
          _miniIconButton(
            tooltip: '2) رفع معالجة المرشدين',
            icon: Icons.upload_file_outlined,
            color: Colors.deepPurple,
            isLoading: isUploading,
            onPressed: isUploading ? null : () => _uploadProcessedForDepartment(shatr, department),
          ),
          _miniIconButton(
            tooltip: '3) تنزيل ملف مرحلة منسّق القسم',
            icon: Icons.assignment_return_outlined,
            color: AppColors.gold,
            isLoading: isDownloading2,
            onPressed: isDownloading2 ? null : () => _downloadStage2(key, tickets),
          ),
          _miniIconButton(
            tooltip: '4) رفع معالجة منسّق القسم',
            icon: Icons.upload_file_outlined,
            color: Colors.deepPurple.shade700,
            isLoading: isUploading,
            onPressed: isUploading ? null : () => _uploadProcessedForDepartment(shatr, department),
          ),
        ],
      ),
    );
  }

  /// صف منسّق الكلية لشطر كامل (تنزيل مرحلة الكلية + رفع ملف معتمَد).
  Widget _collegeStageRow(String shatr, String shatrLabel, List<Map<String, dynamic>> shatrAll) {
    final key = 'stage3|$shatr';
    final uploadKey = 'uploadShatr|$shatr';
    final isDownloading = _stageKeys.contains(key);
    final isUploading = _stageKeys.contains(uploadKey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.goldLight)),
      child: Row(
        children: [
          Expanded(
            child: Text('منسّق الكلية — $shatrLabel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.greenDark), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          _miniIconButton(
            tooltip: 'تنزيل ملف مرحلة منسّق الكلية',
            icon: Icons.download_outlined,
            color: AppColors.green,
            isLoading: isDownloading,
            onPressed: (shatrAll.isEmpty || isDownloading) ? null : () => _downloadStage3(shatr, shatrAll),
          ),
          _miniIconButton(
            tooltip: 'رفع ملف معتمَد نيابةً عن منسّق الكلية',
            icon: Icons.upload_file_outlined,
            color: Colors.deepPurple,
            isLoading: isUploading,
            onPressed: isUploading ? null : () => _uploadProcessedForShatr(shatr),
          ),
        ],
      ),
    );
  }

  Widget _miniIconButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: color, disabledBackgroundColor: color.withValues(alpha: 0.35)),
          icon: isLoading
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 14, color: Colors.white),
          onPressed: onPressed,
        ),
      ),
    );
  }

  /// رأس مصرَّف داكن بخط ذهبي وشارة ماسية، مع زخرفة أقواس ذهبية بزوايا الرأس.
  /// بطاقة مميَّزة بصريًا لرفع ملف طلبات الحذف/الإضافة - مصدرها مختلف عمدًا
  /// عن بقية بطاقات هذه الصفحة (Microsoft Forms لا المنظومة الداخلية)، لذا
  /// صُمِّمت بهوية مغايرة (تدرّج أخضر داكن + شارة ذهبية) بدل قالب البطاقة
  /// البيضاء الموحَّد، وبإشارة صريحة لمصدرها تحت العنوان - بطلب سليمان
  /// 2026-08-19 (نُقلت من لوحة الإدارة إلى هنا).
  Widget _formsFileUploadBanner() {
    return _greenBanner(
      icon: Icons.assignment_outlined,
      title: 'الملف الأساسي - طلبات الحذف والإضافة',
      subtitleIcon: Icons.description_outlined,
      subtitle: 'المصدر: نموذج Microsoft Forms',
      // شريط واحد موحَّد يغطّي دورة الحذف/الإضافة كاملة (بطلب سليمان صراحةً
      // 2026-08-25: "أستطيع أفعل كل شيء من هذا الشريط" - هو من يتولى كل
      // عمليات الرفع/التنزيل هذا الفصل نيابة عن المرشدين/المنسّقين). كل زرّ
      // أيقونة فقط مع تلميح (tooltip) يشرحه عند تمرير الماوس - "رفع الملف"
      // وحده نصّي (بطلب أقدم صريح 2026-08-24: هو الإجراء الأساسي المتكرر
      // يوميًا، يستحق تمييزًا بصريًا عن البقية). فواصل رفيعة ذهبية تقسّم
      // الأزرار لمجموعات حسب المرحلة (أساسي/مرشد/منسّق قسم/منسّق كلية).
      button: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 6,
        children: [
          RoundIconButton(
            tooltip: 'تنزيل ملف مضغوط (10 ملفات خام - قسم/شطر، لإرسال منسّق القسم يدويًا)',
            color: AppColors.gold,
            icon: Icons.download_outlined,
            isLoading: _downloadingFormsFile,
            onPressed: _downloadingFormsFile ? null : _downloadFormsFileZip,
          ),
          RoundIconButton(
            tooltip: 'إفراغ كل البيانات المرفوعة لهذا الملف',
            color: Colors.red.shade700,
            icon: Icons.delete_outline,
            isLoading: _clearingFormsFile,
            onPressed: _clearingFormsFile ? null : _confirmAndClearFormsFile,
          ),
          const SizedBox(width: 4),
          _bannerButton(
            uploading: _uploadingFormsFile,
            label: 'رفع الملف',
            onPressed: _pickAndUploadFormsFile,
          ),
          _bannerDivider(),
          RoundIconButton(
            tooltip: 'مرحلة المرشد: تنزيل الكل مقسَّم لكل مرشد (شطر > قسم > ملف)',
            color: AppColors.gold,
            icon: Icons.folder_zip_outlined,
            isLoading: _downloadingAllAdvisors,
            onPressed: _downloadingAllAdvisors ? null : _downloadAllAdvisorsZip,
          ),
          RoundIconButton(
            tooltip: 'مرحلة المرشد: رفع الملفات المعالجة العائدة من المرشدين',
            color: AppColors.goldLight,
            icon: Icons.upload_file_outlined,
            isLoading: _uploadingProcessedAll,
            onPressed: _uploadingProcessedAll ? null : _pickAndUploadProcessedFilesAll,
          ),
          _bannerDivider(),
          RoundIconButton(
            tooltip: 'مرحلة منسّق القسم: تنزيل كل ملفات الأقسام (10 ملفات) دفعة واحدة',
            color: AppColors.gold,
            icon: Icons.folder_zip_outlined,
            isLoading: _downloadingAllStage2,
            onPressed: _downloadingAllStage2 ? null : _downloadAllStage2Zip,
          ),
          RoundIconButton(
            tooltip: 'مرحلة منسّق القسم: رفع الملفات المعالجة العائدة من منسّقي الأقسام',
            color: AppColors.goldLight,
            icon: Icons.upload_file_outlined,
            isLoading: _uploadingCoordinatorAll,
            onPressed: _uploadingCoordinatorAll ? null : _pickAndUploadCoordinatorProcessedFilesAll,
          ),
          _bannerDivider(),
          RoundIconButton(
            tooltip: 'مرحلة منسّق الكلية: تنزيل ملفَي الشطرين دفعة واحدة',
            color: AppColors.gold,
            icon: Icons.folder_zip_outlined,
            isLoading: _downloadingAllStage3,
            onPressed: _downloadingAllStage3 ? null : _downloadAllStage3Zip,
          ),
          RoundIconButton(
            tooltip: 'مرحلة منسّق الكلية: رفع الملف المعالج العائد من منسّق الكلية',
            color: AppColors.goldLight,
            icon: Icons.upload_file_outlined,
            isLoading: _uploadingCollegeAll,
            onPressed: _uploadingCollegeAll ? null : _pickAndUploadCollegeProcessedFilesAll,
          ),
        ],
      ),
    );
  }

  /// شريط أخضر عام موحَّد (نفس هوية "الملف الأساسي") - يُستخدَم لعنونة أي
  /// قسم رئيسي بالصفحة (الحذف والإضافة/المقررات الدراسية/الإرشاد) بنفس
  /// الهوية البصرية، بزر رفع اختياري (`button`) - بلا زر إن كان القسم
  /// عنوانًا فقط لعناصر أدناه (بطلب سليمان صراحةً 2026-08-20: "ليس بالضرورة
  /// أن يكون فيه كلمة رفع").
  Widget _greenBanner({
    required IconData icon,
    required String title,
    required IconData subtitleIcon,
    required String subtitle,
    Widget? button,
    double verticalPadding = 16,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: verticalPadding),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final info = Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.greenDark, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(subtitleIcon, size: 12, color: AppColors.goldLight.withValues(alpha: 0.9)),
                      const SizedBox(width: 5),
                      Flexible(child: Text(subtitle, style: TextStyle(color: AppColors.goldLight.withValues(alpha: 0.9), fontSize: 10.5), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        if (button == null) return info;
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 12), button]);
        }
        return Row(children: [Expanded(child: info), const SizedBox(width: 14), button]);
      }),
    );
  }

  /// فاصل رفيع بين مجموعات أزرار مرحلة/أخرى داخل شريط "الملف الأساسي" -
  /// يفصل بصريًا بين مراحل الدورة (أساسي/مرشد/منسّق قسم/منسّق كلية) بلا
  /// حاجة لتسميات نصية تُثقل الشريط.
  Widget _bannerDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.gold.withValues(alpha: 0.45),
      );

  /// زر ذهبي موحَّد لكل أشرطة `_greenBanner`.
  Widget _bannerButton({
    required bool uploading,
    required String label,
    required VoidCallback? onPressed,
    IconData icon = Icons.upload_file,
    String loadingLabel = 'جارٍ الرفع...',
  }) {
    return ElevatedButton.icon(
      onPressed: uploading ? null : onPressed,
      icon: uploading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.greenDark))
          : Icon(icon, size: 16),
      label: Text(uploading ? loadingLabel : label, style: const TextStyle(fontSize: 12.5)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.greenDark,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  /// القسم الثاني: المقررات الدراسية - شريط أخضر بنفس هوية "الملف الأساسي"
  /// (بطلب سليمان صراحةً 2026-08-20) بدل بطاقة بيضاء منفصلة ضمن شبكة.
  Widget _coursesBanner() {
    final coursesDate = _latestOf(_maleExportDate, _femaleExportDate);
    final dateFmt = DateFormat('d MMMM yyyy، h:mm a', 'ar');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.goldLight), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenBanner(
            icon: Icons.menu_book_outlined,
            title: 'المقررات الدراسية',
            subtitleIcon: Icons.info_outline,
            subtitle: coursesDate != null ? 'آخر رفع: ${dateFmt.format(coursesDate)}' : 'لاستخراج شعب المقررات الدراسية - لا توجد بيانات مرفوعة بعد',
            button: _bannerButton(uploading: _uploadingCourses, label: 'رفع الملف', onPressed: _uploadCoursesCombined),
            verticalPadding: 12,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _courseCountStat(label: 'مقررات شطر الطلاب', count: _maleCourseCount, emoji: '👨‍🎓')),
              const SizedBox(width: 10),
              Expanded(child: _courseCountStat(label: 'مقررات شطر الطالبات', count: _femaleCourseCount, emoji: '👩‍🎓')),
            ],
          ),
          if (coursesDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(alignment: Alignment.centerLeft, child: _clearDataButton(label: 'مسح بيانات المقررات', onPressed: _clearCourses)),
            ),
        ],
      ),
    );
  }

  /// بطاقة إحصائية صغيرة: عدد شعب المقررات المرفوعة لشطر واحد.
  Widget _courseCountStat({required String label, required int count, required String emoji}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(9)),
      child: Column(
        children: [
          Text('$emoji  $count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.greenDark)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  /// مربع "منسوبي الكلية" - نُقل من صفحة "بيانات منسوبي الكلية" المستقلة
  /// إلى هنا (سليمان 2026-08-22: "يوجد مكان للرفع") ليقع بين مربعَي
  /// "المقررات الدراسية" و"الإرشاد الأكاديمي" بنفس هويتهما البصرية حرفيًا.
  Widget _rosterBanner() {
    final dateFmt = DateFormat('d MMMM yyyy، h:mm a', 'ar');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.goldLight), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenBanner(
            icon: Icons.groups_2_outlined,
            title: 'منسوبي الكلية',
            subtitleIcon: Icons.info_outline,
            subtitle: _rosterLastSavedAt != null ? 'آخر اعتماد: ${dateFmt.format(_rosterLastSavedAt!)}' : 'لا توجد بيانات مرفوعة بعد',
            button: _bannerButton(
              uploading: _uploadingRoster,
              label: 'رفع الملف',
              onPressed: () => runUploadCollegeRoster(
                context: context,
                setUploading: (v) => setState(() => _uploadingRoster = v),
                onSuccess: () async {
                  await _loadDates();
                  if (mounted) _showSuccessSnackBar('تم اعتماد بيانات منسوبي الكلية بنجاح');
                },
              ),
            ),
            verticalPadding: 12,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _courseCountStat(label: 'أعضاء هيئة تدريس', count: _rosterFacultyCount, emoji: '👨‍🏫')),
              const SizedBox(width: 10),
              Expanded(child: _courseCountStat(label: 'إداريون', count: _rosterAdminCount, emoji: '🗂️')),
            ],
          ),
          if (_rosterLastSavedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _clearDataButton(
                  label: 'مسح بيانات المنسوبين',
                  onPressed: () => _clearRoster(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _clearRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ بيانات منسوبي الكلية'),
        content: const Text('سيُحذَف كل ما هو مخزَّن حاليًا (لتسهيل إعادة اختبار الرفع). هل تريد المتابعة؟'),
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
    await CollegeRosterRepository.clear();
    await _loadDates();
    if (!mounted) return;
    _showSuccessSnackBar('تم تفريغ بيانات المنسوبين.');
  }

  /// القسم الثالث: الإرشاد الأكاديمي - شريط أخضر عنوان فقط (بلا زر) يوضّح
  /// أن ما يليه (3 صفوف Compact) خاص بالإرشاد، ثم الصفوف الثلاثة بنفس أسلوب
  /// صفوف الأقسام العلمية بالقسم الأول - بطلب سليمان صراحةً 2026-08-20.
  Widget _advisingSection() {
    final casesDate = _latestOf(_allCollegesMaleDate, _allCollegesFemaleDate);
    final disabilityDate = _latestOf(_healthMaleDate, _healthFemaleDate);
    final scheduleMaxed = _scheduleUploadedCount >= 10;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.goldLight), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenBanner(
            icon: Icons.fact_check_outlined,
            title: 'الإرشاد الأكاديمي',
            subtitleIcon: Icons.info_outline,
            subtitle: 'حالات الإرشاد، ذوو الإعاقة، ومواعيد الإرشاد',
            verticalPadding: 12,
          ),
          const SizedBox(height: 10),
          _advisingCompactRow(
            icon: Icons.groups_outlined,
            title: 'حالات الإرشاد',
            uploading: _uploadingAllColleges,
            date: casesDate,
            onPressed: () => runUploadAllColleges(
              context: context,
              setUploading: (v) => setState(() => _uploadingAllColleges = v),
              onSuccess: () async {
                await _loadDates();
                if (mounted) _showSuccessSnackBar('تم رفع الملف بنجاح');
              },
            ),
            onClear: casesDate != null ? () => _clearKindBoth(AdvisingReportKind.allColleges, 'ملف حالات الإرشاد') : null,
          ),
          _advisingCompactRow(
            icon: Icons.accessible_outlined,
            title: 'طلبة ذوو الإعاقة',
            uploading: _uploadingHealth,
            date: disabilityDate,
            onPressed: () => runUploadHealth(
              context: context,
              setUploading: (v) => setState(() => _uploadingHealth = v),
              onSuccess: () async {
                await _loadDates();
                if (mounted) _showSuccessSnackBar('تم رفع الملف بنجاح');
              },
            ),
            onClear: disabilityDate != null ? () => _clearKindBoth(AdvisingReportKind.health, 'ملف طلبة ذوي الإعاقة') : null,
          ),
          _advisingCompactRow(
            icon: Icons.event_available_outlined,
            title: 'جداول مواعيد الإرشاد',
            uploading: _uploadingSchedule,
            date: _scheduleLatestDate,
            fileCounterText: '$_scheduleUploadedCount / 10',
            disabled: scheduleMaxed,
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
          ),
        ],
      ),
    );
  }

  /// صف Compact واحد لعنصر إرشادي (نفس ارتفاع/هوية صفوف الأقسام العلمية).
  Widget _advisingCompactRow({
    required IconData icon,
    required String title,
    required bool uploading,
    required DateTime? date,
    required VoidCallback? onPressed,
    VoidCallback? onClear,
    String? fileCounterText,
    bool disabled = false,
  }) {
    final dateFmt = DateFormat('d MMM yyyy، h:mm a', 'ar');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(9)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.greenDark),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  date != null ? dateFmt.format(date) : 'لا توجد بيانات مرفوعة',
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (fileCounterText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFF3FAF6), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFFBFD8C9))),
              child: Text(fileCounterText, style: const TextStyle(color: Color(0xFF176044), fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
          ],
          if (onClear != null) _miniIconButton(tooltip: 'مسح البيانات الحالية', icon: Icons.delete_outline, color: Colors.red.shade400, isLoading: false, onPressed: onClear),
          _miniIconButton(
            tooltip: disabled ? 'اكتمل الحد الأعلى' : 'رفع ملف',
            icon: Icons.upload_file_outlined,
            color: AppColors.green,
            isLoading: uploading,
            onPressed: disabled ? null : onPressed,
          ),
        ],
      ),
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
                  'رفع وتنزيل الملفات',
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

/// يعرض بطاقتين جنبًا إلى جنب بنفس الارتفاع تمامًا رغم اختلاف محتواهما -
/// بديل عن `IntrinsicHeight` (يتعارض مع `LayoutBuilder` المتداخل بداخل
/// `_greenBanner`، انظر ملاحظة README.md 2026-08-20) يقيس الارتفاع الفعلي
/// بعد الرسم عبر `GlobalKey` ويطبّق الأطول كحدّ أدنى للطرفين.
/// صفّ Expanded متساوي الارتفاع بعدد عناصر حرّ (كان يقبل عنصرين فقط
/// left/right - عُمِّم ليقبل قائمة بعد إضافة مربع "منسوبي الكلية" الثالث
/// بينهما، سليمان 2026-08-22).
class _EqualHeightRow extends StatefulWidget {
  final List<Widget> children;
  const _EqualHeightRow({required this.children});

  @override
  State<_EqualHeightRow> createState() => _EqualHeightRowState();
}

class _EqualHeightRowState extends State<_EqualHeightRow> {
  late final List<GlobalKey> _keys = [for (var i = 0; i < widget.children.length; i++) GlobalKey()];
  double? _matchedHeight;

  void _measure() {
    double maxHeight = 0;
    for (final key in _keys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      if (box.size.height > maxHeight) maxHeight = box.size.height;
    }
    if (_matchedHeight != maxHeight && mounted) {
      setState(() => _matchedHeight = maxHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i != 0) const SizedBox(width: 14),
          Expanded(
            child: ConstrainedBox(
              key: _keys[i],
              constraints: BoxConstraints(minHeight: _matchedHeight ?? 0),
              child: widget.children[i],
            ),
          ),
        ],
      ],
    );
  }
}

