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

  /// مستند Firestore محدود بـ1 ميجابايت - تقرير "طلاب تابعين لمرشد" الآن
  /// يُقرأ من PDF مباشرة ويغطي الكلية كاملة دفعة واحدة (آلاف السجلات لكل
  /// شطر، بخلاف التحويل اليدوي السابق الذي كان غالبًا أصغر)، فتجاوز الحد
  /// فعليًا وفشل الحفظ. السجلات تُقسَّم الآن لقطع (`chunks`) في مجموعة فرعية
  /// تحت مستند كل شطر بدل حقل مصفوفة واحد بالمستند نفسه.
  static const int _chunkSize = 400;

  static Future<void> save(Shatr shatr, List<AdvisingCaseRecord> records, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final docRef = _col(kind).doc(shatr.docId);
    final chunksRef = docRef.collection('chunks');
    final oldChunks = await chunksRef.get();

    final batch = FirebaseFirestore.instance.batch();
    for (final d in oldChunks.docs) {
      batch.delete(d.reference);
    }
    batch.set(docRef, {
      'uploadedAt': FieldValue.serverTimestamp(),
      'studentsCount': records.length,
    });
    for (var i = 0; i < records.length; i += _chunkSize) {
      final chunk = records.sublist(i, i + _chunkSize > records.length ? records.length : i + _chunkSize);
      batch.set(chunksRef.doc(i.toString()), {'records': chunk.map((r) => r.toJson()).toList()});
    }
    await batch.commit();
  }

  static Future<List<AdvisingCaseRecord>> load(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final docRef = _col(kind).doc(shatr.docId);
    final chunksSnap = await docRef.collection('chunks').get();

    if (chunksSnap.docs.isEmpty) {
      // توافق مع بيانات مخزَّنة بالطريقة القديمة (حقل `records` مباشرةً
      // بالمستند نفسه، قبل التقسيم لقطع).
      final doc = await docRef.get();
      final list = doc.data()?['records'] as List<dynamic>? ?? [];
      return list.map((e) => AdvisingCaseRecord.fromJson(e as Map<String, dynamic>)).toList();
    }

    final sortedChunks = chunksSnap.docs.toList()
      ..sort((a, b) => (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0));
    final result = <AdvisingCaseRecord>[];
    for (final d in sortedChunks) {
      final list = d.data()['records'] as List<dynamic>? ?? [];
      result.addAll(list.map((e) => AdvisingCaseRecord.fromJson(e as Map<String, dynamic>)));
    }
    return result;
  }

  static Future<DateTime?> currentUploadDate(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final doc = await _col(kind).doc(shatr.docId).get();
    final ts = doc.data()?['uploadedAt'] as Timestamp?;
    return ts?.toDate();
  }

  /// تفريغ كامل لتقرير معيّن لشطر واحد - لتسهيل إعادة الاختبار.
  static Future<void> clear(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final docRef = _col(kind).doc(shatr.docId);
    final chunksSnap = await docRef.collection('chunks').get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in chunksSnap.docs) {
      batch.delete(d.reference);
    }
    batch.delete(docRef);
    await batch.commit();
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
