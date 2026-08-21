import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:printing/printing.dart';

import '../models/advisor_roster_entry.dart';
import '../services/advisor_roster_service.dart';
import '../services/advisor_zip_service.dart';
import '../services/disability_file_service.dart';
import '../services/escalation_file_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/processed_file_parser_service.dart';
import '../services/report_data_service.dart';
import '../services/report_excel_service.dart';
import '../services/report_filter_service.dart';
import '../services/report_pdf_service.dart';
import '../services/stage_download_service.dart';
import '../services/stage_snapshot_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'coordinator_nav.dart';
import 'follow_up_chart.dart';
import 'portal_cards.dart';
import 'portal_header.dart';
import 'stage_progress_chart.dart';
import 'ticket_action_stats_panel.dart';

/// شاشة المنسّق في بوابة الويب: تعرض فقط حالات قسمه/شطره (Firestore rules
/// تمنع أي وصول لغير ذلك بنيويًا)، مع زر تنزيل وزر رفع ملف معالج، وتقرير
/// متابعة إنجاز خاص بقسمه فقط (بلا صلاحية على أي تقرير أو قسم آخر).
class CoordinatorWorkspaceScreen extends StatelessWidget {
  final String uid;

  const CoordinatorWorkspaceScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('coordinator_accounts')
          .doc(uid)
          .get(),
      builder: (context, snapshot) {
        // كان الفحص السابق `!snapshot.hasData` فقط - لا يميّز "لا يزال يحمّل"
        // عن "فشل فعليًا" (مثال: PERMISSION_DENIED)، فيظهر دوّار تحميل بلا
        // نهاية بدل رسالة خطأ واضحة تكشف السبب الحقيقي (سليمان 2026-08-16،
        // لاحظه فعليًا بحساب منسّق قسم على الجوال بعد اختبار حي).
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('تعذّر تحميل بيانات الحساب: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data();
        final shatr = data?['shatr']?.toString() ?? '';
        final department = data?['department']?.toString() ?? '';

        if (shatr.isEmpty || department.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('تعذّر تحديد بيانات الحساب')),
          );
        }

        return _CoordinatorBody(shatr: shatr, department: department);
      },
    );
  }
}

class _CoordinatorBody extends StatefulWidget {
  final String shatr;
  final String department;

  const _CoordinatorBody({required this.shatr, required this.department});

  @override
  State<_CoordinatorBody> createState() => _CoordinatorBodyState();
}

class _CoordinatorBodyState extends State<_CoordinatorBody> {
  bool _isDownloading = false;
  bool _isUploading = false;
  bool _isResetting = false;
  bool _isFollowUpPrinting = false;
  bool _isFollowUpExportingExcel = false;
  bool _isFollowUpExportingPdf = false;
  bool _isDownloadingDisabilityFile = false;
  bool _isFreezingStage1 = false;
  bool _isDownloadingStage2 = false;
  bool _isFreezingStage2 = false;
  MergeResult? _lastResult;
  String? _errorMessage;

  /// مُحمَّلة مرة واحدة عند فتح الشاشة - تُستخدم في كل تقارير المتابعة حتى
  /// لا يظهر منسّق القسم كأن لديه حالات معلَّقة بعد أن تفرَّغ منها فعليًا
  /// (نفس تجميع "تفريغ المنسّق" المستخدَم عند بناء ملف ZIP للقسم).
  List<AdvisorRosterEntry> _roster = [];

  @override
  void initState() {
    super.initState();
    AdvisorRosterService.loadAll().then((r) {
      if (mounted) setState(() => _roster = r);
    });
  }

