import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import '../data/course_catalog.dart';
import '../models/advising_schedule.dart';
import 'excel_parser_service.dart';

/// يقرأ ملفات "الدليل" بصيغة HTML وتُرجع جدولاً منفصلاً لكل (قسم × شطر)
/// وُجد فيه. مصمَّم ليتحمّل أكثر من هيكل عناوين مختلف - كل مصدر (شخص/أداة
/// استخرجت البيانات) رتّب عناوينه بترتيب مختلف تمامًا:
///  - "الدليل الشامل": h2 لاسم القسم، h3 يذكر الشطر، h4 لليوم والفترة معًا.
///  - ملف قسم واحد: اسم القسم/الشطر في فقرة مقدّمة (لا عنوان)، h2 لليوم، h3
///    للفترة فقط.
/// لذا يُحدَّد نوع كل عنوان بمحتواه (يحوي "قسم"/"طلاب"/"يوم"/"الفترة") بدل
/// الاعتماد على مستوى الوسم (h2/h3/h4) نفسه، مع تمرير على كامل نص الصفحة
/// أولاً لالتقاط قسم/شطر افتراضيين قبل أي عنوان صريح.
class AdvisingScheduleHtmlParserService {
  static final _deptPrefixPattern = RegExp(r'^(أولاً|ثانياً|ثالثاً|رابعاً|خامساً)\s*:\s*');
  static const _easternDigits = '٠١٢٣٤٥٦٧٨٩';

  static String _toWesternDigits(String s) {
    final buffer = StringBuffer();
    for (final ch in s.runes) {
      final i = _easternDigits.indexOf(String.fromCharCode(ch));
      buffer.write(i == -1 ? String.fromCharCode(ch) : i.toString());
    }
    return buffer.toString();
  }

  static String? _matchDepartment(String text) {
    for (final dept in CourseCatalog.departments) {
      final bare = dept.replaceFirst('قسم ', '');
      if (text.contains(bare)) return dept;
    }
    return null;
  }

  static String? _matchShatr(String text) {
    if (text.contains('طالبات')) return ExcelParserService.shatrFemale;
    if (text.contains('طلاب')) return ExcelParserService.shatrMale;
    return null;
  }

  static Map<(String department, String shatr), List<AdvisingScheduleSlot>> parse(String htmlSource) {
    final document = html_parser.parse(htmlSource);
    final body = document.body;
    if (body == null) return {};

    final result = <(String, String), List<AdvisingScheduleSlot>>{};

    // تمرير أولي: قسم/شطر افتراضيان من أول ظهور لهما في نص الصفحة كاملاً
    // (يغطّي حالة الفقرة التعريفية التي لا تستخدم عناوين h2/h3 صريحة)
    final wholeText = body.text;
    String? currentDept = _matchDepartment(wholeText);
    String? currentShatr = _matchShatr(wholeText);
    String? currentDayLabel;
    String? currentPeriodLabel;

    void addSlotFrom(Element table) {
      if (currentDept == null || currentShatr == null) return;
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) return;

      final entries = <AdvisingScheduleEntry>[];
      for (var r = 1; r < rows.length; r++) {
        final cells = rows[r].querySelectorAll('td');
        if (cells.length < 2) continue;
        final a = cells[0].text.trim();
        final b = cells[1].text.trim();
        final aIsName = a.startsWith('د') || a.startsWith('أ');
        final nameCell = aIsName ? a : b;
        final office = _toWesternDigits(aIsName ? b : a);
        if (nameCell.isEmpty || office.isEmpty) continue;
        for (final rawName in nameCell.split(RegExp('[–-]'))) {
          final name = rawName.trim();
          if (name.isEmpty) continue;
          entries.add(AdvisingScheduleEntry(advisorName: name, office: office));
        }
      }
      if (entries.isEmpty) return;

      final dayLabel = _toWesternDigits((currentDayLabel ?? '').trim());
      final periodLabel = _toWesternDigits((currentPeriodLabel ?? '').trim());

      final key = (currentDept!, currentShatr!);
      result.putIfAbsent(key, () => []).add(
            AdvisingScheduleSlot(dayLabel: dayLabel, periodLabel: periodLabel, entries: entries),
          );
    }

    void walk(Element el) {
      final tag = el.localName;
      if (tag != null && RegExp(r'^h[1-4]$').hasMatch(tag)) {
        final text = el.text.replaceAll(RegExp(r'[📌📅⏰📘]'), '').trim();
        final isPeriod = text.contains('الفترة');
        final isDay = !isPeriod && (text.contains('يوم') || RegExp(r'الأحد|الاحد|الاثنين|الثلاثاء|الأربعاء|الاربعاء|الخميس').hasMatch(text));
        final isDept = !isPeriod && !isDay && text.contains('قسم');
        final isShatr = !isPeriod && !isDay && (text.contains('طلاب') || text.contains('طالبات'));

        if (isDept) {
          currentDept = _matchDepartment(text) ?? text.replaceFirst(_deptPrefixPattern, '').trim();
          // عنوان قسم جديد (هيكل الدليل الشامل) يعيد ضبط الشطر واليوم/الفترة
          currentShatr = _matchShatr(text);
          currentDayLabel = null;
          currentPeriodLabel = null;
        } else if (isShatr) {
          currentShatr = _matchShatr(text);
        } else if (isDay) {
          currentDayLabel = text;
          // عنوان يوم جديد (هيكل ملف القسم الواحد) يُنهي الفترة السابقة
          currentPeriodLabel = null;
        } else if (isPeriod) {
          currentPeriodLabel = text;
        }
      } else if (tag == 'table') {
        addSlotFrom(el);
      }
      for (final child in el.children) {
        walk(child);
      }
    }

    walk(body);
    return result;
  }
}
