import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/advisor_roster_entry.dart';
import 'digital_transformation_stats_service.dart';
import 'report_data_service.dart';
import 'ticket_action_stats_service.dart';

/// وثيقة أرشيف دورة حذف/إضافة كاملة منتهية (انظر [StageSnapshotService.freezeCycleEnd]).
class CycleArchive {
  final String id;
  final DateTime? endedAt;
  final String generatedByEmail;
  final int totalTickets;
  final int totalActions;
  final Map<String, dynamic> overallCounts;
  final List<Map<String, dynamic>> departmentBreakdown;
  final Map<String, dynamic> digitalTransformation;
  final Map<String, dynamic> actionTypeBreakdown;

  const CycleArchive({
    required this.id,
    required this.endedAt,
    required this.generatedByEmail,
    required this.totalTickets,
    required this.totalActions,
    required this.overallCounts,
    required this.departmentBreakdown,
    required this.digitalTransformation,
    required this.actionTypeBreakdown,
  });

  factory CycleArchive.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CycleArchive(
      id: doc.id,
      endedAt: (data['ended_at'] as Timestamp?)?.toDate(),
      generatedByEmail: (data['generated_by_email'] ?? '').toString(),
      totalTickets: (data['total_tickets'] as num?)?.toInt() ?? 0,
      totalActions: (data['total_actions'] as num?)?.toInt() ?? 0,
      overallCounts: Map<String, dynamic>.from(data['overall_counts'] ?? {}),
      departmentBreakdown: (data['department_breakdown'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      digitalTransformation: Map<String, dynamic>.from(data['digital_transformation'] ?? {}),
      actionTypeBreakdown: Map<String, dynamic>.from(data['action_type_breakdown'] ?? {}),
    );
  }

  int get completedCount => (overallCounts['completed'] as num?)?.toInt() ?? 0;
  double get completionRate => totalActions == 0 ? 0 : completedCount / totalActions;
}

/// وثيقة تقرير مرحلي مجمَّدة - ثابتة تمامًا بعد إنشائها (لا تُعدَّل أو تُحذف،
/// انظر firestore.rules) لتبقى توثيقًا تاريخيًا موثوقًا لما أنجزه كل مستوى
/// من مسار التصعيد (مرشد -> منسّق قسم -> منسّق كلية).
class StageSnapshot {
  final String id;
  final int stage;
  final String shatr;
  final String department; // '__ALL__' لمرحلة 3
  final DateTime? generatedAt;
  final String generatedByEmail;
  final Map<String, dynamic> statusCounts;
  final List<Map<String, dynamic>> breakdown;
  final Map<String, dynamic>? delta;

  const StageSnapshot({
    required this.id,
    required this.stage,
    required this.shatr,
    required this.department,
    required this.generatedAt,
    required this.generatedByEmail,
    required this.statusCounts,
    required this.breakdown,
    required this.delta,
  });

  factory StageSnapshot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return StageSnapshot(
      id: doc.id,
      stage: (data['stage'] as num?)?.toInt() ?? 0,
      shatr: (data['shatr'] ?? '').toString(),
      department: (data['department'] ?? '').toString(),
      generatedAt: (data['generated_at'] as Timestamp?)?.toDate(),
      generatedByEmail: (data['generated_by_email'] ?? '').toString(),
      statusCounts: Map<String, dynamic>.from(data['status_counts'] ?? {}),
      breakdown: (data['breakdown'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      delta: data['delta_from_previous_stage'] == null
          ? null
          : Map<String, dynamic>.from(data['delta_from_previous_stage'] as Map),
    );
  }
}

/// يبني وينشئ التقارير المرحلية المجمَّدة الثلاثة (مرشدون / منسّق قسم /
/// منسّق كلية) - بلا أي أتمتة من جهة الخادم (لا Cloud Functions في المشروع)؛
/// كل "تجميد" فعل يدوي صريح يستدعيه المستخدم بالضغط على زر مخصَّص.
class StageSnapshotService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('stage_snapshots');

  static const String allDepartments = '__ALL__';

  static Map<String, dynamic> _countsToMap(StatusCounts c) => {
        'blank': c.blank,
        'not_done': c.notDone,
        'partial': c.partial,
        'completed': c.completed,
        'total': c.total,
      };

  static List<Map<String, dynamic>> _advisorBreakdown(
    ReportData data,
    String shatr,
    String department,
  ) {
    final match = data.departments.where(
      (d) => d.shatr == shatr && d.department == department,
    );
    if (match.isEmpty) return [];
    return match.first.advisors
        .where((a) => a.counts.total > 0)
        .map((a) => {'key': a.name, ..._countsToMap(a.counts)})
        .toList();
  }

