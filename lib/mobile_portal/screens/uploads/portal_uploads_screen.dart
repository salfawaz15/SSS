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

  // نفس آلية الشريط الموحَّد بالموقع (upload_hub_screen.dart) - سليمان
  // صراحةً 2026-08-25: يتولى هو بنفسه كل رفع/تنزيل مراحل الحذف والإضافة
  // هذا الفصل، فيحتاج نفس القدرة من الجوال أيضًا.
  bool _downloadingAllAdvisors = false;
  bool _uploadingProcessedAdvisors = false;
  bool _downloadingAllStage2 = false;
  bool _uploadingProcessedCoordinators = false;
  bool _downloadingAllStage3 = false;
  bool _uploadingProcessedCollege = false;

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
        CourseScheduleRepository.currentUploadedAt(Shatr.male),
        CourseScheduleRepository.currentUploadedAt(Shatr.female),
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

  /// يبني نفس رسالة نتيجة الدمج المستخدَمة بالموقع (`upload_hub_screen.dart`
  /// - `_mergeResultMessage`) - عدد الحالات المطابَقة/غير المطابَقة، وتنبيه
  /// إضافي لو وُجدت حالات "لم يتم التنفيذ" بلا سبب محدَّد.
  void _showMergeResult(MergeResult result) {
    final base = 'تم الدمج: ${result.matchedCount} حالة مطابَقة'
        '${result.unmatchedCount > 0 ? '، ${result.unmatchedCount} غير مطابَقة' : ''}';
    final message = result.missingReasonCount > 0
        ? '$base\nتنبيه: ${result.missingReasonCount} حالة اختار فيها المرشد "لم يتم التنفيذ" بلا تحديد السبب'
        : base;
    _showMessage(message);
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
            _CycleStagesCard(
              // إعادة تصميم كاملة (سليمان صراحةً 2026-08-25: الشكل السابق -
              // 9 أيقونات متلاصقة بصف واحد بلا تمييز - غير واضح إطلاقًا).
              // سطر مستقل لكل مرحلة (أساسي/مرشد/منسّق قسم/منسّق كلية):
              // عنوان المرحلة + أيقونات إجراءاتها، وسطر شرح خفيف اللون تحته
              // مباشرة - يستغل المساحة البيضاء أسفل البطاقة بدل تركها فارغة،
              // بلا حاجة لأي تمرير.
              stages: [
                _CycleStage(
                  label: 'الملف الأساسي',
                  caption: 'رفع/تنزيل/إفراغ الملف الخام',
                  actions: [
                    _UploadActionButton(
                      tooltip: 'تنزيل ملف مضغوط (10 ملفات خام - قسم/شطر، لإرسال منسّق القسم يدويًا)',
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
                      tooltip: 'رفع ملف الفورم الأساسي',
                      icon: Icons.upload_file_outlined,
                      busy: _uploadingForms,
                      iconOnly: true,
                      color: AppColors.green,
                      onPressed: () => runUploadForms(
                        context: context,
                        setUploading: (v) => setState(() => _uploadingForms = v),
                        onSuccess: () {},
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
                  ],
                ),
                _CycleStage(
                  label: 'مرحلة المرشد',
                  caption: 'تنزيل لكل مرشد + رفع الملفات المعالجة',
                  actions: [
                    _UploadActionButton(
                      tooltip: 'تنزيل الكل مقسَّم لكل مرشد (شطر > قسم > ملف)',
                      icon: Icons.folder_zip_outlined,
                      busy: _downloadingAllAdvisors,
                      iconOnly: true,
                      onPressed: () => runDownloadAllAdvisorsZip(
                        context: context,
                        setDownloading: (v) => setState(() => _downloadingAllAdvisors = v),
                        onMessage: _showMessage,
                      ),
                    ),
                    _UploadActionButton(
                      tooltip: 'رفع الملفات المعالجة العائدة من المرشدين',
                      icon: Icons.upload_file_outlined,
                      busy: _uploadingProcessedAdvisors,
                      iconOnly: true,
                      color: AppColors.goldLight,
                      onPressed: () => runUploadProcessedFiles(
                        context: context,
                        setUploading: (v) => setState(() => _uploadingProcessedAdvisors = v),
                        onResult: _showMergeResult,
                      ),
                    ),
                  ],
                ),
                _CycleStage(
                  label: 'مرحلة منسّق القسم',
                  caption: 'تنزيل كل الأقسام + رفع الملفات المعالجة',
                  actions: [
                    _UploadActionButton(
                      tooltip: 'تنزيل كل ملفات الأقسام (10 ملفات) دفعة واحدة',
                      icon: Icons.folder_zip_outlined,
                      busy: _downloadingAllStage2,
                      iconOnly: true,
                      onPressed: () => runDownloadAllStage2Zip(
                        context: context,
                        setDownloading: (v) => setState(() => _downloadingAllStage2 = v),
                        onMessage: _showMessage,
                      ),
                    ),
                    _UploadActionButton(
                      tooltip: 'رفع الملفات المعالجة العائدة من منسّقي الأقسام',
                      icon: Icons.upload_file_outlined,
                      busy: _uploadingProcessedCoordinators,
                      iconOnly: true,
                      color: AppColors.goldLight,
                      onPressed: () => runUploadProcessedFiles(
                        context: context,
                        setUploading: (v) => setState(() => _uploadingProcessedCoordinators = v),
                        onResult: _showMergeResult,
                      ),
                    ),
                  ],
                ),
                _CycleStage(
                  label: 'مرحلة منسّق الكلية',
                  caption: 'تنزيل الشطرين + رفع الملف المعالج',
                  actions: [
                    _UploadActionButton(
                      tooltip: 'تنزيل ملفَي الشطرين دفعة واحدة',
                      icon: Icons.folder_zip_outlined,
                      busy: _downloadingAllStage3,
                      iconOnly: true,
                      onPressed: () => runDownloadAllStage3Zip(
                        context: context,
                        setDownloading: (v) => setState(() => _downloadingAllStage3 = v),
                        onMessage: _showMessage,
                      ),
                    ),
                    _UploadActionButton(
                      tooltip: 'رفع الملف المعالج العائد من منسّق الكلية',
                      icon: Icons.upload_file_outlined,
                      busy: _uploadingProcessedCollege,
                      iconOnly: true,
                      color: AppColors.goldLight,
                      onPressed: () => runUploadProcessedFiles(
                        context: context,
                        setUploading: (v) => setState(() => _uploadingProcessedCollege = v),
                        onResult: _showMergeResult,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _UploadCategoryCard(
              title: 'المقررات الدراسية',
              icon: Icons.menu_book_outlined,
              color: AppColors.gold,
              statusText: _loadingDates ? null : _dateStatusText(_coursesDate),
              busy: _uploadingCourses,
              actions: [
                _UploadActionButton(
                  tooltip: 'رفع ملف الحويّة الجديد',
                  icon: Icons.upload_file_outlined,
                  busy: _uploadingCourses,
                  iconOnly: true,
                  color: AppColors.green,
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
              icon: Icons.groups_outlined,
              color: AppColors.greenDark,
              statusText: _loadingDates ? null : _dateStatusText(_advisingDate),
              busy: _uploadingAdvising,
              actions: [
                _UploadActionButton(
                  tooltip: 'رفع تقرير الإرشاد الكامل الجديد',
                  icon: Icons.upload_file_outlined,
                  busy: _uploadingAdvising,
                  iconOnly: true,
                  color: AppColors.green,
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
  final IconData icon;
  final Color color;
  final String? statusText;
  final bool busy;
  final List<Widget> actions;

  const _UploadCategoryCard({
    required this.title,
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
          // أيقونات الإجراءات بنفس صف العنوان مباشرة - بلا صفّ منفصل أسفلها
          // (سليمان صراحةً 2026-08-25: "بحيث تكون الصفحة بدون تمرير")، بنفس
          // أسلوب أسطر بطاقة "حالات الحذف والإضافة".
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
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ...actions,
            ],
          ),
          if (statusText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(statusText!, style: AppTextStyles.caption(color: Colors.black45)),
          ],
        ],
      ),
    );
  }
}

/// مرحلة واحدة من دورة الحذف/الإضافة (أساسي/مرشد/منسّق قسم/منسّق كلية) -
/// عنوان + أيقونات إجراءاتها + سطر شرح خفيف اللون يوضّح وظيفتها بلا حاجة
/// لتمرير الماوس فوق كل أيقونة على حدة (الجوال لا يملك "hover" أصلاً).
class _CycleStage {
  final String label;
  final String caption;
  final List<Widget> actions;

  const _CycleStage({required this.label, required this.caption, required this.actions});
}

/// بطاقة "حالات الحذف والإضافة" - سطر مستقل واضح لكل مرحلة بدل صفّ أيقونات
/// متلاصقة بلا تمييز (سليمان صراحةً 2026-08-25: "شكلها غير واضح... كل سطر
/// إجراء... يستغل المساحة البيضاء أسفل الصورة... بلا تمرير للأسفل").
class _CycleStagesCard extends StatelessWidget {
  final List<_CycleStage> stages;

  const _CycleStagesCard({required this.stages});

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
                decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: const Icon(Icons.fact_check_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('حالات الحذف والإضافة', style: AppTextStyles.h3()),
                    Text('الملف الأساسي (Microsoft Forms)', style: AppTextStyles.caption(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          for (var i = 0; i < stages.length; i++) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? AppSpacing.md : AppSpacing.sm),
              child: Divider(height: 1, color: Colors.grey.shade200),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  Text(
                    stages[i].label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.black87),
                  ),
                  const Spacer(),
                  ...stages[i].actions,
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stages[i].caption,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
            ),
          ],
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
    this.iconOnly = false,
    this.color,
  }) : primary = true, assert(iconOnly ? tooltip != null : label != null);

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
