import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../data/course_catalog.dart';
import '../data/faculty_sort_order.dart';
import '../data/teaching_load_regulation.dart';
import '../services/teaching_quota_pdf_service.dart';
import '../models/college_roster_member.dart';
import '../models/course_section_record.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_repository.dart';
import '../services/course_table_pdf_service.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/instructor_schedule_pdf_service.dart';
import '../services/instructor_schedule_table.dart';
import '../services/outside_course_repository.dart';
import '../theme/app_theme.dart';
import '../utils/name_display.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

const String _kAllDepartments = 'كل الأقسام';
const String _kAllShatr = 'كل الشطرين';
const String _kUnscheduledOption = 'الشعب غير المسكَّنة';
const String _kAllSectionsOption = 'الكل';
const String _kAllDeptsFacultyOption = 'جميع الشعب لجميع الأقسام';
const String _kQuotaReportOption = 'تقرير النصاب التدريسي';
const String _kQuotaAll = 'الكل';
const String _kQuotaUnder = 'دون النصاب';
const String _kQuotaOver = 'فوق النصاب';

/// نتيجة مقارنة الساعات الفعلية لعضو بالحد النظامي لدرجته العلمية.
/// overWithinRounding: تجاوز شكلي فقط بسبب أن أغلب المقررات 3 ساعات ولا
/// يمكن الوصول للنصاب بالضبط (مثال: نصاب الأستاذ 10، أقرب رقم قابل للتحقيق
/// فوقه بمقررات 3 ساعات هو 12) - هذا لا يُعتبر تجاوزًا حقيقيًا يستدعي معالجة.
enum _QuotaStatus { ok, under, over, overWithinRounding, unknown }

class _QuotaRow {
  final String name;
  final String department;
  final String rank;
  final String staffNumber;
  final int actualHours;
  final int? maxHours;
  final _QuotaStatus status;
  final String? note;

  const _QuotaRow({
    required this.name,
    required this.department,
    required this.rank,
    required this.staffNumber,
    required this.actualHours,
    required this.maxHours,
    required this.status,
    required this.note,
  });
}

String _hoursLabel(int n) {
  if (n == 1) return 'ساعة معتمدة واحدة';
  if (n == 2) return 'ساعتان معتمدتان';
  return '$n ساعات معتمدة';
}

/// أقرب رقم قابل للتحقيق فعليًا عند/فوق الحد النظامي، باعتبار أن أغلب
/// المقررات 3 ساعات معتمدة - مثال: نصاب الأستاذ 10 غير قابل للوصول إليه
/// بالضبط بمقررات 3 ساعات (9 أو 12)، فأقرب رقم يكمل النصاب هو 12.
int _practicalMax(int maxHours) => ((maxHours + 2) ~/ 3) * 3;

/// يبني ملاحظة احترافية بناءً على مقارنة الساعات الفعلية بالحد النظامي -
/// null يعني لا فرق (النصاب مطابق تمامًا) فلا تظهر أي ملاحظة.
///
/// [fullRankMaxHours] هو نصاب الدرجة العلمية الكامل بدون أي تخفيض - يُستخدم
/// حصرًا لحساب "الساعات الزائدة" الحقيقية (التي تُصرف ماليًا)، لأن تخفيض
/// النصاب لمنصب إداري يعفي العضو من جزء من العبء لكنه لا يخفّض السقف الذي
/// تُحسب الزيادة المدفوعة بعده. عضو نصابه المخفّض 7 (50% من 14) وله 9 ساعات
/// فعلية "مكتمل النصاب" فقط، وليس له أي ساعات زائدة لأن 9 لم تتجاوز الـ14.
/// إن كان null (درجة غير معروفة) يُستخدم [maxHours] نفسه كبديل.
({_QuotaStatus status, String? note}) _quotaCompare(int actualHours, int? maxHours, {int? fullRankMaxHours}) {
  if (maxHours == null) return (status: _QuotaStatus.unknown, note: null);
  if (actualHours == maxHours) return (status: _QuotaStatus.ok, note: null);
  if (actualHours < maxHours) {
    final remaining = maxHours - actualHours;
    return (
      status: _QuotaStatus.under,
      note: 'النصاب التدريسي غير مكتمل - يتبقى ${_hoursLabel(remaining)} لاستكمال النصاب.',
    );
  }

  final overtimeBase = fullRankMaxHours ?? maxHours;
  if (actualHours <= overtimeBase) {
    return (status: _QuotaStatus.ok, note: null);
  }

  final extra = actualHours - overtimeBase;
  final note = 'ساعات زائدة عن النصاب التدريسي بمقدار ${_hoursLabel(extra)}.';
  final status = actualHours <= _practicalMax(overtimeBase) ? _QuotaStatus.overWithinRounding : _QuotaStatus.over;
  return (status: status, note: note);
}

class _DisplayRow {
  final CourseSectionRecord record;
  final Shatr shatr;
  final String department;
  final List<String> plans;
  final String? catalogNote;

  _DisplayRow({
    required this.record,
    required this.shatr,
    required this.department,
    required this.plans,
    required this.catalogNote,
  });
}

class CourseScheduleAdminScreen extends StatefulWidget {
  final int initialTabIndex;

  /// إن كانت true، تُفتح الصفحة على تبويب [initialTabIndex] فقط بلا شريط
  /// تبويبات إطلاقًا - يستخدمها كل زر اختصار في لوحة الإدارة يفتح وظيفة
  /// واحدة بعينها (مثل "تسكين المقررات وشعبها") حتى لا يظهر للمستخدم أي
  /// محتوى غير الذي وعده الزر باسمه بالضبط.
  final bool singleTab;

  const CourseScheduleAdminScreen({super.key, this.initialTabIndex = 0, this.singleTab = false});

  @override
  State<CourseScheduleAdminScreen> createState() => _CourseScheduleAdminScreenState();
}

