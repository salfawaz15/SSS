import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/report_data_service.dart';
import '../services/report_excel_service.dart';
import '../services/report_pdf_service.dart';
import '../services/ticket_repository.dart';
import '../theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isGeneratingExcel = false;
  bool _isGeneratingPdf = false;
  String? _message;

  Future<ReportData> _loadReportData() async {
    final tickets = await TicketRepository.loadAll();
    return ReportDataService.build(tickets);
  }

  /// يحفظ الملف في مجلد مؤقت ثم يفتحه مباشرة بتطبيق العرض الافتراضي على
  /// الجهاز (Excel/Acrobat/أي تطبيق مثبّت)، ليختار المستخدم من داخله كيف
  /// يريد حفظ الملف أو مشاركته (مثل OneDrive) دون قفل الطريقة عليه.
  Future<void> _openGeneratedFile(Uint8List bytes, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await OpenFilex.open(file.path);
  }

  Future<void> _exportExcel() async {
    setState(() {
      _isGeneratingExcel = true;
      _message = null;
    });

    try {
      final data = await _loadReportData();
      final bytes = ReportExcelService.build(data);
      final cycleId = DateTime.now().toString().substring(0, 10);

      await _openGeneratedFile(bytes, 'تقرير_شامل_$cycleId.xlsx');

      setState(() {
        _isGeneratingExcel = false;
        _message = 'تم إنشاء تقرير Excel وفتحه';
      });
    } catch (e) {
      setState(() {
        _isGeneratingExcel = false;
        _message = 'حدث خطأ أثناء إنشاء تقرير Excel: $e';
      });
    }
  }

  Future<void> _exportPdf() async {
    setState(() {
      _isGeneratingPdf = true;
      _message = null;
    });

    try {
      final data = await _loadReportData();
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = await ReportPdfService.build(
        data,
        title: 'التقرير الشامل',
      );

      await _openGeneratedFile(bytes, 'تقرير_شامل_$cycleId.pdf');

      setState(() {
        _isGeneratingPdf = false;
        _message = 'تم إنشاء تقرير PDF وفتحه';
      });
    } catch (e) {
      setState(() {
        _isGeneratingPdf = false;
        _message = 'حدث خطأ أثناء إنشاء تقرير PDF: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير الشامل')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.green, AppColors.greenDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.green.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.summarize_outlined,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'التقرير الشامل',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'يبني هذا التقرير ملخصًا كاملاً لحالة الإنجاز في كل الأقسام '
                    'والشطرين، بناءً على آخر بيانات مستوردة ومدمجة في التطبيق. '
                    'سيُفتح الملف مباشرة بتطبيق العرض المناسب، ومن داخله يمكنك '
                    'حفظه أو مشاركته (مثل OneDrive) كما تشاء.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingExcel ? null : _exportExcel,
                      icon: _isGeneratingExcel
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.table_chart_outlined),
                      label: const Text(
                        'تصدير تقرير Excel',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingPdf ? null : _exportPdf,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                      ),
                      icon: _isGeneratingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text(
                        'تصدير تقرير PDF',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _message == null
                        ? const SizedBox.shrink()
                        : Container(
                            key: ValueKey(_message),
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: AppColors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_message!)),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
