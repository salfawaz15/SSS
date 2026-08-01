import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'report_data_service.dart';
import 'report_filter_service.dart';

/// يبني ملف Excel للتقرير الشامل (جداول فقط - بدون رسوم بيانية، لأن مكتبة
/// excel الحالية لا تدعم إنشاء رسوم بيانية حقيقية).
class ReportExcelService {
  static final _thinGrayBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('FFB9C4BF'),
  );

  static CellStyle _headerStyle() => CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF154B36'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _thinGrayBorder,
    rightBorder: _thinGrayBorder,
    topBorder: _thinGrayBorder,
    bottomBorder: _thinGrayBorder,
  );

  static CellStyle _rowStyle({required bool alternate}) => CellStyle(
    backgroundColorHex: alternate
        ? ExcelColor.fromHexString('FFEFF5F2')
        : ExcelColor.white,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _thinGrayBorder,
    rightBorder: _thinGrayBorder,
    topBorder: _thinGrayBorder,
    bottomBorder: _thinGrayBorder,
  );

  static void _writeTable(
    Sheet sheet,
    List<String> headers,
    List<List<dynamic>> rows,
  ) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (var c = 0; c < headers.length; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .cellStyle =
          _headerStyle();
    }

    for (var r = 0; r < rows.length; r++) {
      sheet.appendRow(rows[r].map((v) => TextCellValue(v.toString())).toList());
      final style = _rowStyle(alternate: r.isEven);
      for (var c = 0; c < rows[r].length; c++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
                )
                .cellStyle =
            style;
      }
    }
  }

  static Uint8List build(
    ReportData data, {
    ReportScope scope = ReportScope.overall,
    List<Map<String, dynamic>>? caseDetails,
  }) {
    final workbook = Excel.createExcel();

    // الأقسام العشرة المزروعة صفريًا مفيدة للتقرير الشامل فقط؛ في التقارير
    // المُفلترة (قسم/شطر/مرشد) تُستبعد الإدخالات الفارغة غير ذات الصلة.
    final relevantDepartments = scope == ReportScope.overall
        ? data.departments
        : data.departments.where((d) => d.counts.total > 0).toList();

    final summarySheet = workbook['ملخص عام'];
    _writeTable(
      summarySheet,
      ['إجمالي الحالات', 'تم الإنجاز', 'جزئي', 'لم يتم', 'نسبة الإنجاز'],
      [
        [
          data.overall.total,
          data.overall.completed,
          data.overall.partial,
          data.overall.notDone,
          '${(data.overall.completionRate * 100).toStringAsFixed(1)}%',
        ],
      ],
    );

    if (scope == ReportScope.overall || scope == ReportScope.shatr) {
      final departmentsSheet = workbook['حسب القسم'];
      _writeTable(
        departmentsSheet,
        ['الشطر', 'القسم', 'إجمالي', 'تم الإنجاز', 'جزئي', 'لم يتم', 'نسبة الإنجاز'],
        relevantDepartments.map((d) {
          return [
            d.shatr,
            d.department,
            d.counts.total,
            d.counts.completed,
            d.counts.partial,
            d.counts.notDone,
            '${(d.counts.completionRate * 100).toStringAsFixed(1)}%',
          ];
        }).toList(),
      );
    }

    if (scope != ReportScope.advisor) {
      final advisorsSheet = workbook['حسب المرشد'];
      final advisorRows = <List<dynamic>>[];
      for (final department in relevantDepartments) {
        for (final advisor in department.advisors) {
          if (advisor.counts.total == 0) continue;
          advisorRows.add([
            department.shatr,
            department.department,
            advisor.name,
            advisor.counts.total,
            advisor.counts.completed,
            advisor.counts.partial,
            advisor.counts.notDone,
            '${(advisor.counts.completionRate * 100).toStringAsFixed(1)}%',
          ]);
        }
      }
      _writeTable(advisorsSheet, [
        'الشطر',
        'القسم',
        'المرشد الأكاديمي',
        'إجمالي',
        'تم الإنجاز',
        'جزئي',
        'لم يتم',
        'نسبة الإنجاز',
      ], advisorRows);
    }

    final completedBySheet = workbook['حسب الجهة المُنجزة'];
    _writeTable(completedBySheet, [
      'الجهة المُنجزة',
      'عدد الحالات',
    ], data.completedByOverall.entries.map((e) => [e.key, e.value]).toList());

    if (caseDetails != null && caseDetails.isNotEmpty) {
      final detailsSheet = workbook['تفاصيل الحالات'];
      _writeTable(
        detailsSheet,
        ['اسم الطالب', 'الرقم الجامعي', 'نوع الإجراء', 'المقرر', 'الحالة'],
        caseDetails.map((c) {
          final status = (c['status'] ?? '').toString();
          return [
            c['name'] ?? '',
            c['university_id'] ?? '',
            c['action_type'] ?? '',
            c['course'] ?? '',
            status.isEmpty ? 'لم يتم' : status,
          ];
        }).toList(),
      );
    }

    // إزالة الورقة الافتراضية الفارغة التي تنشئها المكتبة تلقائيًا
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'ملخص عام') {
      workbook.delete(defaultSheet);
    }

    return Uint8List.fromList(workbook.encode()!);
  }

  /// تقرير متابعة الإنجاز: ورقة "ترتيب المرشدين" (الأسوأ إنجازًا أولاً) +
  /// ورقة "الحالات المتبقية" التفصيلية الجاهزة للمراسلة المباشرة.
  static Uint8List buildFollowUp(
    ReportData data, {
    required List<Map<String, dynamic>> pendingCases,
  }) {
    final workbook = Excel.createExcel();
    final ranked = ReportDataService.rankedAdvisors(data);

    final summarySheet = workbook['ملخص المتابعة'];
    final notStarted = ranked.where((a) => a.status == AdvisorProgressStatus.notStarted).length;
    final inProgress = ranked.where((a) => a.status == AdvisorProgressStatus.inProgress).length;
    final complete = ranked.where((a) => a.status == AdvisorProgressStatus.complete).length;
    _writeTable(
      summarySheet,
      ['لم يبدأوا العمل', 'قيد التنفيذ', 'مكتملون', 'نسبة الإنجاز العامة'],
      [
        [
          notStarted,
          inProgress,
          complete,
          '${(data.overall.completionRate * 100).toStringAsFixed(1)}%',
        ],
      ],
    );

    final rankedSheet = workbook['ترتيب المرشدين'];
    _writeTable(
      rankedSheet,
      ['الحالة', 'الشطر', 'القسم', 'المرشد الأكاديمي', 'تم الإنجاز', 'إجمالي', 'نسبة الإنجاز'],
      ranked.map((a) {
        return [
          a.statusLabel,
          a.shatr,
          a.department,
          a.advisorName,
          a.counts.completed,
          a.counts.total,
          '${(a.counts.completionRate * 100).toStringAsFixed(1)}%',
        ];
      }).toList(),
    );

    final pendingSheet = workbook['الحالات المتبقية'];
    _writeTable(
      pendingSheet,
      ['الشطر', 'القسم', 'المرشد', 'اسم الطالب', 'الرقم الجامعي', 'المقرر', 'نوع الإجراء', 'الحالة'],
      pendingCases.map((c) {
        return [
          c['shatr'] ?? '',
          c['department'] ?? '',
          c['advisor'] ?? '',
          c['name'] ?? '',
          c['university_id'] ?? '',
          c['course'] ?? '',
          c['action_type'] ?? '',
          c['status'] ?? '',
        ];
      }).toList(),
    );

    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'ملخص المتابعة') {
      workbook.delete(defaultSheet);
    }

    return Uint8List.fromList(workbook.encode()!);
  }
}
