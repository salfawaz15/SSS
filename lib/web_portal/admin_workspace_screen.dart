import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/advisor_roster_entry.dart';
import '../services/advisor_roster_service.dart';
import '../services/advisor_zip_service.dart';
import '../services/app_update_service.dart';
import '../services/disability_file_service.dart';
import '../services/escalation_file_service.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/processed_file_parser_service.dart';
import '../services/report_data_service.dart';
import '../services/report_excel_service.dart';
import '../services/report_pdf_service.dart';
import '../services/stage_snapshot_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'admin_reports_screen.dart';
import 'advisor_roster_screen.dart';
import 'coordinators_contacts_screen.dart';
import 'portal_accounts.dart';
import 'portal_cards.dart';
import 'portal_header.dart';
import 'portal_operations_guide_page.dart';
import 'portal_sitemap_screen.dart';
import 'reset_user_password_screen.dart';
import 'round_icon_button.dart';
import 'stage_progress_chart.dart';
import 'ticket_action_stats_panel.dart';

/// شاشة الإدارة في بوابة الويب (كل الصلاحيات): رفع ملف Microsoft Forms،
/// لوحة متابعة تعرض حجم الإنجاز، تنزيل ملف أي قسم، والتقرير الشامل
/// (Excel/PDF/طباعة). لا علاقة لها بتطبيق الأندرويد.
class AdminWorkspaceScreen extends StatefulWidget {
  const AdminWorkspaceScreen({super.key});

  @override
  State<AdminWorkspaceScreen> createState() => _AdminWorkspaceScreenState();
}

class _AdminWorkspaceScreenState extends State<AdminWorkspaceScreen> {
  StreamSubscription<List<Map<String, dynamic>>>? _statsSubscription;
  final Set<String> _downloadingKeys = {};

  /// مُحمَّلة مرة واحدة عند فتح اللوحة - تُستخدم في لوحة متابعة الإنجاز حتى
  /// لا يظهر منسّق قسم كأن لديه حالات معلَّقة بعد أن تفرَّغ منها فعليًا.
  List<AdvisorRosterEntry> _roster = [];

  @override
  void initState() {
    super.initState();
    // ينشر ملخص إحصائيات علني (بلا بيانات فردية) في كل مرة تتغيّر فيها
    // بيانات التذاكر - يشمل تعديلات المنسّقين أيضًا لأن هذه اللوحة تشاهد
    // كل التذاكر لحظيًا. يُستخدم في الصفحة الرئيسية العامة قبل تسجيل الدخول.
    _statsSubscription = FirestoreTicketService.watchAllTickets().listen((tickets) {
      FirestoreTicketService.publishPublicStats(tickets);
    });
    AdvisorRosterService.loadAll().then((r) {
      if (mounted) setState(() => _roster = r);
    });
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }

