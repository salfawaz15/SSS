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
import 'follow_up_chart.dart';
import 'portal_cards.dart';
import 'portal_header.dart';
import 'public_landing_screen.dart';
import 'reports_hub_screen.dart';
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
        // كان الفحص السابق `!snapshot.hasData` فقط - لا يميّز "لا يزال يحمّل"
        // عن "فشل فعليًا" (مثال: PERMISSION_DENIED)، فيظهر دوّار تحميل بلا
        // نهاية بدل رسالة خطأ واضحة تكشف السبب الحقيقي (سليمان 2026-08-16،
        // لاحظه فعليًا بحساب منسّق كلية على الجوال بعد اختبار حي).
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

/// إعادة تصميم كاملة (بطلب سليمان 2026-08-09، تعميمًا لنفس مبدأ صفحة منسّق
/// القسم): شريط إحصائيات علوي بأرقام مستوى الكلية كما هو، ثم شبكة أيقونات
/// `PortalIconTileCard` (بدل التبويبات النصية الثلاث السابقة) لوجهتي "الرفع
/// والتنزيل" و"متابعة الحالات"، ثم لوحة "متابعة العمل" (`FollowUpChart` -
/// كانت التبويب الثالث "الأداء والتقارير") ثابتة أسفل الشبكة مباشرة بلا
/// حاجة لفتحها من وجهة منفصلة. لا حذف لأي وظيفة موجودة سابقًا.
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
      // كان يعود بصمت بلا أي رسالة - يبدو للمستخدم وكأن الضغط لم يفعل شيئًا
      // (سليمان 2026-08-20).
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
        throw Exception('تعذّرت قراءة محتوى الملف المختار (قد يكون فارغًا أو غير مدعوم).');
      }

      // مهلة 25 ثانية بدل انتظار بلا نهاية بلا أي رسالة (نفس إصلاح شاشة
      // منسّق القسم - سليمان 2026-08-20).
      final mergeResult = await FirestoreTicketService.mergeProcessedRowsForShatr(
        allRows,
        shatr: widget.shatr,
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
          label: 'الرئيسية',
          icon: Icons.public_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
          ),
        ),
        PortalNavItem(
          label: 'لوحة منسّق الكلية',
          icon: Icons.dashboard_outlined,
          selected: true,
          onTap: () {},
        ),
        PortalNavItem(
          label: 'تقارير',
          icon: Icons.assessment_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
          ),
        ),
      ],
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchShatrTickets(shatr: widget.shatr),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? [];
          final departmentsCount = tickets.map((t) => t['department']).toSet().length;
          final reportData = ReportDataService.build(tickets);
          final rate = (reportData.overall.completionRate * 100).toStringAsFixed(0);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatsBar(tickets.length, departmentsCount, rate),
                    const SizedBox(height: 20),
                    _buildIconGrid(),
                    const SizedBox(height: 24),
                    _buildPerformancePanel(tickets, reportData),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// يفتح صفحة فرعية كاملة (بزر رجوع وشريط تنقّل علوي) لأحد أقسام الصفحة
  /// السابقة (كانت تبويبات نصية) - نفس المحتوى والمنطق بالضبط، فقط الوصول
  /// إليه صار عبر أيقونة من الصفحة الرئيسية بدل تبويب (بطلب سليمان
  /// 2026-08-09، بنفس مبدأ صفحة منسّق القسم).
  void _openSection(String title, Widget Function(List<Map<String, dynamic>> tickets) contentBuilder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => PortalScaffold(
          title: title,
          showBackButton: true,
          navItems: [
            PortalNavItem(
              label: 'الرئيسية',
              icon: Icons.public_outlined,
              onTap: () => Navigator.of(routeContext).push(
                MaterialPageRoute(builder: (_) => const PublicLandingScreen()),
              ),
            ),
            PortalNavItem(
              label: 'لوحة منسّق الكلية',
              icon: Icons.dashboard_outlined,
              selected: true,
              onTap: () {},
            ),
            PortalNavItem(
              label: 'تقارير',
              icon: Icons.assessment_outlined,
              onTap: () => Navigator.of(routeContext).push(
                MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
              ),
            ),
          ],
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirestoreTicketService.watchShatrTickets(shatr: widget.shatr),
            builder: (context, snapshot) {
              final tickets = snapshot.data ?? [];
              return contentBuilder(tickets);
            },
          ),
        ),
      ),
    );
  }

  /// شبكة أيقونتين (`PortalIconTileCard`) تحلّان محل تبويبَي "الرفع والتنزيل"
  /// و"متابعة الحالات" السابقين - نفس الوظائف بالضبط خلف كل أيقونة.
  Widget _buildIconGrid() {
    final tiles = <({IconData icon, String title, Color background, Color foreground, VoidCallback onTap})>[
      (
        icon: Icons.swap_vert_rounded,
        title: 'الرفع والتنزيل',
        background: AppColors.greenDark,
        foreground: Colors.white,
        onTap: () => _openSection('الرفع والتنزيل', _buildUploadDownloadTab),
      ),
      (
        icon: Icons.flag_outlined,
        title: 'متابعة الحالات',
        background: AppColors.gold,
        foreground: Colors.white,
        onTap: () => _openSection('متابعة الحالات', _buildCaseTrackingTab),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 118,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, i) {
        final t = tiles[i];
        return PortalIconTileCard(
          icon: t.icon,
          title: t.title,
          background: t.background,
          foreground: t.foreground,
          onTap: t.onTap,
        );
      },
    );
  }

  /// لوحة "الأداء والتقارير" (كانت التبويب الثالث) - تُعرض الآن دائمًا أسفل
  /// شبكة الأيقونات مباشرة (بطلب سليمان 2026-08-09) بدل الحاجة لفتحها من
  /// تبويب/أيقونة منفصلة، بنفس محتواها ومنطقها بالضبط.
  Widget _buildPerformancePanel(List<Map<String, dynamic>> tickets, ReportData reportData) {
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
                  'الأداء والتقارير',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _sectionHint(
            icon: Icons.insights_outlined,
            text: 'رسم بياني تفاعلي يرتّب المرشدين ومنسّقي الأقسام ومنسّقي الكلية حسب نسبة إنجازهم، مع إمكانية الفلترة حسب القسم.',
          ),
          const SizedBox(height: 10),
          FollowUpChart(
            data: reportData,
            tickets: tickets,
            showDepartmentFilter: true,
          ),
        ],
      ),
    );
  }

  /// شريط إحصائيات مستوى الكلية أعلى الصفحة (بطلب سليمان 2026-08-08) - أرقام
  /// فعلية من نفس بيانات الشطر المعروضة أدناه، لا أرقام مفترَضة: عدد كل
  /// الحالات المجمَّعة من كل أقسام الشطر، عدد الأقسام الفعلية الظاهرة حاليًا،
  /// ونسبة الإنجاز العامة لكل مرشدي الشطر مجتمعين.
  Widget _buildStatsBar(int totalCases, int departmentsCount, String rate) {
    final tiles = [
      (label: 'إجمالي حالات الشطر', value: '$totalCases', icon: Icons.folder_copy_outlined, color: AppColors.greenDark),
      (label: 'عدد الأقسام', value: '$departmentsCount', icon: Icons.apartment_rounded, color: AppColors.gold),
      (label: 'نسبة الإنجاز العامة', value: '$rate%', icon: Icons.trending_up_rounded, color: AppColors.green),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        if (isNarrow) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                PortalStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accentColor: tiles[i].color),
                if (i < tiles.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                Expanded(
                  child: PortalStatCard(icon: tiles[i].icon, value: tiles[i].value, label: tiles[i].label, accentColor: tiles[i].color),
                ),
                if (i < tiles.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  /// تبويب "الرفع والتنزيل": تنزيل الملف المدمج لكل أقسام الشطر ثم رفعه بعد
  /// معالجته - نفس الوظيفتين الموجودتين سابقًا بلا أي تغيير في المنطق، فقط
  /// مع شرح سطر واحد فوق كل زر لتوضيح الغرض منه لمنسّق كلية جديد.
  Widget _buildUploadDownloadTab(List<Map<String, dynamic>> tickets) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHint(
                icon: Icons.download,
                text: 'يُنزّل ملف Excel واحد يضم كل الحالات المتصعّدة من كل أقسام هذا الشطر، لمعالجتها ثم رفعها لاحقًا.',
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 20),
              _sectionHint(
                icon: Icons.upload_file,
                text: 'بعد تعديل الملف الذي نزّلته أعلاه (بتحديث حالة كل طالب)، ارفعه هنا ليُحدَّث سجل كل حالة تلقائيًا.',
              ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }

  /// تبويب "متابعة الحالات": بطاقة عدد الحالات الحالية، تثبيت تقرير مرحلة
  /// منسّق الكلية (يُستخدم عند الانتهاء من معالجة ما استعصى)، وآخر تقرير
  /// مجمَّد سابقًا لهذه المرحلة - بلا أي تغيير في المنطق عن النسخة السابقة.
  Widget _buildCaseTrackingTab(List<Map<String, dynamic>> tickets) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 20),
              _sectionHint(
                icon: Icons.flag_outlined,
                text: 'بعد الانتهاء من معالجة كل ما تستطيع، ثبّت تقريرًا نهائيًا لحالة هذا الشطر - لا يتغيّر لاحقًا حتى لو تغيّرت البيانات.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (tickets.isEmpty || _isFreezing) ? null : () => _confirmFreezeStage3(tickets),
                icon: _isFreezing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.flag_outlined),
                label: const Text('تثبيت تقرير مرحلة منسّق الكلية'),
              ),
              const SizedBox(height: 20),
              _buildStage3History(),
            ],
          ),
        ),
      ),
    );
  }

  /// شرح مختصر (سطر واحد) فوق أي إجراء - بهوية بصرية موحّدة (أيقونة ذهبية +
  /// نص رمادي) حتى يفهم منسّق كلية جديد الغرض من كل زر دون تجربته أولاً.
  Widget _sectionHint({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.gold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4),
          ),
        ),
      ],
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
