import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  /// يجلب رابط وإصدار آخر نسخة منشورة مباشرةً بلا مقارنة إصدار حالي - يُستخدم
  /// من لوحة الإدارة (الموقع) لعرض زر "تحميل التطبيق" لمن لم يثبّته أصلًا بعد
  /// (بخلاف [checkForUpdate] المخصَّص لمستخدم مثبَّت لديه التطبيق فعلًا).
  static Future<({String? apkUrl, String? versionName})> getLatestRelease() async {
    final doc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('cba_advising')
        .get();
    final data = doc.data();
    return (
      apkUrl: data?['apk_url']?.toString(),
      versionName: data?['latest_version_name']?.toString(),
    );
  }

  /// يحل رابط صفحة GitHub Release (`github.com/.../releases/download/...`)
  /// لرابط الملف المباشر الفعلي (`release-assets.githubusercontent.com` أو
  /// ما شابه) عبر متابعة تحويلة الخادم (302) يدويًا بدل تركها لمتصفح
  /// الجهاز - لأن أندرويد يفتح روابط github.com بتطبيق GitHub الرسمي (إن
  /// كان مثبَّتًا) بدل المتصفح، وتطبيق GitHub يطلب تسجيل دخول لأي تفاعل حتى
  /// مع الملفات العامة، بينما الرابط النهائي المباشر لا يمر عبر github.com
  /// إطلاقًا فيُفتح بالمتصفح مباشرة ويبدأ التنزيل فورًا (سليمان 2026-08-09).
  /// يرجع [fallbackUrl] نفسه لو تعذّر الحل (لا يكسر شيئًا، فقط لا يحسّنه).
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

  /// ينزّل ملف APK من [apkUrl] لمجلد التخزين المؤقت للتطبيق، مع استدعاء
  /// [onProgress] (0 إلى 1) كل ما وصل جزء جديد من البيانات - يُستخدَم لعرض
  /// شريط تقدّم حقيقي بدل تنزيل صامت. يرجع المسار المحلي للملف الجاهز
  /// للتثبيت (يُفتح بعدها عبر `OpenFilex.open` لبدء تثبيت أندرويد القياسي).
  static Future<String> downloadApk(String apkUrl, {void Function(double progress)? onProgress}) async {
    final request = http.Request('GET', Uri.parse(apkUrl));
    final response = await http.Client().send(request);
    final total = response.contentLength ?? 0;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/cba_advising_update.apk');
    final sink = file.openWrite();

    var received = 0;
    await response.stream.map((chunk) {
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
      return chunk;
    }).pipe(sink);
    await sink.close();

    // تحقّق من اكتمال الملف قبل محاولة تثبيته - انقطاع الإنترنت أثناء
    // التنزيل ينتج ملفًا ناقصًا يفشل أندرويد بتثبيته برسالة غامضة ("يبدو
    // أن الحزمة غير صالحة") بدل توضيح أن السبب تنزيل غير مكتمل (سليمان
    // 2026-08-09) - رسالة واضحة هنا أفضل من ترك أندرويد يعطي رسالة مبهمة.
    if (total > 0 && received != total) {
      await file.delete();
      throw Exception('التنزيل غير مكتمل ($received من $total بايت) - تحقّق من اتصال الإنترنت وأعد المحاولة');
    }

    return file.path;
  }
}
