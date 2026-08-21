import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MergeResult {
  final int matchedCount;
  final int unmatchedCount;
  final int missingReasonCount;

  const MergeResult({
    required this.matchedCount,
    required this.unmatchedCount,
    this.missingReasonCount = 0,
  });
}

/// يخزّن تذاكر الدفعة اليومية الحالية (طلاب/طالبات كلا الشطرين) بشكل دائم،
/// بحيث لا تُفقد عند إغلاق التطبيق قبل استيراد الملفات المعالجة من المرشدين.
class TicketRepository {
  static const String _storageKey = 'tickets_v1';

  static Future<List<Map<String, dynamic>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  static Future<void> saveAll(List<Map<String, dynamic>> tickets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(tickets));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// مفتاح مطابقة الإجراء: الرقم الجامعي + نوع الإجراء + المقرر + رقم الشعبة.
  /// رقم الشعبة ضروري لأن الطالب قد يطلب نفس نوع الإجراء لنفس المقرر أكثر
  /// من مرة بشعب مختلفة (تحدث فعليًا)، فبدونه تتصادم كل هذه الطلبات على نفس
  /// المفتاح ويطغى آخر صف مُعالَج على البقية.
  static String _actionKey(
    String universityId,
    String actionType,
    String course,
    String section,
  ) {
    return '$universityId|$actionType|$course|$section';
  }

  /// رقم الشعبة الفعلي لإجراء التذكرة الأصلية (نفس منطق ExcelExportService
  /// عند تصدير الملف: المطلوبة للإضافة، أو الحالية للحذف)
  static String _ticketActionSection(Map<String, dynamic> action) {
    return (action['required_section'] ?? action['current_section'] ?? '')
        .toString();
  }

  /// يدمج صفوفًا معالَجة (من ملفات عادت من المرشدين) في التذاكر المخزّنة حاليًا،
  /// بمطابقة كل صف بإجراء الطالب المطابق عبر (الرقم الجامعي، نوع الإجراء، المقرر).
  static Future<MergeResult> mergeProcessedRows(
    List<Map<String, dynamic>> processedRows,
  ) async {
    final tickets = await loadAll();

    final actionIndex = <String, Map<String, dynamic>>{};
    for (final ticket in tickets) {
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
      }
    }

    var matched = 0;
    var unmatched = 0;
    var missingReason = 0;

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

      final rowAdvisorStatus = (row['advisor_status'] ?? '').toString().trim();
      final rowAdvisorNotes = (row['advisor_notes'] ?? '').toString().trim();
      final rowAdvisorOtherReason = (row['advisor_other_reason'] ?? '').toString().trim();
      if (rowAdvisorStatus == 'لم يتم التنفيذ' && rowAdvisorNotes.isEmpty && rowAdvisorOtherReason.isEmpty) {
        missingReason++;
      }

      action['advisor_status'] = row['advisor_status'];
      action['advisor_notes'] = row['advisor_notes'];
      action['advisor_other_reason'] = row['advisor_other_reason'];
      action['coordinator_status'] = row['coordinator_status'];
      action['coordinator_notes'] = row['coordinator_notes'];
      action['college_status'] = row['college_status'];
      action['college_notes'] = row['college_notes'];
      matched++;
    }

    await saveAll(tickets);

    return MergeResult(matchedCount: matched, unmatchedCount: unmatched, missingReasonCount: missingReason);
  }
}
