import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../models/advising_case_record.dart';
import '../../../services/advising_case_analyzer.dart';
import '../../../services/advising_report_repository.dart';
import '../../../services/course_schedule_repository.dart' show Shatr;
import '../../../services/student_status_card_pdf_service.dart';
import '../../../services/student_status_card_service.dart';
import '../../../utils/name_display.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/mobile_empty_state.dart';
import '../../widgets/mobile_error_state.dart';
import '../../widgets/mobile_loading_state.dart';

/// تبويب "بيانات الطلبة" (ضمن شاشة "الجداول الدراسية"، بجانب "المقررات
/// الدراسية"/"الجدول الدراسي" - بطلب سليمان صراحةً 2026-08-27) - معاينة سريعة
/// أثناء الإرشاد الحي فقط: "لو طالب خلال عملية الإرشاد ذكر ليس له جدول، بمجرد
/// البحث برقمه أو اسمه يظهر وضعه كامل (مرشده/معدله/حالته)". بحث مباشر بلا أي
/// إجراء (لا تصدير ولا تعديل) - نفس مصدر بيانات "بحث عن مرشد" بالموقع
/// (تقرير "كل الكليات" مدمَجًا مع "بيانات الطلبة الأكاديمية").
class StudentLookupTab extends StatefulWidget {
  const StudentLookupTab({super.key});

  @override
  State<StudentLookupTab> createState() => _StudentLookupTabState();
}

class _StudentLookupTabState extends State<StudentLookupTab> {
  late Future<List<AdvisingCaseRecord>> _future = _load();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<AdvisingCaseRecord>> _load() async {
    final results = await Future.wait([
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.base),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.base),
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.basePrevious),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.basePrevious),
    ]);
    final academic = [...results[2], ...results[3]];
    final academicPrevious = [...results[4], ...results[5]];
    return AdvisingCaseAnalyzer.mergeAcademicData([...results[0], ...results[1]], academic, academicPrevious);
  }

  static String _normalize(String s) => s
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .toLowerCase();

  List<AdvisingCaseRecord> _filter(List<AdvisingCaseRecord> all) {
    if (_query.trim().isEmpty) return const [];
    final q = _normalize(_query);
    return all.where((s) => s.studentId.contains(_query.trim()) || _normalize(s.studentName).contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdvisingCaseRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MobileErrorState(onRetry: () => setState(() => _future = _load()));
        }
        if (!snapshot.hasData) {
          return const MobileLoadingState();
        }
        final all = snapshot.data!;
        final results = _filter(all);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
              child: TextField(
                controller: _searchController,
                style: AppTextStyles.caption(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'ابحث برقم الطالب أو اسمه',
                  labelStyle: AppTextStyles.caption(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: _query.trim().isEmpty
                  ? const MobileEmptyState(message: 'اكتب رقم الطالب الجامعي أو اسمه لعرض وضعه كاملاً', icon: Icons.person_search_outlined)
                  : results.isEmpty
                      ? MobileEmptyState(message: 'لا يوجد طالب مطابق لـ"$_query"', icon: Icons.person_off_outlined)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                          itemCount: results.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) => _StudentCard(record: results[i]),
                        ),
            ),
          ],
        );
      },
    );
  }
}

/// بطاقة معاينة طالب واحد - كل بياناته دفعة واحدة، بالإضافة إلى طلبه
/// المقدَّم (إضافة/حذف/تعديل) وملاحظة المرشد/ة عليه (`tickets/{studentId}`)
/// وزر تنزيل/مشاركة PDF بنفس تصميم "بطاقة حالة طالب/ة" بالموقع - بطلب
/// سليمان صراحةً (2026-08-31) لتكون متاحة من تطبيق الجوّال أيضًا. نفس منطق
/// تلوين النطاق المعتمَد بشاشة "بحث عن مرشد" بالموقع.
class _StudentCard extends StatefulWidget {
  final AdvisingCaseRecord record;
  const _StudentCard({required this.record});

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  late final Future<StudentTicket?> _ticketFuture = StudentStatusCardService.fetchTicket(widget.record.studentId);
  bool _exporting = false;