  static Map<String, dynamic> _computeDelta({
    required String previousSnapshotId,
    required Map<String, dynamic> previousCounts,
    required StatusCounts currentCounts,
  }) {
    final previousCompleted = (previousCounts['completed'] as num?)?.toInt() ?? 0;
    final previousPartial = (previousCounts['partial'] as num?)?.toInt() ?? 0;
    final newlyCompleted = currentCounts.completed - previousCompleted;
    final newlyPartial = currentCounts.partial - previousPartial;
    return {
      'previous_snapshot_id': previousSnapshotId,
      'newly_completed': newlyCompleted,
      'newly_partial': newlyPartial,
      'moved_count': newlyCompleted + newlyPartial,
    };
  }

  /// إنهاء مرحلة المرشدين وتجميد تقريرها (بلا دلتا - هي المرحلة الأولى).
  static Future<void> freezeStage1({
    required String shatr,
    required String department,
    required List<Map<String, dynamic>> tickets,
    required List<AdvisorRosterEntry> roster,
    required String generatedByEmail,
  }) async {
    final data = ReportDataService.build(tickets, roster: roster);
    await _col.add({
      'stage': 1,
      'shatr': shatr,
      'department': department,
      'generated_at': FieldValue.serverTimestamp(),
      'generated_by_email': generatedByEmail,
      'status_counts': _countsToMap(data.overall),
      'breakdown': _advisorBreakdown(data, shatr, department),
      'delta_from_previous_stage': null,
    });
  }

  /// إنهاء مرحلة منسّق القسم وتجميد تقريرها - يحسب دلتا مقارنةً بآخر تجميد
  /// لمرحلة المرشدين لنفس القسم/الشطر (ما تحديدًا أنجزه المنسّق بنفسه).
  static Future<void> freezeStage2({
    required String shatr,
    required String department,
    required List<Map<String, dynamic>> tickets,
    required List<AdvisorRosterEntry> roster,
    required String generatedByEmail,
  }) async {
    final data = ReportDataService.build(tickets, roster: roster);
    final previous = await latestSnapshot(stage: 1, shatr: shatr, department: department);
    final delta = previous == null
        ? null
        : _computeDelta(
            previousSnapshotId: previous.id,
            previousCounts: previous.statusCounts,
            currentCounts: data.overall,
          );

    await _col.add({
      'stage': 2,
      'shatr': shatr,
      'department': department,
      'generated_at': FieldValue.serverTimestamp(),
      'generated_by_email': generatedByEmail,
      'status_counts': _countsToMap(data.overall),
      'breakdown': _advisorBreakdown(data, shatr, department),
      'delta_from_previous_stage': delta,
    });
  }

  /// إنهاء مرحلة منسّق الكلية وتجميد تقريرها - يحسب دلتا مقارنةً بمجموع آخر
  /// تجميد لمرحلة 2 لكل الأقسام الخمسة في نفس الشطر (بلا roster - لا معنى
  /// لتوزيع "تفريغ المنسّق" في هذه المرحلة).
  static Future<void> freezeStage3({
    required String shatr,
    required List<Map<String, dynamic>> shatrTickets,
    required String generatedByEmail,
  }) async {
    final data = ReportDataService.build(shatrTickets);
    final relevantDepartments = data.departments.where((d) => d.shatr == shatr);
    final breakdown = relevantDepartments
        .where((d) => d.counts.total > 0)
        .map((d) => {'key': d.department, ..._countsToMap(d.counts)})
        .toList();

    final previousCompleted = <int>[];
    final previousPartial = <int>[];
    String? lastPreviousId;
    for (final dept in relevantDepartments) {
      final prev = await latestSnapshot(stage: 2, shatr: shatr, department: dept.department);
      if (prev == null) continue;
      lastPreviousId = prev.id;
      previousCompleted.add((prev.statusCounts['completed'] as num?)?.toInt() ?? 0);
      previousPartial.add((prev.statusCounts['partial'] as num?)?.toInt() ?? 0);
    }

    Map<String, dynamic>? delta;
    if (lastPreviousId != null) {
      final previousCompletedTotal = previousCompleted.fold<int>(0, (a, b) => a + b);
      final previousPartialTotal = previousPartial.fold<int>(0, (a, b) => a + b);
      final newlyCompleted = data.overall.completed - previousCompletedTotal;
      final newlyPartial = data.overall.partial - previousPartialTotal;
      delta = {
        'previous_snapshot_id': lastPreviousId,
        'newly_completed': newlyCompleted,
        'newly_partial': newlyPartial,
        'moved_count': newlyCompleted + newlyPartial,
      };
    }

    await _col.add({
      'stage': 3,
      'shatr': shatr,
      'department': allDepartments,
      'generated_at': FieldValue.serverTimestamp(),
      'generated_by_email': generatedByEmail,
      'status_counts': _countsToMap(data.overall),
      'breakdown': breakdown,
      'delta_from_previous_stage': delta,
    });
  }

