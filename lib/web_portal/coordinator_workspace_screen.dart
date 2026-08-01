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
import '../services/stage_snapshot_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'change_password_dialog.dart';
import 'follow_up_chart.dart';
import 'hardship_cases_coordinator_screen.dart';
import 'portal_footer.dart';
import 'portal_operations_guide_page.dart';
import 'public_landing_screen.dart';
import 'round_icon_button.dart';
import 'stage_progress_chart.dart';
import 'support_cases_coordinator_screen.dart';

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
      setState(() => _isUploading = false);
      return;
    }

    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        final Uint8List bytes = file.bytes!;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(bytes));
      }

      final mergeResult = await FirestoreTicketService.mergeProcessedRows(
        allRows,
        shatr: widget.shatr,
        department: widget.department,
      );

      setState(() {
        _lastResult = mergeResult;
        _isUploading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء معالجة الملف: $e';
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.department} - ${widget.shatr}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'الصفحة الرئيسية للموقع',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.volunteer_activism_outlined),
            tooltip: 'حالات الظروف الخاصة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HardshipCasesCoordinatorScreen(
                  shatr: widget.shatr,
                  department: widget.department,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: 'حالات الدعم النفسي والاجتماعي',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SupportCasesCoordinatorScreen(
                  shatr: widget.shatr,
                  department: widget.department,
                ),
              ),
            ),
          ),
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'المزيد',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PortalOperationsGuidePage()),
                ),
                child: const PortalMenuRow(icon: Icons.menu_book_outlined, label: 'دليل تشغيل البوابة'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: () => showChangePasswordDialog(context),
                child: const PortalMenuRow(icon: Icons.lock_outline, label: 'تغيير كلمة المرور'),
              ),
              PopupMenuItem(
                value: () => FirebaseAuth.instance.signOut(),
                child: PortalMenuRow(icon: Icons.logout, label: 'تسجيل خروج', color: Colors.red.shade700),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const PortalFooterBar(),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchDepartmentTickets(
          shatr: widget.shatr,
          department: widget.department,
        ),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDeadlineReminder(),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HardshipCasesCoordinatorScreen(
                            shatr: widget.shatr,
                            department: widget.department,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.volunteer_activism_outlined),
                      label: const Text(
                        'تسجيل حالات الظروف الخاصة',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SupportCasesCoordinatorScreen(
                            shatr: widget.shatr,
                            department: widget.department,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.greenDark,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.favorite_border),
                      label: const Text(
                        'تسجيل حالات الدعم النفسي والاجتماعي',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.folder_shared_outlined,
                                size: 40, color: AppColors.green),
                            const SizedBox(height: 8),
                            Text(
                              'عدد الحالات الحالية: ${tickets.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildFollowUpSection(tickets),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (tickets.isEmpty || _isDownloading)
                          ? null
                          : () => _download(tickets),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: const Text('تنزيل ملف قسمي'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _pickAndUploadProcessedFile,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        _isUploading ? 'جارٍ الرفع...' : 'رفع الملفات المعالجة',
                      ),
                    ),
                    if (DisabilityFileService.filterDisabilityTickets(tickets).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDisabilitySection(tickets),
                    ],
                    const SizedBox(height: 20),
                    _buildEscalationSection(tickets),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: (tickets.isEmpty || _isResetting)
                          ? null
                          : _confirmResetStatus,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                      icon: _isResetting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.red.shade700,
                              ),
                            )
                          : const Icon(Icons.restart_alt),
                      label: const Text('تفريغ حالة القسم'),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    ],
                    if (_lastResult != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'تم الدمج',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'عدد الصفوف المُطابقة: ${_lastResult!.matchedCount}',
                            ),
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
          FollowUpChart(data: followUpData),
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
