import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/name_display.dart';
import 'pdf_brand_kit.dart';
import 'report_data_service.dart';
import 'report_filter_service.dart';
import 'ticket_action_stats_service.dart' show ActionTypeCaseCounts, AdvisorCaseStats, DeptShatrPerformance;

/// حزمة وسيطات بناء التقرير الشامل - تُرسَل كاملة إلى خيط معالجة منفصل
/// (isolate عبر compute) حتى لا يجمّد بناء PDF الثقيل (تنسيق عربي + جداول
/// ضخمة لكل الجامعة) خيط الواجهة الرئيسي على الويب، وهو ما كان يظهر للمستخدم
/// كتجمّد كامل للصفحة ("الصفحة غير مستجيبة") في التقارير الكبيرة.
class _OverallReportJob {
  final ReportData data;
  final String title;
  final String? subtitle;
  final ReportScope scope;
  final List<Map<String, dynamic>>? caseDetails;
  final bool includeAdvisorDetail;
  final Uint8List regularFontBytes;
  final Uint8List boldFontBytes;
  final Uint8List logoBytes;
  final DateTime generatedAt;

  _OverallReportJob({
    required this.data,
    required this.title,
    required this.subtitle,
    required this.scope,
    required this.caseDetails,
    required this.includeAdvisorDetail,
    required this.regularFontBytes,
    required this.boldFontBytes,
    required this.logoBytes,
    required this.generatedAt,
  });
}

class _FollowUpReportJob {
  final ReportData data;
  final String title;
  final String? subtitle;
  final List<Map<String, dynamic>> pendingCases;
  final Uint8List regularFontBytes;
  final Uint8List boldFontBytes;
  final Uint8List logoBytes;
  final DateTime generatedAt;

  _FollowUpReportJob({
    required this.data,
    required this.title,
    required this.subtitle,
    required this.pendingCases,
    required this.regularFontBytes,
    required this.boldFontBytes,
    required this.logoBytes,
    required this.generatedAt,
  });
}

/// نقطة دخول قابلة للتشغيل داخل isolate منفصل (يجب أن تكون دالة top-level أو
/// static حتى يقبلها compute). تُعيد بناء الخط من البايتات ثم تنفّذ كل منطق
/// التنسيق الثقيل بمعزل عن خيط الواجهة.
Future<Uint8List> _buildOverallReportInIsolate(_OverallReportJob job) async {
  final regularFont = pw.Font.ttf(job.regularFontBytes.buffer.asByteData());
  final boldFont = pw.Font.ttf(job.boldFontBytes.buffer.asByteData());
  final logo = pw.MemoryImage(job.logoBytes);
  return ReportPdfService._buildOverallDoc(
    job.data,
    title: job.title,
    subtitle: job.subtitle,
    scope: job.scope,
    caseDetails: job.caseDetails,
    includeAdvisorDetail: job.includeAdvisorDetail,
    regularFont: regularFont,
    boldFont: boldFont,
    logo: logo,
    generatedAt: job.generatedAt,
  );
}

Future<Uint8List> _buildFollowUpReportInIsolate(_FollowUpReportJob job) async {
  final regularFont = pw.Font.ttf(job.regularFontBytes.buffer.asByteData());
  final boldFont = pw.Font.ttf(job.boldFontBytes.buffer.asByteData());
  final logo = pw.MemoryImage(job.logoBytes);
  return ReportPdfService._buildFollowUpDoc(
    job.data,
    title: job.title,
    subtitle: job.subtitle,
    pendingCases: job.pendingCases,
    regularFont: regularFont,
    boldFont: boldFont,
    logo: logo,
    generatedAt: job.generatedAt,
  );
}

/// يبني ملف PDF لتقارير الوحدة (شامل / حسب القسم / حسب الشطر / حسب المرشد)،
/// بخط عربي (Noto Naskh Arabic)، مع رسوم بيانية بسيطة مرسومة يدويًا وبطاقات
/// إحصائية بارزة. تختلف الأقسام المعروضة حسب [scope] لتفادي عرض جداول فارغة
/// لا تخص التقرير المطلوب.
class ReportPdfService {
  static final _green = PdfColor.fromHex('154B36');
  static final _greenDark = PdfColor.fromHex('0D3324');
  static final _gold = PdfColor.fromHex('C9A227');
  static final _goldLight = PdfColor.fromHex('F0DD9B');
  static final _red = PdfColor.fromHex('C0392B');
  static final _lightGray = PdfColor.fromHex('E5E9E7');

