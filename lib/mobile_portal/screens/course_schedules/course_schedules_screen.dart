import 'package:flutter/material.dart';

import '../../../data/course_catalog.dart';
import '../../../models/course_section_record.dart';
import '../../../services/course_schedule_repository.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/mobile_empty_state.dart';
import '../../widgets/mobile_error_state.dart';
import '../../widgets/mobile_loading_state.dart';
import '../../widgets/portal_app_bar_logo.dart';

const _kDepartments = [
  'قسم الإدارة',
  'قسم المحاسبة',
  'قسم التسويق',
  'قسم الاقتصاد والتمويل',
  'قسم نظم المعلومات الإدارية',
];

/// شاشة "الجداول الدراسية" - بتبويبين فرعيين بطلب سليمان صراحةً (2026-08-23)،
/// بنفس نمط تبويبَي "لوحة الإدارة": "المقررات الدراسية" (فلتر شطر/قسم) و
/// "الجدول الدراسي لعضو هيئة التدريس" (فلتر شطر + بحث بالاسم). نفس مصدر
/// بيانات الموقع (`CourseScheduleRepository`) بلا تكرار حساب - عرض جوّالي
/// مبسَّط (بطاقات) بدل جدول سطح المكتب الكامل.
class CourseSchedulesScreen extends StatefulWidget {
  const CourseSchedulesScreen({super.key});

  @override
  State<CourseSchedulesScreen> createState() => _CourseSchedulesScreenState();
}

class _CourseSchedulesScreenState extends State<CourseSchedulesScreen> {
  late Future<({List<CourseSectionRecord> male, List<CourseSectionRecord> female})> _future = _load();

