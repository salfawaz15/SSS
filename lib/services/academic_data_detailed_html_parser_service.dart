import 'package:html/parser.dart' as html_parser;

import '../data/academic_department_names.dart';
import '../models/advising_case_record.dart';
import 'course_schedule_repository.dart' show Shatr, ShatrLabel;
import 'windows1256_decoder.dart';

/// يقرأ تقرير "بيانات الطلبة الأكاديمية" التفصيلي - تصدير Oracle Reports/HTML
/// (Windows-1256) بامتداد .xls، عادة يُصدَّر كملفات متعددة (كل قسم × نوع
/// دراسة - "انتظام"/"مدفوع" - ملف مستقل) بدل ملف واحد ضخم. **مصدر شامل لكل
/// حالات القيد** (منتظم/مفصول أكاديميًا/منقطع عن الدراسة معًا بعمود "الحالة"
/// الصريح لكل صف) - بخلاف [AcademicDataRegularHtmlParserService] (v1، منتظمين
/// فقط) و[AcademicDataCsvParserService] (يستنتج الحالة من اسم الملف) - هذا
/// المصدر **يستبدل الاثنين معًا بالكامل** إن اعتُمد (تأكيد سليمان 2026-09-29).
///
/// **بنية الملف**: كتل بعنوان "الكلية :"/"القسم :"، ثم جدول لكل طالب بأعمدة:
/// م، الرقم الجامعي، الاسم، التخصص، **الحالة** (قيمة صريحة لكل صف - منتظم/
/// مفصول أكاديميًا/منقطع عن الدراسة...)، **الجنس** (ذكر/أنثى - قيمة صريحة
/// لكل صف بدل استنتاجها من عنوان كتلة "المقر" كما بمصدر v1)، العمر، الجنسية،
/// الدرجة العلمية، نوع الدراسة، تاريخ القبول، تاريخ متوقع تخرجه، تاريخ
/// التخرج، المعدل.
class AcademicDataDetailedHtmlParserService {
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

    final records = <AdvisingCaseRecord>[];

    for (final row in rows) {
      // صف طالب حقيقي: رقم جامعي (يبدأ بـ4، 8-9 خانات) بأي خلية - يُستدَلّ
      // عليه بدل فهرسة ثابتة (نفس أسلوب القارئ المكافئ لملف v1)، لأن أعمدة
      // فارغة (تاريخ التخرج غالبًا فارغ لغير المتخرجين) تُزيح المواضع.
      final idIndex = row.indexWhere((c) => _studentIdPattern.hasMatch(c.trim()));
      if (idIndex == -1) continue;

      final studentId = row[idIndex].trim();
      final studentName = idIndex + 1 < row.length ? row[idIndex + 1].trim() : '';
      final specialization = idIndex + 2 < row.length ? row[idIndex + 2].trim() : '';
      final status = idIndex + 3 < row.length ? row[idIndex + 3].trim() : '';
      final gender = idIndex + 4 < row.length ? row[idIndex + 4].trim() : '';
      if (studentName.isEmpty || gender.isEmpty) continue;

      // المعدل آخر خلية رقمية عشرية بالصف (موقعه متغيّر لاختلاف عدد الأعمدة
      // الفارغة بين الطلاب - تواريخ قبول/تخرج فارغة غالبًا).
      String? gpaText;
      for (var i = row.length - 1; i > idIndex; i--) {
        if (RegExp(r'^\d\.\d{1,2}$').hasMatch(row[i].trim())) {
          gpaText = row[i].trim();
          break;
        }
      }

      records.add(AdvisingCaseRecord(
        studentId: studentId,
        studentName: studentName,
        department: normalizeDepartmentName(specialization),
        shatr: gender.contains('أنثى') ? Shatr.female.label : Shatr.male.label,
        advisorNameRaw: '',
        gpa: gpaText != null ? double.tryParse(gpaText) : null,
        enrollmentStatus: status,
      ));
    }

    return records;
  }
}
