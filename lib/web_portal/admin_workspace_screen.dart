import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/advisor_roster_entry.dart';
import '../services/advisor_roster_service.dart';
import '../services/advisor_zip_service.dart';
import '../services/disability_file_service.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/report_data_service.dart';
import '../services/report_excel_service.dart';
import '../services/report_pdf_service.dart';
import '../services/stage_snapshot_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'admin_reports_screen.dart';
import 'advisor_roster_screen.dart';
import 'change_password_dialog.dart';
import 'coordinators_contacts_screen.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'college_roster_admin_screen.dart';
import 'course_schedule_admin_screen.dart';
import 'follow_up_chart.dart';
import 'hardship_cases_admin_screen.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';
import 'portal_operations_guide_page.dart';
import 'portal_sitemap_screen.dart';
import 'reset_user_password_screen.dart';
import 'round_icon_button.dart';
import 'stage_progress_chart.dart';
import 'support_cases_admin_screen.dart';

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
  bool _isUploading = false;
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

  /// يسأل الأدمن أولًا: هل هذا أول رفع في دورة حذف وإضافة جديدة (يمسح كل
  /// شيء - بداية نظيفة)، أم رفعة يوم تالٍ من نفس الدورة (الاثنين/الثلاثاء -
  /// تصدير Microsoft Forms تراكمي، فيُضاف الجديد فقط بلا مسح أي شيء حتى لا
  /// يُفقَد عمل المرشدين/المنسّقين على حالات الأيام السابقة).
  Future<bool?> _confirmUploadMode() {
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

  Future<void> _pickAndUploadFile() async {
    final isNewCycle = await _confirmUploadMode();
    if (isNewCycle == null) return;

    setState(() => _isUploading = true);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      setState(() => _isUploading = false);
      return;
    }

    final Uint8List bytes = result.files.single.bytes!;
    final tickets = ExcelParserService.parseTickets(bytes);

    String message;
    if (isNewCycle) {
      await FirestoreTicketService.replaceAllTickets(tickets);
      message = 'تم رفع ${tickets.length} حالة بنجاح (دورة جديدة)';
    } else {
      final addedCount = await FirestoreTicketService.addNewTickets(tickets);
      message = 'تمت إضافة $addedCount حالة جديدة (من أصل ${tickets.length} في الملف - '
          'الباقي موجود مسبقًا وتم تجاهله حفاظًا على عمل المرشدين/المنسّقين)';
    }

    setState(() => _isUploading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

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
    final isSuperAdmin =
        FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail;

    return PortalScaffold(
      title: 'لوحة الإدارة',
      showBackButton: false,
      navItems: buildAdminNavItems(context, current: 'dashboard'),
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
              PopupMenuItem(
                value: () => showChangePasswordDialog(context),
                child: const PortalMenuRow(icon: Icons.lock_outline, label: 'تغيير كلمة المرور'),
              ),
              PopupMenuItem(
                value: _confirmClearData,
                child: PortalMenuRow(icon: Icons.delete_sweep_outlined, label: 'تفريغ البيانات', color: Colors.red.shade700),
              ),
              PopupMenuItem(
                value: () => FirebaseAuth.instance.signOut(),
                child: PortalMenuRow(icon: Icons.logout, label: 'تسجيل خروج', color: Colors.red.shade700),
              ),
            ],
          ),
      ],
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchAllTickets(),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? [];
          final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
          final reportData = ReportDataService.build(tickets);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _pickAndUploadFile,
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
                  _isUploading ? 'جارٍ الرفع...' : 'رفع الملف الأساسي (طلبات الحذف والإضافة)',
                ),
              ),
              const SizedBox(height: 20),
              _buildDashboard(
                reportData,
                tickets.length,
                tickets.map((t) => t['department']).toSet().length,
              ),
              const SizedBox(height: 20),
              _buildQuickActionsBar(tickets, groups, snapshot.hasData),
              const SizedBox(height: 24),
              FollowUpChart(
                data: reportData,
                tickets: tickets,
                roster: _roster,
                showShatrFilter: true,
                showDepartmentFilter: true,
              ),
            ],
          );
        },
      ),
    );
  }

  /// شريط الإجراءات الأربعة الرئيسية (متابعة حالات الظروف الخاصة، متابعة
  /// حالات الدعم النفسي والاجتماعي، التقارير، تنزيل ملفات الحالات) - بشكل
  /// موحّد ومتّسق بدل تفرّقها في أماكن مختلفة من الصفحة، وكل زر يفتح صفحته
  /// المستقلة. الألوان تتبادل بين الأخضر والذهبي (هوية الوحدة) بحيث يكون
  /// النص بلون مخالف لخلفيته دائمًا لضمان التباين والوضوح.
  Widget _buildQuickActionsBar(
    List<Map<String, dynamic>> tickets,
    Map<String, List<Map<String, dynamic>>> groups,
    bool hasData,
  ) {
    final isSuperAdmin =
        FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail;
    final actions = [
      (
        title: 'متابعة حالات الظروف الخاصة',
        icon: Icons.volunteer_activism_outlined,
        background: AppColors.gold,
        foreground: AppColors.greenDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HardshipCasesAdminScreen()),
        ),
      ),
      (
        title: 'متابعة حالات الدعم النفسي والاجتماعي',
        icon: Icons.favorite_border,
        background: AppColors.green,
        foreground: AppColors.goldLight,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportCasesAdminScreen()),
        ),
      ),
      (
        title: 'التقارير',
        icon: Icons.assessment_outlined,
        background: AppColors.greenDark,
        foreground: AppColors.goldLight,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PortalScaffold(
              title: 'التقارير',
              navItems: buildAdminNavItems(context, current: 'reports'),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildReportSection(tickets),
                  const SizedBox(height: 24),
                  _buildStageReportsSection(groups),
                ],
              ),
            ),
          ),
        ),
      ),
      (
        title: 'تنزيل ملفات الحالات',
        icon: Icons.folder_zip_outlined,
        background: AppColors.goldLight,
        foreground: AppColors.greenDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PortalScaffold(
              title: 'تنزيل ملفات الحالات',
              navItems: buildAdminNavItems(context, current: 'downloads'),
              body: _buildDownloadsList(groups, hasData),
            ),
          ),
        ),
      ),
    ];
    final adminOnlyActions = isSuperAdmin
        ? [
            (
              title: 'تسكين المقررات وشعبها',
              icon: Icons.event_note_outlined,
              background: AppColors.green,
              foreground: AppColors.goldLight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 0, singleTab: true)),
              ),
            ),
            (
              title: 'الجدول الدراسي لأعضاء هيئة التدريس',
              icon: Icons.person_search_outlined,
              background: AppColors.gold,
              foreground: AppColors.greenDark,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CourseScheduleAdminScreen(initialTabIndex: 1, singleTab: true)),
              ),
            ),
            (
              title: 'بيانات منسوبي الكلية',
              icon: Icons.badge_outlined,
              background: AppColors.greenDark,
              foreground: AppColors.goldLight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CollegeRosterAdminScreen()),
              ),
            ),
            (
              title: 'توزيع فترات الإرشاد',
              icon: Icons.schedule_outlined,
              background: AppColors.gold,
              foreground: AppColors.greenDark,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdvisingScheduleAdminScreen()),
              ),
            ),
            (
              title: 'متابعة حالات الإرشاد',
              icon: Icons.fact_check_outlined,
              background: AppColors.greenDark,
              foreground: AppColors.goldLight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdvisingCasesAdminScreen()),
              ),
            ),
          ]
        : const <_QuickAction>[];

    Widget group(String label, List<_QuickAction> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 4),
            child: Text(label, style: AppTextStyles.h3(color: Colors.grey.shade700)),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 760;
              if (isNarrow) {
                return Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      _QuickActionCard(action: items[i]),
                      if (i < items.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      Expanded(child: _QuickActionCard(action: items[i])),
                      if (i < items.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('إجراءات عامة', actions),
        if (adminOnlyActions.isNotEmpty) ...[
          const SizedBox(height: 20),
          group('أدوات المدير العام', adminOnlyActions),
        ],
      ],
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

  Widget _buildDashboard(ReportData data, int totalCases, int activeDepartments) {
    final rate = (data.overall.completionRate * 100).toStringAsFixed(0);
    final tiles = [
      (label: 'إجمالي الحالات', value: '$totalCases', icon: Icons.folder_copy_outlined, color: AppColors.greenDark),
      (label: 'الأقسام النشطة', value: '$activeDepartments', icon: Icons.apartment_rounded, color: AppColors.gold),
      (label: 'نسبة الإنجاز', value: '$rate%', icon: Icons.trending_up_rounded, color: AppColors.green),
    ];
    final isNarrow = MediaQuery.of(context).size.width < 560;
    if (isNarrow) {
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            _statTile(tiles[i].label, tiles[i].value, tiles[i].icon, tiles[i].color),
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
            Expanded(child: _statTile(tiles[i].label, tiles[i].value, tiles[i].icon, tiles[i].color)),
            if (i < tiles.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  /// بطاقة إحصاء واحدة بأسلوب "رقم بارز + بلوك أيقونة ملوّن" - مستوحاة من
  /// تصميم لوحات المؤشرات الاحترافية، بألوان الهوية البصرية للوحدة.
  Widget _statTile(String label, String value, IconData icon, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.greenDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 60,
            color: accentColor,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ],
      ),
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
        _buildReportEntryCard(
          icon: Icons.summarize_outlined,
          title: 'التقرير الشامل السريع',
          subtitle: 'طباعة أو تنزيل تقرير فوري بكل بيانات البوابة',
          gradientColors: const [AppColors.gold, AppColors.goldLight],
          onTap: () => _showQuickReportSheet(tickets),
        ),
        const SizedBox(height: 14),
        _buildReportEntryCard(
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

  /// بطاقة دخول موحّدة الشكل لكل مداخل التقارير (السريع والتفصيلي) - أيقونة
  /// + عنوان + وصف مختصر داخل تدرّج لوني، بدل عرض كل الأزرار مباشرة على
  /// الصفحة دفعة واحدة.
  Widget _buildReportEntryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
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

/// بطاقة إجراء واحدة ضمن شريط الإجراءات الأربعة (`_buildQuickActionsBar`) -
/// أيقونة + عنوان داخل خلفية ملوّنة بالهوية البصرية، مع نص بلون مخالف
/// للخلفية دائمًا لضمان التباين.
typedef _QuickAction = ({
  String title,
  IconData icon,
  Color background,
  Color foreground,
  VoidCallback onTap,
});

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: action.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: action.foreground, size: 26),
              const SizedBox(height: 10),
              Text(
                action.title,
                textAlign: TextAlign.center,
                style: TextStyle(color: action.foreground, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
