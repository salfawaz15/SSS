import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;

import '../models/advisor_roster_entry.dart';
import 'advisor_name_matching.dart';
import 'excel_export_service.dart';
import 'excel_protection_service.dart';

/// يبني ملف مضغوط (ZIP) يحتوي ملف Excel محمي منفصل لكل مرشد أكاديمي ضمن
/// قائمة حالات (عادة حالات قسم/شطر واحد) - بدل ملف واحد يخلط كل المرشدين،
/// حتى يستلم كل مرشد ملفه الخاص فقط ويسهل معرفة إنجاز كل مرشد لاحقًا.
class AdvisorZipService {
  static String _normalizeForMatch(String s) => normalizeAdvisorNameForMatch(s);

  /// يوحّد نص القسم للمقارنة بين مصدرين يختلفان فعليًا بطريقتين معًا: (1)
  /// قائمة مرشدي القسم الرسمية (`advisor_roster`) تخزّنه بادئة "قسم ..."
  /// (مثال: "قسم نظم المعلومات الادارية") بينما حقل القسم بالتذكرة نفسها
  /// (من `ExcelParserService`) يخزّنه بلا البادئة. (2) تهجئة "الاقتصاد
  /// والتمويل" تحديدًا تختلف بمسافة حول "و" بين المصدرين ("الاقتصاد و
  /// التمويل" بالـroster مقابل "الاقتصاد والتمويل" بالتذكرة) - فتُحذف كل
  /// المسافات لا البادئة فقط. بدون هذا التوحيد الكامل، أي مطابقة مفتاح
  /// (قسم|شطر) بين المصدرين تفشل بصمت لبعض الأقسام - هذا بالضبط ما كان
  /// يمنع توزيع حالات المنسّقين فعليًا رغم التعرّف عليها بنجاح (خلل حقيقي
  /// مؤكَّد ببيانات حية عبر محاكاة Node.js على تذاكر Firestore الفعلية،
  /// سليمان 2026-08-25).
  static String _normalizeDept(String s) {
    final noPrefix = s.trim().replaceFirst(RegExp(r'^قسم\s*'), '');
    return noPrefix.replaceAll(RegExp(r'\s+'), '');
  }

  /// يجمّع الحالات حسب المرشد الأكاديمي المذكور في كل حالة كما هي (بلا أي
  /// إعادة توزيع) - السلوك الافتراضي عند عدم توفر قائمة مرشدي القسم.
  static Map<String, List<Map<String, dynamic>>> _groupByAdvisorName(
    List<Map<String, dynamic>> tickets,
  ) {
    final byAdvisor = <String, List<Map<String, dynamic>>>{};
    for (final t in tickets) {
      final advisor = (t['advisor'] ?? '').toString().trim();
      final key = advisor.isEmpty ? 'بدون مرشد محدد' : advisor;
      byAdvisor.putIfAbsent(key, () => []).add(t);
    }
    return byAdvisor;
  }

