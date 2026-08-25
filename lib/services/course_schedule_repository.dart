import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course_section_record.dart';

enum Shatr { male, female }

extension ShatrLabel on Shatr {
  String get label => this == Shatr.male ? 'شطر الطلاب' : 'شطر الطالبات';
  String get docId => this == Shatr.male ? 'male' : 'female';
}

/// يخزّن آخر نسخة معتمدة من جدول تسكين المقررات لكل شطر بشكل مستقل - رفع
/// جدول جديد لشطر معيّن يستبدل نسخته السابقة بالكامل، ولا يؤثر على الشطر
/// الآخر.
class CourseScheduleRepository {
  static final _col = FirebaseFirestore.instance.collection('courseSchedules');

  static Future<void> saveSchedule(
    Shatr shatr,
    List<CourseSectionRecord> records, {
    DateTime? exportDate,
  }) async {
    await _col.doc(shatr.docId).set({
      'uploadedAt': FieldValue.serverTimestamp(),
      'exportDate': exportDate == null ? null : Timestamp.fromDate(exportDate),
      'sectionsCount': records.length,
      'records': records.map((r) => r.toJson()).toList(),
    });
  }

  /// تاريخ سحب البيانات من المنظومة الداخلية للنسخة المخزّنة حاليًا (وليس
  /// تاريخ الرفع نفسه) - يُستخدم للتأكد أن كل ملف جديد أحدث من السابق.
  static Future<DateTime?> currentExportDate(Shatr shatr) async {
    final doc = await _col.doc(shatr.docId).get();
    final ts = doc.data()?['exportDate'] as Timestamp?;
    return ts?.toDate();
  }

  /// تاريخ آخر رفع فعلي للملف (بخلاف [currentExportDate] الذي يبقى فارغًا
  /// دائمًا لأن `runUploadCourses` لا يمرّر `exportDate`) - هذا هو الحقل
  /// المناسب لعرض "آخر تحديث" بالواجهة.
  static Future<DateTime?> currentUploadedAt(Shatr shatr) async {
    final doc = await _col.doc(shatr.docId).get();
    final ts = doc.data()?['uploadedAt'] as Timestamp?;
    return ts?.toDate();
  }

  static Future<List<CourseSectionRecord>> loadSchedule(Shatr shatr) async {
    final doc = await _col.doc(shatr.docId).get();
    if (!doc.exists) return [];
    final data = doc.data();
    final list = data?['records'] as List<dynamic>? ?? [];
    return list.map((e) => CourseSectionRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// تفريغ كامل لجدول شطر معيّن - لتسهيل إعادة الاختبار (رفع ملف بنفس تاريخ
  /// السحب أو أقدم يُرفض عادةً بسبب فحص "أحدث من السابق").
  static Future<void> clear(Shatr shatr) async {
    await _col.doc(shatr.docId).delete();
  }
}
