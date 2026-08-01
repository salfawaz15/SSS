import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/hardship_case.dart';

/// طبقة وصول Firestore لـ"حالات الظروف الخاصة" - يسجّلها منسّق القسم بعد
/// اعتماد نموذج توثيق الحالة الورقي، وتتابعها إدارة الوحدة عبر سجل تاريخي
/// لكل تحديث (بدل استبدال آخر حالة فقط).
class HardshipCaseService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('hardship_cases');

  /// يضيف حالة جديدة (منسّق قسم واحد فقط، لقسمه/شطره).
  static Future<void> addCase({
    required String studentName,
    required String universityId,
    required String department,
    required String shatr,
    required String description,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    await _col.add({
      'student_name': studentName,
      'university_id': universityId,
      'department': department,
      'shatr': shatr,
      'description': description,
      'status': HardshipStatus.newCase.label,
      'created_by': createdBy,
      'created_at': FieldValue.serverTimestamp(),
      'history': [
        {
          'status': HardshipStatus.newCase.label,
          'notes': description,
          'updated_by': createdBy,
          'updated_at': Timestamp.fromDate(now),
        },
      ],
    });
  }

  /// يضيف نقلة متابعة جديدة (حالة + ملاحظة) لسجل حالة موجودة - يُبقي كل
  /// السجل التاريخي السابق كما هو (arrayUnion بدل استبدال الحقل).
  static Future<void> addFollowUp({
    required String caseId,
    required HardshipStatus status,
    required String notes,
    required String updatedBy,
  }) async {
    await _col.doc(caseId).update({
      'status': status.label,
      'history': FieldValue.arrayUnion([
        {
          'status': status.label,
          'notes': notes,
          'updated_by': updatedBy,
          'updated_at': Timestamp.fromDate(DateTime.now()),
        },
      ]),
    });
  }

  /// تدفّق حالات قسم/شطر واحد فقط (لصفحة المنسّق).
  static Stream<List<HardshipCase>> watchDepartmentCases({
    required String shatr,
    required String department,
  }) {
    return _col
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: department)
        .snapshots()
        .map((s) => s.docs.map((d) => HardshipCase.fromFirestore(d.id, d.data())).toList());
  }

  /// تدفّق كل الحالات من كل الأقسام (لصفحة إدارة الوحدة).
  static Stream<List<HardshipCase>> watchAllCases() {
    return _col.snapshots().map(
          (s) => s.docs.map((d) => HardshipCase.fromFirestore(d.id, d.data())).toList(),
        );
  }
}
