import 'dart:convert' show jsonEncode, utf8;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

enum AdvisingReportKind {
  base, // بيانات الطلبة الأكاديمية (القاعدة + المعدل) - مجمَّدة حاليًا، بلا حذف
  basePrevious, // نسخة القاعدة قبل آخر رفعة - مصدر "النطاق السابق" للمعدل
  assigned, // طلاب تابعين لمرشد (قديم - غير مستخدَم من واجهة الرفع الحالية)
  unassigned, // طلاب غير تابعين لمرشد (قديم - غير مستخدَم من واجهة الرفع الحالية)
  health, // الحالة الصحية للطلبة (ذوو الإعاقة/الحالات الخاصة)
  mismatch, // طلاب على غير مرشدهم (قديم - غير مستخدَم من واجهة الرفع الحالية)

  /// تقرير "طلاب تابعين لمرشد" الرسمي **غير مفلتَر** (كل كليات الجامعة، لا
  /// كليتنا فقط) - المصدر الوحيد الحالي لتوزيع الطلبة على المرشدين، يُرفع
  /// أسبوعيًا. يحل محل base/assigned/unassigned/mismatch مجتمعة لهذا الغرض.
  allColleges,

  /// نسخة [allColleges] قبل آخر رفعة - مصدر مقارنة "حركات الإرشاد" (تغيّر
  /// مرشد الطالب بين رفعتين متتاليتين).
  allCollegesPrevious,
}

extension on AdvisingReportKind {
  String get collectionName => switch (this) {
        AdvisingReportKind.base => 'advisingReports',
        AdvisingReportKind.basePrevious => 'advisingReportsPrevious',
        AdvisingReportKind.assigned => 'advisingAssignedReports',
        AdvisingReportKind.unassigned => 'advisingUnassignedReports',
        AdvisingReportKind.health => 'advisingHealthReports',
        AdvisingReportKind.mismatch => 'advisingMismatchReports',
        AdvisingReportKind.allColleges => 'advisingAllCollegesReports',
        AdvisingReportKind.allCollegesPrevious => 'advisingAllCollegesReportsPrevious',
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
  static const int _chunkSize = 150;

  /// يُغلِّف كل خطوة كتابة برسالة خطأ غنية بموقع الفشل وحجمه الفعلي بالبايت -
  /// أُضيف بعد أن استمر فشل الحفظ بخطأ "Transaction too big" رغم ثلاثة
  /// إصلاحات متتالية مختلفة تمامًا (تصغير حجم القطعة، عزل كل قطعة بطلب
  /// مستقل، حد أقصى لطول أي خلية) - سليمان 2026-08-18. بدل الاستمرار بالتخمين
  /// الأعمى، الرسالة التالية للخطأ ستكشف فعليًا أي خطوة تحديدًا تفشل وبأي حجم
  /// حقيقي، فإما تؤكد نظرية الحجم (وتحدد أين بالضبط) أو تنفيها تمامًا فيتضح
  /// أن السبب غير حجم البيانات إطلاقًا (مثال: قاعدة أمان Firestore، أو نوع
  /// حقل غير مدعوم كـ`NaN`/`Infinity`).
  static Future<void> _writeWithDiagnostics(String label, Map<String, dynamic> data, Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      // data قد تحوي FieldValue.serverTimestamp() (لا يقبل jsonEncode) -
      // نتجاهل فشل حساب الحجم بدل أن يطغى على رسالة الخطأ الأصلية.
      String sizeInfo = 'غير معروف';
      try {
        final bytes = utf8.encode(jsonEncode(data)).length;
        sizeInfo = '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
      } catch (_) {}
      throw Exception('فشل الحفظ عند: $label (الحجم الفعلي: $sizeInfo) - الخطأ الأصلي: $e');
    }
  }

