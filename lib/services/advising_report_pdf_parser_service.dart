import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../models/advising_case_record.dart';
import 'advising_report_parser_service.dart';
import 'course_schedule_repository.dart' show Shatr;
import 'pdf_table_rows_extractor.dart';

class _PdfParseRequest {
  final Uint8List bytes;
  final int? shatrIndex;
  final Map<String, String>? advisorShatrByName;
  final Set<String>? knownAdvisorNameKeys;
  const _PdfParseRequest(this.bytes, this.shatrIndex, this.advisorShatrByName, this.knownAdvisorNameKeys);
}

/// نتيجة [AdvisingReportPdfParserService.parseInBackground]: السجلات
/// الناجحة، بالإضافة إلى وصف كل صف تعذّر تحديد شطره فاستُبعِد (بدل اختفائه
/// بصمت من كل التحليل - انظر التعليق أعلى [unresolvedShatrRows] بملف
/// advising_report_parser_service.dart لسبب حدوث هذا).
class AdvisingReportPdfParseResult {
  final List<AdvisingCaseRecord> records;
  final List<String> unresolvedShatrRows;
  final Map<String, int> exclusionCounts;
  const AdvisingReportPdfParseResult(this.records, this.unresolvedShatrRows, this.exclusionCounts);
}

AdvisingReportPdfParseResult _parseAdvisingPdfInIsolate(_PdfParseRequest request) {
  final unresolved = <String>[];
  final exclusionCounts = <String, int>{};
  final records = AdvisingReportPdfParserService.parse(
    request.bytes,
    shatr: request.shatrIndex == null ? null : Shatr.values[request.shatrIndex!],
    advisorShatrByName: request.advisorShatrByName,
    unresolvedShatrRows: unresolved,
    exclusionCounts: exclusionCounts,
    knownAdvisorNameKeys: request.knownAdvisorNameKeys,
  );
  return AdvisingReportPdfParseResult(records, unresolved, exclusionCounts);
}

/// يقرأ تقرير "طلاب تابعين لمرشد" مباشرةً من ملف PDF الرسمي (دون الحاجة
/// لتحويله يدويًا إلى Word أولًا كبقية تقارير الإرشاد - انظر التعليق أعلى
/// [AdvisingReportParserService]). استخراج الصفوف نفسه بـ[PdfTableRowsExtractor]
/// (مشترك مع قارئ "بيانات الطلبة الأكاديمية" - [AdvisingBasePdfParserService]).
class AdvisingReportPdfParserService {
  static List<AdvisingCaseRecord> parse(
    List<int> pdfBytes, {
    Shatr? shatr,
    Map<String, String>? advisorShatrByName,
    List<String>? unresolvedShatrRows,
    Map<String, int>? exclusionCounts,
    Set<String>? knownAdvisorNameKeys,
  }) {
    return AdvisingReportParserService.parseRows(
      PdfTableRowsExtractor.extract(pdfBytes),
      shatr: shatr,
      requireDepartment: false,
      advisorShatrByName: advisorShatrByName,
      unresolvedShatrRows: unresolvedShatrRows,
      exclusionCounts: exclusionCounts,
      knownAdvisorNameKeys: knownAdvisorNameKeys,
    );
  }

  /// نفس [parse] لكن على Web Worker/Isolate منفصل عبر `compute` - هذا الملف
  /// كبير (مئات الصفحات) والمعالجة (فرز آلاف الكلمات، بناء آلاف الصفوف)
  /// متزامنة بالكامل؛ استدعاؤها مباشرة على خيط الواجهة كان يُجمِّد التبويب
  /// فعليًا (لا مجرد بطء) طوال مدة المعالجة لأن Flutter لا يحصل على فرصة رسم
  /// إطار واحد حتى تنتهي - عزلها في Worker منفصل يبقي الواجهة مستجيبة.
  static Future<AdvisingReportPdfParseResult> parseInBackground(
    Uint8List pdfBytes, {
    Shatr? shatr,
    Map<String, String>? advisorShatrByName,
    Set<String>? knownAdvisorNameKeys,
  }) {
    return compute(
      _parseAdvisingPdfInIsolate,
      _PdfParseRequest(pdfBytes, shatr?.index, advisorShatrByName, knownAdvisorNameKeys),
    );
  }
}
