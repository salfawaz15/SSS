import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/advising_load_rules.dart';
import '../data/faculty_sort_order.dart';
import '../data/teaching_load_regulation.dart';
import '../data/teaching_quota_status.dart';
import '../models/college_roster_member.dart';
import '../models/course_section_record.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_repository.dart';
import '../theme/app_theme.dart';
import '../theme/filter_pills.dart';
import '../utils/name_display.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

const String _kAllDepartments = 'كل الأقسام';
const String _kAllShatr = 'كل الشطرين';

/// نص عرض كل مناصب العضو - يعرض عمود "توضيح المنصب" (مسمى المنصب) كما هو
/// حرفيًا من الملف دون أي دمج أو اجتهاد نصي، لأنه أصلاً العنوان الرسمي
/// الكامل الذي كتبته العمادة (مثال: "وكيل كلية إدارة الأعمال للتدريب") -
/// إضافة "المنصب المعياري" قبله بشرطة يُنتج ازدواجًا مزعجًا ("وكيل كلية —
/// إدارة الأعمال للتدريب"). العمود المعياري (نوع التكليف) يُستخدَم فقط
/// كاحتياط إن كان التوضيح فارغًا (بيانات قديمة، أو ورقة الإداريين التي لا
/// تملك عمود توضيح أصلاً).
/// "أنواع تكليف" عامة لا تحمل أي معنى تصنيفي بذاتها ولا توضيح مرافق لها -
/// تُخفى من العرض بلا بديل بدل عرضها فارغة الدلالة.
const _kMeaninglessPositionLabels = {'تكليف خارجي', 'تكليف داخلي'};

String _positionsDisplay(CollegeRosterMember m) {
  String combine(String position, String detail) {
    if (position.isEmpty) return '';

    // احذف لاحقة "-شطر الطلاب/الطالبات" من نهاية التفصيل - عمود "الشطر"
    // مستقل ومعروض بالفعل بجانب هذا العمود، فذكره هنا مجددًا تكرار.
    final d = detail.replaceFirst(RegExp(r'[-–—]\s*شطر\s*(الطلاب|الطالبات)\s*$'), '').trim();
    if (d.isEmpty) {
      return _kMeaninglessPositionLabels.contains(position) ? '' : position;
    }

    // إن حوى التوضيح أكثر من فقرة مفصولة بفاصلة عربية (بيانات أكثر من دور
    // فعلي حُشرت في خانة منصب واحدة بدل استخدام خانة "منصب آخر" المخصَّصة)،
    // تُعرَض كل فقرة في سطر مستقل بدل دمجها في سطر واحد مزدحم.
    final parts = d.split('،').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return d;
    return '${parts.first}\n${parts.skip(1).map((p) => '   • $p').join('\n')}';
  }

  // استثناء صريح: منصب "مستشار" (تشريف أعلى من المنصب الأساسي غالبًا، مثل
  // "مستشار عميد شؤون الطلاب") يُعرَض أولاً قبل أي منصب آخر للعضو نفسه، بصرف
  // النظر عن ترتيبه الفعلي بين الأعمدة (مثال: سليمان - منصبه الأساسي "نائب
  // رئيس وحدة" ومنصبه الآخر "مستشار عميد شؤون الطلاب" - يظهر المستشار أولاً).
  final entries = [
    MapEntry(m.position, combine(m.position, m.positionDetail)),
    MapEntry(m.position2, combine(m.position2, m.position2Detail)),
    MapEntry(m.position3, combine(m.position3, m.position3Detail)),
  ].where((e) => e.value.isNotEmpty);
  final advisorTitles = entries.where((e) => e.key.contains('مستشار'));
  final otherTitles = entries.where((e) => !e.key.contains('مستشار'));
  return [...advisorTitles, ...otherTitles].map((e) => e.value).join('\n');
}