  // رفع الملف الأساسي (طلبات الحذف والإضافة) انتقل إلى بطاقة مميَّزة بصفحة
  // "رفع ملفات" (upload_hub_screen.dart) - بطلب سليمان 2026-08-19.

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ البيانات'),
        content: const Text(
          'سيتم مسح كل الحالات المرفوعة حاليًا نهائيًا من البوابة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('تفريغ البيانات'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirestoreTicketService.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفريغ البيانات')),
        );
      }
    }
  }

  Future<void> _downloadDepartment(
    String key,
    List<Map<String, dynamic>> tickets,
  ) async {
    setState(() => _downloadingKeys.add(key));
    try {
      // ملف مضغوط بداخله ملف Excel منفصل محمي لكل مرشد أكاديمي، بدل ملف
      // واحد يخلط كل مرشدي القسم - يسهّل توزيع المنسّق للملفات ومعرفة
      // إنجاز كل مرشد. حالات منسّق القسم (حسب قائمة مرشدي القسم) تُوزَّع
      // تلقائيًا على بقية المرشدين خلال فترة الحذف والإضافة. نستخدم القائمة
      // المحمَّلة مسبقًا في initState بدل إعادة جلبها من Firestore عند كل
      // ضغطة - كان هذا الجلب المتكرر يُعلّق الزر لو تأخّرت الشبكة لحظة النقر.
      final zipBytes = AdvisorZipService.buildZip(tickets, roster: _roster);

      final parts = key.split('|');
      final shatrLabel = parts[0] == ExcelParserService.shatrMale ? 'male' : 'female';
      downloadBytes(zipBytes, '${parts.length > 1 ? parts[1] : 'قسم'}_$shatrLabel.zip');
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
      if (mounted) setState(() => _downloadingKeys.remove(key));
    }
  }

  /// نفس ملف ذوي الإعاقة المتاح للمنسّق من حسابه بالضبط (ملف Excel واحد
  /// بجميع حالات القسم) - متاح أيضًا من لوحة الإدارة مباشرة، حتى تستطيع
  /// الإدارة تنزيله وإرساله بنفسها لأمين القسم لو تأخر المنسّق أو غاب.
  Future<void> _downloadDisability(
    String key,
    List<Map<String, dynamic>> tickets,
  ) async {
    final disabilityKey = 'disability|$key';
    setState(() => _downloadingKeys.add(disabilityKey));
    try {
      final bytes = DisabilityFileService.buildFile(tickets);

      final parts = key.split('|');
      final shatrLabel = parts[0] == ExcelParserService.shatrMale ? 'male' : 'female';
      downloadBytes(bytes, '${parts.length > 1 ? parts[1] : 'قسم'}_${shatrLabel}_ذوي_الإعاقة.xlsx');
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
      if (mounted) setState(() => _downloadingKeys.remove(disabilityKey));
    }
  }

  /// نفس ملف "مرحلة المنسّق" (المرحلة 2: كل حالات القسم مدمجة بملف واحد)
  /// المتاح للمنسّق من حسابه بالضبط - متاح أيضًا من لوحة الإدارة مباشرة، جزء
  /// من الخطة البديلة الوقائية (سليمان 2026-08-13): قيام الإدارة بدور
  /// المنسّق كاملاً (تنزيل ورفع) بالتوازي مع استمرار عمل حساب المنسّق نفسه،
  /// حتى لا تتعطل دورة العمل الحرجة لو واجه أحد المنسّقين صعوبة باستخدام الموقع.
  Future<void> _downloadStage2OnBehalf(
    String key,
    List<Map<String, dynamic>> tickets,
  ) async {
    final stage2Key = 'stage2dl|$key';
    setState(() => _downloadingKeys.add(stage2Key));
    try {
      final bytes = EscalationFileService.buildStage2File(tickets);
      final parts = key.split('|');
      final shatrLabel = parts[0] == ExcelParserService.shatrMale ? 'male' : 'female';
      downloadBytes(bytes, '${parts.length > 1 ? parts[1] : 'قسم'}_${shatrLabel}_مرحلة_المنسق.xlsx');
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
      if (mounted) setState(() => _downloadingKeys.remove(stage2Key));
    }
  }

  /// يرفع ملفًا معالجًا (عائدًا من المرشدين/المنسّق) نيابةً عن منسّق قسم معيّن
  /// - نفس دالة `mergeProcessedRows` وحوار النتيجة المستخدَمين بالضبط بصفحة
  /// المنسّق، فقط بقسم/شطر يُحدَّدان صراحةً بدل قراءتهما من حساب المسجَّل
  /// دخوله. جزء من الخطة البديلة الوقائية (سليمان 2026-08-13).
  Future<void> _pickAndUploadProcessedFileOnBehalf(
    String shatr,
    String department,
  ) async {
    final key = 'upload|$shatr|$department';
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      // كان يعود بصمت بلا أي رسالة - يبدو للمستخدم وكأن الضغط لم يفعل شيئًا
      // (سليمان 2026-08-20).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اختيار أي ملف - حاول مرة أخرى.')),
        );
      }
      return;
    }

    setState(() => _downloadingKeys.add(key));
    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(file.bytes!));
      }

      final mergeResult = await FirestoreTicketService.mergeProcessedRows(
        allRows,
        shatr: shatr,
        department: department,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception(
          'انتهت مهلة الاتصال بالخادم (25 ثانية بلا استجابة) - تأكد من اتصال الإنترنت وحاول مرة أخرى',
        ),
      );

      if (mounted) {
        final hasMissingReason = mergeResult.missingReasonCount > 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: hasMissingReason ? Colors.orange.shade800 : null,
            content: Text(
              'تم الرفع نيابةً عن "$department - $shatr": ${mergeResult.matchedCount} '
              'حالة مطابَقة${mergeResult.unmatchedCount > 0 ? '، ${mergeResult.unmatchedCount} غير مطابَقة' : ''}'
              '${hasMissingReason ? '\nتنبيه: ${mergeResult.missingReasonCount} حالة اختار فيها المرشد "لم يتم التنفيذ" بلا تحديد السبب - يُرجى إعادتها له لتحديد السبب' : ''}',
            ),
            duration: Duration(seconds: hasMissingReason ? 10 : 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء معالجة الملف: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingKeys.remove(key));
    }
  }

  /// تجميد أي مرحلة نيابةً عن المنسّق/منسّق الكلية - مهم لو تأخّر أو غاب،
  /// فلا يبقى تقدّم القسم/الشطر موقوفًا بانتظاره. نفس دوال StageSnapshotService
  /// المستخدَمة في شاشتَي المنسّق ومنسّق الكلية بالضبط.
  Future<void> _confirmFreezeOnBehalf({
    required String loadingKey,
    required String title,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'سيتم حفظ صورة نهائية ثابتة من نسبة الإنجاز الحالية باسم إدارة الوحدة '
          '(بدل صاحب الحساب) - تُستخدم عادةً فقط عند تأخّر صاحب الحساب عن '
          'إنهاء مرحلته بنفسه. هذا التقرير لن يتغيّر لاحقًا حتى لو تغيّرت '
          'البيانات. هل تريد المتابعة؟',
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

    setState(() => _downloadingKeys.add(loadingKey));
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التقرير الثابت بنجاح')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingKeys.remove(loadingKey));
    }
  }

  Future<void> _confirmResetDepartment(String shatr, String department) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ حالة القسم'),
        content: Text(
          'سيتم مسح حالة الإنجاز والملاحظات لكل حالات "$department - $shatr" '
          '(بيانات الطلاب الأصلية تبقى كما هي). هل تريد المتابعة؟',
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

    await FirestoreTicketService.resetDepartmentStatus(shatr: shatr, department: department);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفريغ حالة القسم بنجاح')),
      );
    }
  }

  Future<void> _exportExcel(List<Map<String, dynamic>> tickets) async {
    final data = ReportDataService.build(tickets, roster: _roster);
    final bytes = ReportExcelService.build(data);
    final cycleId = DateTime.now().toString().substring(0, 10);
    downloadBytes(bytes, 'تقرير_شامل_$cycleId.xlsx');
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> tickets) async {
    final data = ReportDataService.build(tickets, roster: _roster);
    final cycleId = DateTime.now().toString().substring(0, 10);
    final bytes = await ReportPdfService.build(
      data,
      title: 'التقرير الشامل',
      // يستبعد جدول تفصيل كل مرشد (قد يبلغ مئات الصفوف على مستوى الجامعة
      // كاملة) - هو السبب الأكبر لبطء بناء هذا التقرير تحديدًا لدرجة تجميد
      // المتصفح. لا يزال متاحًا كاملاً عبر "التقارير التفصيلية" لكل قسم/شطر.
      includeAdvisorDetail: false,
    );
    downloadBytes(bytes, 'تقرير_شامل_$cycleId.pdf');
  }

  Future<void> _printPdf(List<Map<String, dynamic>> tickets) async {
    final data = ReportDataService.build(tickets, roster: _roster);
    final bytes = await ReportPdfService.build(
      data,
      title: 'التقرير الشامل',
      // يستبعد جدول تفصيل كل مرشد (قد يبلغ مئات الصفوف على مستوى الجامعة
      // كاملة) - هو السبب الأكبر لبطء بناء هذا التقرير تحديدًا لدرجة تجميد
      // المتصفح. لا يزال متاحًا كاملاً عبر "التقارير التفصيلية" لكل قسم/شطر.
      includeAdvisorDetail: false,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    // بيانات منسّقي الأقسام حصرية على حساب المدير العام (salfawaz) فقط - لا
    // يملكها حساب الإدارة العادي (admin@) رغم أن كليهما "isFullAdmin".
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'الحذف والإضافة',
      showBackButton: false,
      navItems: buildAdminNavItems(context, current: 'delete-add'),
      floatingActionButton: _buildAndroidDownloadBadge(),
      actions: [
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
              if (isSuperAdmin) ...[
                PopupMenuItem(
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CoordinatorsContactsScreen()),
                  ),
                  child: const PortalMenuRow(icon: Icons.contact_mail_outlined, label: 'بيانات منسقي الأقسام'),
                ),
                PopupMenuItem(
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdvisorRosterScreen()),
                  ),
                  child: const PortalMenuRow(icon: Icons.groups_outlined, label: 'قائمة مرشدي القسم'),
                ),
                PopupMenuItem(
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ResetUserPasswordScreen()),
                  ),
                  child: const PortalMenuRow(icon: Icons.vpn_key_outlined, label: 'الحسابات وكلمات المرور'),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PortalSitemapScreen()),
                ),
                child: const PortalMenuRow(icon: Icons.map_outlined, label: 'خريطة صفحات الموقع'),
              ),
              // نُقلت هنا من صف أيقونات كبير بالصفحة الرئيسية (أُزيل بطلب
              // سليمان 2026-08-09 لتبسيط اللوحة) - الوظيفتان لا تزالان
              // متاحتين، فقط عبر قائمة "المزيد" بدل صف بطاقات ظاهر دائمًا.
              PopupMenuItem(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => StreamBuilder<List<Map<String, dynamic>>>(
                      stream: FirestoreTicketService.watchAllTickets(),
                      builder: (context, snapshot) {
                        final tickets = snapshot.data ?? [];
                        final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
                        return PortalScaffold(
                          title: 'تقارير متابعة الحذف والإضافة',
                          navItems: buildAdminNavItems(context, current: 'reports'),
                          body: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildReportSection(tickets),
                              const SizedBox(height: 24),
                              _buildStageReportsSection(groups),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                child: const PortalMenuRow(icon: Icons.assessment_outlined, label: 'تقارير متابعة الحذف والإضافة'),
              ),
              PopupMenuItem(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => StreamBuilder<List<Map<String, dynamic>>>(
                      stream: FirestoreTicketService.watchAllTickets(),
                      builder: (context, snapshot) {
                        final tickets = snapshot.data ?? [];
                        final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
                        return PortalScaffold(
                          title: 'تنزيل ملفات الحالات',
                          navItems: buildAdminNavItems(context, current: 'downloads'),
                          body: _buildDownloadsList(groups, snapshot.hasData),
                        );
                      },
                    ),
                  ),
                ),
                child: const PortalMenuRow(icon: Icons.folder_zip_outlined, label: 'تنزيل ملفات الحالات'),
              ),
              PopupMenuItem(
                value: _confirmClearData,
                child: PortalMenuRow(icon: Icons.delete_sweep_outlined, label: 'تفريغ البيانات', color: Colors.red.shade700),
              ),
            ],
          ),
      ],
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchAllTickets(),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TicketActionStatsPanel(tickets: tickets),
            ],
          );
        },
      ),
    );
  }

  /// قائمة تنزيل ملفات كل قسم/شطر - محتوى صفحة "تنزيل ملفات الحالات"
  /// المستقلة (كانت سابقًا مطويّة داخل الصفحة الرئيسية للوحة الإدارة).
  Widget _buildDownloadsList(Map<String, List<Map<String, dynamic>>> groups, bool hasData) {
    if (!hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups.isEmpty) {
      return Center(
        child: Text('لا توجد بيانات مرفوعة بعد', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: groups.entries.map((e) {
        final key = e.key;
        final parts = key.split('|');
        final department = parts.length > 1 ? parts[1] : '';
        final isDownloading = _downloadingKeys.contains(key);
        final isDownloadingDisability = _downloadingKeys.contains('disability|$key');
        final isDownloadingStage2 = _downloadingKeys.contains('stage2dl|$key');
        final isUploadingProcessed = _downloadingKeys.contains('upload|$key');
        final hasDisabilityCases = DisabilityFileService.filterDisabilityTickets(e.value).isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.green.withValues(alpha: 0.12),
              child: const Icon(Icons.apartment_outlined, color: AppColors.green),
            ),
            title: Text(department.isEmpty ? '(بدون قسم)' : department),
            subtitle: Text('${parts[0]} - عدد الحالات: ${e.value.length}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoundIconButton(
                  tooltip: 'تفريغ حالة هذا القسم',
                  color: Colors.red.shade700,
                  icon: Icons.restart_alt,
                  onPressed: () => _confirmResetDepartment(parts[0], department),
                ),
                RoundIconButton(
                  tooltip: 'تنزيل ملف ذوي الإعاقة لهذا القسم',
                  color: Colors.blue,
                  icon: Icons.accessible_outlined,
                  isLoading: isDownloadingDisability,
                  onPressed: (!hasDisabilityCases || isDownloadingDisability)
                      ? null
                      : () => _downloadDisability(key, e.value),
                ),
                RoundIconButton(
                  tooltip: 'تنزيل ملفات المرشدين لهذا القسم',
                  color: AppColors.green,
                  icon: Icons.download,
                  isLoading: isDownloading,
                  onPressed: isDownloading ? null : () => _downloadDepartment(key, e.value),
                ),
                RoundIconButton(
                  tooltip: 'تنزيل ملف مرحلة المنسّق لهذا القسم (نيابةً عن المنسّق)',
                  color: AppColors.gold,
                  icon: Icons.assignment_return_outlined,
                  isLoading: isDownloadingStage2,
                  onPressed: isDownloadingStage2 ? null : () => _downloadStage2OnBehalf(key, e.value),
                ),
                RoundIconButton(
                  tooltip: 'رفع ملف معالج لهذا القسم (نيابةً عن المنسّق)',
                  color: Colors.deepPurple,
                  icon: Icons.upload_file_outlined,
                  isLoading: isUploadingProcessed,
                  onPressed: isUploadingProcessed
                      ? null
                      : () => _pickAndUploadProcessedFileOnBehalf(parts[0], department),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// قسم "تقارير المراحل الثلاث" - يعرض لكل قسم آخر تقرير مجمَّد لمرحلة
  /// المرشدين ومرحلة المنسّق (مع زر تجميد نيابةً عن المنسّق لو تأخّر أو غاب)،
  /// وبطاقتَي شطر لمرحلة منسّقي الكلية.
  Widget _buildStageReportsSection(Map<String, List<Map<String, dynamic>>> groups) {
    final shatrs = [ExcelParserService.shatrMale, ExcelParserService.shatrFemale];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.timeline_outlined, color: AppColors.greenDark),
        title: const Text('تقارير المراحل الثلاث', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('تقدّم كل قسم عبر مراحل المرشدين، المنسّق، ومنسّق الكلية'),
        children: [
          ...groups.entries.map((e) {
            final parts = e.key.split('|');
            final shatr = parts[0];
            final department = parts.length > 1 ? parts[1] : '';
            return _buildDepartmentStageCard(shatr, department, e.value);
          }),
          const Divider(height: 1),
          ...shatrs.map((shatr) => _buildShatrStageCard(shatr, groups)),
        ],
      ),
    );
  }

  Widget _buildDepartmentStageCard(
    String shatr,
    String department,
    List<Map<String, dynamic>> tickets,
  ) {
    final stage1Key = 'freeze1|$shatr|$department';
    final stage2Key = 'freeze2|$shatr|$department';
    return ExpansionTile(
      title: Text('$department - $shatr', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StreamBuilder<List<StageSnapshot>>(
            stream: StageSnapshotService.watchSnapshots(shatr: shatr, department: department),
            builder: (context, snapshot) {
              final snapshots = snapshot.data ?? [];
              final stage1 = snapshots.where((s) => s.stage == 1).toList();
              final stage2 = snapshots.where((s) => s.stage == 2).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'يُستخدم فقط إذا لم يُنهِ المنسّق مرحلته بنفسه - يُنشئ تقريرًا نهائيًا ثابتًا لا يتغيّر لاحقًا.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        onPressed: (tickets.isEmpty || _downloadingKeys.contains(stage1Key))
                            ? null
                            : () => _confirmFreezeOnBehalf(
                                  loadingKey: stage1Key,
                                  title: 'تثبيت تقرير مرحلة المرشدين',
                                  action: () async {
                                    final roster = await AdvisorRosterService.loadAll();
                                    await StageSnapshotService.freezeStage1(
                                      shatr: shatr,
                                      department: department,
                                      tickets: tickets,
                                      roster: roster,
                                      generatedByEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                                    );
                                  },
                                ),
                        label: const Text('تثبيت تقرير مرحلة المرشدين'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.flag_circle_outlined, size: 16),
                        onPressed: (tickets.isEmpty || stage1.isEmpty || _downloadingKeys.contains(stage2Key))
                            ? null
                            : () => _confirmFreezeOnBehalf(
                                  loadingKey: stage2Key,
                                  title: 'تثبيت تقرير مرحلة المنسّق',
                                  action: () async {
                                    final roster = await AdvisorRosterService.loadAll();
                                    await StageSnapshotService.freezeStage2(
                                      shatr: shatr,
                                      department: department,
                                      tickets: tickets,
                                      roster: roster,
                                      generatedByEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                                    );
                                  },
                                ),
                        label: const Text('تثبيت تقرير مرحلة المنسّق'),
                      ),
                    ],
                  ),
                  if (stage1.isNotEmpty)
                    StageProgressChart(title: 'مرحلة المرشدين', snapshot: stage1.first),
                  if (stage2.isNotEmpty)
                    StageProgressChart(title: 'مرحلة المنسّق', snapshot: stage2.first, showDelta: true),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShatrStageCard(String shatr, Map<String, List<Map<String, dynamic>>> groups) {
    final shatrTickets = groups.entries
        .where((e) => e.key.startsWith('$shatr|'))
        .expand((e) => e.value)
        .toList();
    final stage3Key = 'freeze3|$shatr';

    return ExpansionTile(
      title: Text('منسّق الكلية - $shatr', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.greenDark)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StreamBuilder<List<StageSnapshot>>(
            stream: StageSnapshotService.watchShatrSnapshots(shatr),
            builder: (context, snapshot) {
              final snapshots = snapshot.data ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'يُستخدم فقط إذا لم يُنهِ منسّق الكلية عمله بنفسه - يُنشئ تقريرًا نهائيًا ثابتًا لا يتغيّر لاحقًا.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    onPressed: (shatrTickets.isEmpty || _downloadingKeys.contains(stage3Key))
                        ? null
                        : () => _confirmFreezeOnBehalf(
                              loadingKey: stage3Key,
                              title: 'تثبيت تقرير مرحلة منسّق الكلية',
                              action: () => StageSnapshotService.freezeStage3(
                                shatr: shatr,
                                shatrTickets: shatrTickets,
                                generatedByEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                              ),
                            ),
                    label: const Text('تثبيت تقرير مرحلة منسّق الكلية'),
                  ),
                  if (snapshots.isNotEmpty)
                    StageProgressChart(title: 'مرحلة منسّق الكلية', snapshot: snapshots.first, showDelta: true),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// مربع صغير عائم بأسفل الشاشة (لا شريط علوي بارز) لتحميل تطبيق الجوال
  /// (Android) - تظهر فقط بنسخة الموقع (لا معنى لها داخل التطبيق نفسه بعد
  /// تثبيته) وفقط بلوحة الإدارة. النقر على الأيقونة نفسها يبدأ التحميل
  /// مباشرة - بلا زر "تحميل" منفصل، بأسلوب مربعات التحميل بالمواقع الاحترافية.
  /// تقرأ رابط ورقم آخر نسخة منشورة حيًّا من نفس مصدر [AppUpdateService]
  /// المستخدَم للتحقق من التحديثات داخل التطبيق - فتختفي تلقائيًا لو لم يوجد
  /// رابط منشور بعد.
  Widget _buildAndroidDownloadBadge() {
    if (!kIsWeb) return const SizedBox.shrink();
    return FutureBuilder(
      future: AppUpdateService.getLatestRelease(),
      builder: (context, snapshot) {
        final apkUrl = snapshot.data?.apkUrl;
        if (apkUrl == null || apkUrl.isEmpty) return const SizedBox.shrink();
        final versionName = snapshot.data?.versionName;
        return Tooltip(
          message: 'تحميل تطبيق الجوال (Android)'
              '${versionName != null && versionName.isNotEmpty ? ' - الإصدار $versionName' : ''}',
          child: Material(
            color: AppColors.greenDark,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final directUrl = await AppUpdateService.resolveDirectDownloadUrl(apkUrl);
                launchUrl(Uri.parse(directUrl), mode: LaunchMode.externalApplication);
              },
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Icon(Icons.android, color: Colors.white, size: kPortalCardIconSizeLarge),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportSection(List<Map<String, dynamic>> tickets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            const Text(
              'التقارير',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.greenDark),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PortalActionCard(
          icon: Icons.summarize_outlined,
          title: 'التقرير الشامل السريع',
          subtitle: 'طباعة أو تنزيل تقرير فوري بكل بيانات البوابة',
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onTap: () => _showQuickReportSheet(tickets),
        ),
        const SizedBox(height: 14),
        PortalActionCard(
          icon: Icons.query_stats,
          title: 'التقارير التفصيلية',
          subtitle: 'تقرير كل قسم علمي، كل شطر، أو كل مرشد أكاديمي - ومتابعة الإنجاز',
          gradientColors: const [AppColors.greenDark, AppColors.green],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
          ),
        ),
      ],
    );
  }

  /// يفتح نافذة في منتصف الشاشة بأزرار التقرير الشامل السريع (طباعة/Excel/PDF).
  ///
  /// تصميم متعمَّد: لا يُغلق هذا الكود النافذة تلقائيًا أبدًا بعد نجاح العملية -
  /// النسخة السابقة كانت تستدعي `Navigator.of(context).pop()` من الصفحة نفسها
  /// (لا من النافذة) بعد انتهاء التنزيل، فلو كان المستخدم قد أغلق النافذة يدويًا
  /// قبل ذلك (بالنقر خارجها أثناء الانتظار)، كان هذا الاستدعاء المتأخر يُغلق
  /// الصفحة نفسها بدل النافذة (لأن مسار النافذة كان قد اختفى فعليًا، فينتقل
  /// pop() لأقرب مسار موجود وهو الصفحة). الحل: نتيجة العملية (نجاح/خطأ) تُعرض
  /// كنص داخل النافذة نفسها، والإغلاق حصرًا بضغط المستخدم على زر "إغلاق" عبر
  /// dialogContext الخاص بالنافذة - لا علاقة له بمسار الصفحة إطلاقًا. كذلك
  /// النافذة الآن لا يمكن إغلاقها بالنقر خارجها أثناء تنفيذ العملية.
  void _showQuickReportSheet(List<Map<String, dynamic>> tickets) {
    bool isBusy = false;
    String? resultMessage;
    bool resultIsError = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> startAction(Future<void> Function() action, String successMessage) async {
              if (isBusy) return;
              setDialogState(() {
                isBusy = true;
                resultMessage = null;
              });
              // يسمح للإطار التالي برسم مؤشر التحميل قبل بدء العمل الثقيل
              // (تنسيق تقرير PDF/Excel الكامل) الذي قد يجمّد الواجهة للحظات.
              await Future<void>.delayed(Duration.zero);
              try {
                await action();
                setDialogState(() {
                  isBusy = false;
                  resultMessage = successMessage;
                  resultIsError = false;
                });
              } catch (e) {
                setDialogState(() {
                  isBusy = false;
                  resultMessage = 'تعذّر إتمام العملية: $e';
                  resultIsError = true;
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'التقرير الشامل السريع',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBusy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => startAction(
                              () => _printPdf(tickets),
                              'تم فتح التقرير للطباعة',
                            ),
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: const Text('طباعة'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => startAction(
                              () => _exportExcel(tickets),
                              'تم تنزيل ملف Excel بنجاح',
                            ),
                            icon: const Icon(Icons.table_chart_outlined, size: 18),
                            label: const Text('تنزيل Excel'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => startAction(
                              () => _exportPdf(tickets),
                              'تم تنزيل ملف PDF بنجاح',
                            ),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('تنزيل PDF'),
                          ),
                        ],
                      ),
                    if (resultMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        resultMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: resultIsError ? Colors.red.shade700 : Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isBusy ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

