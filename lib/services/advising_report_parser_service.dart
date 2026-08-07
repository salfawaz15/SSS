import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import 'advisor_name_matching.dart';
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

  /// يفضّل التطابق التام أولًا قبل الاحتواء الجزئي - وإلا فعمود "الجنسية"
  /// (سعودي/يمني...) يُلتقَط خطأً كعمود "الجنس" لأن "الجنسية" تبدأ بنفس حروف
  /// "الجنس"، وبالمثل قد تلتبس أعمدة أخرى ببعضها.
  static int _findColumn(List<String> normalizedHeaders, List<String> candidates) {
    for (final c in candidates) {
      final nc = _normalize(c);
      for (var i = 0; i < normalizedHeaders.length; i++) {
        if (normalizedHeaders[i] == nc) return i;
      }
    }
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

  /// صف "بيانات المرشد" الذي يسبق جدول طلابه في تقارير ربط المرشد (اسم
  /// المرشد، رقمه، ثم خلية تسمية "رقم المرشد" - نفس الترتيب دائمًا في هذه
  /// التقارير المحوَّلة من PDF).
  static bool _isAdvisorHeaderRow(List<String> row) =>
      row.length == 3 && _normalize(row.last).contains(_normalize('رقم المرشد'));

  /// إن كان الملف فارغًا (لا جدول فيه أصلاً - كملف "مرشدين ليس لهم طلاب" حين
  /// لا توجد حالة واحدة) تُرجَع قائمة فارغة بدل رمي استثناء، لأن هذه حالة
  /// طبيعية متوقَّعة وليست خطأً في الملف.
  ///
  /// [requireDepartment] يُفعَّل فقط لتقرير "بيانات الطلبة الأكاديمية"
  /// (القاعدة) الذي يحوي عمود "التخصص" فعليًا - تقارير ربط المرشد لا تحتاجه
  /// (قسم الطالب فيها عنوان صفحة، ويُستكمَل من القاعدة عند الدمج).
  ///
  /// صف العناوين يُعاد اكتشافه في كل مرة يظهر فيها (تقارير ربط المرشد تكرره
  /// لكل مرشد، وترتيب الأعمدة قد يختلف قليلًا بين كتلة وأخرى بسبب تحويل PDF).
  ///
  /// [shatr] اختياري: إن وُجد عمود "الجنس" في الملف يُستنتَج شطر كل صف منه
  /// تلقائيًا، متجاوزًا [shatr] كليًا. إن لم يوجد العمود، يُحاوَل الاستنتاج من
  /// شطر مرشد كل صف عبر [advisorShatrByName] (خريطة اسم المرشد المطبَّع عبر
  /// [normalizeAdvisorNameForMatch] ← تسمية الشطر، من قائمة مرشدي القسم - لا
  /// يوجد رقم مرشد مشترك بين هذا التقرير وقائمة المرشدين فالمطابقة بالاسم لا
  /// بالرقم) - مفيد لتقارير ربط المرشد التي لا تحوي عمود الجنس ولا حتى عنوان
  /// صفحة يفرّق الشطرين، فيُرفع ملف واحد موحَّد يضم الشطرين معًا ويُفرز
  /// تلقائيًا حسب شطر كل مرشد. إن تعذّرت كل الطرق ولم يُمرَّر [shatr] يُرمى
  /// [ShatrRequiredException] لتطلب الشاشة من المستخدم تحديد الشطر يدويًا.
  ///
  /// [isHealthReport] يُفعَّل فقط لتقرير "الحالة الصحية للطلبة" - عموده
  /// الوحيد المتاح لهذا الغرض اسمه أيضًا "الحالة" حرفيًا (نفس اسم عمود الحالة
  /// الدراسية في تقرير القاعدة)، فلا يمكن تمييز الحالة الصحية الحقيقية
  /// (مثال: "بتر بالقدم") عن الحالة الدراسية العادية ("منتظم") بالاسم وحده -
  /// دون هذا العلم كانت كل الحالات الدراسية العادية تُحتسَب خطأً كحالات صحية.
  static List<AdvisingCaseRecord> parse(
    List<int> docxBytes, {
    Shatr? shatr,
    bool requireDepartment = true,
    Map<String, String>? advisorShatrByName,
    bool isHealthReport = false,
  }) {
    final rows = _readTableRows(docxBytes);
    if (rows.isEmpty) return const [];

    String? resolveShatrLabel(String genderText) {
      final n = _normalize(genderText);
      if (_maleGenderWords.any((w) => n.contains(_normalize(w)))) return Shatr.male.label;
      if (_femaleGenderWords.any((w) => n.contains(_normalize(w)))) return Shatr.female.label;
      return null;
    }

    int nameCol = -1, idCol = -1, deptCol = -1;
    int advisorNameCol = -1, advisorIdCol = -1, advisorDeptCol = -1;
    int gpaCol = -1, conditionCol = -1, genderCol = -1, degreeCol = -1;
    var sawHeader = false;
    var missingRequiredColumns = false;
    var firstHeaderRaw = '';

    String? currentAdvisorId;
    String? currentAdvisorName;

    final result = <AdvisingCaseRecord>[];

    for (final row in rows) {
      if (_isAdvisorHeaderRow(row)) {
        currentAdvisorName = row[0].trim();
        currentAdvisorId = row[1].trim();
        continue;
      }

      final isHeaderRow = row.any((c) => _normalize(c).contains(_normalize('اسم')));
      if (isHeaderRow) {
        final headers = row.map(_normalize).toList();
        nameCol = _findColumn(headers, ['اسم الطالب', 'اسم الطالبة', 'الاسم']);
        idCol = _findColumn(headers, ['رقم الطالب', 'الرقم الجامعي', 'الرقم الاكاديمي']);
        deptCol = _findColumn(headers, ['التخصص', 'القسم العلمي']);
        advisorNameCol = _findColumn(headers, ['اسم المرشد', 'المرشد الاكاديمي']);
        advisorIdCol = _findColumn(headers, ['رقم المرشد']);
        advisorDeptCol = _findColumn(headers, ['قسم المرشد']);
        gpaCol = _findColumn(headers, ['المعدل التراكمي', 'المعدل']);
        conditionCol = _findColumn(headers, ['الحالة الصحية', 'الحالة']);
        genderCol = _findColumn(headers, ['الجنس']);
        degreeCol = _findColumn(headers, ['الدرجة العلمية']);
        if (!sawHeader) {
          firstHeaderRaw = row.join(' | ');
          missingRequiredColumns = nameCol == -1 || idCol == -1 || (requireDepartment && deptCol == -1);
        }
        sawHeader = true;
        continue;
      }

      if (!sawHeader) continue;

      final name = _cell(row, nameCol).trim();
      final id = _cell(row, idCol).trim();
      if (name.isEmpty || id.isEmpty) continue;

      // وحدة الإرشاد الأكاديمي تُعنى بطلبة البكالوريوس فقط - أي درجة أعلى
      // (ماجستير/دكتوراه) تُستبعَد إن وُجد عمود "الدرجة العلمية" في الملف.
      if (degreeCol != -1) {
        final degreeText = _normalize(_cell(row, degreeCol));
        final isGraduate =
            degreeText.contains(_normalize('ماجستير')) || degreeText.contains(_normalize('دكتوراه'));
        if (isGraduate) continue;
      }

      // القسم يُوحَّد لنفس صيغة ملف منسوبي الكلية (انظر
      // academic_department_names.dart) وإلا فشلت مقارنته بقسم المرشد/فلتر
      // القسم لمجرد اختلاف نصي شكلي (مثال: "الإدارة" من هذا التقرير مقابل
      // "قسم الادارة" من ملف منسوبي الكلية). برامج الدراسات العليا الخاصة
      // (مثال: "إدارة الأعمال التنفيذي") ليست من الأقسام الخمسة المعروفة
      // فتُستبعَد هنا تلقائيًا حتى لو لم يُفصح عمود "الدرجة العلمية" عنها.
      final normalizedDept = deptCol != -1 ? normalizeDepartmentName(_cell(row, deptCol)) : '';
      if (requireDepartment && !isKnownBachelorDepartment(normalizedDept)) continue;

      // بعض التقارير تكتب المعدل بالفاصلة العشرية العربية "٫" (U+066B) بدل
      // النقطة العادية - double.tryParse لا يتعرف عليها فتفشل قراءة أغلب
      // المعدلات بصمت (تصير null) دون هذا الاستبدال.
      final gpaText = _cell(row, gpaCol).trim().replaceAll('٫', '.');
      final gpa = gpaText.isEmpty ? null : double.tryParse(gpaText);

      // اسم المرشد المرجعي لهذا الصف: من عمود بالجدول نفسه إن وُجد (تقرير
      // "طلاب على غير مرشدهم")، وإلا من آخر صف "بيانات مرشد" منفصل صودف
      // (تقرير "طلاب تابعين لمرشد").
      final rowAdvisorName = advisorNameCol != -1 ? _cell(row, advisorNameCol).trim() : currentAdvisorName;
      String? advisorShatrLabel;
      if (rowAdvisorName != null && rowAdvisorName.isNotEmpty && advisorShatrByName != null) {
        advisorShatrLabel = advisorShatrByName[normalizeAdvisorNameForMatch(rowAdvisorName)];
      }
      final rowShatrLabel = (genderCol != -1 ? resolveShatrLabel(_cell(row, genderCol)) : null) ??
          advisorShatrLabel ??
          shatr?.label;
      if (rowShatrLabel == null) continue; // تعذّر تحديد شطر هذا الصف تحديدًا - يُتجاهَل بدل تخمينه

      result.add(AdvisingCaseRecord(
        studentId: id,
        studentName: name,
        department: normalizedDept.isNotEmpty ? normalizedDept : _cell(row, deptCol).trim(),
        shatr: rowShatrLabel,
        advisorNameRaw: rowAdvisorName ?? '',
        advisorId: advisorIdCol != -1 ? _cell(row, advisorIdCol).trim() : (currentAdvisorId ?? ''),
        advisorDepartment: _cell(row, advisorDeptCol).trim(),
        gpa: gpa,
        healthCondition: isHealthReport ? _cell(row, conditionCol).trim() : '',
        enrollmentStatus: isHealthReport ? '' : _cell(row, conditionCol).trim(),
      ));
    }

    if (!sawHeader) return const [];
    if (missingRequiredColumns) {
      throw Exception(
        'تعذّر التعرّف على الأعمدة المطلوبة في الملف. '
        'العناوين الموجودة فعليًا في صف العناوين: $firstHeaderRaw',
      );
    }
    if (result.isEmpty && genderCol == -1 && shatr == null && (advisorShatrByName?.isEmpty ?? true)) {
      throw const ShatrRequiredException();
    }

    return result;
  }
}
