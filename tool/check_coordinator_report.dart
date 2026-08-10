// One-off debug script: reproduces ReportDataService.build + rankedAdvisors
// using real production data (dumped to JSON via tool/admin_cli) to check
// for exceptions outside the browser, since the coordinator dashboard
// renders blank in production with no visible console error.
//
// Usage: dart run tool/check_coordinator_report.dart
import 'dart:convert';
import 'dart:io';

import '../lib/models/advisor_roster_entry.dart';
import '../lib/services/advisor_zip_service.dart';
import '../lib/services/report_data_service.dart';

void main() {
  final ticketsJson = jsonDecode(
    File('tool/admin_cli/mis_male_tickets.json').readAsStringSync(),
  ) as List;
  final rosterJson = jsonDecode(
    File('tool/admin_cli/advisor_roster.json').readAsStringSync(),
  ) as List;

  final tickets = ticketsJson.cast<Map<String, dynamic>>();
  final roster = [
    for (var i = 0; i < rosterJson.length; i++)
      AdvisorRosterEntry.fromJson('id_$i', rosterJson[i] as Map<String, dynamic>),
  ];

  print('Loaded ${tickets.length} tickets, ${roster.length} roster entries');

  try {
    final groups = AdvisorZipService.resolveEffectiveGroups(tickets, roster: roster);
    print('resolveEffectiveGroups OK: ${groups.length} groups');
  } catch (e, st) {
    print('resolveEffectiveGroups THREW: $e');
    print(st);
  }

  try {
    final data = ReportDataService.build(tickets, roster: roster);
    print('ReportDataService.build OK: ${data.departments.length} dept entries');

    final ranked = ReportDataService.rankedAdvisors(data);
    print('rankedAdvisors OK: ${ranked.length} advisors');
    for (final r in ranked) {
      print('  - ${r.advisorName} (${r.department}/${r.shatr}): ${r.counts.completed}/${r.counts.total}');
    }

    final coords = ReportDataService.rankedCoordinators(data);
    print('rankedCoordinators OK: ${coords.length}');

    final college = ReportDataService.rankedCollegeCoordinators(data);
    print('rankedCollegeCoordinators OK: ${college.length}');

    print('overall.total=${data.overall.total} completionRate=${data.overall.completionRate}');
  } catch (e, st) {
    print('ReportDataService.build/ranked* THREW: $e');
    print(st);
  }
}