/// أعضاء "غير متواجدين فعليًا" (مبتعث/معار/مجاز) - معفَون من الإرشاد لسبب
/// مختلف جذريًا عن إعفاء القياديين (عميد/وكيل/رئيس قسم مشغولون بمهام
/// إدارية لكنهم متواجدون)، فيحتاجون تمييزًا بصريًا مختلفًا (رمادي) بدل نفس
/// الشارة الحمراء "معفى من الإرشاد" حتى لا يُفهَم أنهم مشغولون بمنصب فقط.
bool _isAbsentMember(CollegeRosterMember m) {
  final text = '${m.position} ${m.position2} ${m.position3} ${m.employeeStatus}';
  // "مطوي القيد" أُضيفت هنا (2026-08-14) - كانت مفقودة من هذا الفحص المستقل
  // عن AdvisingLoadRules._frozenKeywords، فظهرت بشرى جمال بكر عمر (حالتها
  // "مطوي قيدها") بشارة "الحالة مجمّدة" العامة بدل "غير متواجد" الرمادية
  // الصحيحة، ولم تُخفَ افتراضيًا كبقية غير المتواجدين رغم تطابق حالتها معهم.
  return text.contains('مبتعث') || text.contains('معار') || text.contains('مجاز') || text.contains('مطوي');
}

String _absenceLabel(CollegeRosterMember m) {
  // تسمية واحدة موحَّدة بلا ذكر السبب (مبتعث/معار/مجاز) - السبب الفعلي
  // موجود أصلاً في عمود المنصب نفسه، فذكره هنا مجددًا تكرار لا داعي له.
  return 'غير متواجد';
}

extension on AdvisingLoad {
  // "إرشاد جزئي" تسمية ثابتة بلا رقم نسبة - النسبة الفعلية تبقى محفوظة
  // برمجيًا (m.reducedToPercent) لكنها لا تُعرَض كرقم في الواجهة.
  String get label => switch (this) {
        AdvisingLoad.full => 'إرشاد كامل',
        AdvisingLoad.reduced => 'إرشاد جزئي',
        AdvisingLoad.exempt => 'معفى من الإرشاد',
        AdvisingLoad.specialCasesOnly => 'حالات خاصة فقط',
        AdvisingLoad.frozen => 'الحالة مجمّدة',
      };

  Color get color => switch (this) {
        AdvisingLoad.full => AppColors.green,
        AdvisingLoad.reduced => Colors.blue.shade700,
        AdvisingLoad.exempt => Colors.red.shade700,
        AdvisingLoad.specialCasesOnly => Colors.purple.shade700,
        AdvisingLoad.frozen => Colors.grey.shade700,
      };
}

class CollegeRosterAdminScreen extends StatefulWidget {
  const CollegeRosterAdminScreen({super.key});

  @override
  State<CollegeRosterAdminScreen> createState() => _CollegeRosterAdminScreenState();
}

class _CollegeRosterAdminScreenState extends State<CollegeRosterAdminScreen> {
  List<CollegeRosterMember> _members = [];
  List<CourseSectionRecord> _maleRecords = [];
  List<CourseSectionRecord> _femaleRecords = [];
  DateTime? _lastSavedAt;
  bool _loading = true;

  // تصنيف مستقل تمامًا: أعضاء هيئة تدريس أو إداريين - لا يشتركان بنفس الفرز
  // ولا نفس الأعمدة، حسب تعليمات صريحة.
  CollegeMemberType _typeFilter = CollegeMemberType.faculty;
  String _deptFilter = _kAllDepartments;
  String _shatrFilter = _kAllShatr;
  final _searchCtrl = TextEditingController();

  // افتراضيًا تُخفى مباشرة الأعضاء غير المتواجدين فعليًا (معار/مجاز/مبتعث)
  // من القائمة تمامًا - لا تظهر إلا من هو متواجد فعليًا (بمنصب، بتكليف، أو
  // بلا أي تكليف) - تعليمات صريحة. صندوق "إظهار الكل" يعطّل هذا الإخفاء.
  bool _showAll = false;

