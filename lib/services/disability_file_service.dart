import 'dart:typed_data';

import 'excel_export_service.dart';
import 'excel_protection_service.dart';

/// يبني ملف Excel واحد مستقل يضم كل حالات "ذوي الإعاقة" في قسم/شطر واحد -
/// نفس الملف بالضبط متاح من لوحة الإدارة ومن شاشة المنسّق، حتى تستطيع إدارة
/// الوحدة تنزيله وإرساله بنفسها لأمين القسم مباشرة لو تأخر المنسّق أو غاب،
/// بدل الاعتماد الحصري عليه. لا يُجمَّع حسب المرشد الأكاديمي (يُتجاهل هذا
/// الحقل هنا لاحتمال وروده خاطئًا) - يعالجه أمين القسم كملف واحد بأسلوب
/// المرشد الأكاديمي نفسه.
class DisabilityFileService {
  static List<Map<String, dynamic>> filterDisabilityTickets(
    List<Map<String, dynamic>> tickets,
  ) {
    return tickets.where((t) => t['has_disability'] == true).toList();
  }

  static Uint8List buildFile(List<Map<String, dynamic>> tickets) {
    final disabilityTickets = filterDisabilityTickets(tickets);
    final rawBytes = ExcelExportService.buildDepartmentWorkbook(disabilityTickets);
    final dataRowCount = disabilityTickets.fold<int>(0, (sum, t) {
      final actions = (t['actions'] as List?) ?? [];
      return sum + (actions.isEmpty ? 1 : actions.length);
    });

    return ExcelProtectionService.protect(
      rawBytes,
      dropdowns: [
        DropdownColumn(
          columnIndex: ExcelExportService.statusColumnIndex,
          options: ExcelProtectionService.statusOptions,
        ),
        DropdownColumn(
          columnIndex: ExcelExportService.completedByColumnIndex,
          options: ExcelExportService.completedByOptions,
        ),
      ],
      unlockedColumnIndexes: [
        ExcelExportService.statusColumnIndex,
        ExcelExportService.notesColumnIndex,
        ExcelExportService.completedByColumnIndex,
      ],
      dataRowCount: dataRowCount,
    );
  }
}
