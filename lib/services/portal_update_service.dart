import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نتيجة فحص وجود تحديث لتطبيق "بوابة الإرشاد" - مصدر المعرفة هو GitHub
/// Releases API لنفس المستودع مباشرة (بلا وسيط Firestore)، بطلب سليمان
/// صراحةً (2026-09-09): استُبدِل بها نظام تحديث "CBA Advising" القديم
/// (المحذوف بالكامل) المعتمِد على مستند Firestore.
///
/// يعيش بـ`lib/services/` (لا `lib/mobile_portal/services/`) لأنه مُستخدَم
/// من مكانين: التطبيق نفسه (فحص/تنزيل/تثبيت تلقائي) وزر "تحميل تطبيق
/// الجوال" العائم بلوحة الإدارة على الموقع (`admin_workspace_screen.dart` -
/// قراءة فقط، بلا تنزيل/تثبيت من داخل المتصفح).
class PortalUpdateInfo {
  final int currentBuildNumber;
  final int latestBuildNumber;
  final String latestVersionName;
  final String apkUrl;
  final String? releaseNotes;

  const PortalUpdateInfo({
    required this.currentBuildNumber,
    required this.latestBuildNumber,
    required this.latestVersionName,
    required this.apkUrl,
    this.releaseNotes,
  });

  bool get hasUpdate => latestBuildNumber > currentBuildNumber;
}

/// فشل التنزيل نفسه (شبكة/انقطاع) - مختلف عمدًا عن [PortalInstallOpenException]
/// حتى تعرض الواجهة رسالة مناسبة لكل حالة بدل فشل صامت موحَّد.
class PortalUpdateDownloadException implements Exception {
  final String message;
  const PortalUpdateDownloadException(this.message);
  @override
  String toString() => message;
}

/// نجح التنزيل لكن تعذّر فتح شاشة تثبيت أندرويد (مثلاً لا يوجد أي تطبيق
/// يتعامل مع APK - نادر لكن ممكن على بعض الأجهزة المعدَّلة).
class PortalInstallOpenException implements Exception {
  final String message;
  const PortalInstallOpenException(this.message);
  @override
  String toString() => message;
}

class PortalUpdateService {
  static const _repoOwner = 'salfawaz15';
  static const _repoName = 'SSS';
  static const _apkFileName = 'app-update.apk';

  static const _prefKeyNeverBuild = 'portal_update_never_show'; // bool
  static const _prefKeyDeferredBuild = 'portal_update_deferred_build'; // int

  /// يفحص GitHub Releases API مباشرة (`GET /repos/$owner/$repo/releases/latest`)
  /// ويقارن رقم البناء (لا رقم النسخة الظاهر فقط - رفعة جديدة قد لا تغيّره)
  /// بالبناء الحالي عبر [PackageInfo]. يرجع `null` إن لم يوجد أي إصدار منشور
  /// بعد (404 - حالة طبيعية، وليست خطأ) أو لم يوجد مرفق APK بالإصدار.
  static Future<PortalUpdateInfo?> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    final uri = Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest');
    final response = await http.get(uri, headers: {'accept': 'application/vnd.github+json'});

    if (response.statusCode == 404) return null; // لا يوجد أي إصدار منشور بعد
    if (response.statusCode != 200) {
      throw Exception('تعذّر الاتصال بخادم التحديثات (رمز ${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = (data['tag_name'] ?? '').toString(); // "vX.Y.Z+buildNumber"
    final withoutV = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    final parts = withoutV.split('+');
    if (parts.length != 2) return null; // وسم لا يطابق الصيغة المتوقَّعة
    final versionName = parts[0];
    final latestBuild = int.tryParse(parts[1]);
    if (latestBuild == null) return null;

    final assets = (data['assets'] as List?) ?? const [];
    String? apkUrl;
    // يُفضَّل مرفق اسمه يحتوي "portal" صراحةً (لتمييزه لو رُفِع APK لتطبيق
    // آخر لنفس الإصدار مستقبلاً) - وإلا أول مرفق ينتهي بـ.apk كحل احتياطي
    // آمن حين لا يوجد لبس (مرفق واحد فقط بالإصدار).
    for (final asset in assets) {
      final name = (asset['name'] ?? '').toString();
      if (name.toLowerCase().endsWith('.apk') && name.toLowerCase().contains('portal')) {
        apkUrl = asset['browser_download_url']?.toString();
        break;
      }
    }
    apkUrl ??= assets
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
          orElse: () => const {},
        )['browser_download_url']
        ?.toString();

    if (apkUrl == null || apkUrl.isEmpty) return null;

    return PortalUpdateInfo(
      currentBuildNumber: currentBuild,
      latestBuildNumber: latestBuild,
      latestVersionName: versionName,
      apkUrl: apkUrl,
      releaseNotes: (data['body'] ?? '').toString().trim().isEmpty ? null : data['body'].toString().trim(),
    );
  }

