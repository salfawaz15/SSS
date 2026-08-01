import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/hardship_case.dart';

/// طبقة وصول Firestore لـ"حالات الدعم النفسي والاجتماعي" - نفس آلية متابعة
/// حالات الظروف الخاصة بالضبط (نفس نموذج البيانات والحالات)، لكن في مجموعة
/// Firestore منفصلة تمامًا حفاظًا على خصوصية طبيعة هذه الحالات الحسّاسة عن
/// حالات الظروف العامة، رغم اشتراكهما في نفس آلية التتبع التي طلبها المستخدم.
class SupportCaseService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('support_cases');

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

  static Stream<List<HardshipCase>> watchAllCases() {
    return _col.snapshots().map(
          (s) => s.docs.map((d) => HardshipCase.fromFirestore(d.id, d.data())).toList(),
        );
  }
}
