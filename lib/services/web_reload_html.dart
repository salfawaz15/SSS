import 'dart:html' as html;

/// يعيد تحميل صفحة الموقع كاملةً من الخادم (بلا استخدام أي نسخة مخبَّأة) -
/// يُستخدَم بزر تحديث النسخة عند اكتشاف إصدار أحدث منشور.
void reloadWebApp() => html.window.location.reload();
