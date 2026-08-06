import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;

const String _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// يُرمى حين لا يحتوي الملف عمود "الجنس" (فلا يمكن فرز صفوفه تلقائيًا حسب
/// الشطر) ولم يُحدَّد شطر صراحةً عند الاستدعاء - تلتقطه الشاشة لتعرض على
/// المستخدم اختيار الشطر يدويًا ثم تعيد المحاولة به.
class ShatrRequiredException implements Exception {
  const ShatrRequiredException();
}

/// يقرأ تقارير المنظومة الداخلية المتعلقة بالإرشاد (كلها بعد تحويلها من PDF
/// إلى Word بنفس الآلية المعتمدة، وكلها بنفس أسلوب الجدول): "بيانات الطلبة
/// الأكاديمية حسب الكلية والقسم" (القاعدة + المعدل)، "طلاب تابعين لمرشد"،
/// و"طلاب غير تابعين لمرشد" (ربط المرشد). **لا يعتمد على ترتيب أعمدة ثابت**
/// بل يبحث عن صف العناوين ويطابق كل عمود مطلوب بالاسم - بعض الأعمدة تكون
/// غائبة حسب نوع التقرير (مثال: تقارير ربط المرشد لا تحوي عمود "التخصص"
/// لأن قسم الطالب فيها يظهر كعنوان صفحة لا كعمود، فيُستكمَل من تقرير القاعدة
/// عند الدمج، وليس هنا).
class AdvisingReportParserService {
  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

  static String _toWestern(String s) {
    final buffer = StringBuffer();
    for (final ch in s.runes) {
      final idx = _arabicDigits.indexOf(String.fromCharCode(ch));
      buffer.write(idx == -1 ? String.fromCharCode(ch) : idx.toString());
    }
    return buffer.toString();
  }

  static String _cellText(XmlElement tc) {
    final buffer = StringBuffer();
    for (final t in tc.findAllElements('t', namespace: _wNs)) {
      buffer.write(t.innerText);
    }
    return _toWestern(buffer.toString()).trim();
  }

  static String _normalize(String s) => s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه');

  static int _findColumn(List<String> normalizedHeaders, List<String> candidates) {
    for (final c in candidates) {
      final nc = _normalize(c);
      for (var i = 0; i < normalizedHeaders.length; i++) {
        if (normalizedHeaders[i].contains(nc)) return i;
      }
    }
    return -1;
  }

  static String _cell(List<String> row, int index) => (index < 0 || index >= row.length) ? '' : row[index];

  static List<List<String>> _readTableRows(List<int> docxBytes) {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    final xmlStr = utf8.decode(docFile.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);

    final rows = <List<String>>[];
    for (final tr in doc.findAllElements('tr', namespace: _wNs)) {
      final cells = tr.findAllElements('tc', namespace: _wNs).map(_cellText).toList();
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  static const List<String> _maleGenderWords = ['ذكر', 'طالب'];
  static const List<String> _femaleGenderWords = ['انثي', 'انثى', 'طالبه'];

  /// إن كان الملف فارغًا (لا جدول فيه أصلاً - كملف "مرشدين ليس لهم طلاب" حين
  /// لا توجد حالة واحدة) تُرجَع قائمة فارغة بدل رمي استثناء، لأن هذه حالة
  /// طبيعية متوقَّعة وليست خطأً في الملف.
  ///
  /// [requireDepartment] يُفعَّل فقط لتقرير "بيانات الطلبة الأكاديمية"
  /// (القاعدة) الذي يحوي عمود "التخصص" فعليًا - تقارير ربط المرشد لا تحتاجه
  /// (قسم الطالب فيها عنوان صفحة، ويُستكمَل من القاعدة عند الدمج).
  ///
  /// [shatr] اختياري الآن: إن وُجد عمود "الجنس" في الملف يُستنتَج شطر كل صف
  /// منه تلقائيًا (فيُرفع ملف واحد موحَّد بدل ملفين منفصلين لكل شطر)، متجاوزًا
  /// [shatr] كليًا. إن لم يوجد العمود ولم يُمرَّر [shatr] يُرمى
  /// [ShatrRequiredException] لتطلب الشاشة من المستخدم تحديد الشطر يدويًا.
  static List<AdvisingCaseRecord> parse(
    List<int> docxBytes, {
    Shatr? shatr,
    bool requireDepartment = true,
  }) {
    final rows = _readTableRows(docxBytes);
    if (rows.isEmpty) return const [];

    // صف العناوين هو أول صف يحتوي على نص يشبه "اسم" (بعض التقارير المحوَّلة
    // من PDF تضيف صفوف عنوان/تاريخ فارغة قبل صف العناوين الفعلي).
    var headerRowIndex = rows.indexWhere((r) => r.any((c) => _normalize(c).contains(_normalize('اسم'))));
    if (headerRowIndex == -1) return const [];

    final headers = rows[headerRowIndex].map(_normalize).toList();

    final nameCol = _findColumn(headers, ['اسم الطالب', 'اسم الطالبة', 'الاسم']);
    final idCol = _findColumn(headers, ['رقم الطالب', 'الرقم الجامعي', 'الرقم الاكاديمي']);
    final deptCol = _findColumn(headers, ['التخصص', 'القسم العلمي']);
    final advisorNameCol = _findColumn(headers, ['اسم المرشد', 'المرشد الاكاديمي']);
    final advisorIdCol = _findColumn(headers, ['رقم المرشد']);
    final advisorDeptCol = _findColumn(headers, ['قسم المرشد']);
    final gpaCol = _findColumn(headers, ['المعدل التراكمي', 'المعدل']);
    final conditionCol = _findColumn(headers, ['الحالة الصحية', 'الحالة']);
    final genderCol = _findColumn(headers, ['الجنس']);

    if (nameCol == -1 || idCol == -1 || (requireDepartment && deptCol == -1)) {
      throw Exception(
        'تعذّر التعرّف على الأعمدة المطلوبة في الملف. '
        'العناوين الموجودة فعليًا في صف العناوين: ${rows[headerRowIndex].join(" | ")}',
      );
    }
    if (genderCol == -1 && shatr == null) {
      throw const ShatrRequiredException();
    }

    String? resolveShatrLabel(String genderText) {
      final n = _normalize(genderText);
      if (_maleGenderWords.any((w) => n.contains(_normalize(w)))) return Shatr.male.label;
      if (_femaleGenderWords.any((w) => n.contains(_normalize(w)))) return Shatr.female.label;
      return null;
    }

    final result = <AdvisingCaseRecord>[];
    for (var r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      final name = _cell(row, nameCol).trim();
      final id = _cell(row, idCol).trim();
      if (name.isEmpty || id.isEmpty) continue;

      final gpaText = _cell(row, gpaCol).trim();
      final gpa = gpaText.isEmpty ? null : double.tryParse(gpaText);

      final rowShatrLabel =
          (genderCol != -1 ? resolveShatrLabel(_cell(row, genderCol)) : null) ?? shatr?.label;
      if (rowShatrLabel == null) continue; // تعذّر تحديد شطر هذا الصف تحديدًا - يُتجاهَل بدل تخمينه

      result.add(AdvisingCaseRecord(
        studentId: id,
        studentName: name,
        department: _cell(row, deptCol).trim(),
        shatr: rowShatrLabel,
        advisorNameRaw: _cell(row, advisorNameCol).trim(),
        advisorId: _cell(row, advisorIdCol).trim(),
        advisorDepartment: _cell(row, advisorDeptCol).trim(),
        gpa: gpa,
        healthCondition: _cell(row, conditionCol).trim(),
      ));
    }

    return result;
  }
}
