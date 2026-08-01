import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// نتيجة التحقق من توفر تحديث لتطبيق CBA Advising.
class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersionName;
  final String? latestVersionName;
  final String? apkUrl;
  final String? releaseNotes;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersionName,
    this.latestVersionName,
    this.apkUrl,
    this.releaseNotes,
  });
}

/// يتحقق من توفر إصدار أحدث لتطبيق CBA Advising عبر مقارنة رقم البناء
/// الحالي للتطبيق (PackageInfo) بالرقم المنشور في Firestore
/// (app_config/cba_advising)، بدل الاعتماد على متجر تطبيقات خارجي - مناسب
/// لتوزيع داخلي بملف APK مباشر.
class AppUpdateService {
  static Future<UpdateCheckResult> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    final doc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('cba_advising')
        .get();

    final data = doc.data();
    if (data == null) {
      return UpdateCheckResult(hasUpdate: false, currentVersionName: info.version);
    }

    final latestBuild = (data['latest_version_code'] as num?)?.toInt() ?? 0;
    final latestVersionName = data['latest_version_name']?.toString();
    final apkUrl = data['apk_url']?.toString();
    final releaseNotes = data['release_notes']?.toString();

    return UpdateCheckResult(
      hasUpdate: latestBuild > currentBuild && (apkUrl?.isNotEmpty ?? false),
      currentVersionName: info.version,
      latestVersionName: latestVersionName,
      apkUrl: apkUrl,
      releaseNotes: releaseNotes,
    );
  }
}
