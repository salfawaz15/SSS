import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advising_case_record.dart';
import 'advising_report_repository.dart';
import 'course_schedule_repository.dart' show Shatr;

/// إجراء واحد ضمن طلب الطالب (إضافة/حذف/تعديل مقرر) كما تُخزَّن في
/// `tickets/{studentId}.actions` - نفس البنية التي تكتبها منظومة الحذف
/// والإضافة، بلا أي تحويل.
class StudentTicketAction {
  final String actionType;
  final String courseName;
  final String courseCode;
  final String requiredSection;
  final String currentSection;
  final String reason;
  final String advisorStatus;
  final String advisorNotes;

  const StudentTicketAction({
    required this.actionType,
    required this.courseName,
    required this.courseCode,
    required this.requiredSection,
    required this.currentSection,
    required this.reason,
    required this.advisorStatus,
    required this.advisorNotes,
  });

  factory StudentTicketAction.fromJson(Map<String, dynamic> json) => StudentTicketAction(
        actionType: (json['action_type'] ?? '').toString(),
        courseName: (json['course_name'] ?? json['course'] ?? '').toString(),
        courseCode: (json['course_code'] ?? '').toString(),
        requiredSection: (json['required_section'] ?? '').toString(),
        currentSection: (json['current_section'] ?? '').toString(),
        reason: (json['reason'] ?? '').toString(),
        advisorStatus: (json['advisor_status'] ?? '').toString(),
        advisorNotes: (json['advisor_notes'] ?? '').toString(),
      );
}

/// طلب الحذف/الإضافة الكامل لطالب واحد (مستند `tickets/{studentId}`).
class StudentTicket {
  final String uploadedDate;
  final List<StudentTicketAction> actions;

  const StudentTicket({required this.uploadedDate, required this.actions});

  factory StudentTicket.fromJson(Map<String, dynamic> json) => StudentTicket(
        uploadedDate: (json['uploaded_date'] ?? '').toString(),
        actions: ((json['actions'] as List?) ?? [])
            .map((a) => StudentTicketAction.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList(),
      );

  /// أول إجراء له قرار مرشد صريح (موافقة/رفض) إن وُجد - يُمثِّل "ملاحظة
  /// المرشد على الحالة" في البطاقة. null يعني لم تُتّخذ أي إجراء بعد.
  StudentTicketAction? get advisorDecision {
    for (final a in actions) {
      if (a.advisorStatus.trim().isNotEmpty || a.advisorNotes.trim().isNotEmpty) return a;
    }
    return null;
  }
}

/// نتيجة بحث كاملة عن طالب واحد برقمه الجامعي - تجمع تقرير المرشد (من
/// `AdvisingReportRepository`، نفس مصدر "متابعة حالات الإرشاد") وطلبها
/// المقدَّم (`tickets/{studentId}`) في كائن واحد تُبنى منه بطاقة الحالة.
class StudentStatusCardData {
  final AdvisingCaseRecord record;
  final StudentTicket? ticket;

  const StudentStatusCardData({required this.record, this.ticket});
}

class StudentStatusCardService {
  /// يمسح تقرير "كل الكليات" لكلا الشطرين بحثًا عن رقم طالب واحد، ثم يجلب
  /// طلبها (إن وُجد) من `tickets/{studentId}` مباشرة (معرّف المستند = الرقم
  /// الجامعي، كما تكتبه منظومة الحذف والإضافة). لا تخزين/فهرسة جديدة - إعادة
  /// استخدام كاملة لمصدرين قائمين فعلاً.
  static Future<StudentStatusCardData?> lookup(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty) return null;

    final results = await Future.wait([
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
    ]);

    AdvisingCaseRecord? record;
    for (final list in results) {
      for (final r in list) {
        if (r.studentId == id) {
          record = r;
          break;
        }
      }
      if (record != null) break;
    }
    if (record == null) return null;

    final ticket = await fetchTicket(id);
    return StudentStatusCardData(record: record, ticket: ticket);
  }

  /// يجلب طلب طالب واحد فقط من `tickets/{studentId}` بلا إعادة مسح تقرير
  /// "كل الكليات" - يُستخدَم حين يكون سجل الطالب (`AdvisingCaseRecord`)
  /// متوفرًا فعلاً من مصدر آخر (مثال: شاشة "بحث عن طالب/ة" بتطبيق الجوّال).
  static Future<StudentTicket?> fetchTicket(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty) return null;
    final doc = await FirebaseFirestore.instance.collection('tickets').doc(id).get();
    return doc.exists ? StudentTicket.fromJson(doc.data()!) : null;
  }
}