  /// ملف Excel واحد بكل حالات ذوي الإعاقة في القسم - نفس الملف بالضبط متاح
  /// أيضًا من لوحة الإدارة مباشرة (لو تأخر المنسّق أو غاب)، حتى يرسله المنسّق
  /// لأمين القسم، ثم يرفع عودته عبر زر "رفع الملفات المعالجة" أعلاه.
  Future<void> _downloadDisabilityFile(List<Map<String, dynamic>> tickets) async {
    setState(() => _isDownloadingDisabilityFile = true);
    try {
      final bytes = DisabilityFileService.buildFile(tickets);
      downloadBytes(bytes, '${widget.department}_ذوي_الإعاقة.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل ملف ذوي الإعاقة بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء ملف ذوي الإعاقة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingDisabilityFile = false);
    }
  }

  String get _followUpTitle => 'متابعة إنجاز ${widget.department} - ${widget.shatr}';

  Future<void> _printFollowUp(List<Map<String, dynamic>> tickets) async {
    setState(() => _isFollowUpPrinting = true);
    try {
      final data = ReportDataService.build(tickets, roster: _roster);
      final bytes = await ReportPdfService.buildFollowUp(
        data,
        title: _followUpTitle,
        pendingCases: ReportFilterService.pendingCases(tickets),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر فتح تقرير المتابعة للطباعة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowUpPrinting = false);
    }
  }

  Future<void> _exportFollowUpPdf(List<Map<String, dynamic>> tickets) async {
    setState(() => _isFollowUpExportingPdf = true);
    try {
      final data = ReportDataService.build(tickets, roster: _roster);
      final bytes = await ReportPdfService.buildFollowUp(
        data,
        title: _followUpTitle,
        pendingCases: ReportFilterService.pendingCases(tickets),
      );
      downloadBytes(bytes, 'متابعة_${widget.department}.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل تقرير المتابعة (PDF) بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء تقرير المتابعة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowUpExportingPdf = false);
    }
  }

  Future<void> _exportFollowUpExcel(List<Map<String, dynamic>> tickets) async {
    setState(() => _isFollowUpExportingExcel = true);
    try {
      final data = ReportDataService.build(tickets, roster: _roster);
      final bytes = ReportExcelService.buildFollowUp(
        data,
        pendingCases: ReportFilterService.pendingCases(tickets),
      );
      downloadBytes(bytes, 'متابعة_${widget.department}.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل تقرير المتابعة (Excel) بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء تقرير المتابعة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowUpExportingExcel = false);
    }
  }

  Future<void> _confirmResetStatus() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ حالة القسم'),
        content: const Text(
          'سيتم مسح حالة الإنجاز والملاحظات لكل حالات هذا القسم (تراجع عن آخر '
          'رفع للملف المعالج) - بيانات الطلاب الأصلية تبقى كما هي، ويمكنك رفع '
          'الملف الصحيح مرة أخرى بعد ذلك. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('تفريغ الحالة'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isResetting = true;
      _errorMessage = null;
      _lastResult = null;
    });
    try {
      await FirestoreTicketService.resetDepartmentStatus(
        shatr: widget.shatr,
        department: widget.department,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفريغ حالة القسم بنجاح')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _download(List<Map<String, dynamic>> tickets) async {
    setState(() => _isDownloading = true);
    try {
      // ملف مضغوط بداخله ملف Excel منفصل محمي لكل مرشد أكاديمي، بدل ملف
      // واحد يخلط كل مرشدي القسم. حالات منسّق القسم تُوزَّع تلقائيًا على
      // بقية المرشدين خلال فترة الحذف والإضافة.
      final roster = await AdvisorRosterService.loadAll();
      final zipBytes = AdvisorZipService.buildZip(tickets, roster: roster);
      downloadBytes(zipBytes, '${widget.department}.zip');
      unawaited(StageDownloadService.recordAdvisorDownload(shatr: widget.shatr, department: widget.department));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل ملف القسم بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء ملف القسم: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// المرحلة 2: ملف مدمج واحد بكل حالات القسم (بما فيها المكتملة وحالات ذوي
  /// الإعاقة معًا) يعالجه المنسّق بنفسه بحكم صلاحياته الأعلى من المرشد.
  Future<void> _downloadStage2(List<Map<String, dynamic>> tickets) async {
    setState(() => _isDownloadingStage2 = true);
    try {
      final bytes = EscalationFileService.buildStage2File(tickets);
      downloadBytes(bytes, '${widget.department}_مرحلة_المنسق.xlsx');
      unawaited(StageDownloadService.recordCoordinatorDownload(shatr: widget.shatr, department: widget.department));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل ملف مرحلة المنسّق بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء ملف مرحلة المنسّق: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingStage2 = false);
    }
  }

  Future<void> _confirmFreezeStage1(List<Map<String, dynamic>> tickets) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تثبيت تقرير مرحلة المرشدين'),
        content: const Text(
          'سيُسجَّل تقرير ثابت بحالة كل مرشدي القسم الآن، ولن يتغيّر لاحقًا حتى '
          'لو تغيّرت البيانات - تأكد أن كل المرشدين رفعوا ملفاتهم أولًا. هل '
          'تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد التثبيت'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isFreezingStage1 = true);
    try {
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      await StageSnapshotService.freezeStage1(
        shatr: widget.shatr,
        department: widget.department,
        tickets: tickets,
        roster: _roster,
        generatedByEmail: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تثبيت تقرير مرحلة المرشدين')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFreezingStage1 = false);
    }
  }

  Future<void> _confirmFreezeStage2(List<Map<String, dynamic>> tickets) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تثبيت تقرير مرحلتي'),
        content: const Text(
          'سيُسجَّل تقرير ثابت بحالة القسم بعد معالجتك الشخصية، ولن يتغيّر '
          'لاحقًا. تأكد أنك انتهيت من معالجة ما تستطيع قبل المتابعة. هل تريد '
          'المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد التثبيت'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isFreezingStage2 = true);
    try {
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      await StageSnapshotService.freezeStage2(
        shatr: widget.shatr,
        department: widget.department,
        tickets: tickets,
        roster: _roster,
        generatedByEmail: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تثبيت تقرير مرحلتي')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFreezingStage2 = false);
    }
  }

  Future<void> _pickAndUploadProcessedFile() async {
    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _lastResult = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      // كان يعود بصمت بلا أي رسالة - يبدو للمستخدم وكأن الضغط لم يفعل شيئًا
      // (سليمان 2026-08-20: "لا يعطي أي رسالة أو أي شيء أنه تم الرفع").
      setState(() {
        _isUploading = false;
        _errorMessage = 'لم يتم اختيار أي ملف - حاول مرة أخرى.';
      });
      return;
    }

    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        final Uint8List bytes = file.bytes!;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(bytes));
      }

      if (allRows.isEmpty) {
        // كل الملفات المختارة بلا بيانات قابلة للقراءة (bytes فارغة أو ملف
        // بلا صفوف) - لا نكمل الرفع بصمت (سليمان 2026-08-20: رفع ملف حقيقي
        // ولم تظهر أي رسالة إطلاقًا).
        throw Exception('تعذّرت قراءة محتوى الملف المختار (قد يكون فارغًا أو غير مدعوم).');
      }

      // مهلة 25 ثانية بدل انتظار بلا نهاية - لو تعثّر الاتصال بـFirestore
      // (بطء شبكة/جانب العميل) يظهر خطأ واضح بدل دوران أبدي بلا أي رسالة
      // (سليمان 2026-08-09: لاحظ الأيقونة تدور بلا توقف بلا خطأ ولا نجاح).
      final mergeResult = await FirestoreTicketService.mergeProcessedRows(
        allRows,
        shatr: widget.shatr,
        department: widget.department,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception(
          'انتهت مهلة الاتصال بالخادم (25 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى',
        ),
      );

      setState(() {
        _lastResult = mergeResult;
        _isUploading = false;
      });
      // SnackBar إضافي يظهر دائمًا أسفل الشاشة بصرف النظر عن موضع التمرير -
      // الرسالة النصية بالبطاقة قد تكون خارج نطاق الرؤية الحالي (سليمان
      // 2026-08-20: "رفعت الملف ولم تظهر أي رسالة" رغم نجاح الدمج فعليًا).
      if (mounted) {
        final hasMissingReason = mergeResult.missingReasonCount > 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: hasMissingReason ? Colors.orange.shade800 : null,
            content: Text(
              'تم الدمج: ${mergeResult.matchedCount} حالة مطابَقة'
              '${mergeResult.unmatchedCount > 0 ? '، ${mergeResult.unmatchedCount} غير مطابَقة' : ''}'
              '${hasMissingReason ? '\nتنبيه: ${mergeResult.missingReasonCount} حالة اختار فيها المرشد "لم يتم التنفيذ" بلا تحديد السبب - يُرجى إعادتها له لتحديد السبب' : ''}',
            ),
            duration: Duration(seconds: hasMissingReason ? 10 : 6),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء معالجة الملف: $e';
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء معالجة الملف: $e'), duration: const Duration(seconds: 8)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'لوحة المنسّق - ${widget.department} (${widget.shatr})',
      showBackButton: false,
      navItems: buildCoordinatorNavItems(
        context,
        current: 'dashboard',
        shatr: widget.shatr,
        department: widget.department,
        onDeleteAdd: _openDeleteAddSection,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchDepartmentTickets(
          shatr: widget.shatr,
          department: widget.department,
        ),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? [];
          return _buildHub(tickets);
        },
      ),
    );
  }

