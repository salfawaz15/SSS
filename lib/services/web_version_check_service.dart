import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';

/// يتحقق هل يوجد إصدار ويب أحدث من النسخة المحمَّلة حاليًا بالمتصفح، عبر
/// جلب `version.json` (يُنشَر كملف ثابت مع كل بناء) من جذر الموقع نفسه -
/// بمعطى عشوائي (`cache-bust`) لتفادي أي نسخة مخبَّأة من الملف ذاته. يُقارَن
/// رقم البناء المجلوب بـ[kAppBuildNumber] المضمَّن بهذه النسخة تحديدًا (كل
/// نسخة مبنية تحمل رقمها الخاص، فلا يتغيّر أثناء التشغيل).
class WebVersionCheckService {
  static Future<bool> isNewerVersionAvailable() async {
    try {
      final uri = Uri.base.replace(
        path: '${Uri.base.path}version.json',
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestBuild = (data['build'] as num?)?.toInt();
      return latestBuild != null && latestBuild > kAppBuildNumber;
    } catch (_) {
      return false;
    }
  }
}
