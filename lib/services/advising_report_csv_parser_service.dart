import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../models/advising_case_record.dart';
import 'advising_report_parser_service.dart';
import 'course_schedule_repository.dart' show Shatr;
import 'windows1256_decoder.dart';

class _CsvParseRequest {
  final Uint8List bytes;
  final int? shatrIndex;
  final Map<String, String>? advisorShatrByName;
  final Set<String>? knownAdvisorNameKeys;
  const _CsvParseRequest(this.bytes, this.shatrIndex, this.advisorShatrByName, this.knownAdvisorNameKeys);
}

/// كـ[AdvisingReportPdfParseResult] لكن لقارئ CSV.
class AdvisingReportCsvParseResult {
  final List<AdvisingCaseRecord> records;
  final List<String> unresolvedShatrRows;
  final Map<String, int> exclusionCounts;
  const AdvisingReportCsvParseResult(this.records, this.unresolvedShatrRows, this.exclusionCounts);
}

AdvisingReportCsvParseResult _parseAdvisingCsvInIsolate(_CsvParseRequest request) {
  final unresolved = <String>[];
  final exclusionCounts = <String, int>{};
  final records = AdvisingReportCsvParserService.parse(
    request.bytes,
    shatr: request.shatrIndex == null ? null : Shatr.values[request.shatrIndex!],
    advisorShatrByName: request.advisorShatrByName,
    unresolvedShatrRows: unresolved,
    exclusionCounts: exclusionCounts,
    knownAdvisorNameKeys: request.knownAdvisorNameKeys,
  );
  return AdvisingReportCsvParseResult(records, unresolved, exclusionCounts);
}

/// يقرأ تقرير "طلاب تابعين لمرشد" من تصدير CSV المباشر للمنظومة الداخلية
/// (Windows-1256، فاصل ";") بدل تحويله لـWord أو PDF أولًا - أسرع وأدق من كليهما
/// لأن الفواصل صريحة بالملف نفسه، لا مُستنتَجة هندسيًا من مواضع كلمات كما في
/// [AdvisingReportPdfParserService]. اختبرته أداة معاينة مستقلة (Artifact) قبل
/// هذا الكود على ملف حقيقي (سليمان 2026-08-27): 1744 مرشدًا، 42479 طالبًا،
/// مطابقة تامة لعينة يدوية من الملف الخام.
///
/// **بنية الملف** (كل صف بفاصل ";"، الخلية الأولى دومًا فارغة):
/// - صف "بيانات مرشد" (يسبق طلابه): الخلية[1]="رقم المرشد"، [6]=رقم المرشد،
///   [9]=اسمه.
/// - صف "الكلية"/"القسم": الخلية[2]="الكلية :" أو "القسم :"، [6]=القيمة -
///   يُستخدَم لاستبعاد فروع المحافظات (نفس منطق [AdvisingReportParserService]).
/// - صف عناوين الجدول: الخلية[1]="م" - يُحوَّل لصف عناوين مضغوط يفهمه
///   [AdvisingReportParserService.parseRows].
/// - صف بيانات طالب: الخلية[1]=م، [3]=رقم الطالب، [7]=اسم الطالب، [10]=التخصص.
///
/// **إعادة استخدام منطق الأعمال الحالي بدل تكراره**: يُحوَّل كل صف لنفس الصيغة
/// المضغوطة التي ينتجها قارئ docx (خلايا غير فارغة فقط، بترتيب مطابق) ثم
/// يُمرَّر لنفس [AdvisingReportParserService.parseRows] المستخدَم بكل قارّاء
/// الإرشاد الأخرى - يحفظ تلقائيًا كل قواعد الاستبعاد المُتراكِمة هناك (فروع
/// المحافظات، الدراسات العليا، استنتاج الشطر...) بدل احتمال نسيان إحداها هنا.
class AdvisingReportCsvParserService {
  static List<List<String>> _rowsFromCsv(String text) {
    final rows = <List<String>>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty || !line.contains(';')) continue;
      // المسافات داخل بعض الخلايا (كأسماء الكليات/الأقسام) تخرج أحيانًا
      // كمسافة غير فاصلة (NBSP، U+00A0) لا مسافة عادية - تُوحَّد هنا وإلا
      // فشلت مطابقات نصية متعددة الكلمات صامتًا (خلل فعلي مماثل اكتُشف
      // بقارئ الحويّة - سليمان 2026-08-27).
      final cells = line.split(';').map((c) => c.trim().replaceAll('\u00A0', ' ')).toList();

      if (cells.length > 1 && cells[1].contains('رقم') && cells[1].contains('مرشد')) {
        final name = cells.length > 9 ? cells[9] : '';
        final id = cells.length > 6 ? cells[6] : '';
        rows.add([name, id, 'رقم المرشد']);
        continue;
      }
      if (cells.length > 2 && cells[2].contains('الكلية')) {
        final value = cells.length > 6 ? cells[6] : '';
        rows.add(['الكلية :', value]);
        continue;
      }
      if (cells.length > 2 && cells[2].contains('القسم')) continue;
      if (cells.length > 1 && cells[1] == 'م') {
        // صف عناوين أو صف بيانات طالب - كلاهما بنفس المواضع الأربعة.
        String at(int i) => i < cells.length ? cells[i] : '';
        rows.add([at(1), at(3), at(7), at(10)]);
        continue;
      }
      if (cells.length > 3 && RegExp(r'^\d+$').hasMatch(cells[1])) {
        String at(int i) => i < cells.length ? cells[i] : '';
        rows.add([at(1), at(3), at(7), at(10)]);
      }
      // صفوف أخرى (فواصل فارغة، هوامش) تُتجاهَل بصمت - لا معنى لها هنا.
    }
    return rows;
  }

  static List<AdvisingCaseRecord> parse(
    List<int> csvBytes, {
    Shatr? shatr,
    Map<String, String>? advisorShatrByName,
    List<String>? unresolvedShatrRows,
    Map<String, int>? exclusionCounts,
    Set<String>? knownAdvisorNameKeys,
  }) {
    final text = Windows1256Decoder.decode(csvBytes);
    return AdvisingReportParserService.parseRows(
      _rowsFromCsv(text),
      shatr: shatr,
      requireDepartment: false,
      advisorShatrByName: advisorShatrByName,
      unresolvedShatrRows: unresolvedShatrRows,
      exclusionCounts: exclusionCounts,
      knownAdvisorNameKeys: knownAdvisorNameKeys,
    );
  }

  /// نفس [parse] على Isolate منفصل - انظر تعليق مثيله بـ
  /// [AdvisingReportPdfParserService.parseInBackground] لسبب الحاجة لهذا مع
  /// الملفات الكبيرة.
  static Future<AdvisingReportCsvParseResult> parseInBackground(
    Uint8List csvBytes, {
    Shatr? shatr,
    Map<String, String>? advisorShatrByName,
    Set<String>? knownAdvisorNameKeys,
  }) {
    return compute(
      _parseAdvisingCsvInIsolate,
      _CsvParseRequest(csvBytes, shatr?.index, advisorShatrByName, knownAdvisorNameKeys),
    );
  }
}