  /// يجمّع الحالات حسب المرشد، لكن حالات أي منسّق قسم أو مرشد في إجازة
  /// (حسب قائمة مرشدي القسم الرسمية) تُوزَّع بالتساوي (Round-robin) على
  /// بقية مرشدي نفس القسم/الشطر بدلاً من إبقائها معه - لتفريغ المنسّق لأعمال
  /// الوحدة، أو لأن المرشد لن يعالج حالاته فعليًا وهو في إجازة، خلال فترة
  /// الحذف والإضافة. لا يغيّر هذا المرشد الأكاديمي الرسمي للطالب في أي مكان
  /// آخر - فقط من يُسنَد إليه معالجة هذه الحالة داخل هذا الملف.
  static Map<String, List<Map<String, dynamic>>> _groupWithCoordinatorRelief(
    List<Map<String, dynamic>> tickets,
    List<AdvisorRosterEntry> roster,
  ) {
    final byAdvisor = <String, List<Map<String, dynamic>>>{};

    // فهرس: (قسم|شطر|اسم مُطبَّع بتسامح) -> إدخال القائمة، لمطابقة اسم
    // المرشد المكتوب في الحالة بقائمة مرشدي نفس القسم/الشطر تحديدًا.
    final rosterByKey = <String, AdvisorRosterEntry>{};
    // فهرس احتياطي بالاسم المطبَّع فقط (بلا قسم/شطر) - يُستخدم فقط عند عدم
    // وجود تطابق بالمفتاح الكامل، وفقط إن كان الاسم فريدًا في كل القائمة.
    final rosterByNameOnly = <String, List<AdvisorRosterEntry>>{};
    for (final r in roster) {
      rosterByKey['${_normalizeDept(r.department)}|${r.shatr}|${_normalizeForMatch(r.name)}'] = r;
      rosterByNameOnly.putIfAbsent(_normalizeForMatch(r.name), () => []).add(r);
    }
    // بقية مرشدي كل (قسم|شطر) بلا المنسّقين ولا من هم في إجازة - لتوزيع
    // حالات المُعفَين عليهم فقط.
    final regularsByGroup = <String, List<AdvisorRosterEntry>>{};
    for (final r in roster) {
      if (r.isCoordinator || r.isOnLeave) continue;
      regularsByGroup.putIfAbsent('${_normalizeDept(r.department)}|${r.shatr}', () => []).add(r);
    }

    // حالات كل مُعفى (منسّق أو في إجازة) مجمَّعة أولاً بمفتاح (قسم|شطر)
    // لتوزيعها دفعة واحدة بالتساوي (round-robin) بدل توزيع كل حالة بمعزل
    // عن الأخرى.
    final reliefTicketsByGroup = <String, List<Map<String, dynamic>>>{};

    for (final t in tickets) {
      final advisorName = (t['advisor'] ?? '').toString().trim();
      final department = _normalizeDept((t['department'] ?? '').toString());
      final shatr = (t['shatr'] ?? '').toString();
      final key = advisorName.isEmpty ? 'بدون مرشد محدد' : advisorName;

      var rosterEntry = rosterByKey['$department|$shatr|${_normalizeForMatch(advisorName)}'];
      if (rosterEntry == null) {
        final candidates = rosterByNameOnly[_normalizeForMatch(advisorName)];
        if (candidates != null && candidates.length == 1) {
          rosterEntry = candidates.first;
        }
      }
      if (rosterEntry != null && (rosterEntry.isCoordinator || rosterEntry.isOnLeave)) {
        reliefTicketsByGroup.putIfAbsent('$department|$shatr', () => []).add(t);
        continue;
      }
      // نستخدم الاسم الموحَّد من قائمة مرشدي القسم الرسمية عند التعرّف عليه
      // بدل الاسم الخام كما كُتب في نموذج Microsoft Forms - حتى لا ينتج ملف
      // منفصل لنفس المرشد بسبب اختلاف بسيط في الكتابة (لقب، مسافة، إلخ).
      final canonicalKey = rosterEntry?.name ?? key;
      byAdvisor.putIfAbsent(canonicalKey, () => []).add(t);
    }

    for (final entry in reliefTicketsByGroup.entries) {
      final regulars = regularsByGroup[entry.key];
      if (regulars == null || regulars.isEmpty) {
        // لا يوجد مرشدون عاديون معروفون لهذا القسم/الشطر - تبقى الحالات
        // مع المرشد نفسه بدل فقدانها.
        for (final t in entry.value) {
          final advisorName = (t['advisor'] ?? '').toString().trim();
          final key = advisorName.isEmpty ? 'بدون مرشد محدد' : advisorName;
          byAdvisor.putIfAbsent(key, () => []).add(t);
        }
        continue;
      }
      for (var i = 0; i < entry.value.length; i++) {
        final target = regulars[i % regulars.length];
        byAdvisor.putIfAbsent(target.name, () => []).add(entry.value[i]);
      }
    }

    return byAdvisor;
  }

  /// يجمّع الحالات حسب من يُسنَد إليه معالجتها فعليًا (بعد تفريغ المنسّق إن
  /// وُجدت قائمة مرشدي القسم) - نفس التجميع المستخدَم لبناء ملفات ZIP، لكن
  /// مُتاح هنا أيضًا للتقارير (ReportDataService) حتى تعكس تقارير المتابعة
  /// من يعالج الحالة فعليًا بدل المرشد الرسمي المسجَّل في نموذج التقديم فقط
  /// (فلا يظهر منسّق قسم "لديه" حالات معلَّقة بعد أن تفرَّغ منها فعليًا).
  static Map<String, List<Map<String, dynamic>>> resolveEffectiveGroups(
    List<Map<String, dynamic>> tickets, {
    List<AdvisorRosterEntry>? roster,
  }) {
    return (roster != null && roster.isNotEmpty)
        ? _groupWithCoordinatorRelief(tickets, roster)
        : _groupByAdvisorName(tickets);
  }