  /// الصفحة الرئيسية - مطابقة لصفحة الإدارة بالحرف (سليمان 2026-08-09:
  /// "الأصل والمميّز صفحة الإدارة، عدّل صفحة المنسّقين"): إحصائيات + رسم
  /// بياني فقط بالجسم، بلا أي أيقونات/بطاقات وصول - كل الوجهات (الحذف
  /// والإضافة، الإرشاد، حالات الظروف الخاصة، الدعم النفسي، التقارير) صارت
  /// بشريط التنقّل العلوي حصرًا (`coordinator_nav.dart`)، تمامًا بنفس فلسفة
  /// admin_workspace_screen.dart.
  Widget _buildHub(List<Map<String, dynamic>> tickets) {
    final reportData = ReportDataService.build(tickets, roster: _roster);
    final rate = (reportData.overall.completionRate * 100).toStringAsFixed(0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PortalStatCard(
                  icon: Icons.folder_shared_outlined,
                  value: '${tickets.length}',
                  label: 'عدد حالات قسمي',
                  accentColor: AppColors.greenDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PortalStatCard(
                  icon: Icons.trending_up_rounded,
                  value: '$rate%',
                  label: 'نسبة الإنجاز',
                  accentColor: AppColors.gold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FollowUpChart(
          data: reportData,
          showCollegePerformance: false,
        ),
        TicketActionStatsPanel(tickets: tickets),
      ],
    );
  }

  /// يفتح صفحة "الحذف والإضافة" (خطوات دورة العمل 1-4) كصفحة فرعية كاملة.
  void _openDeleteAddSection() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => PortalScaffold(
          title: 'الحذف والإضافة - ${widget.department} (${widget.shatr})',
          showBackButton: true,
          navItems: buildCoordinatorNavItems(
            routeContext,
            current: 'delete-add',
            shatr: widget.shatr,
            department: widget.department,
          ),
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirestoreTicketService.watchDepartmentTickets(
              shatr: widget.shatr,
              department: widget.department,
            ),
            builder: (context, snapshot) {
              final tickets = snapshot.data ?? [];
              return _buildHome(tickets);
            },
          ),
        ),
      ),
    );
  }

  /// إطار موحَّد لكل صفحة فرعية (تُفتَح من إحدى الأيقونات) - يُبقي نفس عرض
  /// المحتوى الأقصى المستخدَم سابقًا للتبويبات (460) حتى لا تتمدد
  /// النصوص/الأزرار بعرض غير مريح على الشاشات الواسعة.
  Widget _tabBody(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  /// يفتح صفحة فرعية كاملة (بزر رجوع وشريط تنقّل علوي كامل) لأحد أقسام
  /// الصفحة السابقة (كانت تبويبات نصية) - نفس المحتوى والمنطق بالضبط، فقط
  /// الوصول إليه صار عبر أيقونة من الصفحة الرئيسية بدل تبويب (بطلب سليمان
  /// 2026-08-09). كل صفحة فرعية تراقب بياناتها الحيّة بنفسها حتى تبقى محدَّثة
  /// أثناء فتحها.
  void _openSection(String title, Widget Function(List<Map<String, dynamic>> tickets) contentBuilder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => PortalScaffold(
          title: title,
          showBackButton: true,
          navItems: buildCoordinatorNavItems(
            routeContext,
            current: 'dashboard',
            shatr: widget.shatr,
            department: widget.department,
          ),
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirestoreTicketService.watchDepartmentTickets(
              shatr: widget.shatr,
              department: widget.department,
            ),
            builder: (context, snapshot) {
              final tickets = snapshot.data ?? [];
              return _tabBody([contentBuilder(tickets)]);
            },
          ),
        ),
      ),
    );
  }

  /// الصفحة الرئيسية - إعادة تصميم كاملة (2026-08-09 بطلب سليمان صراحةً:
  /// "طريقة التصميم والعرض صعبة عليّ أنا اللي أبني الموقع معك، فما بالك
  /// بالمنسّق"): دورة العمل الكاملة (تنزيل مرشدين -> رفع + تثبيت مرحلة
  /// المرشدين -> تنزيل مرحلتي -> تثبيت مرحلتي لمنسّق الكلية) تظهر الآن
  /// **مباشرة بالصفحة الرئيسية** كخطوات مرقَّمة واضحة بدل تبويب مخفي باسم
  /// غامض "مسار التصعيد" - بلا أي حذف لأي وظيفة، فقط توضيح الترتيب والتسمية.
  /// كل خطوة بطاقة `Card` مرقَّمة، بلا أي `Container`/حواف مدوّرة مخصَّصة.
  Widget _buildHome(List<Map<String, dynamic>> tickets) {
    final reportData = ReportDataService.build(tickets, roster: _roster);
    final rate = (reportData.overall.completionRate * 100).toStringAsFixed(0);
    final hasDisabilityCases = DisabilityFileService.filterDisabilityTickets(tickets).isNotEmpty;

    return StreamBuilder<List<StageSnapshot>>(
      stream: StageSnapshotService.watchSnapshots(shatr: widget.shatr, department: widget.department),
      builder: (context, snapshot) {
        final snapshots = snapshot.data ?? [];
        final stage1Frozen = snapshots.any((s) => s.stage == 1);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PortalStatCard(
                      icon: Icons.folder_shared_outlined,
                      value: '${tickets.length}',
                      label: 'عدد حالات قسمي',
                      accentColor: AppColors.greenDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PortalStatCard(
                      icon: Icons.trending_up_rounded,
                      value: '$rate%',
                      label: 'نسبة الإنجاز',
                      accentColor: AppColors.gold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _stepCard(
              step: 1,
              title: 'تنزيل ملف قسمي',
              description: 'ملف مضغوط بداخله ملف Excel منفصل لكل مرشد أكاديمي - أرسله لكل مرشد بطريقتك.',
              child: ElevatedButton.icon(
                onPressed: (tickets.isEmpty || _isDownloading) ? null : () => _download(tickets),
                icon: _isDownloading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download),
                label: const Text('تنزيل ملف قسمي'),
              ),
            ),
            const SizedBox(height: 14),
            _stepCard(
              step: 2,
              title: 'رفع ملفات المرشدين وتثبيت مرحلتهم',
              description: 'بعد استلام كل ملفات المرشدين (لا ترفع إلا بعد استلامها كاملة - ملف أي مرشد متأخر يُرفع كما هو فارغًا)، ارفعها هنا ثم ثبّت المرحلة.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _pickAndUploadProcessedFile,
                    icon: _isUploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file),
                    label: Text(_isUploading ? 'جارٍ الرفع...' : 'رفع ملفات المرشدين المعالَجة'),
                  ),
                  if (hasDisabilityCases) ...[
                    const SizedBox(height: 8),
                    _buildDisabilitySection(tickets),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
                  ],
                  if (_lastResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'تم الدمج - مطابَقة: ${_lastResult!.matchedCount}'
                      '${_lastResult!.unmatchedCount > 0 ? '، غير مطابَقة: ${_lastResult!.unmatchedCount}' : ''}',
                      style: TextStyle(color: Colors.green.shade800, fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: (tickets.isEmpty || _isFreezingStage1) ? null : () => _confirmFreezeStage1(tickets),
                    icon: _isFreezingStage1
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(stage1Frozen ? Icons.check_circle : Icons.flag_outlined),
                    label: Text(stage1Frozen ? 'مرحلة المرشدين مثبَّتة ✓ (اضغط لإعادة التثبيت)' : 'تثبيت مرحلة المرشدين'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _stepCard(
              step: 3,
              title: 'تنزيل ملفي (بعد تثبيت مرحلة المرشدين)',
              description: 'ملف مدمج بكل حالات القسم لمعالجة ما تعذّر على المرشدين حلّه أنت شخصيًا.',
              enabled: stage1Frozen,
              disabledHint: 'ثبّت مرحلة المرشدين أولًا (الخطوة 2) قبل تنزيل هذا الملف.',
              child: ElevatedButton.icon(
                onPressed: (!stage1Frozen || tickets.isEmpty || _isDownloadingStage2) ? null : () => _downloadStage2(tickets),
                icon: _isDownloadingStage2
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download),
                label: const Text('تنزيل الملف المدمج لمرحلتي'),
              ),
            ),
            const SizedBox(height: 14),
            _stepCard(
              step: 4,
              title: 'تثبيت مرحلتي وإرسالها لمنسّق الكلية',
              description: 'بعد ما تحل ما تقدر عليه وترفعه بنفس زر "رفع ملفات المرشدين" أعلاه، ثبّت مرحلتك هنا لترسلها رسميًا لمنسّق الكلية.',
              enabled: stage1Frozen,
              disabledHint: 'ثبّت مرحلة المرشدين أولًا (الخطوة 2).',
              child: OutlinedButton.icon(
                onPressed: (!stage1Frozen || tickets.isEmpty || _isFreezingStage2) ? null : () => _confirmFreezeStage2(tickets),
                icon: _isFreezingStage2
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.flag_circle_outlined),
                label: const Text('تثبيت مرحلتي'),
              ),
            ),
            const SizedBox(height: 24),
            FollowUpChart(
              data: reportData,
              showCollegePerformance: false,
            ),
          ],
        );
      },
    );
  }

  /// بطاقة خطوة مرقَّمة موحَّدة لكل مراحل دورة العمل - `Card` قياسي بلا أي
  /// `Container`/حواف مدوّرة مخصَّصة (بديل آمن مؤكَّد على جهاز سليمان). لو
  /// `enabled` false تظهر معطَّلة بصريًا مع سبب واضح بدل إخفائها بالكامل.
  Widget _stepCard({
    required int step,
    required String title,
    required String description,
    required Widget child,
    bool enabled = true,
    String? disabledHint,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.greenDark,
                    foregroundColor: Colors.white,
                    child: Text('$step', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(description, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              IgnorePointer(ignoring: !enabled, child: child),
              if (!enabled && disabledHint != null) ...[
                const SizedBox(height: 8),
                Text(disabledHint, style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// لوحة "متابعة العمل" الثابتة أسفل شبكة الأيقونات مباشرة (بطلب سليمان
  /// 2026-08-09: "والفراغ المتبقي متابعة العمل اللي فيها رسم بياني") - نفس
  /// `FollowUpChart` المستخدَم داخل صفحة "متابعة الإنجاز" (بلا شريط
  /// طباعة/تصدير هنا، فتلك تبقى داخل أيقونتها كما هي) لكن معروضة دائمًا هنا
  /// بلا حاجة لفتح صفحة منفصلة.
  Widget _buildFollowUpChartPanel(List<Map<String, dynamic>> tickets) {
    final reportData = ReportDataService.build(tickets, roster: _roster);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold, width: 1.4),
        borderRadius: BorderRadius.circular(16),
        color: AppColors.gold.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined, color: AppColors.greenDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'متابعة العمل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'رسم بياني يرتّب مرشدي قسمك حسب نسبة الإنجاز، لمتابعة سير العمل من هنا مباشرة.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 10),
          FollowUpChart(data: reportData, showCollegePerformance: false),
        ],
      ),
    );
  }

  /// تبويب "الرفع والتنزيل": كل ما يخص تبادل ملفات Excel بين المنسّق
  /// والمرشدين/أمين القسم - تنزيل ملف القسم، رفع الملفات المعالجة، تنزيل
  /// ملف ذوي الإعاقة (إن وُجد)، وأخيرًا تفريغ حالة القسم (إجراء نادر ومقصود
  /// لذلك وُضع منفصلاً بالأسفل بلون تحذيري).
  Widget _buildUploadDownloadTab(List<Map<String, dynamic>> tickets) {
    return _tabBody([
      _buildActionExplainer(
        icon: Icons.download,
        title: 'تنزيل ملف قسمي',
        description:
            'ينزّل ملفًا مضغوطًا بداخله ملف Excel منفصل لكل مرشد أكاديمي في قسمك، لإرساله له ليعالج حالاته.',
        button: ElevatedButton.icon(
          onPressed: (tickets.isEmpty || _isDownloading) ? null : () => _download(tickets),
          icon: _isDownloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download),
          label: const Text('تنزيل ملف قسمي'),
        ),
      ),
      const SizedBox(height: 16),
      _buildActionExplainer(
        icon: Icons.upload_file,
        title: 'رفع الملفات المعالجة',
        description:
            'بعد أن يعالج المرشدون ملفاتهم ويعيدوها لك، ارفعها هنا (يمكن اختيار أكثر من ملف دفعة واحدة) ليتم تحديث حالة الطلاب تلقائيًا.',
        button: ElevatedButton.icon(
          onPressed: _isUploading ? null : _pickAndUploadProcessedFile,
          icon: _isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.upload_file),
          label: Text(_isUploading ? 'جارٍ الرفع...' : 'رفع الملفات المعالجة'),
        ),
      ),
      if (DisabilityFileService.filterDisabilityTickets(tickets).isNotEmpty) ...[
        const SizedBox(height: 16),
        _buildActionExplainer(
          icon: Icons.accessible_outlined,
          title: 'تنزيل حالات ذوي الإعاقة',
          description:
              'ينزّل ملف Excel واحدًا بكل حالات ذوي الإعاقة في قسمك، لإرساله لأمين القسم ثم استقبال عودته عبر زر "رفع الملفات المعالجة" أعلاه.',
          button: _buildDisabilitySection(tickets),
        ),
      ],
      if (_errorMessage != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade800)),
        ),
      ],
      if (_lastResult != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تم الدمج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('عدد الصفوف المُطابقة: ${_lastResult!.matchedCount}'),
              if (_lastResult!.unmatchedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'صفوف لم تُطابق: ${_lastResult!.unmatchedCount}',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 28),
      const Divider(),
      const SizedBox(height: 8),
      _buildActionExplainer(
        icon: Icons.restart_alt,
        title: 'تفريغ حالة القسم',
        description:
            'إجراء نادر: يمسح حالة الإنجاز والملاحظات لكل حالات قسمك (تراجع عن آخر رفع)، مع بقاء بيانات الطلاب الأصلية كما هي.',
        danger: true,
        button: OutlinedButton.icon(
          onPressed: (tickets.isEmpty || _isResetting) ? null : _confirmResetStatus,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade300),
          ),
          icon: _isResetting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red.shade700),
                )
              : const Icon(Icons.restart_alt),
          label: const Text('تفريغ حالة القسم'),
        ),
      ),
    ]);
  }

  /// إطار موحَّد لكل زر رفع/تنزيل: أيقونة + عنوان + شرح مبسَّط بسطر واحد
  /// (بطلب سليمان: شرح بلغة بسيطة بلا مصطلحات تقنية لكل زر)، ثم الزر نفسه.
  Widget _buildActionExplainer({
    required IconData icon,
    required String title,
    required String description,
    required Widget button,
    bool danger = false,
  }) {
    final accent = danger ? Colors.red.shade700 : AppColors.greenDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: danger ? Colors.red.shade200 : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
        color: danger ? Colors.red.shade50.withValues(alpha: 0.4) : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5)),
          const SizedBox(height: 12),
          button,
        ],
      ),
    );
  }

  /// تبويب "متابعة الإنجاز": نفس قسم المتابعة السابق بلا أي تغيير وظيفي.
  Widget _buildFollowUpTab(List<Map<String, dynamic>> tickets) {
    return _tabBody([_buildFollowUpSection(tickets)]);
  }

  /// تبويب "مسار التصعيد": نفس قسم التصعيد السابق بلا أي تغيير وظيفي.
  Widget _buildEscalationTab(List<Map<String, dynamic>> tickets) {
    return _tabBody([_buildEscalationSection(tickets)]);
  }

  /// زر تنزيل ملف "ذوي الإعاقة" - بنفس تصميم زرّي "تنزيل ملف قسمي" و"رفع
  /// الملفات المعالجة" أعلاه تمامًا (لا تصميم مختلف)، حتى تبقى هوية البوابة
  /// موحّدة. يبني ملفًا واحدًا يضم كل حالات ذوي الإعاقة في هذا القسم/الشطر،
  /// يرسله المنسّق لأمين القسم بنفس طريقته الخاصة، ثم يستقبل عودته عبر نفس
  /// زر "رفع الملفات المعالجة" أعلاه. لا يظهر إطلاقًا إن لم توجد أي حالة
  /// إعاقة فعلية (الشرط في الطرف المستدعي)، بدل إظهاره معطَّلاً باهتًا.
  Widget _buildDisabilitySection(List<Map<String, dynamic>> tickets) {
    return ElevatedButton.icon(
      onPressed: _isDownloadingDisabilityFile ? null : () => _downloadDisabilityFile(tickets),
      icon: _isDownloadingDisabilityFile
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.accessible_outlined),
      label: const Text('تنزيل حالات ذوي الإعاقة'),
    );
  }

  /// تقرير متابعة إنجاز خاص بقسم/شطر هذا المنسّق فقط - يرى فيه ترتيب مرشدي
  /// قسمه من الأقل إنجازًا للأكمل وقائمة الحالات المتبقية، دون أي وصول لأي
  /// قسم آخر أو تقرير عام (البيانات مصدرها stream مقيّد ببيانات قسمه أصلًا).
  Widget _buildFollowUpSection(List<Map<String, dynamic>> tickets) {
    final enabled = tickets.isNotEmpty;
    final followUpData = ReportDataService.build(tickets, roster: _roster);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold, width: 1.4),
        borderRadius: BorderRadius.circular(16),
        color: AppColors.gold.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.greenDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'متابعة إنجاز قسمي',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'يرتّب مرشدي قسمك حسب نسبة الإنجاز ويُظهر كل الحالات المتبقية، لمتابعة سير العمل دون الحاجة لفتح الملف يدويًا.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: (!enabled || _isFollowUpPrinting) ? null : () => _printFollowUp(tickets),
                icon: _isFollowUpPrinting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: const Text('طباعة'),
              ),
              OutlinedButton.icon(
                onPressed: (!enabled || _isFollowUpExportingExcel) ? null : () => _exportFollowUpExcel(tickets),
                icon: _isFollowUpExportingExcel
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_chart_outlined),
                label: const Text('تنزيل Excel'),
              ),
              ElevatedButton.icon(
                onPressed: (!enabled || _isFollowUpExportingPdf) ? null : () => _exportFollowUpPdf(tickets),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                icon: _isFollowUpExportingPdf
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('تنزيل PDF'),
              ),
            ],
          ),
          FollowUpChart(data: followUpData, showCollegePerformance: false),
        ],
      ),
    );
  }

  /// تذكير بصري فقط بمواعيد دورة الحذف والإضافة (بلا أي إنفاذ أو قفل فعلي -
  /// طالما البوابة تحت التجربة) - أحمر عريض ثابت أعلى الصفحة.
  Widget _buildDeadlineReminder() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تذكير بالمواعيد: يجب رفع ملفات المرشدين للمنسّق قبل نهاية دوام كل '
              'يوم (الأحد/الاثنين/الثلاثاء)، ومعالجة المنسّق لحالات "لم يتم" '
              'خلال اليوم التالي مباشرة قبل تصعيدها لمنسّق الكلية.',
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// قسم مسار التصعيد: زر تجميد مرحلة المرشدين، ثم (بعد تجميدها) مرحلة
  /// المنسّق (تنزيل الملف المدمج الكامل + تجميد)، مع عرض آخر تقرير مجمَّد
  /// لكل مرحلة.
  Widget _buildEscalationSection(List<Map<String, dynamic>> tickets) {
    return StreamBuilder<List<StageSnapshot>>(
      stream: StageSnapshotService.watchSnapshots(
        shatr: widget.shatr,
        department: widget.department,
      ),
      builder: (context, snapshot) {
        final snapshots = snapshot.data ?? [];
        final stage1 = snapshots.where((s) => s.stage == 1).toList();
        final stage2 = snapshots.where((s) => s.stage == 2).toList();
        final stage1Frozen = stage1.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.greenDark, width: 1.4),
            borderRadius: BorderRadius.circular(16),
            color: AppColors.greenDark.withValues(alpha: 0.04),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up, color: AppColors.greenDark),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'مسار التصعيد',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: (tickets.isEmpty || _isFreezingStage1)
                    ? null
                    : () => _confirmFreezeStage1(tickets),
                icon: _isFreezingStage1
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.flag_outlined),
                label: const Text('تثبيت تقرير مرحلة المرشدين'),
              ),
              if (stage1.isNotEmpty)
                StageProgressChart(title: 'آخر تقرير مجمَّد - مرحلة المرشدين', snapshot: stage1.first),
              const SizedBox(height: 14),
              if (!stage1Frozen)
                Text(
                  'يلزم تجميد مرحلة المرشدين أولًا قبل تنزيل الملف المدمج لمرحلتك.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: (tickets.isEmpty || _isDownloadingStage2)
                      ? null
                      : () => _downloadStage2(tickets),
                  icon: _isDownloadingStage2
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download),
                  label: const Text('تنزيل الملف المدمج لمرحلتي (كل حالات القسم)'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: (tickets.isEmpty || _isFreezingStage2)
                      ? null
                      : () => _confirmFreezeStage2(tickets),
                  icon: _isFreezingStage2
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.flag_circle_outlined),
                  label: const Text('تثبيت تقرير مرحلتي'),
                ),
                if (stage2.isNotEmpty)
                  StageProgressChart(
                    title: 'آخر تقرير مجمَّد - مرحلتي',
                    snapshot: stage2.first,
                    showDelta: true,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
