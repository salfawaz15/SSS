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
  /// الكلية) - عاد ملفًا واحدًا مدمجًا (سليمان صراحةً 2026-09-05، بعد تجربة
  /// الانقسام لـ5 ملفات ZIP بالمرحلة الأخيرة من التصعيد وتبيّن عدم ملاءمته
  /// هنا). مفروزة حسب حالة **منسّق القسم** (المرحلة السابقة مباشرة على منسّق
  /// الكلية، فهذه الحالات مُصعَّدة أصلاً منه) بثلاث فئات بهذا الترتيب: "تم
  /// التنفيذ" ثم "لم يتم التنفيذ" ثم "لم يعمل عليها" (فارغة)، ثم القسم كمعيار
  /// فرز ثانٍ ليعمل منسّق الكلية قسمًا كاملاً قبل الانتقال للتالي، ثم أولوية
  /// التخرج.
  static Future<Uint8List> buildStage3File(List<Map<String, dynamic>> shatrTickets) {
    return _buildProtectedWorkbook(
      shatrTickets,
      statusColumnIndex: ExcelExportService.collegeStatusColumnIndex,
      notesColumnIndex: ExcelExportService.collegeNotesColumnIndex,
      groupByDepartment: true,
      isCollegeStage: true,
    );
  }

  static Future<Uint8List> _buildProtectedWorkbook(
    List<Map<String, dynamic>> tickets, {
    required int statusColumnIndex,
    required int notesColumnIndex,
    bool groupByDepartment = false,
    bool isCollegeStage = false,
  }) async {
    final workbookResult = await ExcelExportService.buildDepartmentWorkbook(
      tickets,
      groupByDepartment: groupByDepartment,
      isCollegeStage: isCollegeStage,
    );
    final dataRowCount = workbookResult.totalDataRowCount;

    return ExcelProtectionService.protect(
      workbookResult.bytes,
      dropdowns: [
        DropdownColumn(
          columnIndex: statusColumnIndex,
          // خياران فقط (تم/لم يتم التنفيذ) لا الثلاثة القديمة (تم
          // الإنجاز/جزئي/لم يتم) - توحيد مع خياري المرشد بطلب سليمان صراحةً
          // (2026-09-05)، يشمل الآن منسّق القسم ومنسّق الكلية معًا. خيار
          // "جزئي" يبقى مستخدَمًا بتقارير/إحصائيات أخرى بالموقع لحالات
          // مُدخَلة سابقًا - لم تُعدَّل بعد (مرحلة لاحقة بطلب سليمان).
          options: ExcelProtectionService.advisorActionStatusOptions,
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
