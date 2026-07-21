import 'dart:typed_data';
import 'package:excel/excel.dart';

class ExcelParserService {
  // مواضع الأعمدة الثابتة في ملف Microsoft Forms (تبدأ من صفر)
  static const int _colEmail = 2;
  static const int _colName = 3;
  static const int _colPhone = 5;
  static const int _colExpectedGraduate = 6;
  static const int _colDisability = 7;
  static const int _colShatr = 8;
  static const int _colDeptMale = 9;
  static const int _colDeptFemale = 10;
  static const int _colAdvisorMale = 11;
  static const int _colAdvisorFemale = 12;
  static const int _actionsStartCol = 13; // العمود 14 (فهرسة من صفر = 13)
  static const int _actionBlockWidth = 8;
  static const int _maxActions = 5;

  static const String shatrMale = 'شطر الطلاب';
  static const String shatrFemale = 'شطر الطالبات';

  /// يقرأ بايتات ملف xlsx ويرجّع قائمة تذاكر (تذكرة لكل طالب)
  static List<Map<String, dynamic>> parseTickets(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;

    final tickets = <Map<String, dynamic>>[];

    // نتخطى صف العناوين (الصف الأول)
    for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = sheet.row(rowIndex);
      if (row.isEmpty || _cellText(row, _colEmail).isEmpty) continue;

      final shatr = _cellText(row, _colShatr);
      final isMale = shatr.trim() == shatrMale;

      final department = isMale
          ? _cellText(row, _colDeptMale)
          : _cellText(row, _colDeptFemale);

      final advisor = isMale
          ? _cellText(row, _colAdvisorMale)
          : _cellText(row, _colAdvisorFemale);

      final actions = _parseActions(row);

      tickets.add({
        'email': _cellText(row, _colEmail),
        'name': _cellText(row, _colName),
        'university_id': '', // غير موجود بالنموذج حاليًا
        'phone': _cellText(row, _colPhone),
        'expected_graduate': _isYes(_cellText(row, _colExpectedGraduate)),
        'has_disability': _isYes(_cellText(row, _colDisability)),
        'shatr': shatr.trim(),
        'department': department.trim(),
        'advisor': advisor.trim(),
        'actions': actions,
      });
    }

    return tickets;
  }

  static List<Map<String, dynamic>> _parseActions(List<Data?> row) {
    final actions = <Map<String, dynamic>>[];

    for (var i = 0; i < _maxActions; i++) {
      final base = _actionsStartCol + (i * _actionBlockWidth);
      final actionType = _cellText(row, base);

      // إذا العمود الأول بالبلوك فاضي، نعتبر ما فيه إجراء بهذا الرقم
      if (actionType.trim().isEmpty) continue;

      final requiredSection = _cellText(row, base + 1);
      final currentSectionEdit = _cellText(row, base + 2);
      final currentSectionDelete = _cellText(row, base + 3);
      final course = _cellText(row, base + 4);
      final reason = _cellText(row, base + 5);
      final reasonDetail = _cellText(row, base + 6);

      actions.add({
        'action_type': actionType.trim(),
        'required_section': requiredSection.trim(),
        'current_section': currentSectionEdit.trim().isNotEmpty
            ? currentSectionEdit.trim()
            : currentSectionDelete.trim(),
        'course': course.trim(),
        'reason': reason.trim(),
        'reason_detail': reasonDetail.trim(),
      });
    }

    return actions;
  }

  static String _cellText(List<Data?> row, int index) {
    if (index >= row.length) return '';
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
    final groups = <String, List<Map<String, dynamic>>>{};

    for (final t in tickets) {
      final key = '${t['shatr']}|${t['department']}';
      groups.putIfAbsent(key, () => []).add(t);
    }

    for (final list in groups.values) {
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

    return groups;
  }
}