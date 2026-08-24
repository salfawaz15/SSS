import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../models/course_section_record.dart';
import '../services/course_schedule_repository.dart' show ShatrLabel;
import '../services/docx_schedule_parser_service.dart';
import '../services/pdf_schedule_parser_service.dart';
import '../theme/app_theme.dart';
import 'portal_header.dart';

List<ParsedCourseSectionWithShatr> _parsePdfInIsolate(Uint8List bytes) =>
    PdfScheduleParserService.parseSectionsWithShatr(bytes);

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

  Future<void> _pickDocx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    setState(() {
      _docxBusy = true;
      _docxError = null;
      _docxResult = null;
    });
    try {
      final parsed = DocxScheduleParserService.parseSectionsWithShatr(result.files.single.bytes!);
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
    );
    if (result == null || result.files.single.bytes == null) return;
    setState(() {
      _pdfBusy = true;
      _pdfError = null;
      _pdfResult = null;
    });
    try {
      final parsed = await compute(_parsePdfInIsolate, result.files.single.bytes!);
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

  String _key(ParsedCourseSectionWithShatr s) =>
      '${s.record.courseCode}|${s.record.sequence}|${s.shatr}|${s.beneficiary}';

  @override
  Widget build(BuildContext context) {
    final docxKeys = docx.map(_key).toSet();
    final pdfKeys = pdf.map(_key).toSet();
    final onlyInDocx = docxKeys.difference(pdfKeys);
    final onlyInPdf = pdfKeys.difference(docxKeys);
    final matched = docxKeys.intersection(pdfKeys);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          Text('عدد شعب Word: ${docx.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('عدد شعب PDF: ${pdf.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('متطابقة: ${matched.length}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          Text('موجودة بـWord فقط: ${onlyInDocx.length}', style: const TextStyle(color: Colors.red)),
          Text('موجودة بـPDF فقط: ${onlyInPdf.length}', style: const TextStyle(color: Colors.orange)),
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

  const _Panel({
    required this.title,
    required this.busy,
    required this.error,
    required this.result,
    required this.onPick,
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
              ElevatedButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('اختيار ملف'),
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
