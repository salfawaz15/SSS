import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advisor_roster_entry.dart';

/// طبقة وصول Firestore لقائمة "مرشدي القسم" الرسمية (المجموعة advisor_roster)
/// - تُستخدم فقط لمعرفة من هو منسّق قسم كل مجموعة (قسم × شطر) ومن هم بقية
/// المرشدين، لتوزيع حالات الحذف والإضافة الخاصة بالمنسّق عليهم خلال فترة
/// الحذف والإضافة. ستُحدَّث لاحقًا بجدول المنسّقين الرسمي المعتمد من إدارة
/// الكلية.
class AdvisorRosterService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('advisor_roster');

  static Future<List<AdvisorRosterEntry>> loadAll() async {
    final snap = await _col.get();
    return snap.docs.map((d) => AdvisorRosterEntry.fromJson(d.id, d.data())).toList();
  }

  static Stream<List<AdvisorRosterEntry>> watchAll() {
    return _col.snapshots().map(
      (snap) => snap.docs.map((d) => AdvisorRosterEntry.fromJson(d.id, d.data())).toList(),
    );
  }

  static Future<void> add({
    required String name,
    required String department,
    required String shatr,
    required bool isCoordinator,
    bool isOnLeave = false,
    String email = '',
  }) {
    return _col.add({
      'name': name,
      'department': department,
      'shatr': shatr,
      'is_coordinator': isCoordinator,
      'is_on_leave': isOnLeave,
      'email': email,
    });
  }

  static Future<void> update(
    String id, {
    required String name,
    required String department,
    required String shatr,
    required bool isCoordinator,
    bool isOnLeave = false,
    String email = '',
  }) {
    return _col.doc(id).update({
      'name': name,
      'department': department,
      'shatr': shatr,
      'is_coordinator': isCoordinator,
      'is_on_leave': isOnLeave,
      'email': email,
    });
  }

  static Future<void> delete(String id) => _col.doc(id).delete();
}
