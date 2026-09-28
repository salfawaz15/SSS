import 'package:html/parser.dart' as html_parser;

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;
import 'windows1256_decoder.dart';

/// يقرأ ملف "بيانات الطلبة الأكاديمية v1" - تصدير Oracle Reports بامتداد
/// .xls لكنه فعليًا جدول HTML (Windows-1256)، بنفس أسلوب
/// [InstructorTeachingLoadHtmlParserService] تمامًا. **مصدر المنتظمين فقط**
/// (لا عمود حالة قيد بالملف إطلاقًا - بتأكيد سليمان 2026-09-29 كل سجلاته
/// طلبة منتظمون بالفصل الحالي فقط)، أشمل وأعمق من ملفات CSV الستة القديمة:
/// يضيف "الإنذارات"/"المقررات المسجلة"/"الساعات المسجلة" - حقول لا وجود لها
/// بالمصدر القديم إطلاقًا.
///
/// **بنية الملف** (كتل مفصولة بصفوف عناوين "المقر :"/"الدرجة العلمية :"/
/// "الكلية :"/"القسم :"/"التخصص :"، ثم جدول طلاب لكل كتلة): م، رقم الطالب،
/// اسم الطالب، المعدل التراكمي، الانذارات، المقررات المسجلة، الساعات
/// المسجله. صف طالب يُعرَف برقم جامعي حقيقي (يبدأ بـ4، 8-9 خانات) في الخلية
/// الأولى بعد "م" - لا بترتيب أعمدة صارم، لأن الأعمدة الفارغة تختفي بنفس
/// أسلوب كل ملفات Oracle Reports الأخرى بالمشروع.
class AcademicDataRegularHtmlParserService {
  static final RegExp _studentIdPattern = RegExp(r'^4\d{7,8}$');

  static List<AdvisingCaseRecord> parse(List<int> rawBytes) {
    final text = Windows1256Decoder.decode(rawBytes);
    final document = html_parser.parse(text);
    final trs = document.querySelectorAll('tr');

    final rows = <List<String>>[];
    for (final tr in trs) {
      final spans = tr.querySelectorAll('span');
      final texts = <String>[];
      for (final s in spans) {
        final t = s.text.replaceAll(' ', ' ').trim();
        if (t.isNotEmpty) texts.add(t);
      }
      if (texts.isNotEmpty) rows.add(texts);
    }

    String? findValue(List<String> row, String label) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].contains(label)) {
          for (var j = i + 1; j < row.length; j++) {
            final v = row[j].trim();
            if (v.isEmpty) continue;
            if (v.endsWith(':') || v.endsWith('：')) return null;
            return v;
          }
        }
      }
      return null;
    }

    final records = <AdvisingCaseRecord>[];
    Shatr? currentShatr;
    String currentDepartment = '';

    for (final row in rows) {
      final place = findValue(row, 'المقر');
      if (place != null) {
        currentShatr = place.contains('طالبات') ? Shatr.female : Shatr.male;
      }
      final dept = findValue(row, 'القسم');
      if (dept != null) currentDepartment = normalizeDepartmentName(dept);

      // صف طالب حقيقي: رقم جامعي (يبدأ بـ4، 8-9 خانات) بأي خلية - يُستدَلّ
      // عليه بدل فهرسة ثابتة لأن الأعمدة الفارغة (إنذارات/مقررات = 0 قد
      // تُحذَف أحيانًا) تُزيح المواضع.
      final idIndex = row.indexWhere((c) => _studentIdPattern.hasMatch(c.trim()));
      if (idIndex == -1 || currentShatr == null) continue;

      final studentId = row[idIndex].trim();
      final studentName = idIndex + 1 < row.length ? row[idIndex + 1].trim() : '';
      if (studentName.isEmpty) continue;

      final gpaText = idIndex + 2 < row.length ? row[idIndex + 2].trim().replaceAll('٫', '.') : '';
      final warningsText = idIndex + 3 < row.length ? row[idIndex + 3].trim() : '';
      final registeredCoursesText = idIndex + 4 < row.length ? row[idIndex + 4].trim() : '';
      final registeredHoursText = idIndex + 5 < row.length ? row[idIndex + 5].trim() : '';

      records.add(AdvisingCaseRecord(
        studentId: studentId,
        studentName: studentName,
        department: currentDepartment,
        shatr: currentShatr.label,
        advisorNameRaw: '',
        gpa: double.tryParse(gpaText),
        enrollmentStatus: 'منتظم',
        academicWarnings: int.tryParse(warningsText),
        registeredCoursesCount: int.tryParse(registeredCoursesText),
        registeredHours: int.tryParse(registeredHoursText),
      ));
    }

    return records;
  }
}
