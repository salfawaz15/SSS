import 'dart:typed_data';

import 'package:excel/excel.dart';

/// يقرأ ملف تصدير Microsoft Forms الحقيقي بالاعتماد على **أسماء الأعمدة**
/// (صف العناوين) بدل فهرسة ثابتة - لأن Microsoft Forms يُصدّر أعمدة الفروع
/// الشرطية (مرشد كل قسم، تفاصيل كل إجراء إضافي) فقط عند وجود إجابة واحدة
/// على الأقل استخدمت ذلك الفرع، فيختلف عدد الأعمدة وترتيبها من تصدير لآخر
/// حسب البيانات الفعلية المجموعة - أي فهرسة ثابتة ستنكسر عاجلاً أم آجلاً.
class ExcelParserService {
  static const String shatrMale = 'شطر الطلاب';
  static const String shatrFemale = 'شطر الطالبات';

  /// أسماء الأقسام الخمسة كما تظهر بالضبط في نموذج Microsoft Forms
  static const List<String> departments = [
    'قسم الادارة',
    'قسم المحاسبة',
    'قسم التسويق',
    'قسم الاقتصاد و التمويل',
    'قسم نظم المعلومات الادارية',
  ];

  static const int _maxActions = 5;

  // البريد الجامعي بصيغة s<الرقم الجامعي>@student.tu.edu.sa (لا نتقيّد بالنطاق
  // بدقة تحسبًا لاختلافات طفيفة فيه - المهم هو استخراج الرقم بعد حرف s).
  // يُملأ تلقائيًا من Microsoft Forms ببريد الطالب الجامعي الذي سجّل دخوله به
  // (يظهر "anonymous" فقط لو اختُبر النموذج بدون تسجيل دخول جامعي).
  static final RegExp _universityIdPattern = RegExp(r'^[sS](\d+)@');

  static String _extractUniversityId(String email) {
    final match = _universityIdPattern.firstMatch(email.trim());
    return match?.group(1) ?? '';
  }

  /// يطبّع نص العنوان لمقارنة مرنة: يحذف كل المسافات/الأسطر، ويوحّد صور
  /// الألف (أ إ آ) حتى لا تختلف المطابقة بسبب اختلافات إملائية بسيطة بين
  /// نص العمود الفعلي وقيمة ثابتة في الكود (مثل "الادارية" مقابل "الإدارية").
  static String _normalize(String s) {
    return s
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا');
  }

  /// يبحث عن أول عمود يحقق [test] على نصه المطبَّع، أو -1 إن لم يوجد
  static int _findColumn(List<String> normalizedHeaders, bool Function(String h) test) {
    for (var i = 0; i < normalizedHeaders.length; i++) {
      if (test(normalizedHeaders[i])) return i;
    }
    return -1;
  }

  /// يبحث عن أعمدة حقل يتكرر لكل إجراء (1 بلا لاحقة، ثم 2-5)، فيرجّع خريطة
  /// من رقم الإجراء (1-5) إلى فهرس العمود، متضمّنة فقط الأعمدة الموجودة
  /// فعليًا في هذا الملف بالذات.
  static Map<int, int> _findActionColumns(
    List<String> normalizedHeaders,
    String normalizedBase,
  ) {
    final pattern = RegExp('^${RegExp.escape(normalizedBase)}(\\d?)\$');
    final result = <int, int>{};
    for (var i = 0; i < normalizedHeaders.length; i++) {
      final match = pattern.firstMatch(normalizedHeaders[i]);
      if (match == null) continue;
      final suffix = match.group(1);
      final actionNumber = (suffix == null || suffix.isEmpty) ? 1 : int.parse(suffix);
      result[actionNumber] = i;
    }
    return result;
  }

  static int? _findAdvisorColumn(
    List<String> normalizedHeaders,
    String department,
    String shatr,
  ) {
    final deptKey = _normalize(department.replaceFirst('قسم ', ''));
    final shatrKey = _normalize(shatr);
    final advisorPrefix = _normalize('المرشد الأكاديمي');
    for (var i = 0; i < normalizedHeaders.length; i++) {
      final h = normalizedHeaders[i];
      if (h.startsWith(advisorPrefix) && h.contains(deptKey) && h.contains(shatrKey)) {
        return i;
      }
    }
    return null;
  }