  Future<({List<CourseSectionRecord> male, List<CourseSectionRecord> female})> _load() async {
    final results = await Future.wait([
      CourseScheduleRepository.loadSchedule(Shatr.male),
      CourseScheduleRepository.loadSchedule(Shatr.female),
    ]);
    return (male: results[0], female: results[1]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: kPortalAppBarLeadingWidth,
          leading: const PortalAppBarLogo(),
          title: const Text('الجداول الدراسية'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'المقررات الدراسية'),
              Tab(text: 'الجدول الدراسي'),
            ],
          ),
        ),
        body: FutureBuilder<({List<CourseSectionRecord> male, List<CourseSectionRecord> female})>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return MobileErrorState(onRetry: () => setState(() => _future = _load()));
            }
            if (!snapshot.hasData) {
              return const MobileLoadingState();
            }
            final data = snapshot.data!;
            return TabBarView(
              children: [
                _CoursesTab(male: data.male, female: data.female),
                _InstructorScheduleTab(male: data.male, female: data.female),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _ShatrFilter { all, male, female }

/// فلتر "التسكين" (هل عُيِّن محاضر للشعبة النظرية أم لا) - بطلب سليمان
/// صراحةً (2026-08-24)، بجانب فلتر الشطر مباشرة بتبويب "المقررات الدراسية".
enum _PlacementFilter { all, placed, unplaced }

/// تبويب "المقررات الدراسية" - فلتر شطر + قسم أعلى الصفحة، بطاقة لكل شعبة.
class _CoursesTab extends StatefulWidget {
  final List<CourseSectionRecord> male;
  final List<CourseSectionRecord> female;
  const _CoursesTab({required this.male, required this.female});

  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> {
  _ShatrFilter _shatr = _ShatrFilter.all;
  _PlacementFilter _placement = _PlacementFilter.all;
  String _department = 'الكل';

  String? _departmentOf(CourseSectionRecord r) => CourseCatalog.lookup(r.courseCode)?.department;

  // "مسكَّنة" = عُيِّن محاضر لشعبتها النظرية فعليًا - هي ما يُسجَّله الطالب
  // ويحدِّد هل المقرر جاهز للتدريس أم لا (بلا اعتبار للعملي وحده).
  bool _isPlaced(CourseSectionRecord r) => (r.instructorName ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final records = <(CourseSectionRecord, String)>[
      if (_shatr != _ShatrFilter.female) for (final r in widget.male) (r, 'شطر الطلاب'),
      if (_shatr != _ShatrFilter.male) for (final r in widget.female) (r, 'شطر الطالبات'),
    ].where((entry) {
      if (_department != 'الكل' && _departmentOf(entry.$1) != _department) return false;
      if (_placement == _PlacementFilter.placed && !_isPlaced(entry.$1)) return false;
      if (_placement == _PlacementFilter.unplaced && _isPlaced(entry.$1)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // صفّان منفصلان لا جنبًا إلى جنب - نصف العرض لكل منهما كان
              // يقصّ نص الشرائح فيصير غير مقروء على شاشة جوال ضيقة (سليمان
              // 2026-08-24: "أصبح لا يقرأ" بعد وضعهما بصف واحد).
              _ShatrFilterBar(value: _shatr, onChanged: (v) => setState(() => _shatr = v)),
              const SizedBox(height: 6),
              _PlacementFilterBar(value: _placement, onChanged: (v) => setState(() => _placement = v)),
              const SizedBox(height: 6),
              _DepartmentDropdown(value: _department, onChanged: (v) => setState(() => _department = v)),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const MobileEmptyState(message: 'لا توجد مقررات مطابقة', icon: Icons.menu_book_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final (record, shatrLabel) = records[i];
                    // يختفي تصنيف الشطر تلقائيًا لو اختير شطر محدَّد بالفلتر
                    // أعلاه (بديهي حينها بلا داعٍ لتكراره بكل بطاقة) - نفس
                    // قاعدة "إخفاء عمود الفلتر عند تحديده" المعتمَدة بكل
                    // جداول الموقع.
                    return _CourseCard(record: record, shatrLabel: _shatr == _ShatrFilter.all ? shatrLabel : null);
                  },
                ),
        ),
      ],
    );
  }
}

/// تبويب "الجدول الدراسي لعضو هيئة التدريس" - فلتر شطر + بحث بالاسم، ثم
/// جدول مواعيد المحاضر المختار.
class _InstructorScheduleTab extends StatefulWidget {
  final List<CourseSectionRecord> male;
  final List<CourseSectionRecord> female;
  const _InstructorScheduleTab({required this.male, required this.female});

  @override
  State<_InstructorScheduleTab> createState() => _InstructorScheduleTabState();
}

class _InstructorScheduleTabState extends State<_InstructorScheduleTab> {
  _ShatrFilter _shatr = _ShatrFilter.all;
  final _searchController = TextEditingController();
  String? _selectedInstructor;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CourseSectionRecord> get _pool => [
        if (_shatr != _ShatrFilter.female) ...widget.male,
        if (_shatr != _ShatrFilter.male) ...widget.female,
      ];

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    // اسم المحاضر قد يظهر كمحاضر نظري لمقرر ومحاضر عملي لآخر - كلا الحقلين
    // (سليمان 2026-08-23: "خصوصًا فيما يتعلق بالعملي والنظري" لم يكن يظهر
    // إطلاقًا لأن البحث/الجدول كانا يعتمدان على `instructorName` فقط).
    final names = _pool
        .expand((r) => [r.instructorName, r.practicalInstructorName])
        .whereType<String>()
        .where((n) => n.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final matchingNames = query.isEmpty ? <String>[] : names.where((n) => n.contains(query)).toList();

    final selected = _selectedInstructor;
    final schedule = selected == null
        ? <CourseSectionRecord>[]
        : _pool.where((r) => r.instructorName == selected || r.practicalInstructorName == selected).toList();

    return Column(
      children: [
        // ضغط رأسي شامل (فلتر + بحث) لإظهار أكبر قدر من الجدول بلا تمرير -
        // بطلب سليمان صراحةً (2026-08-24).
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShatrFilterBar(
                value: _shatr,
                onChanged: (v) => setState(() {
                  _shatr = v;
                  _selectedInstructor = null;
                }),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _searchController,
                style: AppTextStyles.caption(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'ابحث باسم عضو هيئة التدريس',
                  labelStyle: AppTextStyles.caption(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 0),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                ),
                onChanged: (_) => setState(() => _selectedInstructor = null),
              ),
            ],
          ),
        ),
        Expanded(
          child: selected != null
              ? _InstructorScheduleList(name: selected, records: schedule)
              : query.isEmpty
                  ? const MobileEmptyState(message: 'ابحث باسم عضو هيئة التدريس لعرض جدوله', icon: Icons.person_search_outlined)
                  : matchingNames.isEmpty
                      ? const MobileEmptyState(message: 'لا يوجد تطابق', icon: Icons.person_off_outlined)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          itemCount: matchingNames.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final name = matchingNames[i];
                            return ListTile(
                              title: Text(name, style: AppTextStyles.body()),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () => setState(() => _selectedInstructor = name),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

/// جدول مساعد للمحاضر - **كتلة جدول واحدة** بعمود "المقرر" مدمَج بصريًا
/// (يظهر مرة واحدة أعلى صفوف مادته فقط، لا يتكرر) بدل بطاقات منفصلة لكل
/// مادة - بطلب سليمان صراحةً (2026-08-24: "بحيث يظهر الجدول ككتلة واحدة").
/// المادة تبقى معاملة كوحدة واحدة (نظري+عملي معًا متتاليين)، لكن كل مواد
/// المحاضر الآن بجدول `Table` واحد بلا فواصل/حدود بين البطاقات.
class _InstructorScheduleList extends StatelessWidget {
  final String name;
  final List<CourseSectionRecord> records;
  const _InstructorScheduleList({required this.name, required this.records});

  @override
  Widget build(BuildContext context) {
    // كل شعبة (مادة) يظهر منها فقط الجزء الذي يُدرّسه هذا المحاضر تحديدًا -
    // قد يكون نظري فقط، عملي فقط، أو كلاهما لو كان محاضر الجزأين معًا.
    final courses = records.where((r) => r.instructorName == name || r.practicalInstructorName == name).toList();
    courses.sort((a, b) => a.courseName.compareTo(b.courseName));

    // مجموعات: (اسم المادة، صفوف مواعيدها [النوع/اليوم/الوقت/القاعة]).
    // عمود "المقرر" الآن Row جانبي (لا خلية Table عادية) يتمدَّد بارتفاع كل
    // صفوف مادته فيتوسّط رأسيًا حقًا مقابل المجموعة كاملة - بطلب سليمان
    // صراحةً (2026-08-24: "لا يظهر في متوسط الخلية... اجعله في المنتصف")،
    // فـ`Table` العادي لا يدعم دمج خلايا رأسيًا (rowspan) أصلًا.
    final groups = <(String course, String section, List<(String type, String day, String time, String room)> meetings)>[];
    for (final course in courses) {
      final meetings = <(String type, String day, String time, String room)>[
        if (course.instructorName == name)
          for (final m in course.meetings) ('نظري', m.dayName, '${m.from}\n${m.to}', m.room.isEmpty ? '-' : m.room),
        if (course.practicalInstructorName == name)
          for (final m in course.practicalMeetings) ('عملي', m.dayName, '${m.from}\n${m.to}', m.room.isEmpty ? '-' : m.room),
      ];
      // رقم الشعبة المعروض تحت اسم المقرر هو رقم الشعبة النظرية دائمًا (هي
      // ما يُسجَّله الطالب فعليًا) حتى لو كان المحاضر يُدرّس العملي فقط لهذه
      // الشعبة - بطلب سليمان صراحةً (2026-08-24).
      if (meetings.isNotEmpty) groups.add((course.courseName, course.theorySection, meetings));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      children: [
        Text(name, style: AppTextStyles.h3()),
        const SizedBox(height: AppSpacing.sm),
        if (groups.isEmpty)
          const MobileEmptyState(message: 'لا توجد مواعيد مسجَّلة لهذا المحاضر', icon: Icons.event_busy_outlined)
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: AppColors.background,
                  child: const Row(
                    children: [
                      Expanded(flex: 26, child: _HeaderText('المقرر')),
                      Expanded(flex: 22, child: _HeaderText('اليوم')),
                      Expanded(flex: 20, child: _HeaderText('الوقت')),
                      Expanded(flex: 14, child: _HeaderText('القاعة')),
                    ],
                  ),
                ),
                for (final group in groups)
                  Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1.4))),
                    // `IntrinsicHeight` يمنح الصف ارتفاعًا محدودًا فعليًا (أطول
                    // عنصر بداخله) قبل تطبيق `stretch` - بدونه يفشل التخطيط
                    // بصمت (شاشة بيضاء) لأن `Row` هنا داخل `ListView`/`Column`
                    // يستقبل قيدًا رأسيًا غير محدود (سليمان 2026-08-24).
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 26,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    group.$1,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (group.$2.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'شعبة ${group.$2}',
                                      textAlign: TextAlign.center,
                                      style: AppTextStyles.caption(color: Colors.black45),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 56,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final m in group.$3)
                                  Row(
                                    children: [
                                      Expanded(flex: 22, child: _dayWithTypeCell(day: m.$2, type: m.$1)),
                                      Expanded(flex: 20, child: _tableCell(m.$3)),
                                      Expanded(flex: 14, child: _tableCell(m.$4)),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tableCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption(color: Colors.black54),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  /// اليوم + شارة نظري/عملي معًا بنفس الخلية (بدل عمود "النوع" المستقل) -
  /// بطلب سليمان صراحةً (2026-08-24).
  Widget _dayWithTypeCell({required String day, required String type}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(day, textAlign: TextAlign.center, style: AppTextStyles.caption(color: Colors.black54)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: (type == 'نظري' ? AppColors.green : AppColors.gold).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                type,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: AppTextStyles.caption(color: type == 'نظري' ? AppColors.greenDark : AppColors.gold).copyWith(fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ),
          ],
        ),
      );
}

class _HeaderText extends StatelessWidget {
  final String text;
  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 6),
      child: Center(
        child: Text(text, textAlign: TextAlign.center, style: AppTextStyles.caption(color: Colors.black54).copyWith(fontWeight: FontWeight.w700, fontSize: 11)),
      ),
    );
  }
}

class _ShatrFilterBar extends StatelessWidget {
  final _ShatrFilter value;
  final ValueChanged<_ShatrFilter> onChanged;
  const _ShatrFilterBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: SegmentedButton<_ShatrFilter>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: AppTextStyles.caption().copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        segments: const [
          ButtonSegment(value: _ShatrFilter.all, label: Text('الكل')),
          ButtonSegment(value: _ShatrFilter.male, label: Text('طلاب')),
          ButtonSegment(value: _ShatrFilter.female, label: Text('طالبات')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _PlacementFilterBar extends StatelessWidget {
  final _PlacementFilter value;
  final ValueChanged<_PlacementFilter> onChanged;
  const _PlacementFilterBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: SegmentedButton<_PlacementFilter>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: AppTextStyles.caption().copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        segments: const [
          ButtonSegment(value: _PlacementFilter.all, label: Text('الكل')),
          ButtonSegment(value: _PlacementFilter.placed, label: Text('مسكَّنة')),
          ButtonSegment(value: _PlacementFilter.unplaced, label: Text('غير مسكَّنة')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _DepartmentDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _DepartmentDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      style: AppTextStyles.caption(color: Colors.black87),
      decoration: InputDecoration(
        labelText: 'القسم العلمي',
        labelStyle: AppTextStyles.caption(color: Colors.black54),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      ),
      items: [
        const DropdownMenuItem(value: 'الكل', child: Text('الكل')),
        for (final d in _kDepartments) DropdownMenuItem(value: d, child: Text(d.replaceFirst('قسم ', ''))),
      ],
      onChanged: (v) => onChanged(v ?? 'الكل'),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseSectionRecord record;
  final String? shatrLabel;
  const _CourseCard({required this.record, required this.shatrLabel});

  @override
  Widget build(BuildContext context) {
    // القاعة تُلحَق بكل موعد (سليمان 2026-08-24) - قد تختلف بين أيام الأسبوع
    // لنفس الشعبة، فتظهر بجانب موعدها تحديدًا لا كحقل واحد للشعبة كاملة.
    String meetingText(CourseMeeting m) => m.room.isEmpty ? '${m.dayName} ${m.from}-${m.to}' : '${m.dayName} ${m.from}-${m.to} (${m.room})';
    final theoryTimes = record.meetings.map(meetingText).join('، ');
    final hasPractical = record.practicalSection != null && record.practicalSection!.trim().isNotEmpty;
    final practicalTimes = record.practicalMeetings.map(meetingText).join('، ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${record.courseName} (${record.courseCode})', style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          // نظري وعملي جنبًا إلى جنب كوحدة واحدة (لا اسم محاضر مكرَّر هنا) -
          // بطلب سليمان صراحةً (2026-08-24).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SectionChip(label: 'نظري', section: record.theorySection, times: theoryTimes),
              ),
              if (hasPractical) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _SectionChip(label: 'عملي', section: record.practicalSection!, times: practicalTimes),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(_instructorLine(hasPractical: hasPractical), style: AppTextStyles.caption(color: AppColors.greenDark)),
              ),
              Text('المسجلين (${record.theoryRegistered})', style: AppTextStyles.caption(color: Colors.black45)),
            ],
          ),
          if (shatrLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(shatrLabel!, style: AppTextStyles.caption(color: Colors.black38)),
            ),
        ],
      ),
    );
  }

  /// اسم المحاضر مرة واحدة فقط (لا يتكرر لكل من نظري/عملي) - بطلب سليمان
  /// صراحةً. نفس الشخص عادةً يُدرّس الجزأين معًا فيظهر اسمه فقط؛ لو اختلف
  /// محاضر كل جزء تُذكر التفرقة صراحةً؛ لو لم يُسنَد أي محاضر بعد: "لم تُسكَّن".
  String _instructorLine({required bool hasPractical}) {
    final theory = record.instructorName?.trim();
    final practical = hasPractical ? record.practicalInstructorName?.trim() : null;

    if (!hasPractical) return (theory == null || theory.isEmpty) ? 'لم تُسكَّن بعد' : theory;

    final hasTheory = theory != null && theory.isNotEmpty;
    final hasPracticalInstructor = practical != null && practical.isNotEmpty;

    if (hasTheory && hasPracticalInstructor && theory == practical) return theory;
    if (hasTheory && hasPracticalInstructor) return 'نظري: $theory - عملي: $practical';
    if (hasTheory) return '$theory (نظري) - العملي لم يُسكَّن بعد';
    if (hasPracticalInstructor) return '$practical (عملي) - النظري لم يُسكَّن بعد';
    return 'لم تُسكَّن بعد';
  }
}

/// شارة "نظري"/"عملي" منفصلة داخل بطاقة المقرر - شعبة + مواعيدها فقط (بلا
/// اسم محاضر مكرَّر، يظهر مرة واحدة أسفل البطاقة بدلاً منه).
class _SectionChip extends StatelessWidget {
  final String label;
  final String section;
  final String times;
  const _SectionChip({required this.label, required this.section, required this.times});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (label == 'نظري' ? AppColors.green : AppColors.gold).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label, style: AppTextStyles.caption(color: label == 'نظري' ? AppColors.greenDark : AppColors.gold).copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text('شعبة $section', style: AppTextStyles.caption(color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          if (times.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(times, style: AppTextStyles.caption(color: Colors.black45)),
          ],
        ],
      ),
    );
  }
}
