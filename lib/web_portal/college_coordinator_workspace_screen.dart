import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/escalation_file_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/processed_file_parser_service.dart';
import '../services/report_data_service.dart';
import '../services/stage_snapshot_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'change_password_dialog.dart';
import 'follow_up_chart.dart';
import 'portal_header.dart';
import 'public_landing_screen.dart';
import 'stage_progress_chart.dart';

/// شاشة منسّق/ة الكلية (المستوى الثالث والأخير في مسار التصعيد: مرشد ->
/// منسّق قسم -> منسّق كلية) - يرى كل أقسام شطره مجتمعة (لا قسمًا واحدًا كما
/// في شاشة المنسّق العادية)، ويعالج ما استعصى حتى على منسّقي الأقسام.
/// بلا سقف زمني (مرحلته مفتوحة، بخلاف مرحلتَي المرشدين والمنسّق).
class CollegeCoordinatorWorkspaceScreen extends StatelessWidget {
  final String uid;

  const CollegeCoordinatorWorkspaceScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('college_coordinator_accounts')
          .doc(uid)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final shatr = snapshot.data!.data()?['shatr']?.toString() ?? '';
        if (shatr.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('تعذّر تحديد بيانات الحساب')),
          );
        }

        return _CollegeCoordinatorBody(shatr: shatr);
      },
    );
  }
}

class _CollegeCoordinatorBody extends StatefulWidget {
  final String shatr;

  const _CollegeCoordinatorBody({required this.shatr});

  @override
  State<_CollegeCoordinatorBody> createState() => _CollegeCoordinatorBodyState();
}

class _CollegeCoordinatorBodyState extends State<_CollegeCoordinatorBody> {
  bool _isDownloading = false;
  bool _isUploading = false;
  bool _isFreezing = false;
  MergeResult? _lastResult;
  String? _errorMessage;

  Future<void> _download(List<Map<String, dynamic>> tickets) async {
    setState(() => _isDownloading = true);
    try {
      final bytes = EscalationFileService.buildStage3File(tickets);
      downloadBytes(bytes, 'مرحلة_منسق_الكلية_${widget.shatr}.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل الملف بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء الملف: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
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

      final mergeResult = await FirestoreTicketService.mergeProcessedRowsForShatr(
        allRows,
        shatr: widget.shatr,
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

  Future<void> _confirmFreezeStage3(List<Map<String, dynamic>> tickets) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تثبيت تقرير مرحلة منسّق الكلية'),
        content: const Text(
          'سيُسجَّل تقرير ثابت بحالة كل الأقسام في هذا الشطر الآن، ولن يتغيّر '
          'لاحقًا حتى لو تغيّرت البيانات. تأكد أنك انتهيت من المعالجة قبل '
          'المتابعة. هل تريد المتابعة؟',
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

    setState(() => _isFreezing = true);
    try {
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      await StageSnapshotService.freezeStage3(
        shatr: widget.shatr,
        shatrTickets: tickets,
        generatedByEmail: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تثبيت تقرير مرحلة منسّق الكلية')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFreezing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'منسّق الكلية - ${widget.shatr}',
      showBackButton: false,
      navItems: [
        PortalNavItem(
          label: 'لوحة منسّق الكلية',
          icon: Icons.dashboard_outlined,
          selected: true,
          onTap: () {},
        ),
        PortalNavItem(
          label: 'الموقع العام',
          icon: Icons.public_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
          ),
        ),
      ],
      actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'تغيير كلمة المرور',
            onPressed: () => showChangePasswordDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل خروج',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
      ],
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchShatrTickets(shatr: widget.shatr),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.school_outlined, size: 40, color: AppColors.green),
                            const SizedBox(height: 8),
                            Text(
                              'عدد الحالات الحالية (كل الأقسام): ${tickets.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FollowUpChart(
                      data: ReportDataService.build(tickets),
                      tickets: tickets,
                      showDepartmentFilter: true,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (tickets.isEmpty || _isDownloading) ? null : () => _download(tickets),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download),
                      label: const Text('تنزيل ملف كل الأقسام المدمج'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
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
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (tickets.isEmpty || _isFreezing) ? null : () => _confirmFreezeStage3(tickets),
                      icon: _isFreezing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.flag_outlined),
                      label: const Text('تثبيت تقرير مرحلة منسّق الكلية'),
                    ),
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
                    const SizedBox(height: 20),
                    _buildStage3History(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStage3History() {
    return StreamBuilder<List<StageSnapshot>>(
      stream: StageSnapshotService.watchShatrSnapshots(widget.shatr),
      builder: (context, snapshot) {
        final snapshots = snapshot.data ?? [];
        if (snapshots.isEmpty) return const SizedBox.shrink();
        return StageProgressChart(
          title: 'آخر تقرير مجمَّد لمرحلة منسّق الكلية',
          snapshot: snapshots.first,
          showDelta: true,
        );
      },
    );
  }
}
