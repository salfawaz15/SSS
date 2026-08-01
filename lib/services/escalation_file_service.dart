import 'dart:typed_data';

import 'excel_export_service.dart';
import 'excel_protection_service.dart';

/// يبني ملفات المرحلتين الثانية والثالثة من مسار التصعيد الثلاثي (مرشد ->
/// منسّق قسم -> منسّق كلية). لا تجميع حسب المرشد الأكاديمي هنا (بخلاف
/// AdvisorZipService) - كل الحالات في ملف واحد، بما فيها المكتملة وحالات
/// ذوي الإعاقة، لأن من يعالجه في هاتين المرحلتين شخص واحد بصلاحيات أعلى.
class EscalationFileService {
  /// المرحلة 2: كل حالات قسم/شطر واحد (يعالجها منسّق القسم بنفسه).
  static Uint8List buildStage2File(List<Map<String, dynamic>> departmentTickets) {
    return _buildProtectedWorkbook(departmentTickets);
  }

  /// المرحلة 3: كل حالات شطر كامل (الأقسام الخمسة مدمجة، يعالجها منسّق/ة
  /// الكلية).
  static Uint8List buildStage3File(List<Map<String, dynamic>> shatrTickets) {
    return _buildProtectedWorkbook(shatrTickets);
  }

  static Uint8List _buildProtectedWorkbook(List<Map<String, dynamic>> tickets) {
    final rawBytes = ExcelExportService.buildDepartmentWorkbook(tickets);
    final dataRowCount = tickets.fold<int>(0, (sum, t) {
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
