import 'package:syncfusion_flutter_pdf/pdf.dart';

/// يستخرج صفوف/أعمدة جدول من ملف PDF عبر إعادة بناء الصفوف يدويًا من مواضع
/// الكلمات - عام لأي تقرير من نفس أسلوب تقارير الإرشاد الجامعية (عمود لكل
/// حقل، جدول واحد أو أكثر بالملف)، لا يفترض عدد أعمدة ثابت.
///
/// Syncfusion لا يعيد بناء صفوف/أعمدة الجدول تلقائيًا (يجمع النص عمودًا
/// عمودًا لا صفًا صفًا) - فتُجمَّع الكلمات في نفس الصف حسب تقارب `top`، ثم
/// تُقسَّم داخل الصف إلى أعمدة حسب فجوة أفقية حقيقية بين نهاية كلمة وبداية
/// التالية (باستخدام `bounds.right`/`bounds.left` لا `left` وحدها، وإلا
/// التبست فجوة عمود حقيقية (~10-30) بفجوة مسافة عادية داخل اسم مركَّب من
/// عدة كلمات).
///
/// دقّة إضافية: الكلمات تُرتَّب أفقيًا من اليسار لليمين لتحديد **ترتيب
/// الأعمدة نفسها** (يطابق ترتيب أعمدة نفس التقرير بعد تحويله يدويًا لـWord)،
/// لكن كلمات **داخل** نفس الخلية (كالاسم المكوَّن من عدة كلمات) تُعكَس
/// ترتيبها بعد التجميع لأن الاستخراج لا يطبّق اتجاه الكتابة العربي (RTL)
/// تلقائيًا - نص الاسم يخرج معكوسًا (آخر كلمة أولًا) ما لم يُعكَس يدويًا هنا.
class PdfTableRowsExtractor {
  static const double _rowTopTolerance = 3;
  static const double _columnGapThreshold = 8;

  /// خط تقارير المنظومة الجامعية مبني على "أشكال العرض العربية" (Arabic
  /// Presentation Forms-B, U+FE70 to U+FEFC) - كل حرف مشكَّل حسب موضعه
  /// بالكلمة (منفصل/بداية/وسط/نهاية) بكود يونيكود مختلف عن الحرف العربي
  /// القياسي (U+0600 series) رغم تطابقهما بصريًا تمامًا. Syncfusion يعيد هذه
  /// الأكواد كما هي من خط الملف دون توحيدها، فتفشل كل مطابقة نصية (`اسم`,
  /// `رقم المرشد`...) بصمت ما لم تُحوَّل هنا أولًا لمكافئها القياسي.
  static const Map<int, String> _presentationFormsToStandard = {
    0xFE80: 'ء',
    0xFE81: 'آ', 0xFE82: 'آ',
    0xFE83: 'أ', 0xFE84: 'أ',
    0xFE85: 'ؤ', 0xFE86: 'ؤ',
    0xFE87: 'إ', 0xFE88: 'إ',
    0xFE89: 'ئ', 0xFE8A: 'ئ', 0xFE8B: 'ئ', 0xFE8C: 'ئ',
    0xFE8D: 'ا', 0xFE8E: 'ا',
    0xFE8F: 'ب', 0xFE90: 'ب', 0xFE91: 'ب', 0xFE92: 'ب',
    0xFE93: 'ة', 0xFE94: 'ة',
    0xFE95: 'ت', 0xFE96: 'ت', 0xFE97: 'ت', 0xFE98: 'ت',
    0xFE99: 'ث', 0xFE9A: 'ث', 0xFE9B: 'ث', 0xFE9C: 'ث',
    0xFE9D: 'ج', 0xFE9E: 'ج', 0xFE9F: 'ج', 0xFEA0: 'ج',
    0xFEA1: 'ح', 0xFEA2: 'ح', 0xFEA3: 'ح', 0xFEA4: 'ح',
    0xFEA5: 'خ', 0xFEA6: 'خ', 0xFEA7: 'خ', 0xFEA8: 'خ',
    0xFEA9: 'د', 0xFEAA: 'د',
    0xFEAB: 'ذ', 0xFEAC: 'ذ',
    0xFEAD: 'ر', 0xFEAE: 'ر',
    0xFEAF: 'ز', 0xFEB0: 'ز',
    0xFEB1: 'س', 0xFEB2: 'س', 0xFEB3: 'س', 0xFEB4: 'س',
    0xFEB5: 'ش', 0xFEB6: 'ش', 0xFEB7: 'ش', 0xFEB8: 'ش',
    0xFEB9: 'ص', 0xFEBA: 'ص', 0xFEBB: 'ص', 0xFEBC: 'ص',
    0xFEBD: 'ض', 0xFEBE: 'ض', 0xFEBF: 'ض', 0xFEC0: 'ض',
    0xFEC1: 'ط', 0xFEC2: 'ط', 0xFEC3: 'ط', 0xFEC4: 'ط',
    0xFEC5: 'ظ', 0xFEC6: 'ظ', 0xFEC7: 'ظ', 0xFEC8: 'ظ',
    0xFEC9: 'ع', 0xFECA: 'ع', 0xFECB: 'ع', 0xFECC: 'ع',
    0xFECD: 'غ', 0xFECE: 'غ', 0xFECF: 'غ', 0xFED0: 'غ',
    0xFED1: 'ف', 0xFED2: 'ف', 0xFED3: 'ف', 0xFED4: 'ف',
    0xFED5: 'ق', 0xFED6: 'ق', 0xFED7: 'ق', 0xFED8: 'ق',
    0xFED9: 'ك', 0xFEDA: 'ك', 0xFEDB: 'ك', 0xFEDC: 'ك',
    0xFEDD: 'ل', 0xFEDE: 'ل', 0xFEDF: 'ل', 0xFEE0: 'ل',
    0xFEE1: 'م', 0xFEE2: 'م', 0xFEE3: 'م', 0xFEE4: 'م',
    0xFEE5: 'ن', 0xFEE6: 'ن', 0xFEE7: 'ن', 0xFEE8: 'ن',
    0xFEE9: 'ه', 0xFEEA: 'ه', 0xFEEB: 'ه', 0xFEEC: 'ه',
    0xFEED: 'و', 0xFEEE: 'و',
    0xFEEF: 'ى', 0xFEF0: 'ى',
    0xFEF1: 'ي', 0xFEF2: 'ي', 0xFEF3: 'ي', 0xFEF4: 'ي',
    0xFEF5: 'لآ', 0xFEF6: 'لآ',
    0xFEF7: 'لأ', 0xFEF8: 'لأ',
    0xFEF9: 'لإ', 0xFEFA: 'لإ',
    0xFEFB: 'لا', 0xFEFC: 'لا',
    // أرقام هندية عربية ← أرقام غربية - وإلا لا يطابق رقم الطالب هنا (مثال:
    // "٤٣٩٠٧٨١٨") نفس الرقم في تقارير أخرى مصدرها Word ("43907818")، فيفشل
    // الدمج بينهما بصمت رغم كونهما نفس الطالب فعليًا.
    0x0660: '0', 0x0661: '1', 0x0662: '2', 0x0663: '3', 0x0664: '4',
    0x0665: '5', 0x0666: '6', 0x0667: '7', 0x0668: '8', 0x0669: '9',
  };

