import 'dart:html' as html;

/// ينزّل بايتات كملف عبر متصفح الويب (Blob + رابط تنزيل وهمي بالنقر التلقائي).
/// النوع `Future<void>` (لا void مباشرة) ليطابق تنفيذ الأندرويد في
/// web_download_stub.dart - بعض إصدارات مترجم الويب لا تقبل `await` على
/// تعبير من نوع void مباشرة.
Future<void> downloadBytes(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
