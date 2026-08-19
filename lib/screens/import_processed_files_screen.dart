import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/processed_file_parser_service.dart';
import '../services/ticket_repository.dart';
import '../theme/app_theme.dart';

class ImportProcessedFilesScreen extends StatefulWidget {
  const ImportProcessedFilesScreen({super.key});

  @override
  State<ImportProcessedFilesScreen> createState() =>
      _ImportProcessedFilesScreenState();
}

class _ImportProcessedFilesScreenState
    extends State<ImportProcessedFilesScreen> {
  bool _isProcessing = false;
  MergeResult? _lastResult;
  String? _errorMessage;

  Future<void> _pickAndMergeFiles() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _lastResult = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      // كان يعود بصمت بلا أي رسالة - يبدو للمستخدم وكأن الضغط لم يفعل شيئًا
      // (سليمان 2026-08-20).
      setState(() {
        _isProcessing = false;
        _errorMessage = 'لم يتم اختيار أي ملف - حاول مرة أخرى.';
      });
      return;
    }

    try {
      final allRows = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        final Uint8List bytes = file.bytes!;
        allRows.addAll(ProcessedFileParserService.parseProcessedRows(bytes));
      }

      final mergeResult = await TicketRepository.mergeProcessedRows(allRows);

      setState(() {
        _lastResult = mergeResult;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء معالجة الملفات: $e';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد الملفات المعالجة')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.green.withValues(alpha: 0.12),
              child: const Icon(
                Icons.file_download_outlined,
                color: AppColors.green,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'اختر ملفات Excel التي عادت من المرشدين الأكاديميين بعد '
              'تعبئة عمودي "حالة الإنجاز" و"ملاحظات" (يمكن اختيار عدة '
              'ملفات دفعة واحدة، حتى 10 ملفات).',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndMergeFiles,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_upload_outlined),
              label: Text(
                _isProcessing ? 'جارٍ المعالجة...' : 'اختيار الملفات',
              ),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            if (_lastResult != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: AppColors.green,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'تم الدمج',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'عدد الصفوف المُطابقة والمُحدَّثة: ${_lastResult!.matchedCount}',
                    ),
                    if (_lastResult!.unmatchedCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'صفوف لم تُطابق أي حالة: ${_lastResult!.unmatchedCount} '
                          '(قد تكون من دفعة سابقة أو بيانات مختلفة)',
                          style: TextStyle(color: Colors.orange.shade800),
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