class _CourseScheduleAdminScreenState extends State<CourseScheduleAdminScreen>
    with SingleTickerProviderStateMixin {
  List<CourseSectionRecord> _maleRecords = [];
  List<CourseSectionRecord> _femaleRecords = [];
  DateTime? _maleExportDate;
  DateTime? _femaleExportDate;
  bool _loading = true;
  bool _uploadingMale = false;
  bool _uploadingFemale = false;

  List<String> _maleOutsideCourses = [];
  List<String> _femaleOutsideCourses = [];
  bool _uploadingMaleOutside = false;
  bool _uploadingFemaleOutside = false;

  String _shatrFilter = _kAllShatr;
  String _deptFilter = _kAllDepartments;
  final _searchCtrl = TextEditingController();
  bool _showOutsideCourses = false;

  late final TabController _tabController;

  // فلاتر شاشة عضو هيئة التدريس
  String? _facultyDept;
  Shatr? _facultyShatr;
  String? _facultyInstructor;
  // اختيار من قائمة "طريقة العرض" (كل الشعب/غير المسكَّنة/تقرير النصاب) -
  // منفصلة عن اختيار عضو بعينه، تُجمَّد إحداهما عند اختيار الأخرى.
  String? _facultyViewMode;

  // افتراضيًا تُخفى من قائمة "عضو هيئة التدريس" الأعضاء غير المتواجدين
  // فعليًا (معار/مجاز/مبتعث) - بنفس مبدأ خانة "إظهار الكل" في شاشة بيانات
  // منسوبي الكلية.
  bool _showAllFaculty = false;

  // ملف أعضاء هيئة التدريس المعتمد (رقم المكتب والقسم العلمي الحقيقي لكل
  // عضو) - مفهرَس بالاسم بعد تجريده من اللقب لمطابقته مع اسم المحاضر كما
  // يظهر في ملف الحويّة (أيضًا بلا لقب).
  Map<String, CollegeRosterMember> _rosterByName = {};

  // فلتر تقرير النصاب التدريسي (الكل / دون النصاب / فوق النصاب)
  String _quotaFilter = _kQuotaAll;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    // عنوان الصفحة يتبع التبويب المفتوح فعليًا بدل عنوان عام واحد لا يتغيّر
    // - كان يوهم المستخدم أنه دخل الصفحة الخطأ عند فتح تبويب "الجدول الدراسي".
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadAll();
  }

  static const _tabTitles = ['تسكين المقررات الدراسية', 'الجدول الدراسي'];

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        CourseScheduleRepository.loadSchedule(Shatr.male),
        CourseScheduleRepository.loadSchedule(Shatr.female),
        CourseScheduleRepository.currentExportDate(Shatr.male),
        CourseScheduleRepository.currentExportDate(Shatr.female),
        CollegeRosterRepository.load(),
        OutsideCourseRepository.load(Shatr.male),
        OutsideCourseRepository.load(Shatr.female),
        OutsideCourseRepository.currentUploadDate(Shatr.male),
        OutsideCourseRepository.currentUploadDate(Shatr.female),
      ]);
      if (!mounted) return;
      setState(() {
        _maleRecords = results[0] as List<CourseSectionRecord>;
        _femaleRecords = results[1] as List<CourseSectionRecord>;
        _maleExportDate = results[2] as DateTime?;
        _femaleExportDate = results[3] as DateTime?;
        _rosterByName = {
          for (final m in results[4] as List<CollegeRosterMember>) _normalizeNameKey(displayName(m.name)): m,
        };
        _maleOutsideCourses = results[5] as List<String>;
        _femaleOutsideCourses = results[6] as List<String>;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحميل بيانات الصفحة: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _outsideCoursesFor(Shatr shatr) =>
      shatr == Shatr.male ? _maleOutsideCourses : _femaleOutsideCourses;

  /// رفع موحَّد لملف "الحويّة" الشامل لشطر واحد - يستخرج منه دفعة واحدة
  /// كلا العنصرين معًا بدل رفعتين منفصلتين كسابقًا: (أ) جدول شعب كليتنا
  /// الخاصة (شعب "المستفيد" منها كلية إدارة الأعمال وكودها ليس ضمن قائمة
  /// "مواد خارج الكلية")، و(ب) قائمة "مواد خارج الكلية" المعتمَدة لهذا
  /// الفصل (شرطها: كودها بقائمة الخطة + شعبة فعلية مستفيدها كليتنا - انظر
  /// [[project_faculty_columns_meaning]] وتعليق CourseCatalog.outsideCollegeCourses).
  Future<void> _uploadCombinedFor(Shatr shatr) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;

    setState(() {
      if (shatr == Shatr.male) {
        _uploadingMale = true;
        _uploadingMaleOutside = true;
      } else {
        _uploadingFemale = true;
        _uploadingFemaleOutside = true;
      }
    });

    try {
      final sections = DocxScheduleParserService.parseSections(bytes);
      if (sections.isEmpty) {
        throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف "الحويّة" الشامل الصحيح بصيغة Word (.docx).');
      }

      final ourSections = sections.where((s) => s.beneficiary.contains('كلية إدارة الأعمال')).toList();
      final outsideCodes = CourseCatalog.outsideCollegeCourses.map(CourseCatalog.outsideCourseCode).toSet();

      final ownRecords = ourSections.where((s) => !outsideCodes.contains(s.record.courseCode)).map((s) => s.record).toList();
      final offeredOutsideCodes = ourSections.where((s) => outsideCodes.contains(s.record.courseCode)).map((s) => s.record.courseCode).toSet();
      final outsideOptions = CourseCatalog.filterOutsideCoursesByOfferedCodes(offeredOutsideCodes);

      if (ownRecords.isEmpty) {
        throw Exception(
          'لم يُعثر على أي شعبة "المستفيد" منها كلية إدارة الأعمال ضمن ${sections.length} سطر بالملف. '
          'تأكد أن الملف يحوي عمود "المستفيد" فعليًا وأن نص الكلية مطابق.',
        );
      }

      final exportDate = DocxScheduleParserService.extractExportDate(bytes);
      final currentExportDate = await CourseScheduleRepository.currentExportDate(shatr);
      if (exportDate != null && currentExportDate != null && !exportDate.isAfter(currentExportDate)) {
        final fmt = DateFormat('yyyy/MM/dd');
        throw Exception(
          'تاريخ سحب بيانات هذا الملف (${fmt.format(exportDate)}) ليس أحدث من تاريخ آخر نسخة معتمدة '
          '(${fmt.format(currentExportDate)}). تأكد من رفع أحدث ملف من المنظومة الداخلية.',
        );
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الاعتماد'),
          content: Text(
            'من إجمالي ${sections.length} سطر بالملف لـ ${shatr.label}'
            '${exportDate != null ? ' (تاريخ السحب: ${DateFormat('yyyy/MM/dd').format(exportDate)})' : ''}:\n\n'
            '• ${ownRecords.length} شعبة لجدول كليتنا الخاص.\n'
            '• ${outsideOptions.length} مادة من قائمة "خارج الكلية" (من أصل ${CourseCatalog.outsideCollegeCourses.length}).\n\n'
            'سيستبدل هذا آخر نسخة معتمدة لكليهما لهذا الشطر بالكامل. هل تريد الاعتماد؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      await CourseScheduleRepository.saveSchedule(shatr, ownRecords, exportDate: exportDate);
      await OutsideCourseRepository.save(shatr, outsideOptions);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد جدول ${shatr.label} (${ownRecords.length} شعبة) ومواد خارج الكلية (${outsideOptions.length} مادة) بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر قراءة الملف: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingMale = false;
          _uploadingFemale = false;
          _uploadingMaleOutside = false;
          _uploadingFemaleOutside = false;
        });
      }
    }
  }

  List<_DisplayRow> _buildDisplayRows({required bool forFaculty}) {
    final rows = <_DisplayRow>[];
    void addAll(List<CourseSectionRecord> records, Shatr shatr) {
      for (final r in records) {
        final entry = CourseCatalog.lookup(r.courseCode);
        rows.add(_DisplayRow(
          record: r,
          shatr: shatr,
          department: entry?.department ?? 'غير مصنَّف',
          plans: entry?.plans ?? const [],
          catalogNote: entry?.note,
        ));
      }
    }

    addAll(_maleRecords, Shatr.male);
    addAll(_femaleRecords, Shatr.female);
    return rows;
  }

  /// [includeShared] يتحكم بظهور المقررات المشتركة/الإضافية بين الأقسام:
  /// يجب أن تكون false لعرض الجدول والتقرير المطبوع (يظهر فيهما فقط مقررات
  /// القسم المالك نفسه)، وtrue فقط عند بناء قائمة نسخ فورمز (حيث يحتاج
  /// الطالب رؤية كل ما يُتاح تسجيله فعليًا ضمن قسمه، بما فيه مقررات مشتركة).
  List<_DisplayRow> _filteredRows({required bool includeShared}) {
    final all = _buildDisplayRows(forFaculty: false);
    final search = _searchCtrl.text.trim();
    return all.where((row) {
      if (_shatrFilter != _kAllShatr) {
        final wanted = _shatrFilter == Shatr.male.label ? Shatr.male : Shatr.female;
        if (row.shatr != wanted) return false;
      }
      if (_deptFilter != _kAllDepartments) {
        final isOwn = row.department == _deptFilter;
        final isShared = includeShared && CourseCatalog.isSharedAcrossDepartments(row.record.courseCode);
        final isExtra = includeShared && CourseCatalog.isVisibleInDepartment(row.record.courseCode, _deptFilter);
        if (!isOwn && !isShared && !isExtra) return false;
      } else {
        // في وضع "كل الأقسام": نعرض المقرر المشترك مرة واحدة فقط تحت قسمه المالك.
        // (يحدث ذلك تلقائيًا لأن department هو دائمًا القسم المالك من الفهرس)
      }
      if (search.isNotEmpty) {
        final hay = '${row.record.courseCode} ${row.record.courseName}';
        if (!hay.contains(search)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = CourseCatalog.departments.indexOf(a.department);
        final db = CourseCatalog.departments.indexOf(b.department);
        final d = (da == -1 ? 999 : da).compareTo(db == -1 ? 999 : db);
        if (d != 0) return d;
        final c = a.record.courseCode.compareTo(b.record.courseCode);
        if (c != 0) return c;
        final sa = a.shatr == Shatr.male ? 0 : 1;
        final sb = b.shatr == Shatr.male ? 0 : 1;
        return sa.compareTo(sb);
      });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.singleTab) {
      return PortalScaffold(
        title: _tabTitles[widget.initialTabIndex],
        navItems: buildAdminNavItems(context, current: 'academic-services'),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (widget.initialTabIndex == 0 ? _buildTableTab() : _buildFacultyTab()),
      );
    }
    return PortalScaffold(
      title: _tabTitles[_tabController.index],
      navItems: buildAdminNavItems(context, current: 'academic-services'),
      bottom: _GreenTabBar(
        TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          tabs: const [
            Tab(text: 'تسكين المقررات', icon: Icon(Icons.table_chart_outlined)),
            Tab(text: 'الجدول الدراسي لأعضاء هيئة التدريس', icon: Icon(Icons.person_search_outlined)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildTableTab(), _buildFacultyTab()],
            ),
    );
  }

  /// عنوان ديناميكي يعكس فلتر القسم/الشطر الحالي، يُستخدم أعلى الجدول وفي
  /// التقرير المطبوع بدل عمود "القسم" الثابت في كل صف.
  String _reportTitle() {
    final shatrPart = _shatrFilter == _kAllShatr ? 'كل الشطرين' : _shatrFilter;
    if (_deptFilter != _kAllDepartments) {
      return 'دليل مقررات $_deptFilter - $shatrPart';
    }
    return 'دليل المقررات لكلية إدارة الأعمال - $shatrPart';
  }

  Widget _buildTableTab() {
    final rows = _filteredRows(includeShared: false);
    return Column(
      children: [
        _buildToolbar(),
        _buildOutsideCoursesPanel(),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة'))
              // شريط التمرير الرأسي هو الأعلى مباشرة (يلتصق بحافة الصفحة)،
              // وما بداخله (الحشو والحدود الذهبية) لا يؤثر على موضعه.
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(_reportTitle(), style: AppTextStyles.h3(color: AppColors.greenDark)),
                        ),
                        Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AppColors.green),
                          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          columns: [
                            DataColumn(label: _centerHeader('اسم المقرر')),
                            DataColumn(label: _centerHeader('الشعبة')),
                            DataColumn(label: _centerHeader('المقرر')),
                            DataColumn(label: _centerHeader('عدد الساعات')),
                            DataColumn(label: _centerHeader('النشاط')),
                            DataColumn(label: _centerHeader('اعلى حد')),
                            DataColumn(label: _centerHeader('المسجلين')),
                            DataColumn(label: _centerHeader('اليوم')),
                            DataColumn(label: _centerHeader('الوقت')),
                            DataColumn(label: _centerHeader('المحاضر')),
                            if (_shatrFilter == _kAllShatr) DataColumn(label: _centerHeader('الشطر')),
                          ],
                          rows: [
                            for (var i = 0; i < rows.length; i++)
                              DataRow(
                                color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                                cells: [
                                  DataCell(Center(child: Text(rows[i].record.courseName, textAlign: TextAlign.center))),
                                  DataCell(_sectionCell(rows[i].record)),
                                  DataCell(Center(child: Text(rows[i].record.courseCode, textAlign: TextAlign.center))),
                                  DataCell(_hoursCell(rows[i].record)),
                                  DataCell(_activityCell(rows[i].record)),
                                  DataCell(_maxCapacityCell(rows[i].record)),
                                  DataCell(_registeredCell(rows[i].record)),
                                  DataCell(_dayCell(rows[i].record)),
                                  DataCell(_timeCell(rows[i].record)),
                                  DataCell(_instructorCell(rows[i].record)),
                                  if (_shatrFilter == _kAllShatr) DataCell(Center(child: _shatrChip(rows[i].shatr))),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// شريط علوي واحد أنيق ومضغوط يجمع رفع الملفات وأدوات الفلترة/التصدير،
  /// بدل شريطين منفصلين كانا يتزاحمان بصريًا. مواد خارج الكلية تظهر في لوحة
  /// قابلة للطي أسفله (مطوية افتراضيًا) حتى لا تأكل مساحة عرض الجدول.
  Widget _buildToolbar() {
    final fmt = DateFormat('yyyy/MM/dd');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _uploadTile(
                label: 'رفع ملف الحويّة الشامل - طلاب',
                uploading: _uploadingMale || _uploadingMaleOutside,
                date: _maleExportDate,
                fmt: fmt,
                onPressed: () => _uploadCombinedFor(Shatr.male),
                onClear: () async {
                  if (!await _confirmClear('جدول الطلاب ومواد خارج الكلية - طلاب')) return;
                  await CourseScheduleRepository.clear(Shatr.male);
                  await OutsideCourseRepository.clear(Shatr.male);
                  await _loadAll();
                },
              ),
              _uploadTile(
                label: 'رفع ملف الحويّة الشامل - طالبات',
                uploading: _uploadingFemale || _uploadingFemaleOutside,
                date: _femaleExportDate,
                fmt: fmt,
                onPressed: () => _uploadCombinedFor(Shatr.female),
                onClear: () async {
                  if (!await _confirmClear('جدول الطالبات ومواد خارج الكلية - طالبات')) return;
                  await CourseScheduleRepository.clear(Shatr.female);
                  await OutsideCourseRepository.clear(Shatr.female);
                  await _loadAll();
                },
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: DropdownMenu<String>(
                  label: const Text('الشطر'),
                  initialSelection: _shatrFilter,
                  dropdownMenuEntries: [
                    const DropdownMenuEntry(value: _kAllShatr, label: _kAllShatr),
                    DropdownMenuEntry(value: Shatr.male.label, label: Shatr.male.label),
                    DropdownMenuEntry(value: Shatr.female.label, label: Shatr.female.label),
                  ],
                  onSelected: (v) => setState(() => _shatrFilter = v ?? _kAllShatr),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownMenu<String>(
                  label: const Text('القسم'),
                  initialSelection: _deptFilter,
                  dropdownMenuEntries: [
                    const DropdownMenuEntry(value: _kAllDepartments, label: _kAllDepartments),
                    ...CourseCatalog.departments.map((d) => DropdownMenuEntry(value: d, label: d)),
                  ],
                  onSelected: (v) => setState(() => _deptFilter = v ?? _kAllDepartments),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'بحث باسم أو رمز المقرر',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilterChip(
                selected: _showOutsideCourses,
                onSelected: (v) => setState(() => _showOutsideCourses = v),
                avatar: Icon(Icons.school_outlined, size: 18, color: _showOutsideCourses ? Colors.white : AppColors.green),
                label: const Text('مواد خارج الكلية'),
                labelStyle: TextStyle(color: _showOutsideCourses ? Colors.white : AppColors.green),
                selectedColor: AppColors.green,
                backgroundColor: AppColors.background,
                side: BorderSide(color: AppColors.green.withValues(alpha: 0.4)),
              ),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'عرض PDF',
                    onPressed: () async => Printing.sharePdf(bytes: await _buildCourseTablePdf(), filename: 'دليل_مقررات_الحذف_والإضافة.pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    color: AppColors.green,
                  ),
                  IconButton(
                    tooltip: 'طباعة',
                    onPressed: () async => Printing.layoutPdf(onLayout: (_) async => _buildCourseTablePdf()),
                    icon: const Icon(Icons.print_outlined),
                    color: AppColors.green,
                  ),
                  IconButton(
                    tooltip: 'نسخ مقررات القسم المحدَّد لفورمز (مع مواد خارج الكلية تلقائيًا)',
                    onPressed: _showFormsExportDialog,
                    icon: const Icon(Icons.ios_share_outlined),
                    color: AppColors.green,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _uploadTile({
    required String label,
    required bool uploading,
    required DateTime? date,
    required DateFormat fmt,
    required VoidCallback onPressed,
    Color? color,
    VoidCallback? onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: uploading ? null : onPressed,
                icon: uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file, size: 18),
                label: Text(label),
                style: FilledButton.styleFrom(backgroundColor: color ?? AppColors.green),
              ),
              if (onClear != null && date != null)
                IconButton(
                  tooltip: 'تفريغ البيانات (للاختبار)',
                  onPressed: onClear,
                  icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            date != null ? 'آخر رفع: ${fmt.format(date)}' : 'لم يُرفع بعد',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmClear(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفريغ $label'),
        content: const Text('سيُحذَف كل ما هو مخزَّن حاليًا لهذا العنصر (لتسهيل إعادة اختبار الرفع). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('تفريغ'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// لوحة قابلة للطي (مطوية افتراضيًا) لمواد خارج الكلية - مبنية من آخر رفعة
  /// معتمدة لكل شطر (تقاطع القائمة الثابتة مع ملف حويّة الجامعة الشامل)،
  /// فلا تُعرض كصفوف داخل جدول التسكين الرئيسي.
  Widget _buildOutsideCoursesPanel() {
    if (!_showOutsideCourses) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Text('مواد خارج الكلية', style: AppTextStyles.h3(color: AppColors.greenDark)),
              const Spacer(),
              IconButton(
                tooltip: 'طي',
                onPressed: () => setState(() => _showOutsideCourses = false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _outsideCoursesShatrSection(Shatr.male),
          const SizedBox(height: 12),
          _outsideCoursesShatrSection(Shatr.female),
        ],
      ),
    );
  }

  Widget _outsideCoursesShatrSection(Shatr shatr) {
    final options = _outsideCoursesFor(shatr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${shatr.label} (${options.length})', style: AppTextStyles.body(color: AppColors.greenDark).copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: options.isEmpty ? null : () => _showOutsideCollegeExportDialog(shatr),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('نسخ لفورمز'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (options.isEmpty)
          Text('لم تُرفع بعد قائمة مواد خارج الكلية لهذا الشطر.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                Chip(
                  label: Text(option, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
            ],
          ),
      ],
    );
  }

  /// خيارات سؤال "مقرر خارج الكلية" لشطر معيّن، مبنية من آخر رفعة معتمدة له.
  void _showOutsideCollegeExportDialog(Shatr shatr) {
    final options = _outsideCoursesFor(shatr);
    final text = options.join('\n');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('خيارات سؤال "مقرر خارج الكلية" (${shatr.label})'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${options.length} مقرر - مبنية من آخر ملف حويّة شامل مرفوع لهذا الشطر.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(child: SelectableText(text)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم نسخ ${options.length} مقرر - الصقها الآن في فورمز.')),
              );
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('نسخ الكل'),
          ),
        ],
      ),
    );
  }

  /// قائمة أسماء المقررات الفريدة (بلا تكرار الشعب) للقسم والشطر
  /// المُختارين حاليًا في الفلتر، بصيغة "رمز - اسم" - جاهزة للصق دفعة
  /// واحدة في خيارات سؤال "المقرر الدراسي" بمايكروسوفت فورمز، ومحدَّثة
  /// تلقائيًا من آخر جدول مُعتمَد بدل الاعتماد على ملف خارجي ثابت.
  ///
  /// تُضاف دائمًا مواد خارج الكلية لنفس الشطر في نهاية القائمة - بطلب
  /// سليمان صراحةً أن يظهر خيار "مقرر خارج الكلية" ضمن قائمة كل قسم على
  /// حدة بفورمز، لا كتصدير منفصل، فتتكرر نفس مواد خارج الكلية بكل قسم.
  List<String> _formsExportOptions() {
    final seen = <String>{};
    final options = <String>[];
    for (final row in _filteredRows(includeShared: true)) {
      final option = '${row.record.courseCode} - ${row.record.courseName}';
      if (seen.add(option)) options.add(option);
    }
    if (_shatrFilter != _kAllShatr) {
      final shatr = _shatrFilter == Shatr.male.label ? Shatr.male : Shatr.female;
      for (final option in _outsideCoursesFor(shatr)) {
        if (seen.add(option)) options.add(option);
      }
    }
    return options;
  }

  void _showFormsExportDialog() {
    if (_shatrFilter == _kAllShatr || _deptFilter == _kAllDepartments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر شطرًا وقسمًا محدَّدين أولًا (وليس "الكل") لتصدير قائمة مقرراته.')),
      );
      return;
    }
    final options = _formsExportOptions();
    final text = options.join('\n');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('خيارات سؤال "المقرر الدراسي - $_deptFilter" ($_shatrFilter)'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${options.length} مقرر (تشمل مواد خارج الكلية لنفس الشطر تلقائيًا) - انسخ القائمة كاملة والصقها دفعة واحدة في خيارات السؤال بفورمز.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: SelectableText(text.isEmpty ? 'لا توجد مقررات مطابقة لهذا الفلتر.' : text),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          FilledButton.icon(
            onPressed: text.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم نسخ ${options.length} مقرر - الصقها الآن في فورمز.')),
                    );
                  },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('نسخ الكل'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildCourseTablePdf() async {
    final rows = _filteredRows(includeShared: false);
    final showShatr = _shatrFilter == _kAllShatr;
    String dayText(List<CourseMeeting> meetings) =>
        meetings.isEmpty ? InstructorScheduleTable.noTimePlaceholder : meetings.map((m) => m.dayName).join('\n');
    String timeText(List<CourseMeeting> meetings) =>
        meetings.isEmpty ? InstructorScheduleTable.noTimePlaceholder : meetings.map((m) => '${m.from} - ${m.to}').join('\n');

    final pdfRows = rows.map((row) {
      final r = row.record;
      return CourseTablePdfRow(
        department: row.department,
        courseCode: r.courseCode,
        courseName: r.courseName,
        shatrLabel: showShatr ? row.shatr.label : null,
        theorySection: r.theorySection,
        practicalSection: r.practicalSection,
        theoryHours: r.theoryHours,
        practicalHours: r.practicalHours,
        theoryMaxCapacity: r.theoryMaxCapacity,
        practicalMaxCapacity: r.practicalMaxCapacity,
        theoryRegistered: r.theoryRegistered,
        practicalRegistered: r.practicalRegistered,
        dayText: dayText(r.meetings),
        practicalDayText: r.practicalSection == null ? null : dayText(r.practicalMeetings),
        timeText: timeText(r.meetings),
        practicalTimeText: r.practicalSection == null ? null : timeText(r.practicalMeetings),
        instructorName: r.instructorName ?? 'لم تُسكَّن بعد',
        practicalInstructorName:
            (r.practicalSection != null && r.practicalInstructorName != null && r.practicalInstructorName != r.instructorName)
                ? r.practicalInstructorName
                : null,
      );
    }).toList();

    return CourseTablePdfService.build(rows: pdfRows, showShatrColumn: showShatr, title: _reportTitle());
  }

  Widget _shatrChip(Shatr shatr) {
    final isMale = shatr == Shatr.male;
    return Chip(
      label: Text(shatr.label, style: const TextStyle(fontSize: 12)),
      backgroundColor: isMale ? Colors.blue.shade50 : Colors.pink.shade50,
      side: BorderSide(color: isMale ? Colors.blue.shade200 : Colors.pink.shade200),
      visualDensity: VisualDensity.compact,
    );
  }

  /// عنوان عمود موسَّط داخل خلية الرأس (بدل المحاذاة الافتراضية).
  Widget _centerHeader(String label) => Center(child: Text(label, textAlign: TextAlign.center));

  /// عند وجود شعبة عملية مرتبطة، تُقسَّم الخلية إلى صفّين: الأعلى للنظري
  /// والأسفل للعملي (بدل دمجهما في سطر واحد) حسب طلب المستخدم صراحةً، مع
  /// توسيط كل المحتوى أفقيًا وعموديًا داخل الخلية.
  Widget _splitCell(Widget theoryRow, Widget practicalRow) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          theoryRow,
          const Padding(padding: EdgeInsets.symmetric(vertical: 3), child: Divider(height: 1)),
          practicalRow,
        ],
      ),
    );
  }

  Widget _sectionCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: Text(r.theorySection, textAlign: TextAlign.center));
    return _splitCell(Text(r.theorySection, textAlign: TextAlign.center), Text(r.practicalSection!, textAlign: TextAlign.center));
  }

  Widget _meetingsListText(List<CourseMeeting> meetings) {
    if (meetings.isEmpty) return const Center(child: Text(InstructorScheduleTable.noTimePlaceholder));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: meetings
          .map((m) => Text('${m.dayName}  ${m.from} - ${m.to}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))
          .toList(),
    );
  }

  Widget _meetingsCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: _meetingsListText(r.meetings));
    return _splitCell(_meetingsListText(r.meetings), _meetingsListText(r.practicalMeetings));
  }

  Widget _daysListText(List<CourseMeeting> meetings) {
    if (meetings.isEmpty) return const Center(child: Text(InstructorScheduleTable.noTimePlaceholder));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: meetings.map((m) => Text(m.dayName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))).toList(),
    );
  }

  Widget _timesListText(List<CourseMeeting> meetings) {
    if (meetings.isEmpty) return const Center(child: Text(InstructorScheduleTable.noTimePlaceholder));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children:
          meetings.map((m) => Text('${m.from} - ${m.to}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))).toList(),
    );
  }

  Widget _dayCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: _daysListText(r.meetings));
    return _splitCell(_daysListText(r.meetings), _daysListText(r.practicalMeetings));
  }

  Widget _timeCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: _timesListText(r.meetings));
    return _splitCell(_timesListText(r.meetings), _timesListText(r.practicalMeetings));
  }

  Widget _hoursCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: Text('${r.theoryHours}'));
    return _splitCell(Text('${r.theoryHours}'), Text('${r.practicalHours}'));
  }

  Widget _activityCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return const Center(child: Text('نظري'));
    return _splitCell(const Text('نظري'), const Text('عملي'));
  }

  Widget _maxCapacityCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: Text('${r.theoryMaxCapacity}'));
    return _splitCell(Text('${r.theoryMaxCapacity}'), Text('${r.practicalMaxCapacity ?? 0}'));
  }

  Widget _registeredCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Center(child: Text('${r.theoryRegistered}'));
    return _splitCell(Text('${r.theoryRegistered}'), Text('${r.practicalRegistered ?? 0}'));
  }

  Widget _instructorCell(CourseSectionRecord r) {
    const unassigned = 'لم تُسكَّن بعد';
    if (r.practicalSection == null || r.practicalInstructorName == null || r.practicalInstructorName == r.instructorName) {
      return Center(child: Text(r.instructorName ?? unassigned, textAlign: TextAlign.center));
    }
    return _splitCell(
      Text(r.instructorName ?? unassigned, textAlign: TextAlign.center),
      Text(r.practicalInstructorName!, textAlign: TextAlign.center),
    );
  }

  // ------------------------- شاشة عضو هيئة التدريس -------------------------

  Widget _buildFacultyTab() {
    final allRows = _buildDisplayRows(forFaculty: true);

    final deptOptions = [_kAllDeptsFacultyOption, ...CourseCatalog.departments];
    final shatrOptions = [Shatr.male, Shatr.female];
    final isAllDepts = _facultyDept == _kAllDeptsFacultyOption;

    final rowsForDeptShatr = allRows.where((r) {
      if (!isAllDepts && _facultyDept != null && r.department != _facultyDept) return false;
      if (_facultyShatr != null && r.shatr != _facultyShatr) return false;
      return true;
    }).toList();

    // نفس معيار الترتيب المعتمد في كل الموقع (FacultySortOrder) - من نصابه
    // "الحد الأدنى"/له منصب قيادي يتصدَّر القائمة المنسدلة، بدل الترتيب
    // الأبجدي البسيط.
    final instructorNames = _instructorNamesFor(rowsForDeptShatr, isAllDepts)
      ..sort((a, b) {
        final ma = _rosterFor(a);
        final mb = _rosterFor(b);
        if (ma == null || mb == null) return a.compareTo(b);
        return FacultySortOrder.compareMembers(ma, mb, compareDepartment: isAllDepts);
      });

    // خيارات "طريقة العرض" الجماعية - منفصلة عن اختيار عضو بعينه.
    const viewModeOptions = [_kAllSectionsOption, _kUnscheduledOption, _kQuotaReportOption];

    // "غير مسكَّنة" تعني تحديدًا: لا يوجد اسم عضو هيئة تدريس مُعيَّن لهذه
    // الشعبة (نظري بلا محاضر، أو عملي موجود بلا محاضر خاص به) - وليس عن
    // غياب اليوم/الوقت.
    bool isUnscheduled(_DisplayRow r) =>
        r.record.instructorName == null ||
        (r.record.practicalSection != null && r.record.practicalInstructorName == null);

    // اختيار موحَّد: إما طريقة عرض جماعية أو عضو بعينه، بينهما تنافٍ تام.
    final selection = _facultyViewMode ?? _facultyInstructor;

    final selectedRows = switch (selection) {
      null => const <_DisplayRow>[],
      _kAllSectionsOption => rowsForDeptShatr,
      _kUnscheduledOption => rowsForDeptShatr.where(isUnscheduled).toList(),
      _kQuotaReportOption => rowsForDeptShatr,
      final name => rowsForDeptShatr.where((r) => r.record.instructorName == name).toList(),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              DropdownMenu<Shatr>(
                label: const Text('الشطر'),
                initialSelection: _facultyShatr,
                dropdownMenuEntries: shatrOptions
                    .map((s) => DropdownMenuEntry(value: s, label: s.label))
                    .toList(),
                onSelected: (v) => setState(() {
                  _facultyShatr = v;
                  _facultyInstructor = null;
                  _facultyViewMode = null;
                }),
              ),
              DropdownMenu<String>(
                label: const Text('القسم'),
                initialSelection: _facultyDept,
                dropdownMenuEntries: deptOptions.map((d) => DropdownMenuEntry(value: d, label: d)).toList(),
                onSelected: (v) => setState(() {
                  _facultyDept = v;
                  _facultyInstructor = null;
                  _facultyViewMode = null;
                }),
              ),
              DropdownMenu<String>(
                // مفتاح يتغيّر مع القيمة نفسها - يجبر Flutter على إعادة بناء
                // حقل النص الداخلي بدل الاحتفاظ بالنص القديم معروضًا (باهتًا)
                // حين يُعطَّل الحقل أو تُصفَّر قيمته من كود آخر، وهو سلوك
                // معروف في DropdownMenu لا يُعالَج تلقائيًا بتغيير initialSelection.
                key: ValueKey('instructor-$_facultyInstructor'),
                label: const Text('عضو هيئة التدريس (اكتب للبحث)'),
                enabled: _facultyDept != null && _facultyShatr != null && _facultyViewMode == null,
                enableFilter: true,
                requestFocusOnTap: true,
                initialSelection: _facultyInstructor,
                dropdownMenuEntries: instructorNames.map((n) => DropdownMenuEntry(value: n, label: n)).toList(),
                onSelected: (v) => setState(() {
                  _facultyInstructor = v;
                  _facultyViewMode = null;
                }),
              ),
              DropdownMenu<String>(
                key: ValueKey('viewMode-$_facultyViewMode'),
                label: const Text('تقارير وعروض جماعية'),
                enabled: _facultyDept != null && _facultyShatr != null && _facultyInstructor == null,
                initialSelection: _facultyViewMode,
                dropdownMenuEntries: viewModeOptions.map((n) => DropdownMenuEntry(value: n, label: n)).toList(),
                onSelected: (v) => setState(() {
                  _facultyViewMode = v;
                  _facultyInstructor = null;
                }),
              ),
              FilterChip(
                label: const Text('إظهار الكل'),
                selected: _showAllFaculty,
                onSelected: (v) => setState(() => _showAllFaculty = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (selection) {
            null => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_outlined, size: 52, color: AppColors.gold.withValues(alpha: 0.6)),
                    const SizedBox(height: 14),
                    Text(
                      isAllDepts
                          ? 'اختر الشطر ثم "الكل" أو "الشعب غير المسكَّنة" لعرض شعب الكلية'
                          : 'اختر القسم والشطر واسم العضو لعرض جدوله',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            _kAllSectionsOption =>
              _buildSectionsListCard(isAllDepts ? 'جميع شعب الكلية' : 'جميع شعب القسم', selectedRows),
            _kUnscheduledOption => _buildSectionsListCard('الشعب غير المسكَّنة', selectedRows),
            _kQuotaReportOption => _buildQuotaReportCard(rowsForDeptShatr),
            final name => _buildInstructorScheduleCard(name, selectedRows),
          },
        ),
      ],
    );
  }

  /// قائمة مسطّحة بنفس تصميم جدول "جميع المقررات" - تُستخدم لعرض "الكل" أو
  /// "الشعب غير المسكَّنة" بدل جدول عضو محدَّد.
  Widget _buildSectionsListCard(String title, List<_DisplayRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('◆', style: TextStyle(color: AppColors.gold, fontSize: 12)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('◆', style: TextStyle(color: AppColors.gold, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('لا توجد نتائج'))
              // شريط التمرير الرأسي هو الأعلى مباشرة (يلتصق بحافة الصفحة)،
              // وما بداخله (الحشو والحدود الذهبية) لا يؤثر على موضعه.
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AppColors.green),
                          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          columns: const [
                            DataColumn(label: Text('رمز المقرر')),
                            DataColumn(label: Text('اسم المقرر')),
                            DataColumn(label: Text('الشعبة')),
                            DataColumn(label: Text('الأيام والوقت')),
                            DataColumn(label: Text('المحاضر')),
                          ],
                          rows: [
                            for (var i = 0; i < rows.length; i++)
                              DataRow(
                                color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                                cells: [
                                  DataCell(Text(rows[i].record.courseCode)),
                                  DataCell(Text(rows[i].record.courseName)),
                                  DataCell(_sectionCell(rows[i].record)),
                                  DataCell(_meetingsCell(rows[i].record)),
                                  DataCell(_instructorCell(rows[i].record)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildInstructorScheduleCard(String name, List<_DisplayRow> rows) {
    // عضو غير متواجد فعليًا (معار/مجاز/مبتعث) بلا أي مقرر مسكَّن - رسالة
    // واضحة بدل عرض جدول فارغ يوحي بخطأ في البيانات.
    final roster = _rosterFor(name);
    if (rows.isEmpty && roster != null && _isAbsentRosterMember(roster)) {
      return const Center(child: Text('لا يوجد جدول دراسي'));
    }
    final records = rows.map((r) => r.record).toList();
    final tableRows = InstructorScheduleTable.buildRows(records);
    final totalHours = InstructorScheduleTable.totalCreditHours(records);
    final department = _departmentFor(name, _facultyDept ?? '');
    final quota = _quotaCompare(
      totalHours,
      _effectiveMaxHoursFor(name),
      fullRankMaxHours: TeachingLoadRegulation.maxHoursFor(_rosterFor(name)?.academicRank),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Card(
            elevation: 2,
            color: const Color(0xFFFBF9F3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('◆', style: TextStyle(color: AppColors.gold, fontSize: 12)),
                      const SizedBox(width: 8),
                      const Text('جدول عضو هيئة التدريس', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text('◆', style: TextStyle(color: AppColors.gold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(height: 2, width: 200, color: AppColors.gold),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () async => Printing.sharePdf(
                            bytes: await _buildInstructorPdf(name, department, rows), filename: 'جدول_$name.pdf'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('عرض PDF'),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async =>
                            Printing.layoutPdf(onLayout: (_) async => _buildInstructorPdf(name, department, rows)),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('طباعة'),
                        style:
                            OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: BorderSide(color: AppColors.green)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _infoChip('الفصل الدراسي', 'الفصل الدراسي الأول 1448هـ', icon: Icons.calendar_month_outlined),
                      _infoChip('القسم', department, icon: Icons.apartment_outlined),
                      _infoChip('عضو هيئة التدريس', name, icon: Icons.person_outline),
                      _infoChip('رقم المكتب', _officeNumberFor(name) ?? '—', icon: Icons.meeting_room_outlined),
                    ],
                  ),
                  if (quota.note != null) ...[
                    const SizedBox(height: 14),
                    _quotaNoteBox(quota.status, quota.note!),
                  ],
                  const Divider(height: 32),
                  _instructorTable(tableRows, totalHours),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildQuotaPdf(List<_QuotaRow> rows) => TeachingQuotaPdfService.build(
        scopeLabel: '${_facultyDept ?? _kAllDeptsFacultyOption} - ${_facultyShatr?.label ?? _kAllShatr}',
        rows: rows
            .map((q) => TeachingQuotaPdfRow(
                  name: q.name,
                  department: q.department,
                  actualHours: q.actualHours,
                  maxHours: q.maxHours,
                  note: q.note,
                ))
            .toList(),
      );

  /// تقرير النصاب التدريسي: عدد الأعضاء دون النصاب/فوقه، مع جدول قابل
  /// للفلترة حسب الحالة، وتصدير PDF/طباعة مستقل عن الجدول الدراسي نفسه.
  Widget _buildQuotaReportCard(List<_DisplayRow> rows) {
    final isAllDepts = _facultyDept == _kAllDeptsFacultyOption;
    final names = _instructorNamesFor(rows, isAllDepts)
      ..sort((a, b) {
        final ma = _rosterFor(a);
        final mb = _rosterFor(b);
        if (ma == null || mb == null) return a.compareTo(b);
        return FacultySortOrder.compareMembers(ma, mb, compareDepartment: isAllDepts);
      });

    final quotaRows = <_QuotaRow>[];
    for (final name in names) {
      if (_isExcludedFromQuota(name)) continue; // مجاز/مبتعث/معار - لا يُحتسب إطلاقًا
      final records = rows.where((r) => r.record.instructorName == name).map((r) => r.record).toList();
      final actualHours = InstructorScheduleTable.totalCreditHours(records);
      final rank = _rosterFor(name)?.academicRank ?? '';
      final department = _departmentFor(name, _facultyDept ?? '');
      final staffNumber = _rosterFor(name)?.staffNumber ?? '';
      final maxHours = _effectiveMaxHoursFor(name);
      final compare = _quotaCompare(
        actualHours,
        maxHours,
        fullRankMaxHours: TeachingLoadRegulation.maxHoursFor(rank),
      );
      quotaRows.add(_QuotaRow(
        name: name,
        department: FacultySortOrder.displayDepartment(department),
        rank: rank,
        staffNumber: staffNumber,
        actualHours: actualHours,
        maxHours: maxHours,
        status: compare.status,
        note: compare.note,
      ));
    }

    bool isOverAny(_QuotaRow q) => q.status == _QuotaStatus.over || q.status == _QuotaStatus.overWithinRounding;

    final underCount = quotaRows.where((q) => q.status == _QuotaStatus.under).length;
    final overCount = quotaRows.where(isOverAny).length;

    final filtered = switch (_quotaFilter) {
      _kQuotaUnder => quotaRows.where((q) => q.status == _QuotaStatus.under).toList(),
      _kQuotaOver => quotaRows.where(isOverAny).toList(),
      _ => quotaRows,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _quotaCountChip(_kQuotaUnder, underCount, Colors.red.shade700),
              _quotaCountChip(_kQuotaOver, overCount, Colors.orange.shade800),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: _kQuotaAll, label: Text(_kQuotaAll)),
                  ButtonSegment(value: _kQuotaUnder, label: Text(_kQuotaUnder)),
                  ButtonSegment(value: _kQuotaOver, label: Text(_kQuotaOver)),
                ],
                selected: {_quotaFilter},
                onSelectionChanged: (s) => setState(() => _quotaFilter = s.first),
              ),
              FilledButton.icon(
                onPressed: () async => Printing.sharePdf(
                  bytes: await _buildQuotaPdf(filtered),
                  filename: 'تقرير_النصاب_التدريسي.pdf',
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('عرض PDF'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              ),
              OutlinedButton.icon(
                onPressed: () async => Printing.layoutPdf(onLayout: (_) async => _buildQuotaPdf(filtered)),
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: BorderSide(color: AppColors.green)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AppColors.green),
                          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          columns: const [
                            DataColumn(label: Expanded(child: Center(child: Text('الاسم')))),
                            DataColumn(label: Expanded(child: Center(child: Text('القسم')))),
                            DataColumn(label: Expanded(child: Center(child: Text('الساعات الفعلية')))),
                            DataColumn(label: Expanded(child: Center(child: Text('الحد النظامي')))),
                            DataColumn(label: Expanded(child: Center(child: Text('الملاحظة')))),
                          ],
                          rows: [
                            for (var i = 0; i < filtered.length; i++)
                              DataRow(
                                color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                                cells: [
                                  DataCell(Center(child: Text(filtered[i].name))),
                                  DataCell(Center(child: Text(filtered[i].department))),
                                  DataCell(Center(child: Text('${filtered[i].actualHours}'))),
                                  DataCell(Center(child: Text(filtered[i].maxHours?.toString() ?? '—'))),
                                  DataCell(
                                    Center(
                                      child: filtered[i].note == null
                                          ? Text('مطابق للنصاب', style: TextStyle(color: AppColors.green))
                                          : filtered[i].status == _QuotaStatus.over
                                              ? _optionalOverageBadge(filtered[i].note!)
                                              : Text(filtered[i].note!, style: TextStyle(color: _quotaColor(filtered[i].status))),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _quotaCountChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text('$label: $count', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }

  /// لون كل حالة نصاب - بطلب سليمان: أحمر = دون النصاب، أخضر = مطابق،
  /// برتقالي = زائد إجباري (فارق تقريب لا يمكن التحكم به، المقررات 3
  /// ساعات فلا يمكن تحقيق نصاب كـ10 بالضبط)، وأرجواني مميز = زائد اختياري
  /// (زيادة حقيقية فوق ذلك الهامش، يستحق شارة مستقلة كعبء الإرشاد بدل لون
  /// عادي حتى لا يختلط بحالة الزيادة الإجبارية).
  Color _quotaColor(_QuotaStatus status) => switch (status) {
        _QuotaStatus.over => Colors.purple.shade700,
        _QuotaStatus.overWithinRounding => Colors.orange.shade800,
        _QuotaStatus.under => Colors.red.shade700,
        _ => AppColors.green,
      };

  /// شارة "زائد اختياري" بنفس تصميم شارة عبء الإرشاد (`_loadChip` بملف
  /// college_roster_admin_screen.dart) - حبة مستقلة بخلفية وحدود بلون مميز،
  /// بدل نص ملوّن عادي، لتمييزها بصريًا عن باقي حالات النصاب.
  Widget _optionalOverageBadge(String note) {
    final color = _quotaColor(_QuotaStatus.over);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(note, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5)),
    );
  }

  /// صندوق ملاحظة النصاب - يظهر فقط في عرض الموقع (لا في PDF ولا الطباعة).
  Widget _quotaNoteBox(_QuotaStatus status, String note) {
    if (status == _QuotaStatus.over) return _optionalOverageBadge(note);
    final color = _quotaColor(status);
    final icon = status == _QuotaStatus.overWithinRounding ? Icons.remove_circle_outline : Icons.info_outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(note, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5))),
        ],
      ),
    );
  }

  /// جدول قائمة مسطّحة (وليس شبكة تقويمية) بنفس أعمدة الجدول الرسمي في
  /// البوابة الإلكترونية للجامعة (EduGate)، مرتّب زمنيًا مع إجمالي الساعات.
  Widget _instructorTable(List<InstructorScheduleRow> tableRows, int totalHours) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 44,
              dataRowMaxHeight: double.infinity,
              headingRowColor: WidgetStateProperty.all(AppColors.green),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
              columns: const [
                DataColumn(label: Text('رمز المقرر')),
                DataColumn(label: Text('اسم المقرر')),
                DataColumn(label: Text('النشاط')),
                DataColumn(label: Text('الشعبة')),
                DataColumn(label: Text('الساعات')),
                DataColumn(label: Text('اليوم')),
                DataColumn(label: Text('الوقت')),
              ],
              rows: tableRows.isEmpty
                  ? [
                      const DataRow(cells: [
                        DataCell(Text('لا توجد مقررات مسكَّنة لهذا العضو')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                      ]),
                    ]
                  : [
                      for (var i = 0; i < tableRows.length; i++)
                        DataRow(
                          color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                          cells: [
                            DataCell(Text(tableRows[i].courseCode)),
                            DataCell(Text(tableRows[i].courseName)),
                            DataCell(!tableRows[i].hasPractical
                                ? _activityChip('نظري')
                                : _splitCell(_activityChip('نظري'), _activityChip('عملي'))),
                            DataCell(!tableRows[i].hasPractical
                                ? Text(tableRows[i].theorySection)
                                : _splitCell(Text(tableRows[i].theorySection), Text(tableRows[i].practicalSection!))),
                            DataCell(!tableRows[i].hasPractical
                                ? Text('${tableRows[i].theoryHours}')
                                : _splitCell(Text('${tableRows[i].theoryHours}'), Text('${tableRows[i].practicalHours}'))),
                            DataCell(!tableRows[i].hasPractical
                                ? Text(tableRows[i].theoryDayName)
                                : _splitCell(Text(tableRows[i].theoryDayName), Text(tableRows[i].practicalDayName!))),
                            DataCell(!tableRows[i].hasPractical
                                ? Text(tableRows[i].theoryTimeRange)
                                : _splitCell(Text(tableRows[i].theoryTimeRange), Text(tableRows[i].practicalTimeRange!))),
                          ],
                        ),
                    ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child: Text('مجموع الساعات المعتمدة: $totalHours',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.green)),
          ),
        ),
      ],
    );
  }

  Widget _activityChip(String activity) {
    final isLab = activity == 'عملي';
    final color = isLab ? AppColors.gold : AppColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isLab ? Icons.science_outlined : Icons.menu_book_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Text(activity, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  /// المرجع الوحيد لرقم المكتب/القسم العلمي هو ملف أعضاء هيئة التدريس
  /// المعتمد المرفوع فعليًا عبر الموقع (بعد مطابقة الاسم مجرّدًا من اللقب) -
  /// بلا أي رجوع لقوائم ثابتة قديمة في الكود، مهما كان مصدرها. لو العضو غير
  /// موجود بعد في الملف المرفوع تبقى الخانة فارغة كإشارة واضحة أن العمادة
  /// لم تُدرجه بعد، بدل تخمين قيمة من مكان آخر.
  /// توحيد اسم للمطابقة فقط (ليس للعرض) - يحذف كل الفراغات ويوحّد الهمزة/التاء
  /// المربوطة، لأن اسم نفس الشخص قد يُكتب بفراغ مختلف بين ملف بيانات منسوبي
  /// الكلية وملف الجدول الدراسي (مثال: "عبد الله" في ملف مقابل "عبدالله" في
  /// آخر) فيفشل التطابق الحرفي بصمت، ويظهر نفس العضو مرتين في القوائم
  /// (اسم من الملف الرسمي + اسم آخر "غير موجود بالملف" من الجدول احتياطًا).
  String _normalizeNameKey(String s) => s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه');

  CollegeRosterMember? _rosterFor(String instructorName) =>
      _rosterByName[_normalizeNameKey(displayName(instructorName))];

  /// عضو غير متواجد فعليًا (معار/مجاز/مبتعث) - لا نصاب له، ويُخفى افتراضيًا
  /// من قائمة "عضو هيئة التدريس" ما لم تُفعَّل خانة "إظهار الكل".
  bool _isAbsentRosterMember(CollegeRosterMember m) {
    final text = '${m.position} ${m.position2} ${m.position3} ${m.employeeStatus}';
    return text.contains('مبتعث') || text.contains('معار') || text.contains('مجاز') || text.contains('مطوي');
  }

  /// أسماء الأعضاء ضمن نطاق القسم/الشطر المحدَّد حاليًا (شاشة عضو هيئة
  /// التدريس) - تُبنى من ملف "بيانات منسوبي الكلية" (القسم الأصلي الفعلي
  /// للعضو) لا من قسم المقرر المجدوَل، لسببين: (1) عضو بلا أي مقرر مسكَّن
  /// هذا الفصل يجب أن يظهر أيضًا (له نصاب حتى لو لم يُستوفَ بعد)، (2) عضو
  /// يُدرِّس مقررًا مشتركًا يخصّ قسمًا آخر (مقرر خدمة) لا يجب أن يظهر مكررًا
  /// تحت قسمين مختلفين. مطابقة القسم عبر [FacultySortOrder.departmentRank]
  /// تتحمّل اختلاف إملاء الهمزة بين قيمة CourseCatalog ("قسم الإدارة") وقيمة
  /// الملف المرفوع ("قسم الادارة" بلا همزة).
  List<String> _instructorNamesFor(List<_DisplayRow> rows, bool isAllDepts) {
    bool rosterMatchesScope(CollegeRosterMember m) {
      if (m.type != CollegeMemberType.faculty) return false;
      if (!_showAllFaculty && _isAbsentRosterMember(m)) return false;
      if (!isAllDepts && _facultyDept != null) {
        if (FacultySortOrder.departmentRank(m.department) != FacultySortOrder.departmentRank(_facultyDept!)) {
          return false;
        }
      }
      if (_facultyShatr != null) {
        final wanted = _facultyShatr == Shatr.male ? 0 : 1;
        if (FacultySortOrder.shatrRank(m.shatr) != wanted) return false;
      }
      return true;
    }

    return {
      ..._rosterByName.values.where(rosterMatchesScope).map((m) => displayName(m.name)),
      // أي اسم من الجدول الدراسي **غير موجود إطلاقًا** في ملف منسوبي الكلية
      // (بيانات لم تُحدَّث بعد) يبقى ظاهرًا احتياطًا - لكن لا يُضاف أي اسم
      // معروف بالفعل في الملف، وإلا يعود ليظهر مكررًا تحت أي قسم يُدرِّس فيه
      // مقررًا مشتركًا (وهو بالضبط الخلل الذي نُصلحه هنا).
      ...rows.map((r) => r.record.instructorName).whereType<String>().where((n) => _rosterFor(n) == null),
    }.toList();
  }

  String? _officeNumberFor(String instructorName) {
    final rosterOffice = _rosterFor(instructorName)?.office;
    return (rosterOffice != null && rosterOffice.isNotEmpty) ? rosterOffice : null;
  }

  String _combinedPositionsFor(String instructorName) {
    final m = _rosterFor(instructorName);
    if (m == null) return '';
    return [m.position, m.position2, m.position3].join(' ');
  }

  /// الحد الأعلى الفعلي للنصاب لعضو معيّن - يراعي مناصبه المعروفة (عميد/
  /// وكيل/رئيس قسم/رئيس مركز البحوث والاستشارات/مستشار الشراكات
  /// الاستراتيجية = 3 ساعات ثابتة) قبل الرجوع للحد النظامي حسب درجته
  /// العلمية وحدها.
  int? _effectiveMaxHoursFor(String instructorName) {
    final m = _rosterFor(instructorName);
    if (m == null) return null;
    // نصاب العمادة الصريح (عمود "نصاب عضو هيئة التدريس") هو المرجع الحاسم
    // الأول - يتغلّب على أي استنتاج تلقائي من المنصب/الدرجة العلمية، لأن
    // قرار العمادة قد يخالف القاعدة العامة لحالات خاصة.
    if (m.teachingLoadHours != null) return m.teachingLoadHours;
    return TeachingLoadRegulation.effectiveMaxHoursFor(
      academicRank: m.academicRank,
      combinedPositions: _combinedPositionsFor(instructorName),
      quotaReductionNote: m.quotaReductionNote,
      positions: [m.position, m.position2, m.position3],
    );
  }

  /// مجاز/مبتعث/معار - لا يُحتسب النصاب له إطلاقًا، إلا لو كتبت العمادة
  /// ملاحظة تخفيض صريحة (قرارها حينها أعلى من نص المنصب).
  bool _isExcludedFromQuota(String instructorName) {
    if ((_rosterFor(instructorName)?.quotaReductionNote ?? '').trim().isNotEmpty) return false;
    return TeachingLoadRegulation.isExcluded(_combinedPositionsFor(instructorName));
  }

  String _departmentFor(String instructorName, String fallbackDepartment) {
    final dept = _rosterFor(instructorName)?.department;
    return (dept == null || dept.isEmpty) ? fallbackDepartment : dept;
  }

  Widget _infoChip(String label, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold, width: 1),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CircleAvatar(radius: 13, backgroundColor: AppColors.green.withValues(alpha: 0.1), child: Icon(icon, size: 14, color: AppColors.green)),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              const SizedBox(height: 3),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildInstructorPdf(String name, String department, List<_DisplayRow> rows) {
    return InstructorSchedulePdfService.build(
      instructorName: name,
      department: department,
      records: rows.map((r) => r.record).toList(),
      officeNumber: _officeNumberFor(name),
    );
  }
}

/// يضع TabBar داخل خلفية خضراء صلبة - ألوان TabBar الافتراضية في هذا
/// المشروع (نص أبيض) مصمَّمة لخلفية AppBar الخضراء التقليدية، فتختفي تمامًا
/// (أبيض على أبيض) لو وُضع التبويب مباشرة على الخلفية البيضاء لرأس الصفحة
/// الجديد بلا هذا الغلاف.
class _GreenTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabBar tabBar;
  const _GreenTabBar(this.tabBar);

  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.green, child: tabBar);
  }

  @override
  Size get preferredSize => tabBar.preferredSize;
}
