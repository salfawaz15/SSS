import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

/// يغلّف أي شاشة بتطبيق الجوال بشارة تحديث نابضة (غير جامدة) تظهر تلقائيًا
/// فور توفّر إصدار أحدث من `app_config/cba_advising` بـFirestore - بطلب
/// سليمان صراحةً (2026-08-08): "يوضح إذا فيه تحديث يكون غير جامد، وإذا
/// ضغطت تحديث يحدّث آخر نسخة من داخل التطبيق" (بدل شارة تحميل ثابتة تفتح
/// المتصفح خارجيًا كما كانت الحالة سابقًا على الموقع فقط - انظر
/// `_buildAndroidDownloadBadge` في admin_workspace_screen.dart).
///
/// التنزيل والتثبيت يحدثان من داخل التطبيق فعليًا (`AppUpdateService.
/// downloadApk` ثم `OpenFilex.open`) - لكن أندرويد نفسه يطلب من المستخدم
/// تأكيد التثبيت يدويًا (نافذة نظام "تثبيت التطبيق؟") لأسباب أمنية لا يمكن
/// تجاوزها برمجيًا مهما كان التطبيق، هذا خارج تحكّم أي كود.
class AppUpdateBanner extends StatefulWidget {
  const AppUpdateBanner({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  UpdateCheckResult? _result;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      AppUpdateService.checkForUpdate().then((r) {
        if (mounted && r.hasUpdate) setState(() => _result = r);
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startUpdate() async {
    final apkUrl = _result?.apkUrl;
    if (apkUrl == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final path = await AppUpdateService.downloadApk(apkUrl, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تنزيل التحديث: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result == null) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _downloading ? null : _startUpdate,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) => Transform.scale(
                    scale: _downloading ? 1 : 1 + (_pulseController.value * 0.02),
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        _downloading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  value: _progress > 0 ? _progress : null,
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.system_update_outlined, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _downloading ? 'جارٍ تنزيل التحديث... ${(_progress * 100).toStringAsFixed(0)}%' : 'يتوفر تحديث جديد',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              if (!_downloading)
                                Text(
                                  'الإصدار ${_result!.latestVersionName ?? ''} - اضغط للتحديث الآن',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        if (!_downloading) const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
