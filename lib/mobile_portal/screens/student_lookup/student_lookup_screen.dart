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
              onPressed: _exporting ? null : () async => _downloadPdf(await _ticketFuture),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
