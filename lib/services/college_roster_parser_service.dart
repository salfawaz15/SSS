import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/college_roster_member.dart';

/// يقرأ ملف بيانات منسوبي الكلية المعتمد من عمادة الكلية (ورقات "منسوبو
/// الكلية"، "الإداريين"، و"المبتعثون") بالاعتماد على أسماء الأعمدة لا
/// فهرستها الثابتة، لأن العمادة قد تُعيد ترتيب الأعمدة عرضًا. يقرأ أسماء
/// الأعمدة الرسمية الحالية (نوع التكليف/مسمى المنصب/حالة الموظف) مع إبقاء
/// الأسماء القديمة (المنصب/توضيح المنصب) كمسار احتياطي لأي ملف بالقالب
/// السابق لم يُعَد رفعه بعد بالأسماء الجديدة.
class CollegeRosterParserService {
  static String _normalize(String s) => s.trim();

  static Map<String, int> _headerIndex(List<Data?> headerRow) {
    final map = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final h = headerRow[i]?.value?.toString();
      if (h != null && h.trim().isNotEmpty) map[_normalize(h)] = i;
    }
    return map;
  }

  static String _cell(List<Data?> row, Map<String, int> index, String header) {
    final i = index[header];
    if (i == null || i >= row.length) return '';
    return row[i]?.value?.toString().trim() ?? '';
  }

  /// أول قيمة غير فارغة من عدة أسماء أعمدة محتملة لنفس الحقل (الاسم الرسمي
  /// الحالي أولًا، ثم أسماء قديمة/بديلة) - بلا حاجة لمعرفة أي صيغة موجودة
  /// فعليًا في الملف المرفوع تحديدًا.
  static String _cellAny(List<Data?> row, Map<String, int> index, List<String> headers) {
    for (final h in headers) {
      final v = _cell(row, index, h);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// يوحّد صيغة اسم القسم إلى الصيغة الرسمية "قسم X" - بعض الأوراق (خاصة
  /// "المبتعثون") تكتب اسم القسم بلا كلمة "قسم" ("الاقتصاد والتمويل" بدل
  /// "قسم الاقتصاد و التمويل")، فيظهر القسم مرتين في قوائم الفلترة رغم أنه
  /// نفس القسم فعليًا. يُطبَّق فقط على الأقسام العلمية الخمسة المعروفة؛ أي
  /// جهة أخرى (عمادة الكلية، إدارات...) تبقى كما كُتبت بلا تغيير.
  static const Map<String, String> _canonicalDepartments = {
    'الادارة': 'قسم الادارة',
    'الإدارة': 'قسم الادارة',
    'المحاسبة': 'قسم المحاسبة',
    'التسويق': 'قسم التسويق',
    'الاقتصاد والتمويل': 'قسم الاقتصاد و التمويل',
    'الاقتصاد و التمويل': 'قسم الاقتصاد و التمويل',
    'نظم المعلومات الادارية': 'قسم نظم المعلومات الادارية',
    'نظم المعلومات الإدارية': 'قسم نظم المعلومات الادارية',
  };

  /// مفتاح مطابقة متسامح لاسم القسم: يطوي كل المسافات (تفادي فراغ مزدوج أو
  /// زائد بين الكلمات) ويوحّد صور الهمزة - حتى لا يظهر القسم نفسه "شبحيًا"
  /// كقسم مختلف تمامًا فقط لأن خلية واحدة كُتبت بمسافة إضافية أو همزة مختلفة
  /// عن بقية الصفوف (يكسر فلتر القسم والقائمة المنسدلة بصمت).
  static String _looseKey(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp('[أإآ]'), 'ا');

  static String _normalizeDepartment(String raw) {
    final trimmed = raw.trim();
    final loose = _looseKey(trimmed);
    for (final entry in _canonicalDepartments.entries) {
      if (_looseKey(entry.key) == loose) return entry.value;
    }
    return trimmed;
  }

  /// عضو "مطوي القيد" (توفي) يُستبعَد بالكامل من القائمة في كل الأوراق -
  /// ليس مجرد إعفاء من الإرشاد/النصاب، بل حذف تام فلا يظهر في أي مكان
  /// بالموقع. لا تُطبَّق هذه التصفية على "موقوف الراتب" (وضع صيفي مؤقت لأعضاء
  /// متعاقدين غير سعوديين خارج البلد - ما زالوا على رأس العمل فعليًا ولا
  /// يُستبعَدون من أي حساب).
  static bool _isDeceased(String employeeStatus) => employeeStatus.contains('مطوي');

  static List<CollegeRosterMember> parse(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final members = <CollegeRosterMember>[];

    final facultySheet = excel.tables['منسوبو الكلية'];
    if (facultySheet != null && facultySheet.maxRows > 1) {
      final index = _headerIndex(facultySheet.row(0));
      for (var r = 1; r < facultySheet.maxRows; r++) {
        final row = facultySheet.row(r);
        final name = _cell(row, index, 'الاسم الكامل');
        if (name.isEmpty) continue;
        final employeeStatus = _cell(row, index, 'حالة الموظف');
        if (_isDeceased(employeeStatus)) continue;
        members.add(CollegeRosterMember.fromRaw(
          type: CollegeMemberType.faculty,
          name: name,
          email: _cell(row, index, 'البريد الجامعي'),
          phone: _cell(row, index, 'رقم الجوال'),
          department: _normalizeDepartment(_cell(row, index, 'القسم / الجهة')),
          shatr: _cell(row, index, 'الشطر'),
          academicRank: _cell(row, index, 'الدرجة العلمية'),
          position: _cellAny(row, index, ['نوع التكليف', 'المنصب']),
          position2: _cellAny(row, index, ['منصب آخر (احتياطي - إن وجد)', 'منصب آخر (إن وجد)']),
          position3: _cell(row, index, 'منصب ثالث (احتياطي - إن وجد)'),
          // أعمدة توضيح المنصب اختيارية - تُقرَأ فارغة تلقائيًا من ملفات
          // بالقالب القديم بلا هذه الأعمدة (لا تكسر الرفع).
          positionDetail: _cellAny(row, index, ['مسمى المنصب', 'توضيح المنصب']),
          position2Detail: _cell(row, index, 'توضيح المنصب الآخر'),
          position3Detail: _cell(row, index, 'توضيح المنصب الثالث'),
          office: _cell(row, index, 'رقم المكتب'),
          notes: _cellAny(row, index, ['ملاحظة', 'ملاحظات', 'ملاحظات المكاتب']),
          employeeStatus: employeeStatus,
          quotaReductionNote: _cellAny(row, index, ['نصاب الإرشاد', 'ملاحظات تخفيض النصاب']),
          teachingLoadHours: int.tryParse(_cell(row, index, 'نصاب عضو هيئة التدريس')),
          staffNumber: _cellAny(row, index, ['رقم المنسوب', 'رقم الموظف']),
        ));
      }
    }

    final adminSheet = excel.tables['الإداريين'];
    if (adminSheet != null && adminSheet.maxRows > 1) {
      final index = _headerIndex(adminSheet.row(0));
      for (var r = 1; r < adminSheet.maxRows; r++) {
        final row = adminSheet.row(r);
        final name = _cell(row, index, 'الاسم الكامل');
        if (name.isEmpty) continue;
        final employeeStatus = _cell(row, index, 'حالة الموظف');
        if (_isDeceased(employeeStatus)) continue;
        members.add(CollegeRosterMember.fromRaw(
          type: CollegeMemberType.admin,
          name: name,
          email: _cell(row, index, 'البريد الجامعي'),
          phone: _cell(row, index, 'رقم الجوال'),
          department: _normalizeDepartment(_cell(row, index, 'الجهة / القسم التابع له')),
          // عمود "الشطر" أُضيف حديثًا لورقة الإداريين أيضًا (لم يكن موجودًا
          // سابقًا) - يُقرأ الآن بنفس طريقة ورقة "منسوبو الكلية" تمامًا،
          // فيخضع الإداريون لنفس فرز/فلترة الشطر حيثما استُخدمت.
          shatr: _cell(row, index, 'الشطر'),
          position: _cell(row, index, 'المسمى الوظيفي'),
          position2: _cell(row, index, 'مسمى آخر (إن وجد)'),
          position3: _cell(row, index, 'مسمى ثالث (احتياطي - إن وجد)'),
          office: _cell(row, index, 'رقم المكتب'),
          notes: _cell(row, index, 'ملاحظات'),
          employeeStatus: employeeStatus,
          staffNumber: _cell(row, index, 'رقم المنسوب'),
        ));
      }
    }

    // ورقة "المبتعثون" (جديدة) - تُدمَج ضمن قائمة أعضاء هيئة التدريس نفسها
    // (بدل بقائها منفصلة)، بمنصب "مبتعث" قسريًا (بصرف النظر عمّا يُكتب في
    // عمود "حالة الموظف" الأكثر تفصيلاً، الذي يُحفَظ أيضًا كما هو).
    final scholarshipSheet = excel.tables['المبتعثون'];
    if (scholarshipSheet != null && scholarshipSheet.maxRows > 1) {
      final index = _headerIndex(scholarshipSheet.row(0));
      for (var r = 1; r < scholarshipSheet.maxRows; r++) {
        final row = scholarshipSheet.row(r);
        final name = _cell(row, index, 'اسم الموظف');
        if (name.isEmpty) continue;
        final employeeStatus = _cell(row, index, 'حالة الموظف');
        if (_isDeceased(employeeStatus)) continue;
        members.add(CollegeRosterMember.fromRaw(
          type: CollegeMemberType.faculty,
          name: name,
          email: '',
          phone: '',
          department: _normalizeDepartment(_cell(row, index, 'القسم')),
          shatr: '',
          academicRank: _cell(row, index, 'الوظيفة'),
          // "مبتعث" حالة ابتعاث لا منصب وظيفي رسميًا، لكنها تُعرَض كنص بسيط
          // في عمود "المنصب" لتوضيح حالتهم دون تفاصيل إضافية (لا تخصّص عام) -
          // شارة "عبء الإرشاد" منفصلة تمامًا توضّح آليتهم الفعلية (غير
          // متواجد) بدل الخلط بينها وبين مفهوم "منصب".
          position: 'مبتعث',
          positionDetail: '',
          position2: '',
          position3: '',
          office: '',
          notes: '',
          employeeStatus: employeeStatus,
          staffNumber: _cell(row, index, 'رقم الموظف'),
        ));
      }
    }

    return members;
  }
}
