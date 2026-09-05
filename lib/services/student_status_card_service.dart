import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advising_case_record.dart';
import 'advising_case_analyzer.dart';
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
  // سجل كل قرار فعلي اتُّخذ على هذا الإجراء بتاريخه (تاريخ + الحقول التي
  // تغيّرت حينها) - يُبنى في FirestoreTicketService._mergeProcessedRowsIntoDocs
  // بدل استبدال القرار السابق صامتًا، حتى تُعرض ببطاقة حالة الطالب/ة كل
  // استجابة سابقة من المرشد/المنسّق لا آخر استجابة فقط.
  final List<Map<String, dynamic>> history;

  const StudentTicketAction({
    required this.actionType,
    required this.courseName,
    required this.courseCode,
    required this.requiredSection,
    required this.currentSection,
    required this.reason,
    required this.advisorStatus,
    required this.advisorNotes,
    this.history = const [],
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
        history: ((json['history'] as List?) ?? [])
            .map((h) => Map<String, dynamic>.from(h as Map))
            .toList(),
      );
}

/// طلب الحذف/الإضافة الكامل لطالب واحد (مستند `tickets/{studentId}`).
class StudentTicket {
  final String uploadedDate;
  final List<StudentTicketAction> actions;
  // سجل كل مرة ظهر فيها رقم الطالب/ة الجامعي باستجابة Forms (تقديم أول +
  // أي إعادة تقديم لاحقة بنفس الرقم كانت تُتجاهل بالكامل سابقًا) - تاريخ كل
  // تقديم + لقطة الإجراءات المطلوبة فيه، يُبنى في
  // FirestoreTicketService.addNewTickets/replaceAllTickets (سليمان صراحةً
  // 2026-09-02).
  final List<Map<String, dynamic>> submissionLog;

  const StudentTicket({required this.uploadedDate, required this.actions, this.submissionLog = const []});

  factory StudentTicket.fromJson(Map<String, dynamic> json) => StudentTicket(
        uploadedDate: (json['uploaded_date'] ?? '').toString(),
        actions: ((json['actions'] as List?) ?? [])
            .map((a) => StudentTicketAction.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList(),
        submissionLog: ((json['submission_log'] as List?) ?? [])
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList(),
      );

  /// عدد مرات التقديم الفعلية - يعتمد على submission_log إن وُجد (التذاكر
  /// الجديدة بعد 2026-09-02)، وإلا يُقدَّر بواحدة فقط لتذاكر أقدم لا تحمل
  /// هذا الحقل أصلًا (لا يمكن معرفة تعدد تقديمها القديم بأثر رجعي).
  int get submissionCount => submissionLog.isEmpty ? 1 : submissionLog.length;

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
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.base),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.base),
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.basePrevious),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.basePrevious),
      AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.health),
      AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.health),
    ]);
    final [
      allCollegesMale,
      allCollegesFemale,
      baseMale,
      baseFemale,
      basePreviousMale,
      basePreviousFemale,
      healthMale,
      healthFemale,
    ] = results;

    AdvisingCaseRecord? record;
    for (final list in [allCollegesMale, allCollegesFemale]) {
      for (final r in list) {
        if (r.studentId == id) {
          record = r;
          break;
        }
      }
      if (record != null) break;
    }

    AdvisingCaseRecord? academic;
    for (final list in [baseMale, baseFemale]) {
      for (final r in list) {
        if (r.studentId == id) {
          academic = r;
          break;
        }
      }
      if (academic != null) break;
    }

    // إن لم يكن للطالب/ة سجل مرشد بعد (لم يُسنَد بملف المرشد) يُبنى سجل من
    // بيانات الطلبة الأكاديمية وحدها بدل استبعاده كليًا من البطاقة.
    record ??= academic;
    if (record == null) return null;

    // يدمج كل مصادر بيانات الطالب/ة الأخرى بالرقم الجامعي - ملف المرشد
    // ("كل الكليات") لا يحمل المعدل/الساعات/الحالة الصحية أصلاً، فتبقى "غير
    // مسجَّلة" بالبطاقة رغم توفّرها فعليًا بمصادر أخرى لولا هذا الدمج (نفس
    // الدوال التي تبني تقارير متابعة الإرشاد الأخرى - [AdvisingCaseAnalyzer]).
    if (academic != null) {
      record = AdvisingCaseAnalyzer.mergeAcademicData(
        [record],
        [academic],
        [...basePreviousMale, ...basePreviousFemale],
      ).first;
    }
    record = AdvisingCaseAnalyzer.mergeHealthConditions(
      [record],
      [...healthMale, ...healthFemale],
    ).first;

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
