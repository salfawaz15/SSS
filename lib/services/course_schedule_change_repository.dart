import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course_schedule_change.dart';

/// سجل دائم/تراكمي لكل تغييرات جدول المقررات المكتشَفة عبر كل رفعات "رفع
/// المقررات الدراسية" - كل رفعة تُضيف تغييراتها (إن وُجدت) كمستندات جديدة،
/// لا استبدال، بنفس مبدأ AdvisorMovementRepository لتقرير حركات الإرشاد.
class CourseScheduleChangeRepository {
  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('courseScheduleChanges');

  static Future<void> appendChanges(List<CourseScheduleChangeEntry> changes) async {
    if (changes.isEmpty) return;
    const perBatch = 450;
    for (var i = 0; i < changes.length; i += perBatch) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + perBatch < changes.length) ? i + perBatch : changes.length;
      for (var j = i; j < end; j++) {
        batch.set(_col.doc(), changes[j].toJson());
      }
      await batch.commit();
    }
  }

  static Future<List<CourseScheduleChangeEntry>> loadAll() async {
    final snap = await _col.orderBy('detectedAt', descending: true).get();
    return snap.docs.map((d) => CourseScheduleChangeEntry.fromDoc(d.data())).toList();
  }

  /// تفريغ كامل للسجل التراكمي - لتسهيل إعادة الاختبار، بنفس مبدأ تفريغ
  /// بقية تقارير الإرشاد.
  static Future<void> clear() async {
    final snap = await _col.get();
    const perBatch = 450;
    final docs = snap.docs;
    for (var i = 0; i < docs.length; i += perBatch) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + perBatch < docs.length) ? i + perBatch : docs.length;
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
  }
}
