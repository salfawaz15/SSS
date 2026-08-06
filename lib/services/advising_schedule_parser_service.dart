import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/advising_schedule.dart';

/// يقرأ ملف Word "توزيع فترات الإرشاد" ويستخرج منه هيكلاً موحّدًا (يوم ←
/// فترة ← مرشد ورقم مكتبه)، بصرف النظر عن تصميم الجدول الأصلي - كل قسم صمّم
/// جدوله بطريقة مختلفة (ترتيب الاسم/رقم المكتب، صياغة الوقت، صياغة التاريخ)،
/// لذا يعتمد الاستخراج على حدود فضفاضة (اسم اليوم، كلمة "الفترة") بدل قالب
/// نص ثابت، ويستخرج التاريخ/الوقت بأنماط بديلة متعددة إن وُجدت، وإلا يتركها
/// فارغة بدل أن يفشل بالكامل.
class AdvisingScheduleParserService {
  static const List<String> _dayNames = ['الأحد', 'الاحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الاربعاء', 'الخميس'];

  static final _dayBoundaryPattern = RegExp('يوم\\s+(${_dayNames.join('|')})');
  static final _periodBoundaryPattern = RegExp(r'الفترة\s+(الأولى|الثانية|الثالثة)');

  // صيغة الوقت الصريحة: 8:00 ص - 11:00 ص
  static final _timeColonPattern =
      RegExp(r'\d{1,2}\s*:\s*\d{1,2}\s*[صم]\s*-\s*\d{1,2}\s*:\s*\d{1,2}\s*[صم]');
  // صيغة الوقت المبسّطة: 8 -11 صباحاً
  static final _timeSimplePattern = RegExp(r'\d{1,2}\s*-\s*\d{1,2}\s*(صباحاً|مساءً)');
  // صيغة التاريخ: أرقام مفصولة بـ / ثم "هـ" (تتحمّل مسافات عشوائية بين الأرقام)
  static final _datePattern = RegExp(r'[\d\s]{1,3}/[\d\s]{1,3}/[\d\s]{2,6}هـ+');

  static final _nameOfficePattern = RegExp(r'^(?:د|أ|د\.|أ\.|أ د|د د)\.?\s');
  static final _officeTokenPattern =
      RegExp(r'^(مبنى\s*\)?\s*\d+(\s*\)?\s*مكتب\s*رقم\s*\d+)?|\d{1,4})$');

  static List<AdvisingScheduleSlot> parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final doc = archive.findFile('word/document.xml');
    if (doc == null) return [];
    final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
    final tokens = xml.findAllElements('w:t').map((e) => e.innerText).toList();

    final tokenStart = List<int>.filled(tokens.length, 0);
    var cursor = 0;
    for (var i = 0; i < tokens.length; i++) {
      tokenStart[i] = cursor;
      cursor += tokens[i].length + 1;
    }
    final fullText = tokens.join(' ');

