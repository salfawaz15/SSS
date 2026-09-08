import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/portal_update_service.dart';
import '../widgets/portal_update_dialog.dart';

/// مُنسِّق وحيد (singleton) لفحص التحديث - يفحص عند فتح التطبيق ثم كل 6
/// ساعات دوريًا (سليمان صراحةً 2026-09-09)، ويبثّ النتيجة لكل نسخ بادجة
/// الشعار المنتشرة بكل شاشات "بوابة الإرشاد" (`PortalAppBarLogo` يُستخدَم
/// كـ`leading` بكل AppBar) بدل أن يفحص كل واحدة بمفردها.
class PortalUpdateController {
  PortalUpdateController._();
  static final instance = PortalUpdateController._();

  final ValueNotifier<PortalUpdateInfo?> latest = ValueNotifier(null);
  bool _isChecking = false;
  Timer? _timer;
  GlobalKey<NavigatorState>? _navigatorKey;

  static const _checkInterval = Duration(hours: 6);

  /// يبدأ الفحص الدوري - يُستدعى مرة واحدة من جذر التطبيق
  /// (`AdvisingPortalApp.initState`)، مع مفتاح الملّاح لعرض الحوار التلقائي
  /// بلا حاجة لـBuildContext محلي بكل شاشة.
  void start(GlobalKey<NavigatorState> navigatorKey) {
    // أندرويد فقط - iOS يمنع نظاميًا أي sideloading لملف APK (سليمان
    // صراحةً 2026-09-09)، فلا معنى لفحص تحديث لا يمكن تثبيته أصلاً.
    if (kIsWeb || !Platform.isAndroid) return;
    _navigatorKey = navigatorKey;
    unawaited(checkNow());
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => checkNow());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkNow() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      final result = await PortalUpdateService.checkForUpdate();
      latest.value = (result != null && result.hasUpdate) ? result : null;
      if (latest.value != null && await PortalUpdateService.shouldShowAutoDialog(latest.value!)) {
        _showAutoDialog(latest.value!);
      }
    } catch (_) {
      // فحص صامت - فشل الشبكة هنا لا يستحق إزعاج المستخدم بلا طلب صريح منه
      // (بخلاف الضغط اليدوي على البادجة، حيث الفشل يظهر داخل الحوار نفسه).
    } finally {
      _isChecking = false;
    }
  }

  void _showAutoDialog(PortalUpdateInfo info) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    showPortalUpdateDialog(context, info);
  }

  /// يُستدعى عند ضغط البادجة يدويًا - يُلغي "لا تحدّث أبدًا" ويعرض الحوار
  /// مباشرة بصرف النظر عن أي تأجيل سابق.
  Future<void> openDialogManually(BuildContext context) async {
    final info = latest.value;
    if (info == null) return;
    await PortalUpdateService.clearNeverShow();
    if (context.mounted) showPortalUpdateDialog(context, info);
  }
}
