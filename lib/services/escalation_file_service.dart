import 'dart:typed_data';

import 'package:archive/archive.dart';

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
  /// الكلية) - مفروزة بالقسم كمعيار فرز ثانٍ (بعد الإنجاز، قبل أولوية
  /// التخرج) ليعمل منسّق الكلية قسمًا كاملاً قبل الانتقال للتالي (سليمان
  /// صراحةً 2026-09-03).
  static Future<Uint8List> buildStage3File(List<Map<String, dynamic>> shatrTickets) {
    return _buildProtectedWorkbook(
      shatrTickets,
      statusColumnIndex: ExcelExportService.collegeStatusColumnIndex,
      notesColumnIndex: ExcelExportService.collegeNotesColumnIndex,
      groupByDepartment: true,
    );
  }

  /// المرحلة 3 - نسخة مقسَّمة: بدل ملف واحد يدمج الأقسام الخمسة، يبني ملف
  /// Excel محمي مستقل لكل قسم علمي ضمن [shatrTickets] ثم يضغطها معًا بملف
  /// ZIP واحد - بطلب سليمان صراحةً (2026-09-03): يسهُل على منسّق/ة الكلية
  /// العمل على ملف قسم واحد كامل بدل ملف ضخم يجمع الكل. كل ملف يحمل نفس فرز
  /// الإنجاز-فأولوية-التخرج المعتاد (القسم موحَّد داخل كل ملف فلا حاجة
  /// لمعيار فرز القسم هنا).
  static Future<Uint8List> buildStage3DepartmentZip(List<Map<String, dynamic>> shatrTickets) async {
    final files = await buildStage3DepartmentFiles(shatrTickets);
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  /// نفس تجميع/بناء [buildStage3DepartmentZip] لكن بلا ضغط ZIP - مفتاح كل
  /// ملف هو اسم القسم كما ورد بالتذكرة نفسها ("اسم_القسم.xlsx").
  static Future<Map<String, Uint8List>> buildStage3DepartmentFiles(
    List<Map<String, dynamic>> shatrTickets,
  ) async {
    final byDepartment = <String, List<Map<String, dynamic>>>{};
    for (final t in shatrTickets) {
      final department = (t['department'] ?? '').toString().trim();
      final key = department.isEmpty ? 'بدون قسم محدد' : department;
      byDepartment.putIfAbsent(key, () => []).add(t);
    }

    final files = <String, Uint8List>{};
    for (final entry in byDepartment.entries) {
      final bytes = await _buildProtectedWorkbook(
        entry.value,
        statusColumnIndex: ExcelExportService.collegeStatusColumnIndex,
        notesColumnIndex: ExcelExportService.collegeNotesColumnIndex,
      );
      files['${_sanitizeFileName(entry.key)}.xlsx'] = bytes;
    }
    return files;
  }

  static String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  static Future<Uint8List> _buildProtectedWorkbook(
    List<Map<String, dynamic>> tickets, {
    required int statusColumnIndex,
    required int notesColumnIndex,
    bool groupByDepartment = false,
  }) async {
    final workbookResult = await ExcelExportService.buildDepartmentWorkbook(
      tickets,
      groupByDepartment: groupByDepartment,
    );
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
