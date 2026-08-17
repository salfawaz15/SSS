import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advising_schedule.dart';

/// يخزّن آخر نسخة معتمدة من جدول توزيع فترات الإرشاد لكل (قسم × شطر) - رفع
/// جدول جديد لقسم/شطر معيّن يستبدل نسخته السابقة بالكامل، بنفس مبدأ
/// CourseScheduleRepository.
class AdvisingScheduleRepository {
  static final _col = FirebaseFirestore.instance.collection('advisingSchedules');

  static String _docId(String department, String shatr) => '${department}_$shatr';

  static Future<void> save(String department, String shatr, List<AdvisingScheduleSlot> slots) async {
    await _col.doc(_docId(department, shatr)).set({
      'department': department,
      'shatr': shatr,
      'uploadedAt': FieldValue.serverTimestamp(),
      'slots': slots.map((s) => s.toJson()).toList(),
    });
  }

  static Future<List<AdvisingScheduleSlot>> load(String department, String shatr) async {
    final doc = await _col.doc(_docId(department, shatr)).get();
    if (!doc.exists) return [];
    final list = doc.data()?['slots'] as List<dynamic>? ?? [];
    return list.map((e) => AdvisingScheduleSlot.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// أحدث تاريخ رفع بين كل مستندات (قسم × شطر) - لعرض ملخّص واحد بصفحة "رفع
  /// ملفات" المركزية بلا حاجة لمعرفة القسم/الشطر تحديدًا مسبقًا.
  static Future<DateTime?> latestUploadDate() async {
    final snap = await _col.get();
    DateTime? latest;
    for (final doc in snap.docs) {
      final ts = doc.data()['uploadedAt'] as Timestamp?;
      final date = ts?.toDate();
      if (date != null && (latest == null || date.isAfter(latest))) latest = date;
    }
    return latest;
  }

  /// عدد مستندات (قسم × شطر) التي رُفع لها ملف فعليًا حتى الآن - لعرض عدّاد
  /// "X / 10 ملفات" بصفحة "رفع ملفات" المركزية (10 = 5 أقسام × شطرين).
  static Future<int> uploadedCount() async {
    final snap = await _col.get();
    return snap.docs.length;
  }

  /// تفريغ كامل لكل مستندات (قسم × شطر) - لتسهيل إعادة الاختبار، بنفس مبدأ
  /// تفريغ بقية تقارير الإرشاد.
  static Future<void> clearAll() async {
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
