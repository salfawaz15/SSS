import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../models/course_section_record.dart';
import '../services/course_schedule_repository.dart' show ShatrLabel;
import '../services/docx_schedule_parser_service.dart';
import '../services/pdf_schedule_parser_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'portal_header.dart';

// CSV نصّي بسيط (فاصلة، بلا اقتباس تعقيدًا - النصوص هنا خالية من الفواصل
// أصلاً) - سليمان صراحةً (2026-08-24): "الأفضل تنزيل الملف لكل رفعة كنسخة
// CSV وإرسالها لك للمقارنة" بدل قراءة لقطات شاشة يدويًا.
String _toCsv(List<ParsedCourseSectionWithShatr> sections) {
  final buffer = StringBuffer('الشطر,رمز المقرر,اسم المقرر,التسلسل,الشعبة النظرية,الشعبة العملية,'
      'المحاضر,محاضر العملي,المواعيد,قاعات المواعيد,المستفيد\n');
  for (final s in sections) {
    final r = s.record;
    final meetings = r.meetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join(' | ');
    final rooms = r.meetings.map((m) => m.room).join(' | ');
    buffer.writeln([
      s.shatr?.label ?? '',
      r.courseCode,
      r.courseName,
      r.sequence,
      r.theorySection,
      r.practicalSection ?? '',
      r.instructorName ?? '',
      r.practicalInstructorName ?? '',
      meetings,
      rooms,
      s.beneficiary,
    ].join(','));
  }
  return buffer.toString();
}

Future<void> _downloadCsv(List<ParsedCourseSectionWithShatr> sections, String filename) =>
    downloadBytes(utf8.encode('﻿${_toCsv(sections)}'), filename);

List<ParsedCourseSectionWithShatr> _parsePdfFilesInIsolate(List<Uint8List> filesBytes) => [
      for (final bytes in filesBytes) ...PdfScheduleParserService.parseSectionsWithShatr(bytes),
    ];

/// صفحة اختبار (preview) مفرَّغة بالكامل - بلا أي حفظ Firestore - لمقارنة
/// دقة قراءة جدول "الحويّة" من PDF مباشرة (تجريبي) مقابل القراءة الحالية
/// المعتمدة من Word docx، جنبًا إلى جنب - بطلب سليمان صراحةً (2026-08-24):
/// "تُنشأ صفحتان معاينة مفرَّغة، واحدة تقبل PDF وواحدة تقبل Word، ونقارن
/// النتائج" قبل أي تعديل على تدفّق الرفع الحقيقي.
class ScheduleParsePreviewScreen extends StatefulWidget {
  const ScheduleParsePreviewScreen({super.key});

  @override
  State<ScheduleParsePreviewScreen> createState() => _ScheduleParsePreviewScreenState();
}

class _ScheduleParsePreviewScreenState extends State<ScheduleParsePreviewScreen> {
  List<ParsedCourseSectionWithShatr>? _docxResult;
  List<ParsedCourseSectionWithShatr>? _pdfResult;
  bool _docxBusy = false;
  bool _pdfBusy = false;
  String? _docxError;
  String? _pdfError;

  void _clearDocx() {
    setState(() {
      _docxResult = null;
      _docxError = null;
    });
  }

  void _clearPdf() {
    setState(() {
      _pdfResult = null;
      _pdfError = null;
    });
  }

