import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/firestore_ticket_service.dart';
import '../services/report_data_service.dart';
import '../services/report_excel_service.dart';
import '../services/report_pdf_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'portal_header.dart';

/// شاشة حساب "العرض فقط" (أمين الوحدة / سكرتير الوحدة): استطلاع وعرض
/// وطباعة التقرير الشامل حصرًا - بلا أي صلاحية رفع أو تنزيل ملفات الأقسام
/// أو الاطلاع على تفاصيل الحالات الفردية. قواعد أمان Firestore تمنح هذا
/// الحساب قراءة فقط لمجموعة tickets (بلا كتابة إطلاقًا).
class ViewerReportsScreen extends StatefulWidget {
  const ViewerReportsScreen({super.key});

  @override
  State<ViewerReportsScreen> createState() => _ViewerReportsScreenState();
}

class _ViewerReportsScreenState extends State<ViewerReportsScreen> {
  bool _isExportingExcel = false;
  bool _isExportingPdf = false;
  bool _isPrinting = false;
  String? _message;

  Future<ReportData> _loadReportData() async {
    final tickets = await FirestoreTicketService.watchAllTickets().first;
    return ReportDataService.build(tickets);
  }

  Future<void> _exportExcel() async {
    setState(() {
      _isExportingExcel = true;
      _message = null;
    });
    try {
      final data = await _loadReportData();
      final bytes = ReportExcelService.build(data);
      final cycleId = DateTime.now().toString().substring(0, 10);
      downloadBytes(bytes, 'تقرير_شامل_$cycleId.xlsx');
      setState(() => _message = 'تم تنزيل تقرير Excel');
    } catch (e) {
      setState(() => _message = 'حدث خطأ أثناء إنشاء تقرير Excel: $e');
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() {
      _isExportingPdf = true;
      _message = null;
    });
    try {
      final data = await _loadReportData();
      final cycleId = DateTime.now().toString().substring(0, 10);
      final bytes = await ReportPdfService.build(
        data,
        title: 'التقرير الشامل',
        // يستبعد جدول تفصيل كل مرشد (مئات الصفوف على مستوى الجامعة) - كان
        // السبب الأكبر لتجميد المتصفح أثناء بناء هذا التقرير تحديدًا.
        includeAdvisorDetail: false,
      );
      downloadBytes(bytes, 'تقرير_شامل_$cycleId.pdf');
      setState(() => _message = 'تم تنزيل تقرير PDF');
    } catch (e) {
      setState(() => _message = 'حدث خطأ أثناء إنشاء تقرير PDF: $e');
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _printPdf() async {
    setState(() {
      _isPrinting = true;
      _message = null;
    });
    try {
      final data = await _loadReportData();
      final bytes = await ReportPdfService.build(
        data,
        title: 'التقرير الشامل',
        // يستبعد جدول تفصيل كل مرشد (مئات الصفوف على مستوى الجامعة) - كان
        // السبب الأكبر لتجميد المتصفح أثناء بناء هذا التقرير تحديدًا.
        includeAdvisorDetail: false,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      setState(() => _message = 'حدث خطأ أثناء الطباعة: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'التقرير الشامل',
      showBackButton: false,
      body: Center(
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.green, AppColors.greenDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
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
                  'استطلاع وعرض وطباعة ملخص حالة الإنجاز في كل الأقسام '
                  'والشطرين - بلا صلاحية رفع أو تنزيل ملفات الأقسام.',
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
                    onPressed: _isPrinting ? null : _printPdf,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.print_outlined),
                    label: const Text('طباعة التقرير', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isExportingExcel ? null : _exportExcel,
                    icon: _isExportingExcel
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.table_chart_outlined),
                    label: const Text('تنزيل تقرير Excel', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isExportingPdf ? null : _exportPdf,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                    icon: _isExportingPdf
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('تنزيل تقرير PDF', style: TextStyle(fontSize: 15)),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_message!, textAlign: TextAlign.center),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
