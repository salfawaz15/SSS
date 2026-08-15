import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/unit_committee_member.dart';

/// يخزّن آخر تشكيل معتمد لوحدة الإرشاد الأكاديمي والخريجين - وثيقة عامة
/// القراءة (بلا تسجيل دخول، على غرار public_stats) لأنها تغذّي صفحة "تواصل
/// معنا" العامة، وكتابتها مقصورة على الإدارة (تُحدَّث تلقائيًا عند رفع ملف
/// منسوبي الكلية إن تضمّن ورقة "تشكيل الوحدة" - انظر college_roster_admin_screen.dart).
class UnitCommitteeRepository {
  static final _doc = FirebaseFirestore.instance.collection('public_unit_committee').doc('current');

  static Future<void> save(List<UnitCommitteeMember> members) async {
    await _doc.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'members': members.map((m) => m.toJson()).toList(),
    });
  }

  static Future<List<UnitCommitteeMember>> load() async {
    final doc = await _doc.get();
    if (!doc.exists) return [];
    final list = doc.data()?['members'] as List<dynamic>? ?? [];
    return list.map((e) => UnitCommitteeMember.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Stream<List<UnitCommitteeMember>> watch() {
    return _doc.snapshots().map((doc) {
      final list = doc.data()?['members'] as List<dynamic>? ?? [];
      return list.map((e) => UnitCommitteeMember.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
}