  static Future<void> save(Shatr shatr, List<AdvisingCaseRecord> records, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final docRef = _col(kind).doc(shatr.docId);
    final chunksRef = docRef.collection('chunks');
    final oldChunks = await chunksRef.get();

    // حذف القطع القديمة: **حذف مباشر لكل قطعة على حدة (لا دفعة Firestore
    // مجمَّعة إطلاقًا)**. كانت مجمَّعة بدفعات من 450 حذفًا (ثم جُرِّب تخفيضها)
    // بافتراض أن الحذف عملية خفيفة الحجم دومًا (لا بيانات، فقط مرجع) - لكن
    // التشخيص الفعلي أثبت العكس (سليمان 2026-08-18): فشل حذف 114 قطعة فقط
    // بخطأ "Transaction too big" لـallCollegesPrevious/male، رغم أن كل
    // إصلاحات الكتابة السابقة (تصغير القطعة، عزلها، حد أقصى للخلية) لم تُختبَر
    // فعليًا بعد لأن هذه خطوة حذف سابقة لها بالتسلسل. الحذف الفردي المباشر
    // (بلا batch) يزيل أي افتراض خاطئ عن حجم عملية الحذف نفسها.
    for (final d in oldChunks.docs) {
      try {
        await d.reference.delete();
      } catch (e) {
        throw Exception('فشل حذف القطعة القديمة ${d.id} (من أصل ${oldChunks.docs.length}) لـ${kind.name}/${shatr.docId}: $e');
      }
    }

    final docData = {
      'uploadedAt': FieldValue.serverTimestamp(),
      'studentsCount': records.length,
    };
    await _writeWithDiagnostics('مستند ${kind.name}/${shatr.docId} الرئيسي', docData, () => docRef.set(docData));

    // كتابة القطع الجديدة: **دفعة Firestore مستقلة لكل قطعة على حدة** (لا
    // تجميع عدة قطع بدفعة واحدة). خُفِّض حجم القطعة نفسها إلى 150 سجلًا (كانت
    // 400)، وحتى بعد تخفيض عدد القطع بالدفعة الواحدة من 20 إلى 6 استمر فشل
    // الحفظ فعليًا بخطأ "Transaction too big" مع ملف "كل الكليات" الحقيقي
    // (سليمان 2026-08-18، مرتين متتاليتين) - أي أن حجم القطعة الفعلي أكبر
    // بكثير من التقدير الأصلي مهما قلَّ عدد القطع بالدفعة. دفعة بقطعة واحدة
    // تضمن ألا يتجاوز أي طلب حجم مستند واحد (محدود أصلًا بـ1 ميجابايت من
    // Firestore نفسها)، بصرف النظر عن حجم البيانات الفعلي لكل سجل.
    for (var i = 0; i < records.length; i += _chunkSize) {
      final chunk = records.sublist(i, i + _chunkSize > records.length ? records.length : i + _chunkSize);
      final chunkDocId = i.toString();
      final chunkData = {'records': chunk.map((r) => r.toJson()).toList()};
      await _writeWithDiagnostics(
        'قطعة $chunkDocId (${kind.name}/${shatr.docId}, سجلات $i-${i + chunk.length - 1} من ${records.length})',
        chunkData,
        () => chunksRef.doc(chunkDocId).set(chunkData),
      );
    }
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

  /// تفريغ كامل لتقرير معيّن لشطر واحد - لتسهيل إعادة الاختبار. حذف فردي
  /// مباشر لكل قطعة (لا دفعة Firestore مجمَّعة) - نفس أسلوب حذف القطع القديمة
  /// بـ[save]، بعد أن ثبت فعليًا (سليمان 2026-08-18) أن تجميع الحذف بدفعات
  /// (حتى الصغيرة نسبيًا، 100 أو أقل) قد يفشل أيضًا بخطأ "Transaction too big".
  static Future<void> clear(Shatr shatr, {AdvisingReportKind kind = AdvisingReportKind.base}) async {
    final docRef = _col(kind).doc(shatr.docId);
    final chunksSnap = await docRef.collection('chunks').get();
    for (final d in chunksSnap.docs) {
      try {
        await d.reference.delete();
      } catch (e) {
        throw Exception('فشل حذف القطعة ${d.id} (من أصل ${chunksSnap.docs.length}) لـ${kind.name}/${shatr.docId}: $e');
      }
    }
    await docRef.delete();
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

  /// نفس مبدأ [promoteBaseToPrevious] لكن لتقرير "كل الكليات" - يُستدعى قبل
  /// استبدال الرفعة الحالية مباشرة، ليبقى لدينا دومًا نسخة الرفعة السابقة
  /// كمصدر مقارنة لـ"تقرير حركات الإرشاد" (انظر
  /// [AdvisingCaseAnalyzer.detectAdvisorMovements]).
  static Future<void> promoteAllCollegesToPrevious(Shatr shatr) async {
    final current = await load(shatr, kind: AdvisingReportKind.allColleges);
    if (current.isEmpty) return;
    await save(shatr, current, kind: AdvisingReportKind.allCollegesPrevious);
  }
}
