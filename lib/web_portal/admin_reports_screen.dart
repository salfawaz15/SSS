import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/advisor_roster_entry.dart';
import '../services/advisor_roster_service.dart';
import '../services/disability_file_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/report_data_service.dart';
import '../services/report_excel_service.dart';
import '../services/report_filter_service.dart';
import '../services/report_pdf_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'follow_up_chart.dart';
import 'portal_header.dart';

/// شاشة التقارير التفصيلية: تتيح للإدارة اختيار نوع التقرير (شامل / حسب
/// القسم / حسب الشطر / حسب المرشد الأكاديمي) ثم تصديره Excel أو PDF أو
/// طباعته مباشرة - بدل تقرير واحد شامل فقط.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  ReportScope _scope = ReportScope.overall;
  String? _department;
  String? _shatr;
  String? _advisor;
  bool _isExportingExcel = false;
  bool _isExportingPdf = false;
  bool _isPrinting = false;
  bool _isFollowUpExportingExcel = false;
  bool _isFollowUpExportingPdf = false;
  bool _isFollowUpPrinting = false;
  bool _isDisabilityExportingExcel = false;
  bool _isDisabilityExportingPdf = false;
  bool _isDisabilityPrinting = false;

  /// مُستخدَمة في تقرير متابعة الإنجاز فقط - حتى لا يظهر منسّق قسم كأن لديه
  /// حالات معلَّقة بعد أن تفرَّغ منها فعليًا (نفس تجميع "تفريغ المنسّق"
  /// المستخدَم عند بناء ملف ZIP لأي قسم). لا تُستخدم في تقرير ذوي الإعاقة
  /// لأن حالاتهم موجَّهة عمدًا لاسم أمين/منسّق القسم بغض النظر عن التوزيع.
  List<AdvisorRosterEntry> _roster = [];

  @override
  void initState() {
    super.initState();
    AdvisorRosterService.loadAll().then((r) {
      if (mounted) setState(() => _roster = r);
    });
  }

  String get _title {
    switch (_scope) {
      case ReportScope.overall:
        return 'التقرير الشامل';
      case ReportScope.department:
        return 'تقرير القسم العلمي';
      case ReportScope.shatr:
        return 'تقرير الشطر';
      case ReportScope.advisor:
        return 'تقرير المرشد الأكاديمي';
    }
  }

  String? get _subtitle {
    switch (_scope) {
      case ReportScope.overall:
        return null;
      case ReportScope.department:
        if (_department == null) return null;
        return _shatr == null ? _department : '$_department - $_shatr';
      case ReportScope.shatr:
        return _shatr;
      case ReportScope.advisor:
        if (_advisor == null || _department == null) return null;
        final base = '$_advisor - $_department';
        return _shatr == null ? base : '$base - $_shatr';
    }
  }

  bool get _isReady {
    switch (_scope) {
      case ReportScope.overall:
        return true;
      case ReportScope.department:
        return _department != null;
      case ReportScope.shatr:
        return _shatr != null;
      case ReportScope.advisor:
        return _department != null && _advisor != null;
    }
  }

  List<Map<String, dynamic>> _filteredTickets(List<Map<String, dynamic>> all) {
    return ReportFilterService.apply(
      all,
      scope: _scope,
      department: _department,
      shatr: _shatr,
      advisor: _advisor,
    );
  }

  /// تفاصيل الحالات الفردية (طالب/إجراء) - تُضاف فقط لتقارير القسم والمرشد
  /// لأنها ذات فائدة عملية مباشرة لهما (قوائم أسماء)، لا للتقرير الشامل أو
  /// الشطر لكبر حجم البيانات.
  List<Map<String, dynamic>>? _caseDetails(List<Map<String, dynamic>> filtered) {
    if (_scope != ReportScope.department && _scope != ReportScope.advisor) return null;
    final rows = <Map<String, dynamic>>[];
    for (final t in filtered) {
      final actions = (t['actions'] as List?) ?? [];
      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        rows.add({
          'name': t['name'],
          'university_id': t['university_id'],
          'action_type': action['action_type'],
          'course': action['course'],
          'status': effectiveStatus(action),
        });
      }
    }
    return rows;
  }

  /// نطاق "مرشد" يفلتر التذاكر مسبقًا على مرشد واحد محدَّد بالاسم الخام -
  /// تطبيق إعادة توزيع تفريغ المنسّق هنا قد يُفرغ التقرير تمامًا لو اختار
  /// الأدمن منسّق قسم بالذات، فنستثني هذا النطاق فقط من إعادة التوزيع.
  List<AdvisorRosterEntry>? get _rosterForReport =>
      _scope == ReportScope.advisor ? null : _roster;

  Future<void> _exportExcel(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isExportingExcel = true);
    try {
      final filtered = _filteredTickets(allTickets);
      final data = ReportDataService.build(filtered, roster: _rosterForReport);
      final bytes = ReportExcelService.build(data, scope: _scope, caseDetails: _caseDetails(filtered));
      final cycleId = DateTime.now().toString().substring(0, 10);
      downloadBytes(bytes, '${_title}_$cycleId.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل تقرير Excel بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء تقرير Excel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isExportingPdf = true);
    try {
      final filtered = _filteredTickets(allTickets);
      final data = ReportDataService.build(filtered, roster: _rosterForReport);
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = await ReportPdfService.build(
        data,
        title: _title,
        subtitle: _subtitle,
        scope: _scope,
        caseDetails: _caseDetails(filtered),
        // نطاقا "شامل" و"شطر" كلاهما يعني عشرات/مئات المرشدين معًا - جدول
        // بهذا الحجم هو ما كان يجمّد المتصفح فعليًا (تأكَّد التجمّد حتى في
        // نطاق "شطر" وحده، فلا يكفي استبعاده من "شامل" فقط). يبقى متاحًا
        // كاملاً فقط عند اختيار نطاق "قسم" أو "مرشد" (بيانات صغيرة بما يكفي).
        includeAdvisorDetail: _scope == ReportScope.department || _scope == ReportScope.advisor,
      );
      downloadBytes(bytes, '${_title}_$cycleId.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل تقرير PDF بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء تقرير PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _printPdf(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isPrinting = true);
    try {
      final filtered = _filteredTickets(allTickets);
      final data = ReportDataService.build(filtered, roster: _rosterForReport);
      final bytes = await ReportPdfService.build(
        data,
        title: _title,
        subtitle: _subtitle,
        scope: _scope,
        caseDetails: _caseDetails(filtered),
        // نطاقا "شامل" و"شطر" كلاهما يعني عشرات/مئات المرشدين معًا - جدول
        // بهذا الحجم هو ما كان يجمّد المتصفح فعليًا (تأكَّد التجمّد حتى في
        // نطاق "شطر" وحده، فلا يكفي استبعاده من "شامل" فقط). يبقى متاحًا
        // كاملاً فقط عند اختيار نطاق "قسم" أو "مرشد" (بيانات صغيرة بما يكفي).
        includeAdvisorDetail: _scope == ReportScope.department || _scope == ReportScope.advisor,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر فتح التقرير للطباعة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  /// عنوان تقرير المتابعة يتبع نفس تفريع النطاق الحالي (شامل/قسم/شطر/مرشد)
  /// حتى يستطيع الأدمن التركيز على متابعة قسم أو شطر معيّن عند الحاجة.
  String get _followUpTitle => 'تقرير متابعة الإنجاز - $_title';

  Future<void> _printFollowUp(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isFollowUpPrinting = true);
    try {
      final filtered = _filteredTickets(allTickets);
      final data = ReportDataService.build(filtered, roster: _rosterForReport);
      final bytes = await ReportPdfService.buildFollowUp(
        data,
        title: _followUpTitle,
        subtitle: _subtitle,
        pendingCases: ReportFilterService.pendingCases(filtered),
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

  Future<void> _exportFollowUpPdf(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isFollowUpExportingPdf = true);
    try {
      final filtered = _filteredTickets(allTickets);
      final data = ReportDataService.build(filtered, roster: _rosterForReport);
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = await ReportPdfService.buildFollowUp(
        data,
        title: _followUpTitle,
        subtitle: _subtitle,
        pendingCases: ReportFilterService.pendingCases(filtered),
      );
      downloadBytes(bytes, 'متابعة_الإنجاز_$cycleId.pdf');
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

  Future<void> _exportFollowUpExcel(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isFollowUpExportingExcel = true);
    try {
      final filtered = _filteredTickets(allTickets);
      final data = ReportDataService.build(filtered, roster: _rosterForReport);
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = ReportExcelService.buildFollowUp(
        data,
        pendingCases: ReportFilterService.pendingCases(filtered),
      );
      downloadBytes(bytes, 'متابعة_الإنجاز_$cycleId.xlsx');
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

  /// تقرير ومتابعة مستقلان تمامًا لحالات ذوي الإعاقة فقط (نفس تفريع النطاق
  /// المختار أعلاه)، لأنهم يحصلون على اهتمام ومتابعة أقوى بمعزل عن التقرير
  /// العام - يُبنى من تذاكر هذا النطاق بعد استبعاد كل التذاكر غير المصنّفة
  /// ذوي إعاقة.
  List<Map<String, dynamic>> _disabilityTickets(List<Map<String, dynamic>> allTickets) {
    return DisabilityFileService.filterDisabilityTickets(_filteredTickets(allTickets));
  }

  String get _disabilityTitle => 'تقرير ذوي الإعاقة - $_title';

  Future<void> _printDisability(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isDisabilityPrinting = true);
    try {
      final disability = _disabilityTickets(allTickets);
      final data = ReportDataService.build(disability);
      final bytes = await ReportPdfService.buildFollowUp(
        data,
        title: _disabilityTitle,
        subtitle: _subtitle,
        pendingCases: ReportFilterService.pendingCases(disability),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر فتح تقرير ذوي الإعاقة للطباعة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDisabilityPrinting = false);
    }
  }

  Future<void> _exportDisabilityPdf(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isDisabilityExportingPdf = true);
    try {
      final disability = _disabilityTickets(allTickets);
      final data = ReportDataService.build(disability);
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = await ReportPdfService.buildFollowUp(
        data,
        title: _disabilityTitle,
        subtitle: _subtitle,
        pendingCases: ReportFilterService.pendingCases(disability),
      );
      downloadBytes(bytes, 'ذوي_الإعاقة_$cycleId.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل تقرير ذوي الإعاقة (PDF) بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء تقرير ذوي الإعاقة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDisabilityExportingPdf = false);
    }
  }

  Future<void> _exportDisabilityExcel(List<Map<String, dynamic>> allTickets) async {
    setState(() => _isDisabilityExportingExcel = true);
    try {
      final disability = _disabilityTickets(allTickets);
      final data = ReportDataService.build(disability);
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = ReportExcelService.buildFollowUp(
        data,
        pendingCases: ReportFilterService.pendingCases(disability),
      );
      downloadBytes(bytes, 'ذوي_الإعاقة_$cycleId.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنزيل تقرير ذوي الإعاقة (Excel) بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء تقرير ذوي الإعاقة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDisabilityExportingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'التقارير التفصيلية',
      navItems: buildAdminNavItems(context, current: 'reports'),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchAllTickets(),
        builder: (context, snapshot) {
          final allTickets = snapshot.data ?? [];
          final filtered = _filteredTickets(allTickets);
          final previewData = ReportDataService.build(filtered);

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildScopeSelector(),
                    const SizedBox(height: 16),
                    ..._buildFilterFields(allTickets),
                    const SizedBox(height: 24),
                    _buildPreviewCard(previewData),
                    const SizedBox(height: 24),
                    _buildActionButtons(allTickets),
                    const SizedBox(height: 32),
                    _buildFollowUpSection(allTickets),
                    const SizedBox(height: 32),
                    _buildDisabilitySection(allTickets),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScopeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نوع التقرير', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            // شبكة 2×2 ثابتة بدل Wrap حر - كان يضع 3 بطاقات بالسطر الأول
            // وبطاقة يتيمة وحدها بالسطر الثاني حسب عرض الشاشة، وهو شكل غير
            // احترافي. هذا التقسيم الثابت يبقى متّسقًا على كل الأحجام.
            Row(
              children: [
                Expanded(child: _scopeChip('تقرير شامل', ReportScope.overall, Icons.dashboard_outlined)),
                const SizedBox(width: 10),
                Expanded(child: _scopeChip('حسب القسم العلمي', ReportScope.department, Icons.apartment_outlined)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _scopeChip('حسب الشطر', ReportScope.shatr, Icons.groups_outlined)),
                const SizedBox(width: 10),
                Expanded(child: _scopeChip('حسب المرشد الأكاديمي', ReportScope.advisor, Icons.support_agent_outlined)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// زر اختيار نطاق مصمَّم ليتمدَّد بعرض الخانة المخصَّصة له بالكامل (بدل
  /// ChoiceChip الذي يتقلّص لحجم نصّه فقط ويترك فراغًا غير متّسق داخل شبكة
  /// 2×2)، بنفس الهوية البصرية (أخضر عند التحديد، حدود خضراء فاتحة غير ذلك).
  Widget _scopeChip(String label, ReportScope scope, IconData icon) {
    final selected = _scope == scope;
    return Material(
      color: selected ? AppColors.green : Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() {
          _scope = scope;
          _department = null;
          _shatr = null;
          _advisor = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? AppColors.green : AppColors.green.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : AppColors.green),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.greenDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFilterFields(List<Map<String, dynamic>> allTickets) {
    switch (_scope) {
      case ReportScope.overall:
        return [];
      case ReportScope.shatr:
        return [
          DropdownButtonFormField<String>(
            initialValue: _shatr,
            hint: const Text('اختر الشطر'),
            decoration: const InputDecoration(labelText: 'الشطر'),
            items: ReportFilterService.shatrValues
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _shatr = v),
          ),
        ];
      case ReportScope.department:
        return [
          DropdownButtonFormField<String>(
            initialValue: _department,
            hint: const Text('اختر القسم'),
            decoration: const InputDecoration(labelText: 'القسم العلمي'),
            items: ReportFilterService.departments
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _department = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _shatr,
            decoration: const InputDecoration(labelText: 'الشطر'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('كلا الشطرين')),
              ...ReportFilterService.shatrValues
                  .map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
            ],
            onChanged: (v) => setState(() => _shatr = v),
          ),
        ];
      case ReportScope.advisor:
        final advisorOptions = _department == null
            ? <String>[]
            : ReportFilterService.advisorsInDepartment(allTickets, _department!, shatr: _shatr);
        return [
          DropdownButtonFormField<String>(
            initialValue: _department,
            hint: const Text('اختر القسم أولاً'),
            decoration: const InputDecoration(labelText: 'القسم العلمي'),
            items: ReportFilterService.departments
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() {
              _department = v;
              _advisor = null;
            }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _shatr,
            decoration: const InputDecoration(labelText: 'الشطر'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('كلا الشطرين')),
              ...ReportFilterService.shatrValues
                  .map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
            ],
            onChanged: (v) => setState(() {
              _shatr = v;
              _advisor = null;
            }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _advisor,
            hint: Text(_department == null ? 'اختر القسم أولاً' : 'اختر المرشد'),
            decoration: const InputDecoration(labelText: 'المرشد الأكاديمي'),
            items: advisorOptions.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
            onChanged: advisorOptions.isEmpty ? null : (v) => setState(() => _advisor = v),
          ),
        ];
    }
  }

  Widget _buildPreviewCard(ReportData data) {
    final o = data.overall;
    final rate = (o.completionRate * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.greenDark, AppColors.green],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            _subtitle ?? _title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // نفس تعريف "الحالات" المستخدم في ملفي PDF وExcel المصدَّرين
              // (o.total = عدد الإجراءات وليس عدد الطلاب) لتفادي تناقض
              // الأرقام بين المعاينة على الشاشة والملف الفعلي بعد التنزيل.
              Expanded(child: _previewStat('الحالات', '${o.total}')),
              Expanded(child: _previewStat('تم الإنجاز', '${o.completed}')),
              Expanded(child: _previewStat('نسبة الإنجاز', '$rate%')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildActionButtons(List<Map<String, dynamic>> allTickets) {
    final enabled = _isReady;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: (!enabled || _isPrinting) ? null : () => _printPdf(allTickets),
          icon: _isPrinting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.print_outlined),
          label: const Text('طباعة'),
        ),
        ElevatedButton.icon(
          onPressed: (!enabled || _isExportingExcel) ? null : () => _exportExcel(allTickets),
          icon: _isExportingExcel
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.table_chart_outlined),
          label: const Text('تنزيل Excel'),
        ),
        ElevatedButton.icon(
          onPressed: (!enabled || _isExportingPdf) ? null : () => _exportPdf(allTickets),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
          icon: _isExportingPdf
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('تنزيل PDF'),
        ),
      ],
    );
  }

  /// قسم مميّز ومنفصل بصريًا: "تقرير متابعة الإنجاز" - يجيب فورًا عن سؤال
  /// الأدمن "من أنجز ومن لم يُنجز بعد؟" دون فتح كل ملف قسم يدويًا، عبر ترتيب
  /// المرشدين من الأسوأ إنجازًا إلى الأفضل + قائمة تفصيلية بكل الحالات
  /// المتبقية جاهزة للمراسلة المباشرة. يحترم نفس تفريع النطاق المختار أعلاه.
  Widget _buildFollowUpSection(List<Map<String, dynamic>> allTickets) {
    final enabled = _isReady;
    final followUpData = ReportDataService.build(_filteredTickets(allTickets), roster: _rosterForReport);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold, width: 1.4),
        borderRadius: BorderRadius.circular(16),
        color: AppColors.gold.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.greenDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'تقرير متابعة الإنجاز',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'يرتّب المرشدين الأكاديميين حسب نسبة الإنجاز (الأقل إنجازًا أولًا) ويُظهر كل الحالات المتبقية بالتفصيل، لمتابعة سير العمل فورًا بعد رفع الملفات دون فتح كل ملف يدويًا.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: (!enabled || _isFollowUpPrinting) ? null : () => _printFollowUp(allTickets),
                icon: _isFollowUpPrinting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: const Text('طباعة المتابعة'),
              ),
              OutlinedButton.icon(
                onPressed: (!enabled || _isFollowUpExportingExcel) ? null : () => _exportFollowUpExcel(allTickets),
                icon: _isFollowUpExportingExcel
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_chart_outlined),
                label: const Text('تنزيل Excel'),
              ),
              ElevatedButton.icon(
                onPressed: (!enabled || _isFollowUpExportingPdf) ? null : () => _exportFollowUpPdf(allTickets),
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

  /// قسم مستقل تمامًا لإحصائيات ومتابعة "ذوي الإعاقة" - يحصلون على اهتمام
  /// ومتابعة أقوى بمعزل عن التقرير العام، بما يشمل ملف الحالات المرسل لأمين
  /// القسم (وليس المرشد الأكاديمي).
  Widget _buildDisabilitySection(List<Map<String, dynamic>> allTickets) {
    final enabled = _isReady;
    final disabilityTickets = _disabilityTickets(allTickets);
    final disabilityData = ReportDataService.build(disabilityTickets);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold, width: 1.4),
        borderRadius: BorderRadius.circular(16),
        color: AppColors.gold.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.accessible_outlined, color: AppColors.greenDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'تقرير ومتابعة ذوي الإعاقة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'إحصائيات ومتابعة مستقلة تمامًا عن التقرير العام لحالات ذوي الإعاقة (${disabilityTickets.length} حالة ضمن النطاق الحالي)، بمعزل عن دقة حقل المرشد الأكاديمي.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: (!enabled || _isDisabilityPrinting) ? null : () => _printDisability(allTickets),
                icon: _isDisabilityPrinting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: const Text('طباعة'),
              ),
              OutlinedButton.icon(
                onPressed: (!enabled || _isDisabilityExportingExcel) ? null : () => _exportDisabilityExcel(allTickets),
                icon: _isDisabilityExportingExcel
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_chart_outlined),
                label: const Text('تنزيل Excel'),
              ),
              ElevatedButton.icon(
                onPressed: (!enabled || _isDisabilityExportingPdf) ? null : () => _exportDisabilityPdf(allTickets),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                icon: _isDisabilityExportingPdf
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('تنزيل PDF'),
              ),
            ],
          ),
          FollowUpChart(data: disabilityData),
        ],
      ),
    );
  }
}