  // الخط العربي (Noto Naskh Arabic) يُحمَّل مرة واحدة فقط ويُخزَّن مؤقتًا -
  // كان يُعاد تنزيله وتحليله بالكامل من الإنترنت في كل ضغطة "تنزيل PDF"،
  // ما كان يُجمِّد المتصفح لثوانٍ طويلة على الويب (خيط واجهة واحد فقط).
  // نخزّن هنا البايتات الخام فقط (قراءة ملف سريعة) - تحليل الخط الفعلي
  // (pw.Font.ttf) ينتقل الآن لخيط المعالجة المنفصل مع باقي العمل الثقيل.
  static Future<(Uint8List, Uint8List)>? _cachedFontBytes;

  static Future<(Uint8List, Uint8List)> _loadFontBytes() {
    return _cachedFontBytes ??= () async {
      final regularBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      final boldBytes = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
      return (regularBytes.buffer.asUint8List(), boldBytes.buffer.asUint8List());
    }();
  }

  /// حزمة `pdf` تبني عمود الجدول دائمًا من اليسار لليمين بحسب ترتيب القائمة
  /// نفسها بصرف النظر عن أي إعداد اتجاه نص (الـ `Table` الأساسي لا يعكس
  /// ترتيب الأعمدة تلقائيًا حسب الاتجاه، بخلاف `Row`) - لذا لجعل أول عنصر
  /// منطقيًا (مثل "القسم") يظهر أول عمود من اليمين في تقرير عربي، يجب عكس
  /// ترتيب قائمتَي العناوين والصفوف فعليًا قبل تمريرهما لـ TableHelper.
  static (List<String>, List<List<String>>) _rtlTable(
    List<String> headers,
    List<List<String>> rows,
  ) {
    return (
      headers.reversed.toList(),
      rows.map((r) => r.reversed.toList()).toList(),
    );
  }

  // شعار الوحدة (النسخة الذهبية الشفافة المناسبة لخلفية داكنة) يُحمَّل
  // مرة واحدة ويُخزَّن مؤقتًا، ويظهر في ترويسة كل تقرير PDF.
  static Future<Uint8List>? _cachedLogoBytes;

  static Future<Uint8List> _loadLogoBytes() {
    return _cachedLogoBytes ??= rootBundle
        .load('assets/images/unit_logo_final.png')
        .then((b) => b.buffer.asUint8List());
  }

