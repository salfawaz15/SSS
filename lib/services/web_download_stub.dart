import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// تنفيذ التنزيل على أندرويد (تطبيق "CBA Advising"): يحفظ الملف في مجلد
/// مؤقت على الجهاز ثم يفتحه مباشرة بالتطبيق الافتراضي المناسب (عارض PDF،
/// Excel، إلخ)، تمامًا بنفس الآلية المستخدمة في تطبيق الإدارة (ReportsScreen)
/// - المستخدم يستطيع من داخل ذلك التطبيق حفظ الملف أو مشاركته كيفما شاء.
Future<void> downloadBytes(List<int> bytes, String filename) async {
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$filename');
  await file.writeAsBytes(bytes);
  await OpenFilex.open(file.path);
}