  /// آخر تجميد لمرحلة معيّنة (قسم/شطر واحد لمرحلة 1/2، أو department ==
  /// allDepartments لمرحلة 3) - أو null إن لم تُجمَّد بعد. يُرتَّب في التطبيق
  /// (لا orderBy في الاستعلام) لتفادي الحاجة لفهرس مركّب جديد في Firestore.
  static Future<StageSnapshot?> latestSnapshot({
    required int stage,
    required String shatr,
    required String department,
  }) async {
    final snap = await _col
        .where('stage', isEqualTo: stage)
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: department)
        .get();
    if (snap.docs.isEmpty) return null;
    final all = snap.docs.map(StageSnapshot.fromDoc).toList()
      ..sort((a, b) => (b.generatedAt ?? DateTime(0)).compareTo(a.generatedAt ?? DateTime(0)));
    return all.first;
  }

  /// كل تجميدات مرحلتَي 1 و2 لقسم/شطر واحد (لعرضها في شاشة المنسّق ولوحة
  /// الإدارة) - الأحدث أولًا.
  static Stream<List<StageSnapshot>> watchSnapshots({
    required String shatr,
    required String department,
  }) {
    return _col
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: department)
        .snapshots()
        .map((s) {
      final list = s.docs.map(StageSnapshot.fromDoc).toList()
        ..sort((a, b) => (b.generatedAt ?? DateTime(0)).compareTo(a.generatedAt ?? DateTime(0)));
      return list;
    });
  }

  /// كل تجميدات مرحلة 3 لشطر كامل (لعرضها في شاشة منسّق الكلية ولوحة
  /// الإدارة) - الأحدث أولًا.
  static Stream<List<StageSnapshot>> watchShatrSnapshots(String shatr) {
    return _col
        .where('shatr', isEqualTo: shatr)
        .where('department', isEqualTo: allDepartments)
        .snapshots()
        .map((s) {
      final list = s.docs.map(StageSnapshot.fromDoc).toList()
        ..sort((a, b) => (b.generatedAt ?? DateTime(0)).compareTo(a.generatedAt ?? DateTime(0)));
      return list;
    });
  }

  static final CollectionReference<Map<String, dynamic>> _archiveCol =
      FirebaseFirestore.instance.collection('cycle_archives');

  /// يؤرشف ملخّصًا شاملًا لدورة حذف/إضافة كاملة (كل الأقسام والشطرين) - يُستدعى
  /// مباشرة قبل `FirestoreTicketService.clearAll()` عند "تفريغ البيانات" لبدء
  /// دورة جديدة، حتى لا تُفقَد أرقام الدورة المنتهية نهائيًا بلا أي أثر تاريخي
  /// (بطلب سليمان صراحةً 2026-09-05: مقارنة الأداء بين الدورات). وثيقة واحدة
  /// بمجموعة منفصلة `cycle_archives` (لا `stage_snapshots` - هذه بمستوى دورة
  /// كاملة لا قسم/مرحلة واحدة)، ثابتة بعد إنشائها كبقية توثيق `StageSnapshot`.
  static Future<void> freezeCycleEnd({
    required List<Map<String, dynamic>> tickets,
    required String generatedByEmail,
  }) async {
    final reportData = ReportDataService.build(tickets);
    final digital = DigitalTransformationStatsService.build(tickets);
    final actionStats = TicketActionStatsService.build(tickets);

    final departmentBreakdown = reportData.departments
        .where((d) => d.counts.total > 0)
        .map((d) => {
              'shatr': d.shatr,
              'department': d.department,
              ..._countsToMap(d.counts),
            })
        .toList();

    final actionTypeBreakdown = {
      for (final entry in actionStats.byActionType.entries)
        entry.key: {
          'total': entry.value.total,
          ..._countsToMap(entry.value.statusCounts),
        },
    };

    await _archiveCol.add({
      'ended_at': FieldValue.serverTimestamp(),
      'generated_by_email': generatedByEmail,
      'total_tickets': actionStats.totalTickets,
      'total_actions': actionStats.totalActions,
      'overall_counts': _countsToMap(reportData.overall),
      'department_breakdown': departmentBreakdown,
      'digital_transformation': {
        'forms_ticket_count': digital.formsTicketCount,
        'paper_ticket_count': digital.paperTicketCount,
        'digital_share_percent': digital.digitalSharePercent,
      },
      'action_type_breakdown': actionTypeBreakdown,
    });
  }

  /// أحدث [limit] دورة مؤرشَفة (الأحدث أولًا) - لقسم "سجل الدورات السابقة"
  /// بلوحة الإدارة التنفيذية.
  static Stream<List<CycleArchive>> watchCycleArchives({int limit = 12}) {
    return _archiveCol.snapshots().map((s) {
      final list = s.docs.map(CycleArchive.fromDoc).toList()
        ..sort((a, b) => (b.endedAt ?? DateTime(0)).compareTo(a.endedAt ?? DateTime(0)));
      return list.take(limit).toList();
    });
  }
}