  /// يقرأ بايتات ملف xlsx ويرجّع قائمة تذاكر (تذكرة لكل طالب)
  static List<Map<String, dynamic>> parseTickets(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;

    if (sheet.maxRows < 2) return [];

    final headerRow = sheet.row(0);
    final headers = headerRow.map((c) => (c?.value?.toString() ?? '')).toList();
    final normalizedHeaders = headers.map(_normalize).toList();

    final emailCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('البريد الإلكتروني')),
    );
    final nameCol = _findColumn(normalizedHeaders, (h) => h == _normalize('الاسم'));
    final phoneCol = _findColumn(normalizedHeaders, (h) => h.contains(_normalize('رقم الجوال')));
    final expectedGradCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('تخرجهم')),
    );
    final disabilityCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('ذوي الإعاقة')),
    );
    final shatrCol = _findColumn(normalizedHeaders, (h) => h.contains(_normalize('مقر الدراسة')));
    final deptMaleCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('القسم العلمي')) && h.contains(_normalize('الطلاب')),
    );
    final deptFemaleCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('القسم العلمي')) && h.contains(_normalize('الطالبات')),
    );

    final actionTypeCols = _findActionColumns(normalizedHeaders, _normalize('نوع الاجراء'));
    final requiredSectionCols =
        _findActionColumns(normalizedHeaders, _normalize('رقم الشعبة المطلوبة'));
    final currentEditCols = _findActionColumns(
      normalizedHeaders,
      _normalize('رقم الشعبة الحالية (للتعديل)'),
    );
    final currentDeleteCols = _findActionColumns(
      normalizedHeaders,
      _normalize('رقم الشعبة الحالية (للحذف)'),
    );
    final courseCols = _findActionColumns(normalizedHeaders, _normalize('المقرر الدراسي'));
    final reasonCols = _findActionColumns(normalizedHeaders, _normalize('سبب الطلب'));
    final reasonDetailCols =
        _findActionColumns(normalizedHeaders, _normalize('يرجى توضيح سبب الطلب'));

    final tickets = <Map<String, dynamic>>[];

    // نتخطى صف العناوين (الصف الأول)
    for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = sheet.row(rowIndex);
      if (row.isEmpty) continue;

      final email = _cellText(row, emailCol);
      if (email.isEmpty) continue;

      final shatr = _cellText(row, shatrCol).trim();
      final isMale = shatr == shatrMale;

      final department = _cellText(row, isMale ? deptMaleCol : deptFemaleCol).trim();
      final advisorCol = _findAdvisorColumn(normalizedHeaders, department, shatr);

      final actions = _parseActions(
        row,
        actionTypeCols: actionTypeCols,
        requiredSectionCols: requiredSectionCols,
        currentEditCols: currentEditCols,
        currentDeleteCols: currentDeleteCols,
        courseCols: courseCols,
        reasonCols: reasonCols,
        reasonDetailCols: reasonDetailCols,
      );

      tickets.add({
        'email': email,
        'name': _cellText(row, nameCol),
        'university_id': _extractUniversityId(email),
        'phone': _cellText(row, phoneCol),
        'expected_graduate': _isYes(_cellText(row, expectedGradCol)),
        'has_disability': _isYes(_cellText(row, disabilityCol)),
        'shatr': shatr,
        'department': department,
        'advisor': advisorCol != null ? _cellText(row, advisorCol).trim() : '',
        'actions': actions,
      });
    }

    return tickets;
  }

  static List<Map<String, dynamic>> _parseActions(
    List<Data?> row, {
    required Map<int, int> actionTypeCols,
    required Map<int, int> requiredSectionCols,
    required Map<int, int> currentEditCols,
    required Map<int, int> currentDeleteCols,
    required Map<int, int> courseCols,
    required Map<int, int> reasonCols,
    required Map<int, int> reasonDetailCols,
  }) {
    final actions = <Map<String, dynamic>>[];

    for (var n = 1; n <= _maxActions; n++) {
      final typeCol = actionTypeCols[n];
      if (typeCol == null) continue;

      final actionType = _cellText(row, typeCol).trim();
      if (actionType.isEmpty) continue;

      final currentSectionEdit = _cellText(row, currentEditCols[n] ?? -1).trim();
      final currentSectionDelete = _cellText(row, currentDeleteCols[n] ?? -1).trim();

      actions.add({
        'action_type': actionType,
        'required_section': _cellText(row, requiredSectionCols[n] ?? -1).trim(),
        'current_section': currentSectionEdit.isNotEmpty
            ? currentSectionEdit
            : currentSectionDelete,
        'course': _cellText(row, courseCols[n] ?? -1).trim(),
        'reason': _cellText(row, reasonCols[n] ?? -1).trim(),
        'reason_detail': _cellText(row, reasonDetailCols[n] ?? -1).trim(),
      });
    }

    return actions;
  }

  static String _cellText(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final value = row[index]?.value;
    if (value == null) return '';
    return value.toString();
  }

  static bool _isYes(String value) {
    final v = value.trim();
    return v == 'نعم' || v.toLowerCase() == 'yes';
  }

  /// يجمّع التذاكر حسب (الشطر، القسم) مع ترتيب الأولوية:
  /// الخريجون المتوقعون وذوو الإعاقة أولاً
  static Map<String, List<Map<String, dynamic>>> groupByShatrAndDepartment(
    List<Map<String, dynamic>> tickets,
  ) {
    final rawGroups = <String, List<Map<String, dynamic>>>{};

    for (final t in tickets) {
      final key = '${t['shatr']}|${t['department']}';
      rawGroups.putIfAbsent(key, () => []).add(t);
    }

    for (final list in rawGroups.values) {
      list.sort((a, b) {
        final aPriority =
            (a['expected_graduate'] == true || a['has_disability'] == true)
            ? 0
            : 1;
        final bPriority =
            (b['expected_graduate'] == true || b['has_disability'] == true)
            ? 0
            : 1;
        return aPriority.compareTo(bPriority);
      });
    }

    // إعادة ترتيب المفاتيح بالترتيب المعتمد الثابت (كل شطر: الإدارة ... نظم
    // المعلومات الإدارية) بدل ترتيب أول ظهور في التذاكر الخام (يعتمد على
    // ترتيب الرفع/Firestore ويختلف عشوائيًا من دورة لأخرى) - يضمن ظهور كل
    // شاشات الإدارة (تنزيل الملفات، تقارير المراحل الثلاث، ...) بنفس الترتيب
    // المعتمد دائمًا.
    final orderedGroups = <String, List<Map<String, dynamic>>>{};
    for (final shatr in [shatrMale, shatrFemale]) {
      for (final department in departments) {
        final key = '$shatr|$department';
        final value = rawGroups.remove(key);
        if (value != null) orderedGroups[key] = value;
      }
    }
    // أي مفاتيح غير متوقَّعة (قسم/شطر خارج القائمة الثابتة) تُضاف أخيرًا
    // بدل فقدانها.
    orderedGroups.addAll(rawGroups);

    return orderedGroups;
  }
}