  // فرز الجدول بالضغط على رأس أي عمود (بطلب سليمان 2026-08-09: "زي المواقع
  // الاحترافية") - `_sortKey` بدل رقم عمود ثابت لأن أعمدة القسم/الشطر تظهر
  // أو تختفي حسب الفلتر النشط، فيتغيّر ترقيمها الفعلي. null = الفرز
  // الافتراضي (FacultySortOrder.compareMembers) بلا تعديل المستخدم.
  String? _sortKey;
  bool _sortAscending = true;

  void _onSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = true;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      CollegeRosterRepository.load(),
      CollegeRosterRepository.currentLastSavedAt(),
      CourseScheduleRepository.loadSchedule(Shatr.male),
      CourseScheduleRepository.loadSchedule(Shatr.female),
    ]);
    if (!mounted) return;
    setState(() {
      _members = results[0] as List<CollegeRosterMember>;
      _lastSavedAt = results[1] as DateTime?;
      _maleRecords = results[2] as List<CourseSectionRecord>;
      _femaleRecords = results[3] as List<CourseSectionRecord>;
      _loading = false;
    });
  }

  static String _nameKey(String s) => s
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه');

  /// العبء الدراسي الفعلي لعضو هيئة التدريس - مجموع ساعات كل شعبة (نظري/عملي)
  /// أُسنِدت له فعليًا في آخر جدول دراسي معتمد (كلا الشطرين)، وليس النصاب
  /// النظري المكتوب في ملف العمادة (`teachingLoadHours`، عمود منفصل تمامًا).
  int _teachingLoadFor(CollegeRosterMember m) {
    final key = _nameKey(displayName(m.name));
    var total = 0;
    for (final r in [..._maleRecords, ..._femaleRecords]) {
      // النظري والعملي لنفس الشعبة قد يُسنَدان لعضوين مختلفين - تُحتسَب فقط
      // الساعات التي يُدرِّسها هذا العضو تحديدًا، لا الشعبة كاملة.
      if (r.instructorName != null && _nameKey(displayName(r.instructorName!)) == key) {
        total += r.theoryHours;
      }
      if (r.practicalInstructorName != null && _nameKey(displayName(r.practicalInstructorName!)) == key) {
        total += r.practicalHours;
      }
    }
    return total;
  }

  /// لون عمود "العبء الدراسي" بنفس منطق/ألوان تقرير النصاب التدريسي
  /// (`course_schedule_admin_screen.dart`): أحمر دون النصاب، أخضر مطابق،
  /// برتقالي زائد إجباري (فارق تقريب)، أرجواني زائد اختياري - كانت تظهر
  /// كرقم عادي بلا تلوين بهذه الشاشة تحديدًا (سليمان 2026-08-09).
  Color? _teachingLoadColorFor(CollegeRosterMember m) {
    if (m.academicRank.trim().isEmpty) return null;
    final combinedPositions = [m.position, m.position2, m.position3].join('، ');
    final effectiveMax = m.teachingLoadHours ??
        TeachingLoadRegulation.effectiveMaxHoursFor(
          academicRank: m.academicRank,
          combinedPositions: combinedPositions,
          quotaReductionNote: m.quotaReductionNote,
          positions: [m.position, m.position2, m.position3],
        );
    final fullRankMax = TeachingLoadRegulation.maxHoursFor(m.academicRank);
    final status = compareTeachingQuota(_teachingLoadFor(m), effectiveMax, fullRankMaxHours: fullRankMax);
    return teachingQuotaColor(status);
  }

  /// شارة "العبء الدراسي" بنفس قالب `_loadChip` (خلفية معبّأة بلون الحالة +
  /// حدّ بنفس اللون) بدل رقم ملوَّن بلا خلفية - توحيدًا بصريًا مع شارة عبء
  /// الإرشاد بنفس الجدول (بطلب سليمان).
  Widget _teachingLoadChip(CollegeRosterMember m) {
    final color = _teachingLoadColorFor(m) ?? Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text('${_teachingLoadFor(m)}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }


  List<CollegeRosterMember> get _typedMembers => _members.where((m) => m.type == _typeFilter).toList();

  List<String> get _departments =>
      _typedMembers.map((m) => m.department).where((d) => d.isNotEmpty).toSet().toList()..sort();

  List<CollegeRosterMember> get _filtered {
    final search = _searchCtrl.text.trim();
    final list = _typedMembers.where((m) {
      if (_deptFilter != _kAllDepartments && m.department != _deptFilter) return false;
      // فلتر الشطر يشمل الإداريين أيضًا الآن بعد إضافة عمود "الشطر" لورقتهم.
      if (_shatrFilter != _kAllShatr && m.shatr != _shatrFilter) return false;
      if (search.isNotEmpty && !m.name.contains(search)) return false;
      if (!_showAll && _isAbsentMember(m)) return false;
      return true;
    }).toList();

    if (_typeFilter == CollegeMemberType.faculty) {
      list.sort((a, b) => FacultySortOrder.compareMembers(
            a,
            b,
            compareDepartment: _deptFilter == _kAllDepartments,
          ));
    }
    // الإداريون: بلا أي فرز آلي - يظهرون بنفس ترتيب صفوفهم بملف الإكسل
    // المرفوع تمامًا (ترتيب `list.where()` أعلاه يحافظ على الترتيب الأصلي
    // للقائمة المحمَّلة)، بطلب سليمان صراحةً 2026-08-11 بعد تحديثه للملف
    // ورفعه - كان الفرز السابق (جهة، شطر، مستوى منصب، اسم) يعيد ترتيبهم
    // خلافًا لترتيبه المتعمَّد بالملف.

    // فرز المستخدم اليدوي (بالضغط على رأس عمود) يتغلّب على الفرز الافتراضي
    // أعلاه إن اختير - لجدول أعضاء هيئة التدريس فقط حاليًا (نفس الأعمدة
    // الخمسة المطلوبة: الاسم، القسم، المنصب، عبء الإرشاد، العبء الدراسي).
    if (_sortKey != null && _typeFilter == CollegeMemberType.faculty) {
      int cmp(CollegeRosterMember a, CollegeRosterMember b) {
        switch (_sortKey) {
          case 'department':
            return FacultySortOrder.displayDepartment(a.department)
                .compareTo(FacultySortOrder.displayDepartment(b.department));
          case 'position':
            return _positionsDisplay(a).compareTo(_positionsDisplay(b));
          case 'advisingLoad':
            return a.advisingLoad.label.compareTo(b.advisingLoad.label);
          case 'teachingLoad':
            return _teachingLoadFor(a).compareTo(_teachingLoadFor(b));
          case 'name':
          default:
            return a.name.compareTo(b.name);
        }
      }

      list.sort(_sortAscending ? cmp : (a, b) => cmp(b, a));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'بيانات منسوبي الكلية',
      navItems: buildAdminNavItems(context, current: 'college-roster'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildUploadBar(),
                _buildTypeBar(),
                _buildFilterBar(),
                const Divider(height: 1),
                Expanded(
                  child: _typeFilter == CollegeMemberType.faculty ? _buildFacultyTable() : _buildAdminTable(),
                ),
              ],
            ),
    );
  }

  /// شريط معلوماتي فقط (بلا زر رفع) - الرفع انتقل لصفحة "رفع وتنزيل الملفات"
  /// الموحَّدة (سليمان 2026-08-22: "قم بإزالة الرفع من هنا، يوجد مكان للرفع").
  Widget _buildUploadBar() {
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _lastSavedAt != null
                    ? 'آخر نسخة معتمدة: ${fmt.format(_lastSavedAt!)} - الرفع من صفحة "رفع وتنزيل الملفات"'
                    : 'لم يُرفع بعد - ارفع الملف من صفحة "رفع وتنزيل الملفات"',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: SegmentedButton<CollegeMemberType>(
          segments: const [
            ButtonSegment(value: CollegeMemberType.faculty, label: Text('أعضاء هيئة تدريس'), icon: Icon(Icons.school_outlined)),
            ButtonSegment(value: CollegeMemberType.admin, label: Text('إداريين'), icon: Icon(Icons.badge_outlined)),
          ],
          selected: {_typeFilter},
          onSelectionChanged: (s) => setState(() {
            _typeFilter = s.first;
            _deptFilter = _kAllDepartments;
          }),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.greenDark,
            selectedForegroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterResetChip(
            active: _shatrFilter == _kAllShatr && _deptFilter == _kAllDepartments,
            onTap: () => setState(() {
              _shatrFilter = _kAllShatr;
              _deptFilter = _kAllDepartments;
            }),
          ),
          // متاح الآن للإداريين أيضًا بعد إضافة عمود "الشطر" لورقتهم.
          FilterPillDropdown<String>(
            label: 'الشطر',
            value: _shatrFilter == _kAllShatr ? null : _shatrFilter,
            items: const ['طلاب', 'طالبات'],
            itemLabel: (v) => v,
            onChanged: (v) => setState(() => _shatrFilter = v ?? _kAllShatr),
          ),
          FilterPillDropdown<String>(
            key: ValueKey(_typeFilter),
            label: 'القسم / الجهة',
            value: _deptFilter == _kAllDepartments ? null : _deptFilter,
            items: _departments,
            itemLabel: (v) => v,
            onChanged: (v) => setState(() => _deptFilter = v ?? _kAllDepartments),
          ),
          SizedBox(
            width: 240,
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.gold, width: 1.4)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // مخفي افتراضيًا: المعارون/المجازون/المبتعثون غير متواجدين فعليًا،
          // فلا يظهرون في القائمة إلا بتفعيل هذا الصندوق صراحةً.
          FilterChip(
            label: const Text('إظهار الكل'),
            selected: _showAll,
            onSelected: (v) => setState(() => _showAll = v),
            selectedColor: AppColors.greenDark,
            labelStyle: TextStyle(color: _showAll ? Colors.white : Colors.grey.shade700),
            backgroundColor: Colors.grey.shade100,
            side: BorderSide.none,
            shape: const StadiumBorder(),
          ),
        ],
      ),
    );
  }

  Widget _buildFacultyTable() {
    final rows = _filtered;
    if (rows.isEmpty) {
      return const Center(child: Text('لا توجد بيانات - ارفع الملف الرسمي أولاً'));
    }
    return SingleChildScrollView(
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
            child: Builder(
              builder: (context) {
                // كل عمود قابل للفرز مرتبط بمفتاح دلالي (`_sortKey`) لا رقم
                // ثابت - لأن عمودَي القسم/الشطر يظهران أو يختفيان حسب الفلتر
                // النشط فيتحرّك ترقيم الأعمدة الفعلي (سليمان 2026-08-09:
                // فرز الجدول بالضغط على رأس أي عمود، زي المواقع الاحترافية).
                final sortableColumns = <({String key, String label})>[
                  (key: 'name', label: 'الاسم'),
                  if (_deptFilter == _kAllDepartments) (key: 'department', label: 'القسم / الجهة'),
                  (key: 'position', label: 'المنصب'),
                  (key: 'advisingLoad', label: 'عبء الإرشاد'),
                  (key: 'teachingLoad', label: 'العبء الدراسي'),
                ];
                int? sortColumnIndex;
                var idx = 0;
                final columns = <DataColumn>[];
                for (final c in sortableColumns) {
                  if (c.key == _sortKey) sortColumnIndex = idx;
                  columns.add(DataColumn(
                    label: Expanded(child: Center(child: Text(c.label))),
                    onSort: (_, _) => _onSort(c.key),
                  ));
                  idx++;
                  if (c.key == 'department' && _shatrFilter == _kAllShatr) {
                    columns.add(const DataColumn(label: Expanded(child: Center(child: Text('الشطر')))));
                    idx++;
                  }
                }
                return DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.green),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: _sortAscending,
                  columns: columns,
                  rows: [
                    for (var i = 0; i < rows.length; i++)
                      DataRow(
                        color: WidgetStateProperty.all(_isAbsentMember(rows[i])
                            ? Colors.grey.shade200
                            : (i.isEven ? Colors.white : const Color(0xFFF7F5EF))),
                        cells: [
                          DataCell(Center(child: Text(rows[i].name, textAlign: TextAlign.center))),
                          if (_deptFilter == _kAllDepartments)
                            DataCell(Center(
                                child: Text(FacultySortOrder.displayDepartment(rows[i].department),
                                    textAlign: TextAlign.center))),
                          if (_shatrFilter == _kAllShatr)
                            DataCell(Center(child: Text(rows[i].shatr.isEmpty ? '—' : rows[i].shatr))),
                          DataCell(Center(
                              child: Text(
                                  _positionsDisplay(rows[i]).ifEmptyDash(),
                                  textAlign: TextAlign.center))),
                          DataCell(Center(child: _loadChip(rows[i]))),
                          DataCell(Center(child: _teachingLoadChip(rows[i]))),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// جدول الإداريين - مستقل تمامًا عن جدول أعضاء هيئة التدريس: لا عبء إرشاد
  /// ولا شطر ولا أي بيانات خاصة بعضو هيئة التدريس، فقط بيانات الإداري نفسه.
  Widget _buildAdminTable() {
    final rows = _filtered;
    if (rows.isEmpty) {
      return const Center(child: Text('لا توجد بيانات إدارية - ارفع الملف الرسمي أولاً'));
    }
    return SingleChildScrollView(
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
              columns: [
                const DataColumn(label: Expanded(child: Center(child: Text('الاسم')))),
                if (_deptFilter == _kAllDepartments)
                  const DataColumn(label: Expanded(child: Center(child: Text('الجهة')))),
                if (_shatrFilter == _kAllShatr)
                  const DataColumn(label: Expanded(child: Center(child: Text('الشطر')))),
                const DataColumn(label: Expanded(child: Center(child: Text('المسمى الوظيفي')))),
                const DataColumn(label: Expanded(child: Center(child: Text('رقم المكتب')))),
                const DataColumn(label: Expanded(child: Center(child: Text('ملاحظات')))),
              ],
              rows: [
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                    cells: [
                      DataCell(Center(child: Text(rows[i].name, textAlign: TextAlign.center))),
                      if (_deptFilter == _kAllDepartments)
                        DataCell(Center(
                            child: Text(FacultySortOrder.displayDepartment(rows[i].department),
                                textAlign: TextAlign.center))),
                      if (_shatrFilter == _kAllShatr)
                        DataCell(Center(child: Text(rows[i].shatr.ifEmptyDash()))),
                      DataCell(Center(
                          child: Text(
                              _positionsDisplay(rows[i]).ifEmptyDash(),
                              textAlign: TextAlign.center))),
                      DataCell(Center(child: Text(rows[i].office.ifEmptyDash()))),
                      DataCell(Center(child: Text(rows[i].notes.ifEmptyDash(), textAlign: TextAlign.center))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadChip(CollegeRosterMember m) {
    // مبتعث/معار/مجاز: غير متواجدين فعليًا لسبب مختلف جذريًا عن إعفاء
    // القياديين - شارة رمادية مستقلة توضّح آليتهم بدل شارة "معفى من
    // الإرشاد" الحمراء المعتادة، حتى لا يُفهَم أنهم مشغولون بمنصب فقط.
    if (_isAbsentMember(m)) {
      final color = Colors.grey.shade600;
      return Tooltip(
        message: m.advisingReason,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(_absenceLabel(m), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      );
    }

    final label = m.advisingLoad.label;
    return Tooltip(
      message: m.advisingReason,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: m.advisingLoad.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: m.advisingLoad.color.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(color: m.advisingLoad.color, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
}

extension _IfEmptyDash on String {
  String ifEmptyDash() => isEmpty ? '—' : this;
}
