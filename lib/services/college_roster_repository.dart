import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/college_roster_member.dart';

/// يخزّن آخر نسخة معتمدة من ملف منسوبي الكلية - رفع ملف جديد يستبدل النسخة
/// السابقة بالكامل (نفس مبدأ CourseScheduleRepository لجدول الحويّة)، بناءً
/// على قرار صريح: عند التعارض، الملف الجديد هو المرجع - أي منسوب غاب عن
/// الملف الجديد يُعتبر لم يعد منسوبًا للكلية.
class CollegeRosterRepository {
  static final _doc = FirebaseFirestore.instance.collection('collegeRoster').doc('current');

  static Future<void> save(List<CollegeRosterMember> members, {DateTime? lastSavedAt}) async {
    await _doc.set({
      'uploadedAt': FieldValue.serverTimestamp(),
      'lastSavedAt': lastSavedAt == null ? null : Timestamp.fromDate(lastSavedAt),
      'membersCount': members.length,
      'members': members.map((m) => m.toJson()).toList(),
    });
  }

  /// تاريخ آخر حفظ فعلي (من بيانات وصف ملف xlsx) للنسخة المخزَّنة حاليًا -
  /// يُستخدم للتأكد أن كل ملف جديد أحدث من السابق قبل قبول استبداله.
  static Future<DateTime?> currentLastSavedAt() async {
    final doc = await _doc.get();
    final ts = doc.data()?['lastSavedAt'] as Timestamp?;
    return ts?.toDate();
  }

  static Future<List<CollegeRosterMember>> load() async {
    final doc = await _doc.get();
    if (!doc.exists) return [];
    final list = doc.data()?['members'] as List<dynamic>? ?? [];
    return list.map((e) => CollegeRosterMember.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// تفريغ كامل للبيانات المخزَّنة - لتسهيل إعادة الاختبار (رفع ملف بنفس
  /// تاريخ الحفظ أو أقدم يُرفض عادةً بسبب فحص "أحدث من السابق").
  static Future<void> clear() async {
    await _doc.delete();
  }
}
