import 'package:url_launcher/url_launcher.dart';

/// يفتح برنامج البريد الافتراضي عند المستخدم (Outlook، Gmail، تطبيق البريد
/// بالجوال...) برسالة جديدة موجَّهة لهذا العنوان، عبر رابط mailto: القياسي -
/// يعمل من التطبيق ومن بوابة الويب على حد سواء بلا أي خدمة خارجية أو تكلفة.
Future<void> openMailto(String email) async {
  final uri = Uri(scheme: 'mailto', path: email);
  await launchUrl(uri);
}