  static Future<Uint8List> buildZip(
    List<Map<String, dynamic>> tickets, {
    List<AdvisorRosterEntry>? roster,
  }) async {
    final files = await buildAdvisorFiles(tickets, roster: roster);
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final zipBytes = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipBytes);
  }

  /// يبني ملف Excel محمي مستقل لكل مرشد أكاديمي ضمن [tickets]، بلا ضغطهم
  /// بملف ZIP - يُستخدَم مباشرة عبر [buildZip] (قسم/شطر واحد)، ومتاح هنا
  /// أيضًا لتجميع عدة أقسام/شطرين معًا بمجلدات متداخلة (مثال: تنزيل الكل).
  /// المفتاح هو اسم الملف الآمن ("اسم_المرشد.xlsx") بلا أي مسار مجلد.
  static Future<Map<String, Uint8List>> buildAdvisorFiles(
    List<Map<String, dynamic>> tickets, {
    List<AdvisorRosterEntry>? roster,
  }) async {
    final byAdvisor = resolveEffectiveGroups(tickets, roster: roster);

    final files = <String, Uint8List>{};

    for (final entry in byAdvisor.entries) {
      final advisorTickets = entry.value;
      final workbookResult = await ExcelExportService.buildDepartmentWorkbook(advisorTickets, includeInstructions: true);
      final withReasonsSheet = _addReasonsReferenceSheet(workbookResult.bytes);
      final dataRowCount = workbookResult.totalDataRowCount;
      final protectedBytes = ExcelProtectionService.protect(
        withReasonsSheet,
        dropdowns: [
          DropdownColumn(
            columnIndex: ExcelExportService.advisorStatusColumnIndex,
            options: ExcelProtectionService.advisorActionStatusOptions,
          ),
          DropdownColumn(
            columnIndex: ExcelExportService.advisorNotesColumnIndex,
            rangeFormula: "'$_reasonsSheetName'!\$A\$1:\$A\$${ExcelExportService.advisorReasonOptions.length}",
          ),
        ],
        unlockedColumnIndexes: [
          ExcelExportService.advisorStatusColumnIndex,
          ExcelExportService.advisorNotesColumnIndex,
          ExcelExportService.advisorOtherReasonColumnIndex,
        ],
        // تبسيط الملف قدر الإمكان (سليمان صراحةً 2026-08-25): يُخفى كل ما لا
        // يحتاجه المرشد فعليًا أو لا يجوز أن يظهر له - تبقى القيم موجودة
        // بالملف فعليًا (لازمة عند إعادة القراءة/الدمج) لكن مخفيّة عنه بصريًا.
        // الشطر/القسم/اسم المرشد: موحَّدة عبر كل صفوف ملفه، تكرارها لا يفيد.
        // رقم الجوال: التواصل مع الطالب عبر القنوات الرسمية فقط، لا هاتفيًا.
        // رمز المقرر: اسم المقرر وحده كافٍ عمليًا.
        // منسّق القسم/الكلية: لا يملؤهما المرشد أصلاً.
        hiddenColumnIndexes: [
          ExcelExportService.shatrColumnIndex,
          ExcelExportService.departmentColumnIndex,
          ExcelExportService.advisorNameColumnIndex,
          ExcelExportService.phoneColumnIndex,
          ExcelExportService.courseCodeColumnIndex,
          ExcelExportService.coordinatorStatusColumnIndex,
          ExcelExportService.coordinatorNotesColumnIndex,
          ExcelExportService.collegeStatusColumnIndex,
          ExcelExportService.collegeNotesColumnIndex,
        ],
        dataRowCount: dataRowCount,
        headerRowCount: 2,
      );

      final finalBytes = ExcelProtectionService.finalizeWorkbook(
        protectedBytes,
        hiddenSheetNames: [_reasonsSheetName],
      );

      final safeName = _sanitizeFileName(entry.key);
      files['$safeName.xlsx'] = finalBytes;
    }

    return files;
  }

  static const String _reasonsSheetName = 'قائمة الأسباب';

  /// يضيف ورقة مرجعية مخفية بأسباب عدم التنفيذ الاثني عشر - قائمة القيم
  /// كاملة (468 حرفًا) تتجاوز حد الطول (~255 حرفًا) الذي يرفضه إكسل لقائمة
  /// مكتوبة مباشرة داخل صيغة `dataValidation`، فيجب أن تكون مرجعًا لنطاق
  /// خلايا بدل نص حرفي (نفس أسلوب [AdvisingScheduleExcelService]).
  static Uint8List _addReasonsReferenceSheet(Uint8List rawBytes) {
    final workbook = xls.Excel.decodeBytes(rawBytes);
    final reasonsSheet = workbook[_reasonsSheetName];
    for (var i = 0; i < ExcelExportService.advisorReasonOptions.length; i++) {
      reasonsSheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i)).value =
          xls.TextCellValue(ExcelExportService.advisorReasonOptions[i]);
    }
    return Uint8List.fromList(workbook.encode()!);
  }

  static String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }
}
