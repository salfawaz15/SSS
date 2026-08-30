import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/firestore_ticket_service.dart' show MergeResult;

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

/// حوار "الحالات غير المطابَقة" بعد رفع ملف معالج - بطلب سليمان صراحةً
/// (2026-08-30: "كيف أعرف الحالات التي لم ترفع أو غير المطابقة؟"). قبل هذا
/// كان يُعرَض عدد مجرَّد بلا أي تفاصيل تُمكِّن المتابعة الفعلية - يعرض الآن
/// هوية كل صف فشلت مطابقته (رقم جامعي/نوع الإجراء/المقرر) حتى يمكن مراجعتها
/// يدويًا (غالبًا: طالب حُذفت حالته من الملف الأساسي، أو خطأ كتابي بالمقرر/الشعبة).
void showUnmatchedRowsDialog(BuildContext context, MergeResult result) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('الحالات غير المطابَقة'),
      content: SizedBox(
        width: 520,
        child: result.unmatchedRows.isEmpty
            ? const Text('لا توجد تفاصيل إضافية لهذه الحالات.')
            : SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('الرقم الجامعي')),
                    DataColumn(label: Text('نوع الإجراء')),
                    DataColumn(label: Text('المقرر')),
                    DataColumn(label: Text('الشعبة')),
                  ],
                  rows: [
                    for (final row in result.unmatchedRows)
                      DataRow(cells: [
                        DataCell(Text((row['university_id'] ?? '').toString())),
                        DataCell(Text((row['action_type'] ?? '').toString())),
                        DataCell(Text((row['course'] ?? '').toString())),
                        DataCell(Text((row['section'] ?? '').toString())),
                      ]),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    ),
  );
}
