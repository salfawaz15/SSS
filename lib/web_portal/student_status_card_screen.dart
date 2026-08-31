import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/student_status_card_pdf_service.dart';
import '../services/student_status_card_service.dart';
import '../theme/app_theme.dart';
import '../theme/dashboard_tokens.dart';
import '../utils/name_display.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';

/// بحث عن طالب/ة واحد برقمه الجامعي - يعرض "بطاقة حالة" واحدة (تقرير
/// المرشد + الطلب المقدَّم + ملاحظة المرشد) قابلة للتنزيل PDF لإرسالها
/// للطالب/ة أو العميد أو أي جهة، بطلب سليمان صراحةً (2026-08-31). يُبنى على
/// نفس مصدري بيانات "بحث عن مرشد" و"تذاكر الحذف والإضافة" الموجودين فعلاً
/// (`StudentStatusCardService`) بلا أي تخزين جديد.
class StudentStatusCardScreen extends StatefulWidget {
  const StudentStatusCardScreen({super.key});

  @override
  State<StudentStatusCardScreen> createState() => _StudentStatusCardScreenState();
}

class _StudentStatusCardScreenState extends State<StudentStatusCardScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  StudentStatusCardData? _data;
  String? _searchedId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
      _searchedId = id;
    });
    try {
      final data = await StudentStatusCardService.lookup(id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        if (data == null) _error = 'لم يُعثر على طالب/ة بهذا الرقم الجامعي ضمن تقرير "كل الكليات" المرفوع.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر إتمام البحث: $e';
        _loading = false;
      });
    }
  }

  Future<void> _downloadPdf() async {
    if (_data == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await StudentStatusCardPdfService.build(_data!);
      await Printing.sharePdf(bytes: bytes, filename: 'بطاقة_حالة_${_data!.record.studentId}.pdf');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'بطاقة حالة طالب/ة',
      navItems: buildAdminNavItems(context, current: 'advising-hub'),
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.studentCard, isSuperAdmin: isSuperAdmin),
          Expanded(
            child: Container(
              color: DashTokens.pageBg,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AdvisingPageHeader(
                          breadcrumbTrail: 'بطاقة حالة طالب/ة',
                          title: 'بطاقة حالة طالب/ة',
                          description: 'ابحث برقم الطالب/ة الجامعي لعرض تقرير مرشده وطلبه المقدَّم في بطاقة واحدة قابلة للتنزيل PDF.',
                          icon: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 18),
                        _searchBar(),
                        const SizedBox(height: 20),
                        if (_loading)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
                        else if (_error != null)
                          AdvisingEmptyState(icon: Icons.search_off, title: 'لا توجد نتيجة', description: _error!)
                        else if (_data != null)
                          _card(_data!)
                        else
                          const AdvisingEmptyState(
                            icon: Icons.badge_outlined,
                            title: 'ابحث عن طالب/ة',
                            description: 'اكتب الرقم الجامعي واضغط بحث لعرض بطاقة حالته/ا.',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        boxShadow: DashTokens.cardShadow,
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: DashTokens.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'الرقم الجامعي...'),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() {
                _controller.clear();
                _data = null;
                _error = null;
                _searchedId = null;
              }),
            ),
          FilledButton(
            onPressed: _loading ? null : _search,
            style: FilledButton.styleFrom(backgroundColor: AppColors.greenDark),
            child: const Text('بحث'),
          ),
        ],
      ),
    );
  }

  Widget _card(StudentStatusCardData data) {
    final r = data.record;
    final ticket = data.ticket;
    final decision = ticket?.advisorDecision;

    final (statusLabel, statusFg, statusBg) = _statusStyle(data);

    return Container(
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        border: Border.all(color: DashTokens.border),
        boxShadow: DashTokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.green, AppColors.greenDark], begin: Alignment.topRight, end: Alignment.bottomLeft),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName(r.studentName), style: AppTextStyles.h2(color: Colors.white)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          Text(r.department, style: const TextStyle(color: Color(0xFFCFE0D6), fontSize: 12.5)),
                          Text('· ${r.shatr}', style: const TextStyle(color: Color(0xFFCFE0D6), fontSize: 12.5)),
                          Text.rich(TextSpan(children: [
                            const TextSpan(text: 'المرشد/ة الأكاديمي/ة: ', style: TextStyle(color: Color(0xFFCFE0D6), fontSize: 12.5)),
                            TextSpan(
                              text: r.hasAdvisor ? displayName(r.advisorNameRaw) : 'غير محدَّد',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ])),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(r.studentId, style: const TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            color: DashTokens.pageBg,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: statusFg, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(statusLabel, style: TextStyle(color: statusFg, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _narrative(data),
                    style: const TextStyle(fontSize: 12.5, color: DashTokens.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final panels = [
                Expanded(
                  child: _panel('تقرير المرشد', [
                    _kv('الحالة الصحية', r.healthCondition.isEmpty ? 'لا يوجد' : r.healthCondition),
                    _kv('حالة القيد', r.enrollmentStatus.isEmpty ? 'منتظم/ة' : r.enrollmentStatus),
                    _kv('المعدل التراكمي', r.gpa?.toStringAsFixed(2) ?? 'غير مسجَّل بالتقرير'),
                  ]),
                ),
                SizedBox(width: narrow ? 0 : 14, height: narrow ? 14 : 0),
                Expanded(
                  child: _panel(
                    ticket == null || ticket.actions.isEmpty ? 'الطلب المقدَّم' : 'الطلب المقدَّم (${ticket.actions.length})',
                    ticket == null || ticket.actions.isEmpty
                        ? [const Text('لم تتقدَّم بأي طلب إضافة/حذف/تعديل حتى الآن.', style: TextStyle(fontSize: 12.5, color: DashTokens.textMuted))]
                        : [
                            for (final a in ticket.actions) _requestTile(a),
                          ],
                  ),
                ),
              ];
              return narrow ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: panels) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: panels);
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DashTokens.pageBg,
                borderRadius: BorderRadius.circular(10),
                border: const Border(right: BorderSide(color: AppColors.gold, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ملاحظة المرشد/ة على الحالة',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.gold.withValues(alpha: 0.9), letterSpacing: .3)),
                  const SizedBox(height: 6),
                  Text(
                    decision == null || decision.advisorNotes.trim().isEmpty
                        ? 'لم يكتب المرشد/ة أي ملاحظة بعد — الطلب لم يُفتَح من قِبله/ا.'
                        : '"${decision.advisorNotes.trim()}"',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      fontStyle: decision == null || decision.advisorNotes.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
                      color: decision == null || decision.advisorNotes.trim().isEmpty ? DashTokens.textMuted : DashTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: DashTokens.border))),
            child: Row(
              children: [
                Text('الرقم الجامعي المبحوث عنه: ${_searchedId ?? r.studentId}', style: const TextStyle(fontSize: 11, color: DashTokens.textMuted)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _exporting ? null : _downloadPdf,
                  icon: _exporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('تنزيل PDF / مشاركة'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(StudentTicketAction a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: DashTokens.pageBg, border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(a.courseName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: AppColors.goldLight, borderRadius: BorderRadius.circular(999)),
                child: Text(a.actionType, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.greenDark)),
              ),
            ],
          ),
          if (a.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(a.reason, style: const TextStyle(fontSize: 10.5, color: DashTokens.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _panel(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: DashTokens.border), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.gold.withValues(alpha: 0.9), letterSpacing: .5)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12.5, color: DashTokens.textMuted)),
            Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  static (String, Color, Color) _statusStyle(StudentStatusCardData data) {
    const ok = Color(0xFF1C7A4E);
    const okBg = Color(0xFFE7F4EC);
    const pending = Color(0xFF96731A);
    const pendingBg = Color(0xFFFBF2DE);
    const warn = AppColors.errorRed;
    const warnBg = Color(0xFFFBEAE9);

    final ticket = data.ticket;
    if (ticket == null || ticket.actions.isEmpty) return ('لا يوجد طلب مقدَّم', DashTokens.textMuted, DashTokens.pageBg);
    final decision = ticket.advisorDecision;
    if (decision == null) return ('بانتظار المرشد/ة', pending, pendingBg);
    if (decision.advisorStatus.contains('رفض')) return ('مرفوض — يحتاج متابعة', warn, warnBg);
    if (decision.advisorStatus.isNotEmpty) return ('تمت الموافقة', ok, okBg);
    return ('بانتظار المرشد/ة', pending, pendingBg);
  }

  static String _narrative(StudentStatusCardData data) {
    final ticket = data.ticket;
    if (ticket == null || ticket.actions.isEmpty) return 'لا يوجد أي طلب إضافة/حذف/تعديل مقدَّم من هذا/هذه الطالب/ة.';
    final decision = ticket.advisorDecision;
    if (decision == null) return 'لم تُتّخذ أي إجراء بعد على الطلب المرفوع بتاريخ ${ticket.uploadedDate.isEmpty ? '—' : ticket.uploadedDate}.';
    if (decision.advisorStatus.contains('رفض')) return 'رفض المرشد/ة الطلب — راجع/ي ملاحظته/ا أدناه لمعرفة السبب.';
    return 'وافق المرشد/ة على الطلب.';
  }
}
