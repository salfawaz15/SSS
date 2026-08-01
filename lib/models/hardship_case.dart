import 'package:cloud_firestore/cloud_firestore.dart';

/// حالات المتابعة الممكنة لحالة الظرف الخاص - تتغيّر بمرور الوقت حسب ما
/// يستجدّ مع الطالب، وتُحفَظ كل نقلة كسجل تاريخي بدل استبدال آخر حالة فقط.
enum HardshipStatus {
  newCase,
  underReview,
  contactedStudent,
  contactedFamily,
  referred,
  improved,
  needsOngoingFollowUp,
}

extension HardshipStatusLabel on HardshipStatus {
  String get label {
    switch (this) {
      case HardshipStatus.newCase:
        return 'جديدة';
      case HardshipStatus.underReview:
        return 'قيد الدراسة';
      case HardshipStatus.contactedStudent:
        return 'تم التواصل مع الطالب';
      case HardshipStatus.contactedFamily:
        return 'تم التواصل مع ذوي الطالب';
      case HardshipStatus.referred:
        return 'تم تحويل الحالة لجهة أخرى';
      case HardshipStatus.improved:
        return 'تحسّنت الحالة / أُغلقت';
      case HardshipStatus.needsOngoingFollowUp:
        return 'تحتاج متابعة مستمرة';
    }
  }

  static HardshipStatus fromLabel(String label) {
    return HardshipStatus.values.firstWhere(
      (s) => s.label == label,
      orElse: () => HardshipStatus.newCase,
    );
  }
}

/// نقلة واحدة في مسار متابعة الحالة (سجل تاريخي - لا يُستبدَل، بل يُضاف إليه).
class HardshipHistoryEntry {
  final HardshipStatus status;
  final String notes;
  final String updatedBy;
  final DateTime? updatedAt;

  const HardshipHistoryEntry({
    required this.status,
    required this.notes,
    required this.updatedBy,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'status': status.label,
    'notes': notes,
    'updated_by': updatedBy,
    'updated_at': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
  };

  factory HardshipHistoryEntry.fromJson(Map<String, dynamic> json) {
    final ts = json['updated_at'];
    return HardshipHistoryEntry(
      status: HardshipStatusLabel.fromLabel((json['status'] ?? '').toString()),
      notes: (json['notes'] ?? '').toString(),
      updatedBy: (json['updated_by'] ?? '').toString(),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class HardshipCase {
  final String id;
  final String studentName;
  final String universityId;
  final String department;
  final String shatr;
  final String description;
  final HardshipStatus status;
  final String createdBy;
  final DateTime? createdAt;
  final List<HardshipHistoryEntry> history;

  const HardshipCase({
    required this.id,
    required this.studentName,
    required this.universityId,
    required this.department,
    required this.shatr,
    required this.description,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.history,
  });

  factory HardshipCase.fromFirestore(String id, Map<String, dynamic> json) {
    final ts = json['created_at'];
    return HardshipCase(
      id: id,
      studentName: (json['student_name'] ?? '').toString(),
      universityId: (json['university_id'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      shatr: (json['shatr'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      status: HardshipStatusLabel.fromLabel((json['status'] ?? '').toString()),
      createdBy: (json['created_by'] ?? '').toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      history: ((json['history'] as List?) ?? [])
          .map((e) => HardshipHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
