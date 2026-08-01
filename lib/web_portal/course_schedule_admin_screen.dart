import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../data/course_catalog.dart';
import '../models/course_section_record.dart';
import '../services/course_schedule_repository.dart';
import '../data/instructor_offices.dart';
import '../services/course_table_pdf_service.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/instructor_schedule_pdf_service.dart';
import '../services/instructor_schedule_table.dart';
import '../theme/app_theme.dart';
import 'portal_footer.dart';

const String _kAllDepartments = 'كل الأقسام';
const String _kAllShatr = 'كل الشطرين';
const String _kUnscheduledOption = 'الشعب غير المسكَّنة';
const String _kAllSectionsOption = 'الكل';
const String _kAllDeptsFacultyOption = 'جميع الشعب لجميع الأقسام';

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

  const CourseScheduleAdminScreen({super.key, this.initialTabIndex = 0});

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

  String _shatrFilter = _kAllShatr;
  String _deptFilter = _kAllDepartments;
  final _searchCtrl = TextEditingController();

  late final TabController _tabController;

  // فلاتر شاشة عضو هيئة التدريس
  String? _facultyDept;
  Shatr? _facultyShatr;
  String? _facultyInstructor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      CourseScheduleRepository.loadSchedule(Shatr.male),
      CourseScheduleRepository.loadSchedule(Shatr.female),
      CourseScheduleRepository.currentExportDate(Shatr.male),
      CourseScheduleRepository.currentExportDate(Shatr.female),
    ]);
    if (!mounted) return;
    setState(() {
      _maleRecords = results[0] as List<CourseSectionRecord>;
      _femaleRecords = results[1] as List<CourseSectionRecord>;
      _maleExportDate = results[2] as DateTime?;
      _femaleExportDate = results[3] as DateTime?;
      _loading = false;
    });
  }

  Future<void> _uploadFor(Shatr shatr) async {
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
      } else {
        _uploadingFemale = true;
      }
    });

    try {
      final records = DocxScheduleParserService.parse(bytes);
      if (records.isEmpty) {
        throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف "الحوية" الصحيح بصيغة Word (.docx).');
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
            'تم استخراج ${records.length} شعبة فعلية من الملف لـ ${shatr.label}'
            '${exportDate != null ? ' (تاريخ السحب: ${DateFormat('yyyy/MM/dd').format(exportDate)})' : ''}.\n\n'
            'سيستبدل هذا آخر نسخة معتمدة لهذا الشطر بالكامل. هل تريد الاعتماد؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      await CourseScheduleRepository.saveSchedule(shatr, records, exportDate: exportDate);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد جدول ${shatr.label} بنجاح (${records.length} شعبة).')),
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

  List<_DisplayRow> get _filteredTableRows {
    final all = _buildDisplayRows(forFaculty: false);
    final search = _searchCtrl.text.trim();
    return all.where((row) {
      if (_shatrFilter != _kAllShatr) {
        final wanted = _shatrFilter == Shatr.male.label ? Shatr.male : Shatr.female;
        if (row.shatr != wanted) return false;
      }
      if (_deptFilter != _kAllDepartments) {
        final isOwn = row.department == _deptFilter;
        final isShared = CourseCatalog.isSharedAcrossDepartments(row.record.courseCode);
        if (!isOwn && !isShared) return false;
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('دليل تسكين المقررات وجداول أعضاء هيئة التدريس'),
        backgroundColor: AppColors.green,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          tabs: const [
            Tab(text: 'تسكين المقررات', icon: Icon(Icons.table_chart_outlined)),
            Tab(text: 'الجدول الدراسي لأعضاء هيئة التدريس', icon: Icon(Icons.person_search_outlined)),
          ],
        ),
      ),
      bottomNavigationBar: const PortalFooterBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBrandBanner(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildTableTab(), _buildFacultyTab()],
                  ),
                ),
              ],
            ),
    );
  }

  /// شريط هوية موحّد (شعاراسم الوحدة) - نسخة واحدة فقط أعلى الصفحة، تُعرض
  /// مرة واحدة لكلا التبويبين بدل تكرارها داخل كل تبويب على حدة.
  Widget _buildBrandBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.greenDark,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Image.asset('assets/images/unit_logo_light.png', height: 28, errorBuilder: (_, _, _) => const SizedBox()),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'وحدة الإرشاد الأكاديمي - كلية إدارة الأعمال',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableTab() {
    final rows = _filteredTableRows;
    return Column(
      children: [
        _buildUploadBar(),
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة'))
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
                          columns: [
                            const DataColumn(label: Text('القسم')),
                            const DataColumn(label: Text('رمز المقرر')),
                            const DataColumn(label: Text('اسم المقرر')),
                            const DataColumn(label: Text('نوع الخطة')),
                            if (_shatrFilter == _kAllShatr) const DataColumn(label: Text('الشطر')),
                            const DataColumn(label: Text('الشعبة')),
                            const DataColumn(label: Text('الأيام والوقت')),
                            const DataColumn(label: Text('المحاضر')),
                            const DataColumn(label: Text('ملاحظات')),
                          ],
                          rows: [
                            for (var i = 0; i < rows.length; i++)
                              DataRow(
                                color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7F5EF)),
                                cells: [
                                  DataCell(Text(rows[i].department)),
                                  DataCell(Text(rows[i].record.courseCode)),
                                  DataCell(Text(rows[i].record.courseName)),
                                  DataCell(Text(rows[i].plans.join(' / '))),
                                  if (_shatrFilter == _kAllShatr) DataCell(_shatrChip(rows[i].shatr)),
                                  DataCell(_sectionCell(rows[i].record)),
                                  DataCell(_meetingsCell(rows[i].record)),
                                  DataCell(_instructorCell(rows[i].record)),
                                  DataCell(Text(rows[i].catalogNote ?? '—')),
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

  Widget _buildUploadBar() {
    final fmt = DateFormat('yyyy/MM/dd');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _uploadingMale ? null : () => _uploadFor(Shatr.male),
            icon: _uploadingMale
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('رفع جدول الطلاب'),
          ),
          Text(
            _maleExportDate != null ? 'تاريخ سحب البيانات: ${fmt.format(_maleExportDate!)}' : 'لم يُرفع بعد',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(width: 24),
          FilledButton.icon(
            onPressed: _uploadingFemale ? null : () => _uploadFor(Shatr.female),
            icon: _uploadingFemale
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('رفع جدول الطالبات'),
          ),
          Text(
            _femaleExportDate != null ? 'تاريخ سحب البيانات: ${fmt.format(_femaleExportDate!)}' : 'لم يُرفع بعد',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
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
          DropdownMenu<String>(
            label: const Text('القسم'),
            initialSelection: _deptFilter,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: _kAllDepartments, label: _kAllDepartments),
              ...CourseCatalog.departments.map((d) => DropdownMenuEntry(value: d, label: d)),
            ],
            onSelected: (v) => setState(() => _deptFilter = v ?? _kAllDepartments),
          ),
          DropdownMenu<String>(
            label: const Text('الشطر'),
            initialSelection: _shatrFilter,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: _kAllShatr, label: _kAllShatr),
              DropdownMenuEntry(value: Shatr.male.label, label: Shatr.male.label),
              DropdownMenuEntry(value: Shatr.female.label, label: Shatr.female.label),
            ],
            onSelected: (v) => setState(() => _shatrFilter = v ?? _kAllShatr),
          ),
          SizedBox(
            width: 260,
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
          FilledButton.icon(
            onPressed: () async => Printing.sharePdf(bytes: await _buildCourseTablePdf(), filename: 'دليل_مقررات_الحذف_والإضافة.pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('عرض PDF'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          ),
          OutlinedButton.icon(
            onPressed: () async => Printing.layoutPdf(onLayout: (_) async => _buildCourseTablePdf()),
            icon: const Icon(Icons.print_outlined),
            label: const Text('طباعة'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: BorderSide(color: AppColors.green)),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildCourseTablePdf() async {
    final rows = _filteredTableRows;
    final showShatr = _shatrFilter == _kAllShatr;
    String meetingsText(List<CourseMeeting> meetings) => meetings.isEmpty
        ? InstructorScheduleTable.noTimePlaceholder
        : meetings.map((m) => '${m.dayName} ${m.from}-${m.to}').join('\n');

    final pdfRows = rows.map((row) {
      final r = row.record;
      return CourseTablePdfRow(
        department: row.department,
        courseCode: r.courseCode,
        courseName: r.courseName,
        plans: row.plans.join(' / '),
        shatrLabel: showShatr ? row.shatr.label : null,
        theorySection: r.theorySection,
        practicalSection: r.practicalSection,
        meetingsText: meetingsText(r.meetings),
        practicalMeetingsText: r.practicalSection == null ? null : meetingsText(r.practicalMeetings),
        instructorName: r.instructorName ?? 'لم تُسكَّن بعد',
        practicalInstructorName:
            (r.practicalSection != null && r.practicalInstructorName != null && r.practicalInstructorName != r.instructorName)
                ? r.practicalInstructorName
                : null,
        note: row.catalogNote ?? '—',
      );
    }).toList();

    return CourseTablePdfService.build(rows: pdfRows, showShatrColumn: showShatr);
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

  /// عند وجود شعبة عملية مرتبطة، تُقسَّم الخلية إلى صفّين: الأعلى للنظري
  /// والأسفل للعملي (بدل دمجهما في سطر واحد) حسب طلب المستخدم صراحةً.
  Widget _splitCell(Widget theoryRow, Widget practicalRow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        theoryRow,
        const Padding(padding: EdgeInsets.symmetric(vertical: 3), child: Divider(height: 1)),
        practicalRow,
      ],
    );
  }

  Widget _sectionCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return Text(r.theorySection);
    return _splitCell(Text(r.theorySection), Text(r.practicalSection!));
  }

  Widget _meetingsListText(List<CourseMeeting> meetings) {
    if (meetings.isEmpty) return const Text(InstructorScheduleTable.noTimePlaceholder);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: meetings
          .map((m) => Text('${m.dayName}  ${m.from} - ${m.to}', style: const TextStyle(fontSize: 12)))
          .toList(),
    );
  }

  Widget _meetingsCell(CourseSectionRecord r) {
    if (r.practicalSection == null) return _meetingsListText(r.meetings);
    return _splitCell(_meetingsListText(r.meetings), _meetingsListText(r.practicalMeetings));
  }

  Widget _instructorCell(CourseSectionRecord r) {
    const unassigned = 'لم تُسكَّن بعد';
    if (r.practicalSection == null || r.practicalInstructorName == null || r.practicalInstructorName == r.instructorName) {
      return Text(r.instructorName ?? unassigned);
    }
    return _splitCell(
      Text(r.instructorName ?? unassigned),
      Text(r.practicalInstructorName!),
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

    final instructorNames = rowsForDeptShatr
        .map((r) => r.record.instructorName)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    // عبر كل الأقسام لا تُعرض أسماء أعضاء بعينهم (لأنها سياق قسم محدد) لكن
    // خياري "الكل" و"الشعب غير المسكَّنة" يبقيان متاحين.
    final dropdownOptions = isAllDepts
        ? [_kAllSectionsOption, _kUnscheduledOption]
        : [_kAllSectionsOption, _kUnscheduledOption, ...instructorNames];

    // "غير مسكَّنة" تعني تحديدًا: لا يوجد اسم عضو هيئة تدريس مُعيَّن لهذه
    // الشعبة (نظري بلا محاضر، أو عملي موجود بلا محاضر خاص به) - وليس عن
    // غياب اليوم/الوقت.
    bool isUnscheduled(_DisplayRow r) =>
        r.record.instructorName == null ||
        (r.record.practicalSection != null && r.record.practicalInstructorName == null);

    final selectedRows = switch (_facultyInstructor) {
      null => const <_DisplayRow>[],
      _kAllSectionsOption => rowsForDeptShatr,
      _kUnscheduledOption => rowsForDeptShatr.where(isUnscheduled).toList(),
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
              DropdownMenu<String>(
                label: const Text('القسم'),
                initialSelection: _facultyDept,
                dropdownMenuEntries: deptOptions.map((d) => DropdownMenuEntry(value: d, label: d)).toList(),
                onSelected: (v) => setState(() {
                  _facultyDept = v;
                  _facultyInstructor = null;
                }),
              ),
              DropdownMenu<Shatr>(
                label: const Text('الشطر'),
                initialSelection: _facultyShatr,
                dropdownMenuEntries: shatrOptions
                    .map((s) => DropdownMenuEntry(value: s, label: s.label))
                    .toList(),
                onSelected: (v) => setState(() {
                  _facultyShatr = v;
                  _facultyInstructor = null;
                }),
              ),
              DropdownMenu<String>(
                label: const Text('عضو هيئة التدريس'),
                enabled: _facultyDept != null && _facultyShatr != null,
                initialSelection: _facultyInstructor,
                dropdownMenuEntries: dropdownOptions.map((n) => DropdownMenuEntry(value: n, label: n)).toList(),
                onSelected: (v) => setState(() => _facultyInstructor = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_facultyInstructor) {
            null => Center(
                child: Text(
                  isAllDepts
                      ? 'اختر الشطر ثم "الكل" أو "الشعب غير المسكَّنة" لعرض شعب الكلية'
                      : 'اختر القسم والشطر واسم العضو لعرض جدوله',
                ),
              ),
            _kAllSectionsOption =>
              _buildSectionsListCard(isAllDepts ? 'جميع شعب الكلية' : 'جميع شعب القسم', selectedRows),
            _kUnscheduledOption => _buildSectionsListCard('الشعب غير المسكَّنة', selectedRows),
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
    final records = rows.map((r) => r.record).toList();
    final tableRows = InstructorScheduleTable.buildRows(records);
    final totalHours = InstructorScheduleTable.totalCreditHours(records);
    final department = _facultyDept ?? '';

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

  /// يُطابق اسم العضو مع بيانات "جدول الإرشاد الأكاديمي" (المصدر الوحيد
  /// المتوفر حاليًا لرقم المكتب)؛ يُترك فارغًا لأي عضو غير مطابق حتى تتوفر
  /// بيانات إضافية مستقبلًا.
  String? _officeNumberFor(String instructorName) => InstructorOffices.lookup(instructorName);

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
