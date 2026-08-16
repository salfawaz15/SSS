import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// حوارات مشتركة لعمليات الرفع الثقيلة (معالجة/خطأ) - مستخدَمة من صفحاتها
/// الأصلية (منسّق القسم/الكلية) ومن صفحة "رفع ملفات" المركزية معًا، حتى لا
/// يتكرر نفس الكود بمكانين قد يختلفان لاحقًا بلا قصد.

/// حوار تحميل غير قابل للإغلاق يدويًا - يظهر أثناء معالجة الملف تحديدًا (لا
/// طوال الرفع بالكامل) حتى لا يبدو للمستخدم أن الصفحة تجمَّدت بصمت. بعض
/// الملفات (مثل "كل الكليات" الذي يغطي الجامعة كاملة) قد تستغرق معالجتها
/// دقائق.
void showUploadProcessingDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

void hideUploadProcessingDialog(BuildContext context) {
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
}

/// حوار خطأ لا يختفي تلقائيًا (بخلاف SnackBar) والنص قابل للنسخ لتسهيل
/// إرساله لتشخيص المشكلة.
void showUploadErrorDialog(BuildContext context, String title, String details) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: TextStyle(color: Colors.red.shade700)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: SelectableText(details)),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: '$title\n$details'));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ نص الخطأ')));
            }
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('نسخ'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    ),
  );
}
