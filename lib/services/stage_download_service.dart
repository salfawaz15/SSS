import 'package:cloud_firestore/cloud_firestore.dart';

/// يسجّل لحظة أول تنزيل لملف كل مرحلة (مرشد/منسّق قسم) لكل قسم-شطر - نقطة
/// انطلاق حساب "التأخر" بلوحة الإدارة (بطلب سليمان صراحةً 2026-08-20: "من
/// تاريخ تنزيل الملف يبدأ العدّ" لا تاريخ رفع الفورمز). منسّق الكلية بلا
/// مهلة زمنية إطلاقًا فلا يُسجَّل له شيء هنا.
///
/// يُكتَب من نقطتَي التنزيل الحقيقيتين معًا (شاشة المنسّق الفعلية
/// `coordinator_workspace_screen.dart` والمسار الاحتياطي الشامل بصفحة
/// "رفع وتنزيل الملفات") - كلاهما يكتب لنفس المستند بمفتاح شطر-قسم واحد،
/// و`merge: true` يحفظ أول تنزيل فقط (لا يُستبدَل بتنزيلات لاحقة لنفس
/// المرحلة، فالمهلة تُحسب من أول استلام فعلي للملف لا كل مرة يُعاد تنزيله).
class StageDownloadService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('stage_downloads');

  static String _docId(String shatr, String department) => '${shatr}_$department';

  static Future<void> recordAdvisorDownload({
    required String shatr,
    required String department,
  }) async {
    final ref = _col.doc(_docId(shatr, department));
    final doc = await ref.get();
    if (doc.exists && doc.data()?['advisor_downloaded_at'] != null) return;
    await ref.set({
      'shatr': shatr,
      'department': department,
      'advisor_downloaded_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> recordCoordinatorDownload({
    required String shatr,
    required String department,
  }) async {
    final ref = _col.doc(_docId(shatr, department));
    final doc = await ref.get();
    if (doc.exists && doc.data()?['coordinator_downloaded_at'] != null) return;
    await ref.set({
      'shatr': shatr,
      'department': department,
      'coordinator_downloaded_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// تدفّق كل سجلات التنزيل (للوحة الإدارة) - مفهرسة بمفتاح شطر-قسم.
  static Stream<Map<String, Map<String, dynamic>>> watchAll() {
    return _col.snapshots().map((s) => {for (final d in s.docs) d.id: d.data()});
  }

  /// يمسح سجل تنزيل قسم-شطر واحد (يُستدعى مع "تفريغ حالة القسم" حتى لا تبقى
  /// مهلة دورة سابقة سارية على دورة حذف/إضافة جديدة).
  static Future<void> clear({required String shatr, required String department}) =>
      _col.doc(_docId(shatr, department)).delete();
}
