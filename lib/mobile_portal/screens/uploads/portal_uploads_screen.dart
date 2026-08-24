import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/advising_report_repository.dart';
import '../../../services/course_schedule_repository.dart';
import '../../../services/firestore_ticket_service.dart';
import '../../../web_portal/upload_flows.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/portal_app_bar_logo.dart';

/// شاشة "رفع الملفات" - ثلاث فئات فقط بطلب سليمان صراحةً (2026-08-23): ملف
/// الفورم (رفع + تنزيل)، المقررات الدراسية (الحويّة)، الإرشاد الكامل (كل
/// الكليات). بقية الفئات (ذوو الإعاقة/جداول المواعيد) نادرة التغيير، تُؤجَّل
/// لمرحلة تالية. **لا تُنشئ منطق رفع جديدًا** - كل بطاقة تستدعي مباشرة نفس
/// دوال `upload_flows.dart` المستخدَمة بصفحة "رفع وتنزيل الملفات" بالموقع
/// (`runUploadForms`/`runDownloadFormsZip`/`runUploadCourses`/
/// `runUploadAllColleges`) - نفس الحوارات/التحقق/الحفظ بالضبط بلا تكرار.
class PortalUploadsScreen extends StatefulWidget {
  const PortalUploadsScreen({super.key});

  @override
  State<PortalUploadsScreen> createState() => _PortalUploadsScreenState();
}

class _PortalUploadsScreenState extends State<PortalUploadsScreen> {
  bool _uploadingForms = false;
  bool _downloadingForms = false;
  bool _clearingForms = false;
  bool _uploadingCourses = false;
  bool _uploadingAdvising = false;

