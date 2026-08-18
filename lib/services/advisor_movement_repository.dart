import 'package:cloud_firestore/cloud_firestore.dart';

/// حركة إرشاد واحدة مخزَّنة بشكل دائم (تراكمي عبر كل الرفعات، لا آخر رفعتين
/// فقط) - طالب تغيّر اسم مرشده بين رفعتين متتاليتين لملف "كل الكليات"،
/// بتاريخ اكتشافها فعليًا.
class AdvisorMovementLogEntry {
  final String studentId;
  final String studentName;
  final String department;
  final String shatr;
  final String fromAdvisorNameRaw;
  final String toAdvisorNameRaw;
  final DateTime? detectedAt;

  const AdvisorMovementLogEntry({
    required this.studentId,
    required this.studentName,
    required this.department,
    required this.shatr,
    required this.fromAdvisorNameRaw,
    required this.toAdvisorNameRaw,
    this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'studentName': studentName,
        'department': department,
        'shatr': shatr,
        'fromAdvisorNameRaw': fromAdvisorNameRaw,
        'toAdvisorNameRaw': toAdvisorNameRaw,
        'detectedAt': FieldValue.serverTimestamp(),
      };

  factory AdvisorMovementLogEntry.fromDoc(Map<String, dynamic> json) => AdvisorMovementLogEntry(
        studentId: json['studentId'] as String? ?? '',
        studentName: json['studentName'] as String? ?? '',
        department: json['department'] as String? ?? '',
        shatr: json['shatr'] as String? ?? '',
        fromAdvisorNameRaw: json['fromAdvisorNameRaw'] as String? ?? '',
        toAdvisorNameRaw: json['toAdvisorNameRaw'] as String? ?? '',
        detectedAt: (json['detectedAt'] as Timestamp?)?.toDate(),
      );
}

/// سجل دائم/تراكمي لكل حركات الإرشاد المكتشَفة عبر كل رفعات "كل الكليات" -
/// بخلاف `AdvisingReportKind.allCollegesPrevious` (يحتفظ فقط بآخر نسخة سابقة
/// للمقارنة)، هذا السجل **لا يُستبدَل أبدًا** - كل رفعة جديدة تُضيف حركاتها
/// (إن وُجدت) كمستندات جديدة، فتبقى كل الحركات التاريخية متاحة دومًا مهما
/// تكررت الرفعات - بطلب سليمان صراحةً (2026-08-14): "لو عشر مرات تظهر
/// الحركات" (لا مقارنة آخر رفعتين فقط).
class AdvisorMovementRepository {
  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('advisingAdvisorMovements');

  static Future<void> appendMovements(List<AdvisorMovementLogEntry> movements) async {
    if (movements.isEmpty) return;
    const perBatch = 450;
    for (var i = 0; i < movements.length; i += perBatch) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + perBatch < movements.length) ? i + perBatch : movements.length;
      for (var j = i; j < end; j++) {
        batch.set(_col.doc(), movements[j].toJson());
      }
      try {
        await batch.commit();
      } catch (e) {
        throw Exception('فشل حفظ حركات الإرشاد $i-${end - 1} من ${movements.length} حركة: $e');
      }
    }
  }

  static Future<List<AdvisorMovementLogEntry>> loadAll() async {
    final snap = await _col.orderBy('detectedAt', descending: true).get();
    return snap.docs.map((d) => AdvisorMovementLogEntry.fromDoc(d.data())).toList();
  }

  /// تفريغ كامل للسجل التراكمي - بطلب سليمان الصريح (2026-08-15)، لتسهيل
  /// إعادة الاختبار (نفس مبدأ "تفريغ البيانات" لبقية تقارير الإرشاد). دفعات
  /// صغيرة متتالية (لا دفعة واحدة ضخمة) لأن السجل تراكمي وقد يتجاوز حد
  /// Firestore الأقصى (500 عملية/دفعة) مع مرور الوقت.
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
