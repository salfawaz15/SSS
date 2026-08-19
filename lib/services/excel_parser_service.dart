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

  static const int _maxAddActions = 3;
  static const int _maxDeleteActions = 2;
  static const int _maxChangeActions = 2;

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

  /// يبحث عن كل الأعمدة التي تحقق [test] ضمن نطاق فهارس [start, end) فقط،
  /// بترتيب ظهورها. ضروري لأن النموذج الجديد يكرّر نفس عنوان السؤال حرفيًا
  /// بين أقسام مختلفة (مثل "المقرر الأول ورقم الشعبة" في كل من قسمي الإضافة
  /// والحذف)، فلا يمكن تمييزها إلا بموقعها ضمن نطاق قسمها (محصور بين عمودي
  /// بوابة "هل لديك طلب ...؟" الفريدين قبله وبعده).
  static List<int> _findColumnsInRange(
    List<String> normalizedHeaders,
    int start,
    int end,
    bool Function(String h) test,
  ) {
    final result = <int>[];
    final safeStart = start < 0 ? 0 : start;
    final safeEnd = end < 0 || end > normalizedHeaders.length ? normalizedHeaders.length : end;
    for (var i = safeStart; i < safeEnd; i++) {
      if (test(normalizedHeaders[i])) result.add(i);
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
    // العمود الحقيقي بملف Microsoft Forms اسمه "الشطر" بالضبط (تحقَّقنا من
    // تصدير حقيقي فعليًا) - "مقر الدراسة" أُبقيَت كبديل احتياطي فقط تحسبًا
    // لتسمية قديمة مختلفة، لا كالمطابقة الأساسية (كانت هي الوحيدة سابقًا،
    // فتفشل صامتة مع كل ملف حقيقي وتُفرغ قيمة الشطر لكل الحالات).
    final shatrCol = _findColumn(
      normalizedHeaders,
      (h) => h == _normalize('الشطر') || h.contains(_normalize('مقر الدراسة')),
    );
    final deptMaleCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('القسم العلمي')) && h.contains(_normalize('الطلاب')),
    );
    final deptFemaleCol = _findColumn(
      normalizedHeaders,
      (h) => h.contains(_normalize('القسم العلمي')) && h.contains(_normalize('الطالبات')),
    );

    final universityIdTypedCol =
        _findColumn(normalizedHeaders, (h) => h == _normalize('الرقم الجامعي'));

    // بوابات الأقسام الثلاثة: سؤال "هل لديك طلب إضافة مقرر؟" (بخلاف الحذف
    // والتعديل) يقع داخل تفريع القسم/الشطر، فيُصدَّر بعشر نسخ شبه متطابقة
    // (نفس العنوان الحرفي بلاحقة تعداد تُضيفها Excel تلقائيًا: "؟"، "؟  2"،
    // ... "؟  10") واحدة لكل توليفة (شطر × قسم) تمامًا كأعمدة المرشد العشرة -
    // القيمة الفعلية تكون في نسخة واحدة فقط منها (فرع الطالب) والباقي فارغ،
    // فيجب فحص كل النسخ معًا (أي منها "نعم") بدل الاكتفاء بأول عمود مطابق.
    // الحذف والتعديل يقعان بعد تلاقي كل الفروع فتكفيهما نسخة واحدة، لكن نتعامل
    // معهما بنفس الأسلوب احتياطًا لو تغيّر تصميم النموذج لاحقًا.
    final addGateCols = _findColumnsInRange(
      normalizedHeaders,
      0,
      normalizedHeaders.length,
      (h) => h.contains(_normalize('طلب إضافة مقرر')),
    );
    final deleteGateCols = _findColumnsInRange(
      normalizedHeaders,
      0,
      normalizedHeaders.length,
      (h) => h.contains(_normalize('طلب حذف مقرر')),
    );
    final changeGateCols = _findColumnsInRange(
      normalizedHeaders,
      0,
      normalizedHeaders.length,
      (h) => h.contains(_normalize('طلب تعديل شعبة')),
    );

    // نستخدم أول فهرس من كل مجموعة بوابات فقط لترسيم حدود نطاق القسم (كل
    // النسخ المكرَّرة متجاورة قبل الحقول النصية الحرة المشتركة أصلاً)، وليس
    // لقراءة قيمة الإجابة - تلك تُفحص عبر كل النسخ معًا أدناه.
    final addGateCol = addGateCols.isEmpty ? -1 : addGateCols.first;
    final deleteGateCol = deleteGateCols.isEmpty ? -1 : deleteGateCols.first;
    final changeGateCol = changeGateCols.isEmpty ? -1 : changeGateCols.first;

    final addRangeStart = addGateCol >= 0 ? addGateCol + 1 : -1;
    final addRangeEnd = deleteGateCol >= 0 ? deleteGateCol : normalizedHeaders.length;
    final deleteRangeStart = deleteGateCol >= 0 ? deleteGateCol + 1 : -1;
    final deleteRangeEnd = changeGateCol >= 0 ? changeGateCol : normalizedHeaders.length;
    final changeRangeStart = changeGateCol >= 0 ? changeGateCol + 1 : -1;
    final changeRangeEnd = normalizedHeaders.length;

    final addCourseCols = addGateCol < 0
        ? const <int>[]
        : _findColumnsInRange(
            normalizedHeaders,
            addRangeStart,
            addRangeEnd,
            (h) => h.contains(_normalize('ورقم الشعبة')),
          );
    final addReasonColInRange = addGateCol < 0
        ? -1
        : (_findColumnsInRange(
            normalizedHeaders,
            addRangeStart,
            addRangeEnd,
            (h) => h.contains(_normalize('سبب')),
          )..sort())
            .firstOrNull ??
            -1;

    final deleteCourseCols = deleteGateCol < 0
        ? const <int>[]
        : _findColumnsInRange(
            normalizedHeaders,
            deleteRangeStart,
            deleteRangeEnd,
            (h) => h.contains(_normalize('ورقم الشعبة')),
          );
    final deleteReasonColInRange = deleteGateCol < 0
        ? -1
        : (_findColumnsInRange(
            normalizedHeaders,
            deleteRangeStart,
            deleteRangeEnd,
            (h) => h.contains(_normalize('سبب')),
          )..sort())
            .firstOrNull ??
            -1;
    final deleteDetailColInRange = deleteGateCol < 0
        ? -1
        : (_findColumnsInRange(
            normalizedHeaders,
            deleteRangeStart,
            deleteRangeEnd,
            (h) => h.contains(_normalize('الظروف الخاصة')),
          )..sort())
            .firstOrNull ??
            -1;

    final changeCourseCols = changeGateCol < 0
        ? const <int>[]
        : _findColumnsInRange(
            normalizedHeaders,
            changeRangeStart,
            changeRangeEnd,
            (h) => h.contains(_normalize('الحالية والمطلوبة')),
          );
    final changeReasonColInRange = changeGateCol < 0
        ? -1
        : (_findColumnsInRange(
            normalizedHeaders,
            changeRangeStart,
            changeRangeEnd,
            (h) => h.contains(_normalize('سبب')),
          )..sort())
            .firstOrNull ??
            -1;
    final changeDetailColInRange = changeGateCol < 0
        ? -1
        : (_findColumnsInRange(
            normalizedHeaders,
            changeRangeStart,
            changeRangeEnd,
            (h) => h.contains(_normalize('الظروف الخاصة')),
          )..sort())
            .firstOrNull ??
            -1;

    final tickets = <Map<String, dynamic>>[];

    // نتخطى صف العناوين (الصف الأول)
    for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = sheet.row(rowIndex);
      if (row.isEmpty) continue;

      final email = _cellText(row, emailCol);
      if (email.isEmpty) continue;

      // القيمة الفعلية القادمة من Microsoft Forms هي "شطر طلاب"/"شطر طالبات"
      // (بلا "ال" التعريف) - مختلفة حرفيًا عن shatrMale/shatrFemale
      // ('شطر الطلاب'/'شطر الطالبات') المعتمدين بكل الموقع لمقارنات المساواة
      // التامة بعشرات الملفات (فلاتر، قوائم منسدلة، توجيه صلاحيات...). مقارنة
      // شرطية بـ.contains('طلاب') تكتشف الجنس بشكل موثوق (لا تلتبس بـ"طالبات"
      // لأن "طلاب" ليست جزءًا منها حرفيًا)، ثم نخزّن القيمة الكنسية المعتمدة
      // في التذكرة الناتجة بدل النص الخام - فكل مستهلك حالي بالموقع يستمر
      // بالعمل بلا أي تعديل عليه. نُبقي [shatrRaw] فقط لمطابقة عمود المرشد
      // (عناوينه تستخدم "طلاب"/"طالبات" بلا "ال" مطابقةً للنص الخام).
      final shatrRaw = _cellText(row, shatrCol).trim();
      final isMale = shatrRaw.contains('طلاب');
      final shatr = isMale ? shatrMale : shatrFemale;

      final department = _cellText(row, isMale ? deptMaleCol : deptFemaleCol).trim();
      final advisorCol = _findAdvisorColumn(normalizedHeaders, department, shatrRaw);

      final actions = <Map<String, dynamic>>[];

      final wantsAdd = addGateCols.any((c) => _isYes(_cellText(row, c)));
      if (wantsAdd) {
        final reason = _cellText(row, addReasonColInRange).trim();
        for (var i = 0; i < addCourseCols.length && i < _maxAddActions; i++) {
          final raw = _cellText(row, addCourseCols[i]).trim();
          if (raw.isEmpty) continue;
          final parsed = _parseCourseAndSection(raw);
          actions.add({
            'action_type': 'إضافة',
            'required_section': parsed['section'] ?? '',
            'current_section': '',
            'course': _joinCourse(parsed),
            'reason': reason,
            'reason_detail': reason,
          });
        }
      }

      final wantsDelete = deleteGateCols.any((c) => _isYes(_cellText(row, c)));
      if (wantsDelete) {
        final reason = _cellText(row, deleteReasonColInRange).trim();
        final detail = _cellText(row, deleteDetailColInRange).trim();
        for (var i = 0; i < deleteCourseCols.length && i < _maxDeleteActions; i++) {
          final raw = _cellText(row, deleteCourseCols[i]).trim();
          if (raw.isEmpty) continue;
          final parsed = _parseCourseAndSection(raw);
          actions.add({
            'action_type': 'حذف',
            'required_section': '',
            'current_section': parsed['section'] ?? '',
            'course': _joinCourse(parsed),
            'reason': reason,
            'reason_detail': detail.isNotEmpty ? detail : reason,
          });
        }
      }

      final wantsChange = changeGateCols.any((c) => _isYes(_cellText(row, c)));
      if (wantsChange) {
        final reason = _cellText(row, changeReasonColInRange).trim();
        final detail = _cellText(row, changeDetailColInRange).trim();
        for (var i = 0; i < changeCourseCols.length && i < _maxChangeActions; i++) {
          final raw = _cellText(row, changeCourseCols[i]).trim();
          if (raw.isEmpty) continue;
          final parsed = _parseSectionChange(raw);
          actions.add({
            'action_type': 'تعديل',
            'required_section': parsed['requestedSection'] ?? '',
            'current_section': parsed['currentSection'] ?? '',
            'course': _joinCourse(parsed),
            'reason': reason,
            'reason_detail': detail.isNotEmpty ? detail : reason,
          });
        }
      }

      final typedUniversityId =
          universityIdTypedCol >= 0 ? _cellText(row, universityIdTypedCol).trim() : '';

      tickets.add({
        'email': email,
        'name': _cellText(row, nameCol),
        'university_id': _extractUniversityId(email),
        'typed_university_id': typedUniversityId,
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

  // نمط "<رمز> - <اسم المقرر> - <رقم الشعبة>" (الحقول الحرة لأقسام الإضافة
  // والحذف) - نلتقط رقم الشعبة كآخر عدد بنهاية النص بعد فاصل شرطة، والباقي
  // نص المقرر (رمز + اسم).
  static final RegExp _trailingSectionPattern = RegExp(r'^(.*?)[-–—]\s*(\d{2,6})\s*$');
  static final RegExp _courseCodeNamePattern = RegExp(r'^(\d+)\s*[-–—]\s*(.+)$');
  static final RegExp _currentSectionKeywordPattern =
      RegExp(r'(?:الحالي(?:ة)?|الشعبةالحالية)\s*[:\-]?\s*(\d{2,6})');
  static final RegExp _requestedSectionKeywordPattern =
      RegExp(r'(?:المطلوب(?:ة)?|الشعبةالمطلوبة)\s*[:\-]?\s*(\d{2,6})');

  static Map<String, String> _parseCourseAndSection(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const {'code': '', 'name': '', 'section': ''};

    var coursePart = text;
    var section = '';
    final sectionMatch = _trailingSectionPattern.firstMatch(text);
    if (sectionMatch != null) {
      coursePart = sectionMatch.group(1)!.trim();
      section = sectionMatch.group(2)!.trim();
    }

    final courseMatch = _courseCodeNamePattern.firstMatch(coursePart);
    if (courseMatch != null) {
      return {
        'code': courseMatch.group(1)!.trim(),
        'name': courseMatch.group(2)!.trim(),
        'section': section,
      };
    }
    return {'code': '', 'name': coursePart, 'section': section};
  }

  /// يحلّل نص "التعديل الأول/الثاني - المقرر والشعبة الحالية والمطلوبة"،
  /// يبحث عن رقمي الشعبة الحالية والمطلوبة بمرافقة كلماتهما الدالة، والباقي
  /// بعد حذفهما هو نص المقرر (رمز + اسم).
  static Map<String, String> _parseSectionChange(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const {'code': '', 'name': '', 'currentSection': '', 'requestedSection': ''};
    }

    final compact = _normalize(text);
    final currentMatch = _currentSectionKeywordPattern.firstMatch(compact);
    final requestedMatch = _requestedSectionKeywordPattern.firstMatch(compact);

    var courseText = text;
    if (currentMatch != null || requestedMatch != null) {
      // نحذف من النص الأصلي كل رقم شعبة التقطناه (بمطابقة الرقم نفسه) حتى لا
      // يبقى ضمن اسم المقرر المُستخرَج.
      if (currentMatch != null) {
        courseText = courseText.replaceAll(currentMatch.group(1)!, '');
      }
      if (requestedMatch != null) {
        courseText = courseText.replaceAll(requestedMatch.group(1)!, '');
      }
    }

    final parsed = _parseCourseAndSection(courseText.replaceAll(RegExp(r'[:\-–—]+$'), '').trim());
    return {
      'code': parsed['code'] ?? '',
      'name': parsed['name'] ?? '',
      'currentSection': currentMatch?.group(1) ?? '',
      'requestedSection': requestedMatch?.group(1) ?? '',
    };
  }

  static String _joinCourse(Map<String, String> parsed) {
    final code = parsed['code'] ?? '';
    final name = parsed['name'] ?? '';
    if (code.isEmpty) return name;
    if (name.isEmpty) return code;
    return '$code - $name';
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