  DateTime? _coursesDate;
  DateTime? _advisingDate;
  bool _loadingDates = true;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    setState(() => _loadingDates = true);
    try {
      final results = await Future.wait([
        CourseScheduleRepository.currentExportDate(Shatr.male),
        CourseScheduleRepository.currentExportDate(Shatr.female),
        AdvisingReportRepository.currentUploadDate(Shatr.male, kind: AdvisingReportKind.allColleges),
        AdvisingReportRepository.currentUploadDate(Shatr.female, kind: AdvisingReportKind.allColleges),
      ]);
      if (!mounted) return;
      setState(() {
        _coursesDate = _latestOf(results[0], results[1]);
        _advisingDate = _latestOf(results[2], results[3]);
      });
    } finally {
      if (mounted) setState(() => _loadingDates = false);
    }
  }

  DateTime? _latestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    AppNotice.success(context, message);
  }

  /// إفراغ كل بيانات "الملف الأساسي - طلبات الحذف والإضافة" - نفس منطق
  /// وحوار التأكيد الموجودَين بالموقع (`upload_hub_screen.dart`) حرفيًا
  /// (سليمان 2026-08-24: زر ثالث بجانب رفع/تنزيل، أيقونة فقط بلا نص).
  Future<void> _confirmAndClearForms() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إفراغ البيانات'),
        content: const Text(
          'سيُحذَف كل ما هو مرفوع حاليًا لـ"الملف الأساسي - طلبات الحذف والإضافة" (كل الحالات وحالة معالجتها) '
          'من كل الأقسام والشطرين بلا استثناء ولا رجعة. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إفراغ نهائيًا'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearingForms = true);
    try {
      await FirestoreTicketService.clearAll();
      _showMessage('تم إفراغ بيانات "الملف الأساسي" بنجاح');
    } finally {
      if (mounted) setState(() => _clearingForms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: kPortalAppBarLeadingWidth,
        leading: const PortalAppBarLogo(),
        title: const Text('رفع الملفات'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDates,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _UploadCategoryCard(
              title: 'حالات الحذف والإضافة',
              subtitle: 'الملف الأساسي (Microsoft Forms)',
              icon: Icons.fact_check_outlined,
              color: AppColors.green,
              statusText: null,
              busy: _uploadingForms || _downloadingForms || _clearingForms,
              actions: [
                _UploadActionButton(
                  tooltip: 'تنزيل ملف مضغوط (10 ملفات - قسم/شطر)',
                  icon: Icons.download_outlined,
                  busy: _downloadingForms,
                  iconOnly: true,
                  onPressed: () => runDownloadFormsZip(
                    context: context,
                    setDownloading: (v) => setState(() => _downloadingForms = v),
                    onMessage: _showMessage,
                  ),
                ),
                _UploadActionButton(
                  tooltip: 'إفراغ كل البيانات المرفوعة لهذا الملف',
                  icon: Icons.delete_outline,
                  busy: _clearingForms,
                  iconOnly: true,
                  color: Colors.red.shade700,
                  onPressed: _confirmAndClearForms,
                ),
                _UploadActionButton(
                  label: 'رفع ملف جديد',
                  icon: Icons.upload_file_outlined,
                  busy: _uploadingForms,
                  onPressed: () => runUploadForms(
                    context: context,
                    setUploading: (v) => setState(() => _uploadingForms = v),
                    onSuccess: () {},
                    onMessage: _showMessage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _UploadCategoryCard(
              title: 'المقررات الدراسية',
              subtitle: 'ملف الحويّة (Word .docx) - الشطرين معًا',
              icon: Icons.menu_book_outlined,
              color: AppColors.gold,
              statusText: _loadingDates ? null : _dateStatusText(_coursesDate),
              busy: _uploadingCourses,
              actions: [
                _UploadActionButton(
                  label: 'رفع ملف جديد',
                  icon: Icons.upload_file_outlined,
                  busy: _uploadingCourses,
                  onPressed: () => runUploadCourses(
                    context: context,
                    setUploading: (v) => setState(() => _uploadingCourses = v),
                    onSuccess: _loadDates,
                    onMessage: _showMessage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _UploadCategoryCard(
              title: 'الإرشاد الكامل',
              subtitle: 'تقرير "كل الكليات" (PDF) - يغطي الجامعة كاملة',
              icon: Icons.groups_outlined,
              color: AppColors.greenDark,
              statusText: _loadingDates ? null : _dateStatusText(_advisingDate),
              busy: _uploadingAdvising,
              actions: [
                _UploadActionButton(
                  label: 'رفع ملف جديد',
                  icon: Icons.upload_file_outlined,
                  busy: _uploadingAdvising,
                  onPressed: () => runUploadAllColleges(
                    context: context,
                    setUploading: (v) => setState(() => _uploadingAdvising = v),
                    onSuccess: _loadDates,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateStatusText(DateTime? date) {
    if (date == null) return 'لم يُرفع أي ملف بعد';
    return 'آخر تحديث: ${DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(date)}';
  }
}

class _UploadCategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? statusText;
  final bool busy;
  final List<Widget> actions;

  const _UploadCategoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.statusText,
    required this.busy,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.h3()),
                    Text(subtitle, style: AppTextStyles.caption(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          if (statusText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(statusText!, style: AppTextStyles.caption(color: Colors.black45)),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
        ],
      ),
    );
  }
}

class _UploadActionButton extends StatelessWidget {
  final String? label;
  final String? tooltip;
  final IconData icon;
  final bool busy;
  final bool primary;
  final bool iconOnly;
  final Color? color;
  final VoidCallback onPressed;

  const _UploadActionButton({
    this.label,
    this.tooltip,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.primary = true,
    this.iconOnly = false,
    this.color,
  }) : assert(iconOnly ? tooltip != null : label != null);

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: iconOnly ? Colors.white : null),
          )
        : Icon(icon, size: 18, color: iconOnly ? Colors.white : null);

    // زر أيقونة فقط بلا نص (تنزيل/إفراغ) - بطلب سليمان صراحةً 2026-08-24،
    // نفس أسلوب `RoundIconButton` بالموقع (خلفية صلبة + رمز أبيض).
    if (iconOnly) {
      return SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: color ?? AppColors.gold),
          icon: child,
          onPressed: busy ? null : onPressed,
        ),
      );
    }

    if (primary) {
      return ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: child,
        label: Text(label!),
      );
    }
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: child,
      label: Text(label!),
    );
  }
}