  /// يحل رابط تنزيل مرفق GitHub Release (`github.com/.../releases/download/...`)
  /// لرابط الملف المباشر الفعلي عبر متابعة تحويلة الخادم (302) يدويًا - يُستخدَم
  /// فقط من زر تحميل الموقع (`launchUrl` خارجي بالمتصفح) لأن أندرويد يفتح
  /// روابط github.com بتطبيق GitHub الرسمي (إن كان مثبَّتًا) بدل المتصفح،
  /// وتطبيق GitHub يطلب تسجيل دخول حتى لملف عام (سليمان 2026-08-09). التنزيل
  /// الداخلي بالتطبيق نفسه ([downloadApk]) لا يحتاج هذا - طلب HTTP مباشر
  /// يتبع أي تحويلة تلقائيًا بلا فتح متصفح. يرجع [fallbackUrl] نفسه لو تعذّر
  /// الحل (لا يكسر شيئًا، فقط لا يحسّنه).
  static Future<String> resolveDirectDownloadUrl(String fallbackUrl) async {
    try {
      final request = http.Request('GET', Uri.parse(fallbackUrl))..followRedirects = false;
      final response = await http.Client().send(request);
      final location = response.headers['location'];
      return (location != null && location.isNotEmpty) ? location : fallbackUrl;
    } catch (_) {
      return fallbackUrl;
    }
  }

  /// ينزّل ملف APK إلى مجلد وثائق التطبيق (`getApplicationDocumentsDirectory`)
  /// باسم ثابت (يحذف أي نسخة سابقة أولاً)، مع استدعاء [onProgress] (0 إلى 1)
  /// تدريجيًا. يرمي [PortalUpdateDownloadException] عند فشل الشبكة/انقطاعها.
  static Future<File> downloadApk(String apkUrl, {void Function(double progress)? onProgress}) async {
    final File file;
    try {
      final dir = await getApplicationDocumentsDirectory();
      file = File('${dir.path}/$_apkFileName');
      if (await file.exists()) await file.delete();

      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        throw PortalUpdateDownloadException('تعذّر تنزيل ملف التحديث (رمز ${response.statusCode})');
      }

      final total = response.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await response.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
        return chunk;
      }).pipe(sink);
      await sink.close();

      if (total > 0 && received != total) {
        await file.delete();
        throw const PortalUpdateDownloadException(
          'التنزيل غير مكتمل - تحقّق من اتصال الإنترنت وأعد المحاولة',
        );
      }
    } on PortalUpdateDownloadException {
      rethrow;
    } catch (e) {
      throw PortalUpdateDownloadException('تعذّر تنزيل ملف التحديث: $e');
    }
    return file;
  }

  /// يفتح شاشة تثبيت أندرويد القياسية للملف المنزَّل. أندرويد نفسه يطلب
  /// صلاحية "التثبيت من مصادر غير معروفة" تلقائيًا أول مرة - سلوك نظام
  /// التشغيل، لا شيء يُبنى هنا. يرمي [PortalInstallOpenException] لو تعذّر
  /// فتح أي مثبّت (لا يوجد تطبيق يتعامل مع APK مثلاً).
  static Future<void> openInstaller(File apkFile) async {
    final result = await OpenFilex.open(apkFile.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw PortalInstallOpenException(result.message.isNotEmpty ? result.message : 'تعذّر فتح شاشة التثبيت');
    }
  }

  /// تنزيل ثم فتح المثبّت مباشرة - الاستخدام المعتاد من الواجهة.
  static Future<void> downloadAndInstall(String apkUrl, {void Function(double progress)? onProgress}) async {
    final file = await downloadApk(apkUrl, onProgress: onProgress);
    await openInstaller(file);
  }

  /// "لا تحدّث أبدًا" - يُخفي الحوار التلقائي كليًا حتى يضغط المستخدم البادجة
  /// يدويًا (انظر [clearNeverShow]).
  static Future<void> setNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyNeverBuild, true);
  }

  static Future<bool> getNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyNeverBuild) ?? false;
  }

  /// يُستدعى عند ضغط البادجة يدويًا - يُلغي خيار "لا تحدّث أبدًا" السابق.
  static Future<void> clearNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyNeverBuild);
  }

  /// "لاحقًا" - يُخفى الحوار لهذا البناء تحديدًا فقط، ويظهر مجددًا تلقائيًا
  /// مع أي بناء أحدث لاحقًا.
  static Future<void> deferBuild(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyDeferredBuild, buildNumber);
  }

  static Future<int?> getDeferredBuild() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefKeyDeferredBuild);
  }

  /// هل يجب عرض الحوار التلقائي لهذا التحديث؟ (بادجة الإشعار الصغيرة تظهر
  /// دائمًا بصرف النظر عن هذا الفحص - فقط الحوار التلقائي يحترم التفضيلات).
  static Future<bool> shouldShowAutoDialog(PortalUpdateInfo info) async {
    if (await getNeverShow()) return false;
    final deferred = await getDeferredBuild();
    if (deferred != null && deferred >= info.latestBuildNumber) return false;
    return true;
  }
}
