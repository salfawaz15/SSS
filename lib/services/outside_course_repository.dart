import 'package:cloud_firestore/cloud_firestore.dart';

import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

/// يخزّن قائمة مواد خارج الكلية المتاحة فعليًا هذا الفصل لكل شطر - ناتجة عن
/// تقاطع القائمة الثابتة في CourseCatalog.outsideCollegeCourses مع رموز
/// المقررات الفعلية المستخرجة من ملف "حويّة" الجامعة الشامل عند كل رفعة.
class OutsideCourseRepository {
  static final _col = FirebaseFirestore.instance.collection('outsideCourses');

  static Future<void> save(Shatr shatr, List<String> options) async {
    await _col.doc(shatr.docId).set({
      'uploadedAt': FieldValue.serverTimestamp(),
      'options': options,
    });
  }

  static Future<List<String>> load(Shatr shatr) async {
    final doc = await _col.doc(shatr.docId).get();
    if (!doc.exists) return [];
    final list = doc.data()?['options'] as List<dynamic>? ?? [];
    return list.map((e) => e.toString()).toList();
  }

  static Future<DateTime?> currentUploadDate(Shatr shatr) async {
    final doc = await _col.doc(shatr.docId).get();
    final ts = doc.data()?['uploadedAt'] as Timestamp?;
    return ts?.toDate();
  }

  static Future<void> clear(Shatr shatr) async {
    await _col.doc(shatr.docId).delete();
  }
}
