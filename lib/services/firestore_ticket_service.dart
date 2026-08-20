import 'package:cloud_firestore/cloud_firestore.dart';

class MergeResult {
  final int matchedCount;
  final int unmatchedCount;

  const MergeResult({required this.matchedCount, required this.unmatchedCount});
}

/// طبقة وصول Firestore الخاصة ببوابة الويب فقط (إدارة + منسقين) - منفصلة
/// تمامًا عن TicketRepository المحلي (SharedPreferences) المستخدم في تطبيق
/// الأندرويد، حتى لا يتأثر الأخير بأي تعديل هنا.
class FirestoreTicketService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('tickets');

  /// يستبدل كل التذاكر الحالية بدفعة جديدة (أول رفع في دورة حذف وإضافة جديدة
  /// - بداية نظيفة) - للإدارة فقط.
  static Future<void> replaceAllTickets(
    List<Map<String, dynamic>> tickets,
  ) async {
    await clearAll();

    final batch = FirebaseFirestore.instance.batch();
    for (final t in tickets) {
      final id = (t['university_id'] ?? '').toString();
      if (id.isEmpty) continue;
      batch.set(_col.doc(id), t);
    }
    await batch.commit();
  }

  /// يضيف فقط التذاكر الجديدة (رفعات اليوم الثاني/الثالث من نفس الدورة) دون
  /// مسح أي شيء - تصدير Microsoft Forms تراكمي (يحتوي كل الطلبات منذ الفتح
  /// الأول)، فأي رقم جامعي موجود مسبقًا يُتجاهل تمامًا حفاظًا على أي عمل
  /// أنجزه المرشد/المنسّق عليه، ويُضاف فقط من هو جديد فعليًا. يرجّع عدد
  /// التذاكر الجديدة المُضافة فعليًا (للتنبيه في واجهة الرفع).
  static Future<int> addNewTickets(
    List<Map<String, dynamic>> tickets,
  ) async {
    final existingSnap = await _col.get();
    final existingIds = existingSnap.docs.map((d) => d.id).toSet();

    final newTickets = tickets.where((t) {
      final id = (t['university_id'] ?? '').toString();
      return id.isNotEmpty && !existingIds.contains(id);
    }).toList();

    final batch = FirebaseFirestore.instance.batch();
    for (final t in newTickets) {
      final id = (t['university_id'] ?? '').toString();
      batch.set(_col.doc(id), t);
    }
    await batch.commit();

    return newTickets.length;
  }

  static Future<void> clearAll() async {
    final snap = await _col.get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// تدفّق كل التذاكر (للإدارة).
  static Stream<List<Map<String, dynamic>>> watchAllTickets() {
    return _col.snapshots().map((s) => s.docs.map((d) => d.data()).toList());
  }

  /// تدفّق تذاكر قسم/شطر واحد فقط (للمنسّق - يطابقه أيضًا قواعد أمان Firestore).
  static Stream<List<Map<String, dynamic>>> watchDepartmentTickets({
    required String shatr,
    required String department,
  }) {
    return _col
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: department)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  /// تدفّق كل تذاكر شطر واحد عبر الأقسام الخمسة مجتمعة (لمنسّق/ة الكلية -
  /// المستوى الثالث في مسار التصعيد) - يطابقه أيضًا قواعد أمان Firestore
  /// (isCollegeCoordinatorFor).
  static Stream<List<Map<String, dynamic>>> watchShatrTickets({
    required String shatr,
  }) {
    return _col
        .where('shatr', isEqualTo: shatr)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  static String _actionKey(
    String universityId,
    String actionType,
    String course,
    String section,
  ) {
    return '$universityId|$actionType|$course|$section';
  }

  // خلل حقيقي مُصحَّح (سليمان 2026-08-20): ExcelParserService يكتب
  // 'required_section': '' صراحةً (نص فارغ لا null) لكل إجراء "حذف" -
  // عامل `??` لا يتخطى النص الفارغ، يتخطى فقط null، فكانت هذه الدالة تُرجع
  // '' دائمًا لكل حذف بدل الرجوع لـcurrent_section، فيفشل مفتاح المطابقة
  // (uid|النوع|المقرر|الشعبة) دائمًا لأي ملف معالجة يعيد قسم "رقم الشعبة"
  // الفعلي لحالة حذف - أي رفع حقيقي لحالات حذف كان لا يُطابَق أبدًا.
  static String _ticketActionSection(Map<String, dynamic> action) {
    final required = (action['required_section'] ?? '').toString();
    if (required.isNotEmpty) return required;
    return (action['current_section'] ?? '').toString();
  }

  /// يدمج صفوف ملف معالج عائد من المرشدين، مقصورًا على قسم/شطر واحد فقط
  /// (المنسّق لا يستطيع أصلاً قراءة/تعديل أي وثيقة خارج قسمه - قواعد الأمان
  /// تمنع ذلك بنيويًا حتى لو تم تجاوز هذا الفلترة الاحترازية هنا).
  static Future<MergeResult> mergeProcessedRows(
    List<Map<String, dynamic>> processedRows, {
    required String shatr,
    required String department,
  }) async {
    final snap = await _col
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: department)
        .get();
    return _mergeProcessedRowsIntoDocs(processedRows, snap.docs);
  }

  /// نفس دمج الملف المعالَج لكن على مستوى شطر كامل (كل الأقسام الخمسة) -
  /// لمنسّق/ة الكلية (المستوى الثالث في مسار التصعيد)، تحكمه أيضًا قواعد
  /// أمان Firestore (isCollegeCoordinatorFor).
  static Future<MergeResult> mergeProcessedRowsForShatr(
    List<Map<String, dynamic>> processedRows, {
    required String shatr,
  }) async {
    final snap = await _col.where('shatr', isEqualTo: shatr).get();
    return _mergeProcessedRowsIntoDocs(processedRows, snap.docs);
  }

  /// دمج على مستوى **كل الأقسام وكلا الشطرين معًا** بدفعة واحدة - إجراء
  /// وقائي/احتياطي لإدارة الوحدة لرفع ملفات معالجة نيابةً عن أي مرشد/منسّق
  /// قسم/منسّق كلية غائب، بلا حاجة لتحديد قسم أو شطر يدويًا لكل ملف (بطلب
  /// سليمان صراحةً 2026-08-20، صفحة "رفع ملفات"). كل صف يُطابَق بمفتاحه
  /// الخاص (رقم جامعي/نوع/مقرر/شعبة) بصرف النظر عن قسمه أو شطره.
  static Future<MergeResult> mergeAllProcessedRows(
    List<Map<String, dynamic>> processedRows,
  ) async {
    final snap = await _col.get();
    return _mergeProcessedRowsIntoDocs(processedRows, snap.docs);
  }

  static Future<MergeResult> _mergeProcessedRowsIntoDocs(
    List<Map<String, dynamic>> processedRows,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final ticketsData = <String, Map<String, dynamic>>{
      for (final doc in docs) doc.id: Map<String, dynamic>.from(doc.data()),
    };

    final actionIndex = <String, Map<String, dynamic>>{};
    // فهرس مفتاح-الإجراء -> رقم مستند التذكرة المالكة له، حتى نكتب فقط
    // المستندات التي تغيّرت فعليًا بدل كل تذاكر القسم في كل مرة (كانت الدفعة
    // تشمل كل تذكرة بلا استثناء حتى لو لم تُطابَق - إبطاء وكتابات غير
    // ضرورية، سليمان 2026-08-09).
    final actionOwnerDocId = <String, String>{};
    for (final entry in ticketsData.entries) {
      final ticket = entry.value;
      final universityId = (ticket['university_id'] ?? '').toString();
      if (universityId.isEmpty) continue;

      final actions = (ticket['actions'] as List?) ?? [];
      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final key = _actionKey(
          universityId,
          (action['action_type'] ?? '').toString(),
          (action['course'] ?? '').toString(),
          _ticketActionSection(action),
        );
        actionIndex.putIfAbsent(key, () => action);
        actionOwnerDocId.putIfAbsent(key, () => entry.key);
      }
    }

    var matched = 0;
    var unmatched = 0;
    final changedDocIds = <String>{};

    for (final row in processedRows) {
      final key = _actionKey(
        (row['university_id'] ?? '').toString(),
        (row['action_type'] ?? '').toString(),
        (row['course'] ?? '').toString(),
        (row['section'] ?? '').toString(),
      );
      final action = actionIndex[key];
      if (action == null) {
        unmatched++;
        continue;
      }

      // الأعمدة الثلاثة (مرشد/منسّق قسم/منسّق كلية) منفصلة الآن بالملف -
      // كانت هذه الدالة لا تزال تكتب لحقول قديمة (status/notes/completed_by)
      // غير موجودة أصلًا بالصف المُستخرَج (parseProcessedRows يُرجِع
      // advisor_status/coordinator_status/college_status الخ)، فتُهمَل كل
      // البيانات المرفوعة فعليًا بصمت بلا أي أثر (خلل جذري، سليمان
      // 2026-08-09). يُحدَّث كل حقل فقط لو أُدخِلت له قيمة فعلية بالملف
      // المرفوع (بلا مسح حقل جهة أخرى لم تُملَأ بهذا الملف تحديدًا).
      for (final field in ['advisor_status', 'advisor_notes', 'coordinator_status', 'coordinator_notes', 'college_status', 'college_notes']) {
        final value = (row[field] ?? '').toString();
        if (value.isNotEmpty) action[field] = value;
      }
      matched++;
      final ownerId = actionOwnerDocId[key];
      if (ownerId != null) changedDocIds.add(ownerId);
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final docId in changedDocIds) {
      batch.update(_col.doc(docId), {'actions': ticketsData[docId]!['actions']});
    }
    await batch.commit();

    return MergeResult(matchedCount: matched, unmatchedCount: unmatched);
  }

  /// يفرّغ حالة الإنجاز/الملاحظات/جهة الإنجاز لكل حالات قسم/شطر واحد (تراجع
  /// عن دمج خاطئ - مثلاً لو رفع المنسّق ملفًا معالجًا غير صحيح) دون حذف
  /// الحالات نفسها (يبقى بيانات الطلاب الأصلية من رفع الإدارة كما هي).
  /// يعدّل حقل actions فقط، فيتوافق مع صلاحية المنسّق في قواعد أمان Firestore.
  static Future<void> resetDepartmentStatus({
    required String shatr,
    required String department,
  }) async {
    final snap = await _col
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: department)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final actions = (doc.data()['actions'] as List?) ?? [];
      final resetActions = actions.map((a) {
        final action = Map<String, dynamic>.from(a as Map<String, dynamic>);
        action['status'] = '';
        action['notes'] = '';
        action['completed_by'] = '';
        return action;
      }).toList();
      batch.update(doc.reference, {'actions': resetActions});
    }
    await batch.commit();
  }

  /// يحسب ملخصًا علنيًا (بلا أي بيانات طالب فردية) وينشره في وثيقة واحدة
  /// يقرأها الجميع من الصفحة الرئيسية العامة قبل تسجيل الدخول. يُستدعى من
  /// لوحة الإدارة تلقائيًا عند كل تحديث لبيانات التذاكر (بما فيها التعديلات
  /// التي يجريها المنسّقون، لأن لوحة الإدارة تشاهد كل التذاكر لحظيًا).
  static Future<void> publishPublicStats(List<Map<String, dynamic>> tickets) async {
    var completedActions = 0;
    var totalActions = 0;
    final advisors = <String>{};

    for (final t in tickets) {
      final advisor = (t['advisor'] ?? '').toString().trim();
      if (advisor.isNotEmpty) advisors.add(advisor);

      final actions = (t['actions'] as List?) ?? [];
      for (final a in actions) {
        totalActions++;
        final action = a as Map<String, dynamic>;
        if ((action['status'] ?? '').toString() == 'تم الإنجاز') completedActions++;
      }
    }

    final completionRate = totalActions == 0 ? 0 : ((completedActions / totalActions) * 100).round();

    await FirebaseFirestore.instance.collection('public_stats').doc('summary').set({
      'completed_requests': completedActions,
      'students_served': tickets.length,
      'advisors_count': advisors.length,
      'completion_rate': completionRate,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
