import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

enum AdvisingReportKind {
  base, // بيانات الطلبة الأكاديمية (القاعدة + المعدل)
  basePrevious, // نسخة القاعدة قبل آخر رفعة - مصدر "النطاق السابق" للمعدل
  assigned, // طلاب تابعين لمرشد
  unassigned, // طلاب غير تابعين لمرشد
  health, // الحالة الصحية للطلبة (ذوو الإعاقة/الحالات الخاصة)
  mismatch, // طلاب على غير مرشدهم (تقرير الجامعة الرسمي - للمقارنة والتحقق)
}

extension on AdvisingReportKind {
  String get collectionName => switch (this) {
        AdvisingReportKind.base => 'advisingReports',
        AdvisingReportKind.basePrevious => 'advisingReportsPrevious',
        AdvisingReportKind.assigned => 'advisingAssignedReports',
        AdvisingReportKind.unassigned => 'advisingUnassignedReports',
        AdvisingReportKind.health => 'advisingHealthReports',
        AdvisingReportKind.mismatch => 'advisingMismatchReports',
      };
}

/// يخزّن آخر نسخة معتمدة من كل نوع تقرير إرشاد لكل شطر - نفس مبدأ
/// CourseScheduleRepository (استبدال كامل عند كل رفعة جديدة، بلا تراكم
/// تاريخي)، مع مجموعة Firestore مستقلة لكل نوع تقرير حتى لا يطغى رفع أحدها
/// على الآخر.
class AdvisingReportRepository {
  static CollectionReference<Map<String, dynamic>> _col(AdvisingReportKind kind) =>
      FirebaseFirestore.instance.collection(kind.collectionName);

  static Future<void> save(Shatr shatr, List<AdvisingCaseRecord> records, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    await _col(kind).doc(shatr.docId).set({
      'uploadedAt': FieldValue.serverTimestamp(),
      'studentsCount': records.length,
      'records': records.map((r) => r.toJson()).toList(),
    });
  }

  static Future<List<AdvisingCaseRecord>> load(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final doc = await _col(kind).doc(shatr.docId).get();
    if (!doc.exists) return [];
    final list = doc.data()?['records'] as List<dynamic>? ?? [];
    return list.map((e) => AdvisingCaseRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<DateTime?> currentUploadDate(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final doc = await _col(kind).doc(shatr.docId).get();
    final ts = doc.data()?['uploadedAt'] as Timestamp?;
    return ts?.toDate();
  }

  /// تفريغ كامل لتقرير معيّن لشطر واحد - لتسهيل إعادة الاختبار.
  static Future<void> clear(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    await _col(kind).doc(shatr.docId).delete();
  }

  /// يُستدعى قبل استبدال تقرير "بيانات الطلبة" (القاعدة) مباشرة: ينقل النسخة
  /// الحالية (قبل الاستبدال) إلى "النسخة السابقة" - مصدر "النطاق السابق"
  /// للمعدل في الرفعة القادمة. أول رفعة لا نطاق سابق لها (طبيعي للمواقع
  /// الجديدة)، ويبدأ الظهور من الفصل الذي يليها تلقائيًا.
  static Future<void> promoteBaseToPrevious(Shatr shatr) async {
    final current = await load(shatr, kind: AdvisingReportKind.base);
    if (current.isEmpty) return;
    await save(shatr, current, kind: AdvisingReportKind.basePrevious);
  }
}
