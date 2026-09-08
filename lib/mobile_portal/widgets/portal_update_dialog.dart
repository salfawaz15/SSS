import 'package:flutter/material.dart';

import '../../services/portal_update_service.dart';
import '../../theme/app_theme.dart';

/// حوار التحديث - يظهر تلقائيًا مرة واحدة لكل رقم بناء جديد (ما لم يختر
/// المستخدم "لا تحدّث أبدًا")، أو عند ضغط بادجة الإشعار يدويًا. ثلاثة خيارات
/// (سليمان صراحةً 2026-09-09): "تحديث الآن" يبدأ التنزيل/التثبيت مباشرة
/// داخل نفس الحوار (شريط تقدّم)، "لاحقًا" يؤجّل لهذا البناء فقط، "لا تحدّث
/// أبدًا" يُخفي الحوار التلقائي كليًا حتى يُلغيه المستخدم بضغط البادجة.
Future<void> showPortalUpdateDialog(BuildContext context, PortalUpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PortalUpdateDialogContent(info: info),
  );
}

class _PortalUpdateDialogContent extends StatefulWidget {
  final PortalUpdateInfo info;
  const _PortalUpdateDialogContent({required this.info});

  @override
  State<_PortalUpdateDialogContent> createState() => _PortalUpdateDialogContentState();
}

class _PortalUpdateDialogContentState extends State<_PortalUpdateDialogContent> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _updateNow() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      await PortalUpdateService.downloadAndInstall(
        widget.info.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } on PortalUpdateDownloadException catch (e) {
      if (mounted) setState(() => _error = 'فشل التنزيل: $e');
    } on PortalInstallOpenException catch (e) {
      if (mounted) setState(() => _error = 'تعذّر فتح شاشة التثبيت: $e');
    } catch (e) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقَّع: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _later() async {
    await PortalUpdateService.deferBuild(widget.info.latestBuildNumber);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _never() async {
    await PortalUpdateService.setNeverShow();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('يتوفّر تحديث جديد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الإصدار الجديد: ${widget.info.latestVersionName}'),
          if ((widget.info.releaseNotes ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(widget.info.releaseNotes!, style: const TextStyle(fontSize: 13)),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 6),
            Text('جارٍ التنزيل... ${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 12.5)),
          ],
        ],
      ),
      actions: _downloading
          ? const []
          : [
              TextButton(onPressed: _never, child: const Text('لا تحدّث أبدًا')),
              TextButton(onPressed: _later, child: const Text('لاحقًا')),
              ElevatedButton(onPressed: _updateNow, child: const Text('تحديث الآن')),
            ],
    );
  }
}
