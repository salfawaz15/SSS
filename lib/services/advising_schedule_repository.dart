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
}