    int tokenIndexAtOffset(int offset) {
      var lo = 0, hi = tokens.length - 1, result = tokens.length;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        if (tokenStart[mid] >= offset) {
          result = mid;
          hi = mid - 1;
        } else {
          lo = mid + 1;
        }
      }
      return result;
    }

    // يرجّع نص التطابق **وموضع نهايته المطلق** داخل fullText (لا النسبي)،
    // حتى تبدأ منطقة استخراج المرشدين بعد نهاية عبارة الوقت نفسها - وإلا
    // تبقى أرقام الوقت (00، 8، 11...) داخل المنطقة فتُقرأ خطأً كأرقام مكاتب
    // وتزيح كل الأزواج التالية عن مكانها.
    ({String text, int end})? findNear(RegExp pattern, int from, int windowLen) {
      final windowEnd = (from + windowLen).clamp(0, fullText.length);
      if (from >= windowEnd) return null;
      final m = pattern.firstMatch(fullText.substring(from, windowEnd));
      if (m == null) return null;
      return (text: m.group(0)!, end: from + m.end);
    }

    final dayMatches = _dayBoundaryPattern.allMatches(fullText).toList();
    final periodMatches = _periodBoundaryPattern.allMatches(fullText).toList();

    final slots = <AdvisingScheduleSlot>[];
    for (var d = 0; d < dayMatches.length; d++) {
      final dayMatch = dayMatches[d];
      final dayName = dayMatch.group(1) ?? '';
      final dateMatch = findNear(_datePattern, dayMatch.end, 40);
      final date = dateMatch?.text.replaceAll(RegExp(r'\s+'), '');
      final dayLabel = (date == null || date.isEmpty) ? dayName : '$dayName - $date';
      final dayEnd = d + 1 < dayMatches.length ? dayMatches[d + 1].start : fullText.length;

      final periodsInDay =
          periodMatches.where((p) => p.start >= dayMatch.end && p.start < dayEnd).toList();
      for (var p = 0; p < periodsInDay.length; p++) {
        final periodMatch = periodsInDay[p];
        final timeMatch = findNear(_timeColonPattern, periodMatch.end, 60) ??
            findNear(_timeSimplePattern, periodMatch.end, 60);
        final periodLabel =
            (timeMatch?.text ?? periodMatch.group(1) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final periodEnd = p + 1 < periodsInDay.length ? periodsInDay[p + 1].start : dayEnd;

        // منطقة استخراج المرشدين تبدأ بعد نهاية عبارة الوقت نفسها إن وُجدت
        // (لا بعد "الفترة الأولى" مباشرة) حتى لا تدخل أرقام الوقت ضمن أرقام
        // المكاتب المستخرجة.
        final entriesStart = timeMatch?.end ?? periodMatch.end;
        final startTokenIndex = tokenIndexAtOffset(entriesStart);
        final endTokenIndex = tokenIndexAtOffset(periodEnd);
        final tokenSlice = tokens.sublist(
          startTokenIndex.clamp(0, tokens.length),
          endTokenIndex.clamp(startTokenIndex, tokens.length),
        );

        final entries = _extractEntries(tokenSlice);
        if (entries.isEmpty) continue;
        slots.add(AdvisingScheduleSlot(dayLabel: dayLabel, periodLabel: periodLabel, entries: entries));
      }
    }
    return slots;
  }

  /// يبني قائمة (نوع، قيمة) لكل عنصر نصي يطابق اسمًا أو رقم مكتب، بترتيب
  /// ظهورها الأصلي، ثم يزاوج كل عنصرين متجاورين من نوعين مختلفين معًا -
  /// يتحمّل بذلك ترتيب "اسم ثم رقم" أو "رقم ثم اسم" على حدٍّ سواء، لأن كل
  /// قسم يرتّب عموده بطريقة مختلفة.
  static List<AdvisingScheduleEntry> _extractEntries(List<String> tokens) {
    final typed = <(String type, String value)>[];
    for (final raw in tokens) {
      final w = raw.trim();
      if (w.isEmpty) continue;
      if (_nameOfficePattern.hasMatch(w) && w.length > 4) {
        typed.add(('name', w));
      } else if (_officeTokenPattern.hasMatch(w) && w != 'اسم المرشد الأكاديمي' && w != 'رقم المكتب') {
        typed.add(('office', w));
      }
    }

    final entries = <AdvisingScheduleEntry>[];
    var i = 0;
    while (i < typed.length - 1) {
      final a = typed[i];
      final b = typed[i + 1];
      if (a.$1 != b.$1) {
        final name = a.$1 == 'name' ? a.$2 : b.$2;
        final office = a.$1 == 'office' ? a.$2 : b.$2;
        entries.add(AdvisingScheduleEntry(advisorName: name, office: office));
        i += 2;
      } else {
        i += 1;
      }
    }
    return entries;
  }
}
