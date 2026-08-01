import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/coordinator.dart';

/// طبقة وصول Firestore لبيانات منسّقي الأقسام (اسم + بريد إلكتروني رسمي لكل
/// قسم × شطر) - مشتركة بين لوحة الإدارة (تعديل) والصفحة الرئيسية العامة
/// (عرض فقط)، وبين الموقع وتطبيق CBA Advising لأنهما يشتركان في نفس قاعدة
/// Firebase. منفصلة تمامًا عن CoordinatorService المحلي (SharedPreferences)
/// المستخدم في تطبيق الأندرويد القديم.
class FirestoreCoordinatorService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('coordinator_contacts');

  static String _docId(String shatr, String department) {
    return '$shatr|$department';
  }

  /// تدفّق حي بكل بيانات المنسّقين المحفوظة، مفهرسة بمفتاح Coordinator.key.
  static Stream<Map<String, Coordinator>> watchAll() {
    return _col.snapshots().map((snap) {
      final map = <String, Coordinator>{};
      for (final doc in snap.docs) {
        final c = Coordinator.fromJson(doc.data());
        map[c.key] = c;
      }
      return map;
    });
  }

  /// يحفظ دفعة كاملة (كل الأقسام العشرة) دفعة واحدة - للإدارة فقط (تُطبَّق
  /// أيضًا قواعد أمان Firestore).
  static Future<void> saveAll(Map<String, Coordinator> coordinators) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final c in coordinators.values) {
      batch.set(_col.doc(_docId(c.shatr, c.department)), c.toJson());
    }
    await batch.commit();
  }
}