  /// يبني تقرير PDF الشامل/المُفلتر. التنفيذ الفعلي الثقيل (تنسيق الخط
  /// العربي وبناء الجداول والصفحات) ينتقل بالكامل إلى isolate منفصل عبر
  /// compute حتى لا يجمّد خيط الواجهة على الويب أثناء التقارير الكبيرة (كل
  /// حالات الجامعة دفعة واحدة) - كان هذا يظهر للمستخدم كصفحة "غير مستجيبة"
  /// تمامًا لثوانٍ أو دقائق طويلة.
  static Future<Uint8List> build(
    ReportData data, {
    required String title,
    String? subtitle,
    ReportScope scope = ReportScope.overall,
    List<Map<String, dynamic>>? caseDetails,
    bool includeAdvisorDetail = true,
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final logoBytes = await _loadLogoBytes();
    return compute(
      _buildOverallReportInIsolate,
      _OverallReportJob(
        data: data,
        title: title,
        subtitle: subtitle,
        scope: scope,
        caseDetails: caseDetails,
        includeAdvisorDetail: includeAdvisorDetail,
        regularFontBytes: regularBytes,
        boldFontBytes: boldBytes,
        logoBytes: logoBytes,
        generatedAt: DateTime.now(),
      ),
    );
  }

  static Future<Uint8List> _buildOverallDoc(
    ReportData data, {
    required String title,
    String? subtitle,
    ReportScope scope = ReportScope.overall,
    List<Map<String, dynamic>>? caseDetails,
    bool includeAdvisorDetail = true,
    required pw.Font regularFont,
    required pw.Font boldFont,
    required pw.MemoryImage logo,
    required DateTime generatedAt,
  }) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    // الأقسام العشرة المزروعة صفريًا في ReportDataService مفيدة للتقرير
    // الشامل فقط (لإظهار تغطية كل الأقسام)؛ في التقارير المُفلترة تُعتبر
    // إدخالات فارغة مزعجة يجب حذفها.
    final relevantDepartments = scope == ReportScope.overall
        ? data.departments
        : data.departments.where((d) => d.counts.total > 0).toList();

    final sections = <pw.Widget>[
      _summarySection(data),
      pw.SizedBox(height: 18),
    ];

    if (scope == ReportScope.overall) {
      sections.addAll([
        _shatrTable(data),
        pw.SizedBox(height: 16),
        _departmentsTable(relevantDepartments),
        pw.SizedBox(height: 16),
        // نسخة مضغوطة (بلا رسم عمودي إضافي مكرِّر لنفس البيانات) حتى يبقى
        // التقرير بأكمله صفحتين فقط كما طُلب تحديدًا.
        _departmentsChart(relevantDepartments),
        pw.SizedBox(height: 16),
        // جدول تفصيل كل مرشد على حدة (قد يبلغ مئات الصفوف على مستوى الجامعة
        // كاملة) يُستبعَد من "التقرير الشامل السريع" تحديدًا - هذا الجدول
        // كان السبب الأكبر في إبطاء بناء PDF لدرجة تجميد المتصفح. لا يزال
        // متاحًا كاملاً عبر "التقارير التفصيلية" لكل قسم/شطر على حدة (نطاق
        // أصغر بكثير وأسرع بناءً).
        if (includeAdvisorDetail) ...[
          _advisorsTable(relevantDepartments),
          pw.SizedBox(height: 16),
        ],
      ]);
    } else if (scope == ReportScope.shatr) {
      sections.addAll([
        _departmentsTable(relevantDepartments),
        pw.SizedBox(height: 16),
        _departmentsChart(relevantDepartments),
        pw.SizedBox(height: 16),
        _advisorsTable(relevantDepartments),
        pw.SizedBox(height: 16),
      ]);
    } else if (scope == ReportScope.department) {
      sections.addAll([
        _advisorsChart(relevantDepartments),
        pw.SizedBox(height: 16),
        _advisorsTable(relevantDepartments),
        pw.SizedBox(height: 16),
      ]);
    }
    // scope == advisor: الملخص فقط + تفاصيل الحالات أدناه (لا حاجة لجداول
    // تجميعية لشخص واحد).

    sections.add(_completedByChart(data));

    if (caseDetails != null && caseDetails.isNotEmpty) {
      sections.add(pw.SizedBox(height: 16));
      sections.add(_caseDetailsTable(caseDetails));
    }

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => PdfBrandKit.header(title: title, logo: logo, subtitle: subtitle, generatedAt: generatedAt),
        footer: PdfBrandKit.footer,
        build: (context) => sections,
      ),
    );

    return doc.save();
  }

  static pw.Widget _summarySection(ReportData data) {
    final o = data.overall;
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _lightGray,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryStat('إجمالي الحالات', '${o.total}', _greenDark),
          _summaryStat('تم الإنجاز', '${o.completed}', _green),
          _summaryStat('جزئي', '${o.partial}', _gold),
          _summaryStat('لم يتم', '${o.notDone}', _red),
          _summaryStat(
            'نسبة الإنجاز',
            '${(o.completionRate * 100).toStringAsFixed(1)}%',
            _greenDark,
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryStat(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: color),
        ),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  /// يجمع شريطَي إنجاز الشطرين (طلاب/طالبات) لنفس القسم داخل بطاقة واحدة
  /// بعنوان القسم مرة واحدة فوقهما - بدل عرض قسم كل شطر بشكل منفصل ومكرَّر
  /// بصريًا كأنهما قسمان مختلفان.
  static pw.Widget _departmentsChart(List<DepartmentReport> departments) {
    final withData = departments.where((d) => d.counts.total > 0).toList();
    if (withData.isEmpty) return pw.SizedBox();

    final byDepartment = <String, List<DepartmentReport>>{};
    final order = <String>[];
    for (final d in withData) {
      final bucket = byDepartment.putIfAbsent(d.department, () {
        order.add(d.department);
        return [];
      });
      bucket.add(d);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'نسبة الإنجاز حسب القسم',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        ...order.map((deptName) {
          final entries = byDepartment[deptName]!;
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 5),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _lightGray,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  deptName,
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _greenDark),
                ),
                pw.SizedBox(height: 3),
                ...entries.map((d) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 60,
                          child: pw.Text(d.shatr, style: const pw.TextStyle(fontSize: 6.5)),
                        ),
                        pw.Expanded(child: _horizontalBar(d.counts.completionRate)),
                        pw.SizedBox(width: 5),
                        pw.SizedBox(
                          width: 26,
                          child: pw.Text(
                            '${(d.counts.completionRate * 100).toStringAsFixed(0)}%',
                            style: const pw.TextStyle(fontSize: 6.5),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // "الإجمالي": متوسط بسيط لنسبتَي إنجاز الشطرين (وليس متوسطًا
                // مرجّحًا بعدد الحالات) - جمع النسبتين وقسمتهما على 2 كما
                // طُلب تحديدًا، حتى لا يطغى شطر كبير العدد على الآخر.
                pw.Divider(color: PdfColors.white, height: 5, thickness: 1),
                pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 60,
                      child: pw.Text(
                        'الإجمالي',
                        style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Expanded(
                      child: _horizontalBar(
                        entries.map((e) => e.counts.completionRate).reduce((a, b) => a + b) /
                            entries.length,
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    pw.SizedBox(
                      width: 26,
                      child: pw.Text(
                        '${(entries.map((e) => e.counts.completionRate).reduce((a, b) => a + b) / entries.length * 100).toStringAsFixed(0)}%',
                        style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  static pw.Widget _advisorsChart(List<DepartmentReport> departments) {
    final rows = <AdvisorReport>[];
    for (final d in departments) {
      rows.addAll(d.advisors.where((a) => a.counts.total > 0));
    }
    if (rows.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'نسبة الإنجاز حسب المرشد الأكاديمي',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        ...rows.map((a) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 140,
                  child: pw.Text(a.name, style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Expanded(child: _horizontalBar(a.counts.completionRate)),
                pw.SizedBox(width: 6),
                pw.SizedBox(
                  width: 32,
                  child: pw.Text(
                    '${(a.counts.completionRate * 100).toStringAsFixed(0)}%',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  static pw.Widget _horizontalBar(double ratio) {
    final color = ratio >= 0.7 ? _green : (ratio >= 0.4 ? _gold : _red);
    final clamped = ratio.clamp(0, 1).toDouble();
    final filled = (clamped * 1000).round();
    final empty = 1000 - filled;

    return pw.Container(
      height: 7,
      decoration: pw.BoxDecoration(
        color: _lightGray,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(
        children: [
          if (filled > 0)
            pw.Expanded(
              flex: filled,
              child: pw.Container(
                height: 7,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
            ),
          if (empty > 0) pw.Expanded(flex: empty, child: pw.SizedBox()),
        ],
      ),
    );
  }

  /// جدول الأقسام: قسم واحد في كل صف (بدل صفّين منفصلين لنفس القسم -
  /// أحدهما لشطر الطلاب والآخر لشطر الطالبات - وهو ما كان يبدو غير احترافي
  /// ومكرَّرًا)، مع عرض إحصاءات كل شطر جنبًا إلى جنب ضمن نفس الصف.
  static pw.Widget _departmentsTable(List<DepartmentReport> departments) {
    if (departments.isEmpty) return pw.SizedBox();

    // ترتيب الشُطر بحسب أول ظهور فعلي بالبيانات (عادة: شطر الطلاب ثم شطر
    // الطالبات) بدل ترتيب أبجدي قد يعكسهما.
    final shatrs = <String>[];
    for (final d in departments) {
      if (!shatrs.contains(d.shatr)) shatrs.add(d.shatr);
    }

    final byDepartment = <String, Map<String, DepartmentReport>>{};
    final departmentOrder = <String>[];
    for (final d in departments) {
      final bucket = byDepartment.putIfAbsent(d.department, () {
        departmentOrder.add(d.department);
        return {};
      });
      bucket[d.shatr] = d;
    }

    final headers = <String>['القسم'];
    for (final s in shatrs) {
      headers.addAll(['$s - إجمالي', '$s - تم الإنجاز', '$s - نسبة الإنجاز']);
    }
    headers.add('الإجمالي (الشطرين)');

    final rows = departmentOrder.map((deptName) {
      final row = <String>[deptName];
      var combinedTotal = 0;
      for (final s in shatrs) {
        final d = byDepartment[deptName]?[s];
        combinedTotal += d?.counts.total ?? 0;
        if (d == null || d.counts.total == 0) {
          row.addAll(['${d?.counts.total ?? 0}', '${d?.counts.completed ?? 0}', '-']);
        } else {
          row.addAll([
            '${d.counts.total}',
            '${d.counts.completed}',
            '${(d.counts.completionRate * 100).toStringAsFixed(0)}%',
          ]);
        }
      }
      row.add('$combinedTotal');
      return row;
    }).toList();

    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: _green),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.center,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
    );
  }

  static pw.Widget _shatrTable(ReportData data) {
    final byShatr = <String, StatusCounts>{};
    for (final d in data.departments) {
      final counts = byShatr.putIfAbsent(d.shatr, () => StatusCounts());
      counts.total += d.counts.total;
      counts.completed += d.counts.completed;
      counts.partial += d.counts.partial;
      counts.notDone += d.counts.notDone;
    }

    final headers = ['الشطر', 'إجمالي', 'تم الإنجاز', 'جزئي', 'لم يتم', 'نسبة الإنجاز'];
    final rows = byShatr.entries.map((e) {
      return [
        e.key,
        '${e.value.total}',
        '${e.value.completed}',
        '${e.value.partial}',
        '${e.value.notDone}',
        '${(e.value.completionRate * 100).toStringAsFixed(1)}%',
      ];
    }).toList();

    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('التفصيل حسب الشطر', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: rtlHeaders,
          data: rtlRows,
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: _green),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.center,
          border: pw.TableBorder.all(color: _lightGray, width: 0.5),
          tableDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  static pw.Widget _advisorsTable(List<DepartmentReport> departments) {
    final headers = ['الشطر', 'القسم', 'المرشد الأكاديمي', 'إجمالي', 'تم الإنجاز', 'جزئي', 'لم يتم', 'نسبة الإنجاز'];
    final rows = <List<String>>[];
    for (final department in departments) {
      for (final advisor in department.advisors) {
        if (advisor.counts.total == 0) continue;
        rows.add([
          department.shatr,
          department.department,
          advisor.name,
          '${advisor.counts.total}',
          '${advisor.counts.completed}',
          '${advisor.counts.partial}',
          '${advisor.counts.notDone}',
          '${(advisor.counts.completionRate * 100).toStringAsFixed(1)}%',
        ]);
      }
    }

    if (rows.isEmpty) return pw.SizedBox();

    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'التفصيل حسب المرشد الأكاديمي',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: rtlHeaders,
          data: rtlRows,
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: _green),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.center,
          border: pw.TableBorder.all(color: _lightGray, width: 0.5),
          tableDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  static pw.Widget _caseDetailsTable(List<Map<String, dynamic>> caseDetails) {
    final headers = ['اسم الطالب', 'الرقم الجامعي', 'نوع الإجراء', 'المقرر', 'الحالة'];
    final rows = caseDetails.map((c) {
      final status = (c['status'] ?? '').toString();
      return [
        (c['name'] ?? '').toString(),
        (c['university_id'] ?? '').toString(),
        (c['action_type'] ?? '').toString(),
        (c['course'] ?? '').toString(),
        status.isEmpty ? 'لم يتم' : status,
      ];
    }).toList();

    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('تفاصيل الحالات', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: rtlHeaders,
          data: rtlRows,
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: _greenDark),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.center,
          border: pw.TableBorder.all(color: _lightGray, width: 0.5),
          tableDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  static pw.Widget _completedByChart(ReportData data) {
    final total = data.completedByOverall.values.fold(0, (a, b) => a + b);
    if (total == 0) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'توزيع الحالات المُنجزة حسب الجهة',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        ...data.completedByOverall.entries.where((e) => e.value > 0).map((e) {
          final ratio = e.value / total;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 140,
                  child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Expanded(child: _horizontalBar(ratio)),
                pw.SizedBox(width: 6),
                pw.SizedBox(
                  width: 32,
                  child: pw.Text('${e.value}', style: const pw.TextStyle(fontSize: 8)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// تقرير متابعة الإنجاز: يرتّب كل المرشدين حسب نسبة الإنجاز تصاعديًا (من
  /// لم يبدأ أولاً) ليعرف المسؤول فورًا من يحتاج متابعة، مع قائمة تفصيلية
  /// بكل الحالات المتبقية (لم تُنجز بعد) جاهزة للمراسلة المباشرة.
  static Future<Uint8List> buildFollowUp(
    ReportData data, {
    required String title,
    String? subtitle,
    required List<Map<String, dynamic>> pendingCases,
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final logoBytes = await _loadLogoBytes();
    return compute(
      _buildFollowUpReportInIsolate,
      _FollowUpReportJob(
        data: data,
        title: title,
        subtitle: subtitle,
        pendingCases: pendingCases,
        regularFontBytes: regularBytes,
        boldFontBytes: boldBytes,
        logoBytes: logoBytes,
        generatedAt: DateTime.now(),
      ),
    );
  }

  static Future<Uint8List> _buildFollowUpDoc(
    ReportData data, {
    required String title,
    String? subtitle,
    required List<Map<String, dynamic>> pendingCases,
    required pw.Font regularFont,
    required pw.Font boldFont,
    required pw.MemoryImage logo,
    required DateTime generatedAt,
  }) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    final ranked = ReportDataService.rankedAdvisors(data);
    final notStarted = ranked.where((a) => a.status == AdvisorProgressStatus.notStarted).length;
    final inProgress = ranked.where((a) => a.status == AdvisorProgressStatus.inProgress).length;
    final complete = ranked.where((a) => a.status == AdvisorProgressStatus.complete).length;

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => PdfBrandKit.header(title: title, logo: logo, subtitle: subtitle, generatedAt: generatedAt),
        footer: PdfBrandKit.footer,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: _lightGray, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _summaryStat('لم يبدأوا العمل', '$notStarted', _red),
                _summaryStat('قيد التنفيذ', '$inProgress', _gold),
                _summaryStat('مكتملون', '$complete', _green),
                _summaryStat(
                  'نسبة الإنجاز العامة',
                  '${(data.overall.completionRate * 100).toStringAsFixed(1)}%',
                  _greenDark,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'المتابعة حسب كل قسم وشطر على حدة (الأقل إنجازًا أولاً داخل كل مجموعة)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          ..._groupedFollowUpSections(data, pendingCases),
        ],
      ),
    );

    return doc.save();
  }

  /// جدول حالات متبقية خاص بقسم/شطر واحد فقط - بلا عمودَي "الشطر"/"القسم"
  /// المكرَّرين لأن عنوان المجموعة نفسه (فوق الجدول) يوضّحهما مسبقًا.
  static pw.Widget _pendingCasesTable(List<Map<String, dynamic>> pending) {
    if (pending.isEmpty) {
      return pw.Text('لا توجد حالات متبقية - كل الحالات مُنجزة 🎉', style: const pw.TextStyle(fontSize: 10));
    }
    final headers = ['المرشد', 'الطالب', 'الرقم الجامعي', 'المقرر', 'نوع الإجراء', 'الحالة'];
    final rows = pending.map((c) {
      return [
        (c['advisor'] ?? '').toString(),
        (c['name'] ?? '').toString(),
        (c['university_id'] ?? '').toString(),
        (c['course'] ?? '').toString(),
        (c['action_type'] ?? '').toString(),
        (c['status'] ?? '').toString(),
      ];
    }).toList();

    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: _red),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellAlignment: pw.Alignment.center,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
    );
  }

  /// جدول ترتيب مرشدي قسم/شطر واحد فقط (بلا عمودَي "الشطر"/"القسم") مرتَّب
  /// تصاعديًا حسب نسبة الإنجاز (الأقل أولاً) داخل نفس المجموعة.
  static pw.Widget _groupAdvisorsRankTable(List<AdvisorReport> advisors) {
    final sorted = advisors.toList()
      ..sort((a, b) => a.counts.completionRate.compareTo(b.counts.completionRate));
    final headers = ['الحالة', 'المرشد الأكاديمي', 'منجز/إجمالي', 'نسبة الإنجاز'];
    final rows = sorted.map((a) {
      final status = a.counts.completed == 0
          ? AdvisorProgressStatus.notStarted
          : (a.counts.completed >= a.counts.total ? AdvisorProgressStatus.complete : AdvisorProgressStatus.inProgress);
      final label = status == AdvisorProgressStatus.notStarted
          ? 'لم يبدأ العمل'
          : (status == AdvisorProgressStatus.inProgress ? 'قيد التنفيذ' : 'مكتمل');
      return [
        label,
        a.name,
        '${a.counts.completed}/${a.counts.total}',
        '${(a.counts.completionRate * 100).toStringAsFixed(0)}%',
      ];
    }).toList();

    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: _greenDark),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.center,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
      cellDecoration: (index, data, rowNum) {
        if (rowNum == 0) return const pw.BoxDecoration();
        final status = sorted[rowNum - 1].counts.completed == 0
            ? AdvisorProgressStatus.notStarted
            : (sorted[rowNum - 1].counts.completed >= sorted[rowNum - 1].counts.total
                ? AdvisorProgressStatus.complete
                : AdvisorProgressStatus.inProgress);
        final color = status == AdvisorProgressStatus.notStarted
            ? PdfColor.fromHex('FDEAEA')
            : status == AdvisorProgressStatus.inProgress
                ? PdfColor.fromHex('FBF3DD')
                : PdfColor.fromHex('EAF3EE');
        return pw.BoxDecoration(color: color);
      },
    );
  }

  /// يبني قائمة أقسام مرتَّبة (شطر الطلاب لكل الأقسام، ثم شطر الطالبات لكل
  /// الأقسام - نفس ترتيب [ReportDataService.build])، كل قسم/شطر ببطاقته
  /// الخاصة (عنوان + جدول ترتيب مرشدين + جدول حالات متبقية) بدل جدول واحد
  /// ضخم يخلط كل الأقسام والشطرين معًا.
  static List<pw.Widget> _groupedFollowUpSections(
    ReportData data,
    List<Map<String, dynamic>> pendingCases,
  ) {
    final pendingByGroup = <String, List<Map<String, dynamic>>>{};
    for (final c in pendingCases) {
      final key = '${c['shatr']}|${c['department']}';
      pendingByGroup.putIfAbsent(key, () => []).add(c);
    }

    final widgets = <pw.Widget>[];
    for (final dept in data.departments) {
      final advisors = dept.advisors.where((a) => a.counts.total > 0).toList();
      final pending = pendingByGroup['${dept.shatr}|${dept.department}'] ?? [];
      if (advisors.isEmpty && pending.isEmpty) continue;

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text(
                  '${dept.department} - ${dept.shatr}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              ),
              pw.SizedBox(height: 6),
              if (advisors.isNotEmpty) ...[
                _groupAdvisorsRankTable(advisors),
                pw.SizedBox(height: 6),
              ],
              if (pending.isNotEmpty) _pendingCasesTable(pending),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  /// "تقرير الأداء اليومي" لعمادة الكلية - بطلب سليمان صراحةً (2026-08-30):
  /// يقارن الأقسام والمرشدين ببعضهم (أفضل قسم لكل شطر، أفضل 3 مرشدين لكل
  /// شطر، ثم جدول مقارنة كامل) بهدف تحفيزي - إبراز المتقدّمين لا فقط متابعة
  /// المتأخرين (بخلاف [buildFollowUp]). بلا isolate (بيانات صغيرة: أقسام
  /// وشطران فقط، لا آلاف الصفوف).
  static Future<Uint8List> buildDailyPerformanceReport(
    List<DeptShatrPerformance> deptRows,
    List<AdvisorCaseStats> advisors, {
    required String title,
    String? subtitle,
    Map<String, ActionTypeCaseCounts> actionTypeStats = const {},
  }) async {
    final (regularBytes, boldBytes) = await _loadFontBytes();
    final logoBytes = await _loadLogoBytes();
    final regularFont = pw.Font.ttf(regularBytes.buffer.asByteData());
    final boldFont = pw.Font.ttf(boldBytes.buffer.asByteData());
    final logo = pw.MemoryImage(logoBytes);

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    const maleShatr = 'شطر الطلاب';
    const femaleShatr = 'شطر الطالبات';

    final maleDepts = deptRows.where((d) => d.shatr == maleShatr && d.total > 0).toList();
    final femaleDepts = deptRows.where((d) => d.shatr == femaleShatr && d.total > 0).toList();
    final bestMaleDept = maleDepts.isEmpty ? null : maleDepts.first;
    final bestFemaleDept = femaleDepts.isEmpty ? null : femaleDepts.first;

    final maleAdvisors = advisors.where((a) => a.shatr == maleShatr && a.total > 0).toList()
      ..sort((a, b) {
        final rateA = a.total == 0 ? 0.0 : a.completed / a.total;
        final rateB = b.total == 0 ? 0.0 : b.completed / b.total;
        return rateB.compareTo(rateA);
      });
    final femaleAdvisors = advisors.where((a) => a.shatr == femaleShatr && a.total > 0).toList()
      ..sort((a, b) {
        final rateA = a.total == 0 ? 0.0 : a.completed / a.total;
        final rateB = b.total == 0 ? 0.0 : b.completed / b.total;
        return rateB.compareTo(rateA);
      });

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => PdfBrandKit.header(title: title, logo: logo, subtitle: subtitle, generatedAt: DateTime.now()),
        footer: PdfBrandKit.footer,
        build: (context) => [
          if (actionTypeStats.isNotEmpty) ...[
            _actionTypeCaseSummaryRow(actionTypeStats),
            pw.SizedBox(height: 14),
          ],
          pw.Text('أفضل قسم لكل شطر', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _bestDeptCard('شطر الطلاب', bestMaleDept)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _bestDeptCard('شطر الطالبات', bestFemaleDept)),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('أفضل 3 مرشدين لكل شطر', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _topAdvisorsTable('شطر الطلاب', maleAdvisors.take(3).toList())),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _topAdvisorsTable('شطر الطالبات', femaleAdvisors.take(3).toList())),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('مقارنة شاملة بكل الأقسام والشطرين (الأعلى إنجازًا أولاً)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _deptComparisonTable(deptRows.where((d) => d.total > 0).toList()),
          pw.SizedBox(height: 30),
          pw.Center(
            child: pw.Text(
              'وحدة الإرشاد الأكاديمي والخريجين',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _greenDark),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// "عدد الحالات الكاملة" (إجمالي إضافة+حذف+تعديل) + تفصيل منجز/مصعَّد/لم
  /// يُعمل عليه تحت كل نوع إجراء - بطلب سليمان صراحةً (2026-08-30) بعد سؤاله
  /// عن معنى الأرقام بلوحة الإدارة. صف واحد مضغوط حتى يبقى التقرير بصفحة واحدة.
  static pw.Widget _actionTypeCaseSummaryRow(Map<String, ActionTypeCaseCounts> stats) {
    const order = ['إضافة', 'حذف', 'تعديل'];
    final types = order.where(stats.containsKey).toList();
    final totalCases = types.fold<int>(0, (sum, t) => sum + stats[t]!.total);

    pw.Widget cell(String label, String value, PdfColor color, {String? sub}) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: color, width: 3)),
            color: const PdfColor.fromInt(0xFFF8FAF9),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _greenDark)),
              if (sub != null) ...[
                pw.SizedBox(height: 3),
                pw.Text(sub, style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
              ],
            ],
          ),
        ),
      );
    }

    return pw.Row(
      children: [
        cell('عدد الحالات الكاملة', '$totalCases', _greenDark),
        for (final t in types) ...[
          pw.SizedBox(width: 8),
          cell(
            'طلبات $t',
            '${stats[t]!.total}',
            _gold,
            sub: 'منجز ${stats[t]!.completed} · مصعَّد ${stats[t]!.escalatedToCoordinator} · لم يُعمل عليه ${stats[t]!.notStarted}',
          ),
        ],
      ],
    );
  }

  static pw.Widget _bestDeptCard(String shatrLabel, DeptShatrPerformance? dept) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: _greenDark, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(shatrLabel, style: pw.TextStyle(fontSize: 10, color: PdfColors.white)),
          pw.SizedBox(height: 4),
          pw.Text(
            dept == null ? '-' : dept.department,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            dept == null ? 'لا توجد بيانات' : 'نسبة الإنجاز ${(dept.completionRate * 100).toStringAsFixed(0)}%',
            style: pw.TextStyle(fontSize: 10, color: _goldLight),
          ),
        ],
      ),
    );
  }

  static pw.Widget _topAdvisorsTable(String shatrLabel, List<AdvisorCaseStats> top) {
    if (top.isEmpty) {
      return pw.Text('لا توجد بيانات كافية ($shatrLabel)', style: const pw.TextStyle(fontSize: 9));
    }
    final headers = ['المرشد', 'القسم', 'نسبة الإنجاز'];
    final rows = top.map((a) {
      final rate = a.total == 0 ? 0.0 : a.completed / a.total;
      return [displayName(a.advisorName), a.department, '${(rate * 100).toStringAsFixed(0)}%'];
    }).toList();
    final (rtlHeaders, rtlRows) = _rtlTable(headers, rows);
    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: _gold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.center,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
    );
  }

  static pw.Widget _deptComparisonTable(List<DeptShatrPerformance> rows) {
    if (rows.isEmpty) {
      return pw.Text('لا توجد بيانات', style: const pw.TextStyle(fontSize: 10));
    }
    final headers = ['القسم', 'الشطر', 'إجمالي الحالات', 'باشرها المرشد', 'صُعِّدت دون مباشرة', 'لم يُباشَر إطلاقًا', 'نسبة الإنجاز'];
    final tableRows = rows.map((d) {
      return [
        d.department.replaceFirst('قسم ', ''),
        d.shatr,
        '${d.total}',
        '${d.completed}',
        '${d.escalatedToCoordinator}',
        '${d.notStarted}',
        '${(d.completionRate * 100).toStringAsFixed(0)}%',
      ];
    }).toList();
    final (rtlHeaders, rtlRows) = _rtlTable(headers, tableRows);
    return pw.TableHelper.fromTextArray(
      headers: rtlHeaders,
      data: rtlRows,
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: _greenDark),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.center,
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      tableDirection: pw.TextDirection.rtl,
    );
  }
}