  Future<void> _downloadPdf(StudentTicket? ticket) async {
    setState(() => _exporting = true);
    try {
      final bytes = await StudentStatusCardPdfService.build(StudentStatusCardData(record: widget.record, ticket: ticket));
      await Printing.sharePdf(bytes: bytes, filename: 'بطاقة_حالة_${widget.record.studentId}.pdf');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // معاينة منبثقة بنفس تصميم "بطاقة حالة طالب/ة" بالموقع (تدرّج أخضر +
  // شارة حالة) قبل التنزيل الفعلي - بطلب سليمان صراحةً (2026-09-02): أراد
  // شكل بطاقة الموقع نفسها بالتطبيق، كمعاينة تظهر عند الضغط على "تنزيل" فقط
  // بدل استبدال شكل القائمة الحالي بالكامل.
  Future<void> _showCardPreview(StudentTicket? ticket) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _StatusCardPreviewSheet(
        record: widget.record,
        ticket: ticket,
        exporting: _exporting,
        onDownload: () async {
          await _downloadPdf(ticket);
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  static Color _rangeColor(GpaStatus status) => switch (status) {
        GpaStatus.excellent => const Color(0xFF1B5E20),
        GpaStatus.veryGood => const Color(0xFF7CB342),
        GpaStatus.good => const Color(0xFFFBC02D),
        GpaStatus.pass => const Color(0xFFFB8C00),
        GpaStatus.weak => const Color(0xFFE53935),
        GpaStatus.unknown => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final status = gpaStatusOf(record.gpa);
    final isDismissed = record.isAcademicallyDismissed;
    final isWithdrawn = record.enrollmentStatus.contains('منقطع');
    final statusLabel = isDismissed ? 'مفصول أكاديميًا' : (isWithdrawn ? 'منقطع عن الدراسة' : 'منتظم');
    final statusColor = isDismissed || isWithdrawn ? AppColors.errorRed : AppColors.green;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.studentName, style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(record.studentId, style: AppTextStyles.caption(color: Colors.black45)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel, style: AppTextStyles.caption(color: statusColor).copyWith(fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          _row('القسم', record.department.isEmpty ? '—' : record.department),
          _row('الشطر', record.shatr.isEmpty ? '—' : record.shatr),
          _row('المرشد الأكاديمي', record.hasAdvisor ? displayName(record.advisorNameRaw) : 'بلا مرشد'),
          if (record.hasHealthCondition) _row('الحالة الصحية', record.healthCondition),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  label: 'المعدل التراكمي',
                  value: record.gpa != null ? record.gpa!.toStringAsFixed(2) : '—',
                  color: _rangeColor(status),
                  sub: status.label,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatChip(
                  label: 'الساعات المتبقية',
                  value: record.remainingHours?.toString() ?? '—',
                  color: AppColors.greenDark,
                  sub: record.completedHours != null ? 'مجتازة: ${record.completedHours}' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<StudentTicket?>(
            future: _ticketFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final ticket = snapshot.data;
              return _RequestAndNoteSection(ticket: ticket);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _exporting ? null : () async => _showCardPreview(await _ticketFuture),
              icon: _exporting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('تنزيل PDF / مشاركة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label, style: AppTextStyles.caption(color: Colors.black45))),
            Expanded(child: Text(value, style: AppTextStyles.caption(color: Colors.black87).copyWith(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

/// الطلب المقدَّم (إضافة/حذف/تعديل) + ملاحظة المرشد/ة على الحالة - نفس
/// المحتوى المعروض ببطاقة "بطاقة حالة طالب/ة" بالموقع، مصدره `tickets`.
class _RequestAndNoteSection extends StatelessWidget {
  final StudentTicket? ticket;
  const _RequestAndNoteSection({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final actions = ticket?.actions ?? const [];
    final decision = ticket?.advisorDecision;
    final submissionLog = ticket?.submissionLog ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ticket != null && ticket!.submissionCount > 1) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سجل التقديم (${ticket!.submissionCount} مرات)',
                    style: AppTextStyles.caption(color: AppColors.gold).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final entry in submissionLog) _submissionLogLine(entry),
              ],
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          Text('الطلب المقدَّم (${actions.length})', style: AppTextStyles.caption(color: AppColors.gold).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final a in actions)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(a.courseName, style: AppTextStyles.caption(color: Colors.black87).copyWith(fontWeight: FontWeight.w600))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.goldLight, borderRadius: BorderRadius.circular(6)),
                        child: Text(a.actionType, style: AppTextStyles.caption(color: AppColors.greenDark).copyWith(fontWeight: FontWeight.w700, fontSize: 10.5)),
                      ),
                    ],
                  ),
                  if (a.reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(a.reason, style: AppTextStyles.caption(color: Colors.black45)),
                  ],
                  if (a.history.length > 1) ...[
                    const SizedBox(height: 4),
                    for (final h in a.history)
                      Text(
                        '${(h['date'] ?? '').toString()} — ${(h['advisor_status'] ?? h['coordinator_status'] ?? h['college_status'] ?? '').toString()}',
                        style: AppTextStyles.caption(color: Colors.black38).copyWith(fontSize: 10),
                      ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2F0),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: const Border(right: BorderSide(color: AppColors.gold, width: 2.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ملاحظة المرشد/ة على الحالة', style: AppTextStyles.caption(color: AppColors.greenDark).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                decision == null || decision.advisorNotes.trim().isEmpty
                    ? 'لم يكتب المرشد/ة أي ملاحظة بعد - الطلب لم يُفتَح من قِبله/ا.'
                    : '"${decision.advisorNotes.trim()}"',
                style: AppTextStyles.caption(color: decision == null ? Colors.black45 : Colors.black87),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _submissionLogLine(Map<String, dynamic> entry) {
    final date = (entry['date'] ?? '').toString();
    final actions = (entry['actions'] as List?) ?? [];
    final summary = actions.isEmpty
        ? 'بلا إجراءات محدَّدة'
        : actions
            .map((a) => (a as Map)['action_type'] ?? '')
            .where((s) => s.toString().isNotEmpty)
            .join('، ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: date.isEmpty ? '—' : date, style: AppTextStyles.caption(color: Colors.black87).copyWith(fontWeight: FontWeight.w700)),
        TextSpan(text: '  $summary', style: AppTextStyles.caption(color: Colors.black45)),
      ])),
    );
  }
}

/// معاينة منبثقة بنفس هوية "بطاقة حالة طالب/ة" بالموقع (تدرّج أخضر + شارة
/// حالة + لوحتا تقرير المرشد/الطلب المقدَّم) - تظهر فقط عند الضغط على زر
/// "تنزيل" بدل استبدال شكل القائمة المدمَجة الحالي بالكامل (سليمان صراحةً
/// 2026-09-02). نفس منطق تلوين الحالة المعتمَد بـ`student_status_card_screen.dart`.
class _StatusCardPreviewSheet extends StatelessWidget {
  final AdvisingCaseRecord record;
  final StudentTicket? ticket;
  final bool exporting;
  final VoidCallback onDownload;

  const _StatusCardPreviewSheet({
    required this.record,
    required this.ticket,
    required this.exporting,
    required this.onDownload,
  });

  (String, Color, Color) get _statusStyle {
    const ok = Color(0xFF1C7A4E);
    const okBg = Color(0xFFE7F4EC);
    const pending = Color(0xFF96731A);
    const pendingBg = Color(0xFFFBF2DE);
    const warn = AppColors.errorRed;
    const warnBg = Color(0xFFFBEAE9);

    if (ticket == null || ticket!.actions.isEmpty) return ('لا يوجد طلب مقدَّم', Colors.black45, AppColors.background);
    final decision = ticket!.advisorDecision;
    if (decision == null) return ('بانتظار المرشد/ة', pending, pendingBg);
    if (decision.advisorStatus.contains('رفض')) return ('مرفوض — يحتاج متابعة', warn, warnBg);
    if (decision.advisorStatus.isNotEmpty) return ('تمت الموافقة', ok, okBg);
    return ('بانتظار المرشد/ة', pending, pendingBg);
  }

  String get _narrative {
    if (ticket == null || ticket!.actions.isEmpty) return 'لا يوجد أي طلب إضافة/حذف/تعديل مقدَّم من هذا/هذه الطالب/ة.';
    final decision = ticket!.advisorDecision;
    if (decision == null) return 'لم تُتّخذ أي إجراء بعد على الطلب المرفوع بتاريخ ${ticket!.uploadedDate.isEmpty ? '—' : ticket!.uploadedDate}.';
    if (decision.advisorStatus.contains('رفض')) return 'رفض المرشد/ة الطلب — راجع/ي ملاحظته/ا أدناه لمعرفة السبب.';
    return 'وافق المرشد/ة على الطلب.';
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusFg, statusBg) = _statusStyle;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
                        Text(displayName(record.studentName), style: AppTextStyles.h3(color: Colors.white)),
                        const SizedBox(height: 6),
                        Text('${record.department} · ${record.shatr}', style: const TextStyle(color: Color(0xFFCFE0D6), fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          'المرشد/ة: ${record.hasAdvisor ? displayName(record.advisorNameRaw) : 'غير محدَّد'}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(record.studentId, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              color: AppColors.background,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: statusFg, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(statusLabel, style: TextStyle(color: statusFg, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_narrative, style: AppTextStyles.caption(color: Colors.black54))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: _RequestAndNoteSection(ticket: ticket),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: exporting ? null : onDownload,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.greenDark),
                  icon: exporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('تنزيل PDF / مشاركة'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? sub;
  const _StatChip({required this.label, required this.value, required this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.caption(color: Colors.black45)),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.h3(color: color)),
          if (sub != null) Text(sub!, style: AppTextStyles.caption(color: Colors.black45)),
        ],
      ),
    );
  }
}
