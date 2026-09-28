import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/instructor_teaching_load_report.dart';

/// يخزّن تقارير "جدول المحاضرين" الرسمية (عمادة القبول والتسجيل) - مصدر
/// منفصل تمامًا عن `courseSchedules` (الحويّة)، لا يُقرأ منه ولا يُكتب إليه.
/// مستند لكل (عضو + فصل دراسي) - انظر [InstructorTeachingLoadReport.docKey].
class InstructorTeachingLoadReportRepository {
  static final _col = FirebaseFirestore.instance.collection('instructorTeachingLoadReports');
  static const _metaDocId = '_meta';

  /// رفع جديد = استبدال كامل لكل المستندات (batched writes، حد 500 كتابة لكل
  /// batch من Firestore) - نفس فكرة [CourseScheduleRepository.saveSchedule]
  /// لكن مستند مستقل لكل عضو بدل مستند واحد للشطر كله (لأن حجم هذا التقرير
  /// الإجمالي لكل الكلية قد يتجاوز حد 1 ميجابايت لمستند Firestore واحد).
  static Future<void> saveAll(List<InstructorTeachingLoadReport> reports) async {
    // تفريغ المجموعة بالكامل أولًا - رفع جديد يمثّل نسخة كاملة بديلة، لا دمجًا
    // تراكميًا (قد يبقى عضو محذوف من الملف الجديد بمستند قديم يتيم بدون هذا).
    final existing = await _col.get();
    for (var i = 0; i < existing.docs.length; i += 450) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in existing.docs.skip(i).take(450)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    for (var i = 0; i < reports.length; i += 450) {
      final batch = FirebaseFirestore.instance.batch();
      for (final r in reports.skip(i).take(450)) {
        batch.set(_col.doc(r.docKey), r.toJson());
      }
      await batch.commit();
    }

    await _col.doc(_metaDocId).set({
      'uploadedAt': FieldValue.serverTimestamp(),
      'reportsCount': reports.length,
    });
  }

  static Future<DateTime?> lastUploadedAt() async {
    final doc = await _col.doc(_metaDocId).get();
    final ts = doc.data()?['uploadedAt'] as Timestamp?;
    return ts?.toDate();
  }

  /// (تاريخ آخر رفع، عدد التقارير المخزَّنة) بقراءة واحدة لمستند الوصف -
  /// أرخص من تحميل كل المستندات لمجرد عدّها بشاشة الرفع.
  static Future<({DateTime? uploadedAt, int count})> currentMeta() async {
    final doc = await _col.doc(_metaDocId).get();
    final data = doc.data();
    final ts = data?['uploadedAt'] as Timestamp?;
    return (uploadedAt: ts?.toDate(), count: data?['reportsCount'] as int? ?? 0);
  }

  /// كل تقارير عضو بعينه (كل الفصول المخزَّنة له) - مطابقة برقم المنسوب.
  static Future<List<InstructorTeachingLoadReport>> forStaffNumber(String staffNumber) async {
    if (staffNumber.trim().isEmpty) return [];
    final snap = await _col.where('staffNumber', isEqualTo: staffNumber.trim()).get();
    return snap.docs.map((d) => InstructorTeachingLoadReport.fromJson(d.data())).toList();
  }

  /// نفس فكرة [forStaffNumber] لكن بالاسم - عند تعذّر معرفة رقم المنسوب من
  /// سياق العرض الحالي (الشاشة تعتمد أسماءً لا أرقامًا).
  static Future<List<InstructorTeachingLoadReport>> forInstructorName(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return [];
    final snap = await _col.where('instructorName', isEqualTo: cleaned).get();
    return snap.docs.map((d) => InstructorTeachingLoadReport.fromJson(d.data())).toList();
  }

  /// إجمالي ساعات كل عضو (مجموع "عبء" كل صفوف مقرراته بآخر تقرير مرفوع) -
  /// قراءة واحدة لكل الجدول، بدل استعلام منفصل لكل عضو - تُستخدَم لعرض
  /// "العبء الدراسي" بشاشات تسرد عشرات/مئات الأعضاء دفعة واحدة (مثل شاشة
  /// منسوبي الكلية) بلا حاجة لجلب كل تقرير على حدة.
  static Future<Map<String, int>> totalHoursByInstructorName() async {
    final snap = await _col.get();
    final totals = <String, int>{};
    for (final doc in snap.docs) {
      if (doc.id == _metaDocId) continue;
      final data = doc.data();
      final name = data['instructorName'] as String? ?? '';
      if (name.trim().isEmpty) continue;
      final courses = data['courses'] as List<dynamic>? ?? [];
      final total = courses.fold<double>(0, (sum, c) => sum + ((c as Map<String, dynamic>)['load'] as num? ?? 0));
      totals[name.trim()] = (totals[name.trim()] ?? 0) + total.round();
    }
    return totals;
  }
}