  // يسمح باختيار ملفين معًا (شطر الطلاب + شطر الطالبات) دفعة واحدة بدل رفع كل
  // شطر بمحاولة منفصلة - سليمان صراحةً (2026-08-24).
  Future<void> _pickDocx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _docxBusy = true;
      _docxError = null;
      _docxResult = null;
    });
    try {
      final parsed = <ParsedCourseSectionWithShatr>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        parsed.addAll(DocxScheduleParserService.parseSectionsWithShatr(file.bytes!));
      }
      setState(() => _docxResult = parsed);
    } catch (e) {
      setState(() => _docxError = 'تعذّرت قراءة الملف: $e');
    } finally {
      setState(() => _docxBusy = false);
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _pdfBusy = true;
      _pdfError = null;
      _pdfResult = null;
    });
    try {
      final filesBytes = [for (final f in result.files) if (f.bytes != null) f.bytes!];
      final parsed = await compute(_parsePdfFilesInIsolate, filesBytes);
      setState(() => _pdfResult = parsed);
    } catch (e) {
      setState(() => _pdfError = 'تعذّرت قراءة الملف: $e');
    } finally {
      setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'معاينة تجريبية: مقارنة قراءة PDF مقابل Word',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // علامة نسخة صريحة - للتحقق أن المتصفح يعرض فعلاً آخر نشر لا نسخة
            // مخبَّأة (سليمان صراحةً 2026-08-24: نفس الخلل القديم بالمحاضر
            // والملخص لا يزالان يظهران رغم تأكيد الخادم نشر نسخة أحدث - يُرفع
            // هذا الرقم يدويًا بكل نشرة تجريبية لهذه الصفحة تحديدًا).
            const Text(
              'نسخة الاختبار: 7 (إن كنت ترى رقمًا مختلفًا فالمتصفح يعرض نسخة مخبَّأة)',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'أداة اختبار فقط - لا تحفظ أي بيانات. ارفع نفس ملف الجدول الدراسي '
              'بصيغتيه (docx و pdf) وقارن عدد الشعب والتفاصيل بين النتيجتين.',
              style: TextStyle(color: AppColors.greenDark, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_docxResult != null && _pdfResult != null) ...[
              _ComparisonSummary(docx: _docxResult!, pdf: _pdfResult!),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Panel(
                      title: 'Word (docx) - المعتمد حاليًا',
                      busy: _docxBusy,
                      error: _docxError,
                      result: _docxResult,
                      onPick: _pickDocx,
                      onClear: _clearDocx,
                      onDownload: () => _downloadCsv(_docxResult!, 'نتيجة_قراءة_Word.csv'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Panel(
                      title: 'PDF - تجريبي',
                      busy: _pdfBusy,
                      error: _pdfError,
                      result: _pdfResult,
                      onPick: _pickPdf,
                      onClear: _clearPdf,
                      onDownload: () => _downloadCsv(_pdfResult!, 'نتيجة_قراءة_PDF.csv'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonSummary extends StatelessWidget {
  final List<ParsedCourseSectionWithShatr> docx;
  final List<ParsedCourseSectionWithShatr> pdf;

  const _ComparisonSummary({required this.docx, required this.pdf});

  // رمز المقرر + التسلسل + الشطر. استُبعد "المستفيد" من مفتاح المطابقة
  // (خلافًا لمفتاح الدمج الداخلي بالمحلِّلَين) لأن نصه قد يمتد لسطرين بالملف
  // الأصلي (أكثر من كلية مستفيدة)، ومستخرِج PDF يقرأ كل سطر كصف مستقل بموضع
  // مختلف فينتج نصًا مختلفًا شكليًا عن نص Word المدمَج رغم كونهما نفس الشعبة
  // فعليًا - سليمان صراحةً (2026-08-24) بعد أول اختبار حي أظهر 0 تطابق رغم
  // تساوي العددين تمامًا (412=412). **الشطر أُعيد للمفتاح لاحقًا** بعد رفع
  // ملفَي الطلاب والطالبات معًا: بدونه تصادمت شعب من الملفين لها نفس رمز
  // المقرر والتسلسل (كل شطر يبدأ ترقيم التسلسل من جديد) فاختُزل 710 شعبة
  // فعلية إلى 440 مفتاحًا فريدًا فقط - دليل فعلي من سليمان (لقطة شاشة).
  String _key(ParsedCourseSectionWithShatr s) => '${s.record.courseCode}|${s.record.sequence}|${s.shatr}';

  @override
  Widget build(BuildContext context) {
    final docxByKey = {for (final s in docx) _key(s): s};
    final pdfByKey = {for (final s in pdf) _key(s): s};
    final onlyInDocx = docxByKey.keys.toSet().difference(pdfByKey.keys.toSet());
    final onlyInPdf = pdfByKey.keys.toSet().difference(docxByKey.keys.toSet());
    final commonKeys = docxByKey.keys.toSet().intersection(pdfByKey.keys.toSet());

    var identicalCount = 0;
    final fieldDiffs = <String>[];
    for (final key in commonKeys) {
      final d = docxByKey[key]!.record;
      final p = pdfByKey[key]!.record;
      final sameInstructor = (d.instructorName ?? '') == (p.instructorName ?? '');
      final sameRoom = d.meetings.isNotEmpty &&
          p.meetings.isNotEmpty &&
          d.meetings.first.room == p.meetings.first.room;
      final sameTime = d.meetings.isNotEmpty &&
          p.meetings.isNotEmpty &&
          d.meetings.first.from == p.meetings.first.from &&
          d.meetings.first.to == p.meetings.first.to;
      final sameMeetingsCount = d.meetings.length == p.meetings.length;
      if (sameInstructor && sameRoom && sameTime && sameMeetingsCount) {
        identicalCount++;
      } else if (fieldDiffs.length < 15) {
        fieldDiffs.add(key);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              Text('عدد شعب Word: ${docx.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('عدد شعب PDF: ${pdf.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('نفس رمز المقرر+التسلسل: ${commonKeys.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('متطابقة تمامًا (محاضر/وقت/قاعة): $identicalCount',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              Text('نفس الشعبة لكن باختلاف تفاصيل: ${commonKeys.length - identicalCount}',
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              Text('موجودة بـWord فقط: ${onlyInDocx.length}', style: const TextStyle(color: Colors.red)),
              Text('موجودة بـPDF فقط: ${onlyInPdf.length}', style: const TextStyle(color: Colors.red)),
            ],
          ),
          if (fieldDiffs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('أمثلة شعب باختلاف تفاصيل: ${fieldDiffs.join('، ')}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final bool busy;
  final String? error;
  final List<ParsedCourseSectionWithShatr>? result;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final VoidCallback onDownload;

  const _Panel({
    required this.title,
    required this.busy,
    required this.error,
    required this.result,
    required this.onPick,
    required this.onClear,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              // زر التفريغ دائمًا يسار مستطيل زر الاختيار (قاعدة ثابتة بكل
              // الموقع) - يظهر فقط بعد وجود نتيجة أو خطأ ليُمسحا قبل رفعة
              // جديدة، لا قبل أول رفعة حين لا شيء لتفريغه أصلًا.
              if (result != null) ...[
                OutlinedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('تنزيل CSV'),
                ),
                const SizedBox(width: 8),
              ],
              if (result != null || error != null) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : onClear,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تفريغ'),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('اختيار ملف/ملفين'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          if (result != null) Text('عدد الشعب: ${result!.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (result != null)
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 14,
                  headingRowHeight: 34,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 46,
                  columns: const [
                    DataColumn(label: Text('المقرر')),
                    DataColumn(label: Text('تسلسل')),
                    DataColumn(label: Text('شعبة')),
                    DataColumn(label: Text('الشطر')),
                    DataColumn(label: Text('المحاضر')),
                    DataColumn(label: Text('الموعد')),
                    DataColumn(label: Text('المستفيد')),
                  ],
                  rows: [
                    for (final s in result!)
                      DataRow(cells: [
                        DataCell(SizedBox(width: 140, child: Text(s.record.courseName, overflow: TextOverflow.ellipsis))),
                        DataCell(Text('${s.record.sequence}')),
                        DataCell(Text(s.record.theorySection)),
                        DataCell(Text(s.shatr?.label ?? '-')),
                        DataCell(Text(s.record.instructorName ?? '-')),
                        DataCell(Text(_meetingsText(s.record.meetings))),
                        DataCell(SizedBox(width: 140, child: Text(s.beneficiary, overflow: TextOverflow.ellipsis))),
                      ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _meetingsText(List<CourseMeeting> meetings) =>
      meetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join(' | ');
}
