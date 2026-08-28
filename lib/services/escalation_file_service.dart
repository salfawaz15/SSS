import 'dart:typed_data';

import 'excel_export_service.dart';
import 'excel_protection_service.dart';

/// يبني ملفات المرحلتين الثانية والثالثة من مسار التصعيد الثلاثي (مرشد ->
/// منسّق قسم -> منسّق كلية). لا تجميع حسب المرشد الأكاديمي هنا (بخلاف
/// AdvisorZipService) - كل الحالات في ملف واحد، بما فيها المكتملة وحالات
/// ذوي الإعاقة، لأن من يعالجه في هاتين المرحلتين شخص واحد بصلاحيات أعلى.
class EscalationFileService {
  /// المرحلة 2: كل حالات قسم/شطر واحد (يعالجها منسّق القسم بنفسه).
  static Future<Uint8List> buildStage2File(List<Map<String, dynamic>> departmentTickets) {
    return _buildProtectedWorkbook(
      departmentTickets,
      statusColumnIndex: ExcelExportService.coordinatorStatusColumnIndex,
      notesColumnIndex: ExcelExportService.coordinatorNotesColumnIndex,
    );
  }

  /// المرحلة 3: كل حالات شطر كامل (الأقسام الخمسة مدمجة، يعالجها منسّق/ة
  /// الكلية).
  static Future<Uint8List> buildStage3File(List<Map<String, dynamic>> shatrTickets) {
    return _buildProtectedWorkbook(
      shatrTickets,
      statusColumnIndex: ExcelExportService.collegeStatusColumnIndex,
      notesColumnIndex: ExcelExportService.collegeNotesColumnIndex,
    );
  }

  static Future<Uint8List> _buildProtectedWorkbook(
    List<Map<String, dynamic>> tickets, {
    required int statusColumnIndex,
    required int notesColumnIndex,
  }) async {
    final workbookResult = await ExcelExportService.buildDepartmentWorkbook(tickets);
    final dataRowCount = workbookResult.totalDataRowCount;

    return ExcelProtectionService.protect(
      workbookResult.bytes,
      dropdowns: [
        DropdownColumn(
          columnIndex: statusColumnIndex,
          options: ExcelProtectionService.statusOptions,
        ),
      ],
      unlockedColumnIndexes: [
        statusColumnIndex,
        notesColumnIndex,
      ],
      dataRowCount: dataRowCount,
    );
  }
}