  static String _deshape(String s) {
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      buffer.write(_presentationFormsToStandard[rune] ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  static List<List<String>> extract(List<int> pdfBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    try {
      final extractor = PdfTextExtractor(document);
      // استدعاء واحد لكل الصفحات معًا (لا حلقة صفحة-بصفحة) - أسرع بكثير
      // (~78 ثانية لملف 315 صفحة مقابل ~32 دقيقة عند استدعاء منفصل لكل صفحة).
      final lines = extractor.extractTextLines(startPageIndex: 0, endPageIndex: document.pages.count - 1);
      return _rowsFromLines(lines);
    } finally {
      document.dispose();
    }
  }

  static List<List<String>> _rowsFromLines(List<TextLine> lines) {
    // إحداثي `top` نسبي **لكل صفحة على حدة** فيتكرر نفس المدى تقريبًا في كل
    // صفحة - فيُنزَّح (offset) بمضاعف كبير لرقم الصفحة قبل التجميع، وإلا
    // اختلطت صفوف من صفحات مختلفة تشترك نفس ارتفاع `top` في صف واحد.
    const pageOffset = 100000.0;
    final words = <TextWord>[];
    final wordAdjustedTop = <TextWord, double>{};
    for (final line in lines) {
      for (final w in line.wordCollection) {
        if (w.text.trim().isEmpty) continue;
        words.add(w);
        wordAdjustedTop[w] = line.pageIndex * pageOffset + w.bounds.top;
      }
    }
    words.sort((a, b) {
      final t = wordAdjustedTop[a]!.compareTo(wordAdjustedTop[b]!);
      return t != 0 ? t : a.bounds.left.compareTo(b.bounds.left);
    });

    final rows = <List<String>>[];
    var i = 0;
    while (i < words.length) {
      final rowTop = wordAdjustedTop[words[i]]!;
      final rowWords = <TextWord>[];
      var j = i;
      while (j < words.length && (wordAdjustedTop[words[j]]! - rowTop).abs() <= _rowTopTolerance) {
        rowWords.add(words[j]);
        j++;
      }
      rowWords.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

      final cells = <String>[];
      var currentCellWords = <TextWord>[];
      for (var k = 0; k < rowWords.length; k++) {
        if (k > 0 && rowWords[k].bounds.left - rowWords[k - 1].bounds.right > _columnGapThreshold) {
          cells.add(_deshape(currentCellWords.reversed.map((w) => w.text).join(' ')));
          currentCellWords = [];
        }
        currentCellWords.add(rowWords[k]);
      }
      if (currentCellWords.isNotEmpty) {
        cells.add(_deshape(currentCellWords.reversed.map((w) => w.text).join(' ')));
      }
      rows.add(cells);
      i = j;
    }
    return rows;
  }
}
