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

  static Future<Uint8List> buildFile(List<Map<String, dynamic>> tickets) async {
    final disabilityTickets = filterDisabilityTickets(tickets);
    final workbookResult = await ExcelExportService.buildDepartmentWorkbook(disabilityTickets);
    final dataRowCount = workbookResult.totalDataRowCount;

    return ExcelProtectionService.protect(
      workbookResult.bytes,
      dropdowns: [
        DropdownColumn(
          columnIndex: ExcelExportService.advisorStatusColumnIndex,
          options: ExcelProtectionService.statusOptions,
        ),
      ],
      unlockedColumnIndexes: [
        ExcelExportService.advisorStatusColumnIndex,
        ExcelExportService.advisorNotesColumnIndex,
      ],
      dataRowCount: dataRowCount,
    );
  }
}
