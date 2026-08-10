import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/advising_load_rules.dart';
import '../data/faculty_sort_order.dart';
import '../data/teaching_load_regulation.dart';
import '../data/teaching_quota_status.dart';
import '../models/college_roster_member.dart';
import '../models/course_section_record.dart';
import '../services/college_roster_parser_service.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_repository.dart';
import '../services/xlsx_metadata_service.dart';
import '../theme/app_theme.dart';
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
  return text.contains('مبتعث') || text.contains('معار') || text.contains('مجاز');
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
  bool _uploading = false;

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

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ بيانات منسوبي الكلية'),
        content: const Text('سيُحذَف كل ما هو مخزَّن حاليًا (لتسهيل إعادة اختبار الرفع). هل تريد المتابعة؟'),
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
    if (confirmed != true) return;
    await CollegeRosterRepository.clear();
    await _loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تفريغ البيانات.')));
  }

  /// يفحص عمودي "نصاب الإرشاد" و"النصاب التدريسي" لكل عضو مقابل القيم
  /// المعتمدة فقط - بديل عن قائمة منسدلة داخل ملف الإكسل (لا يدعمها قارئ
  /// الموقع، انظر lib/data/advising_load_rules.dart). يُرجع سطرًا تحذيريًا
  /// لكل قيمة غريبة (اسم العضو + العمود + القيمة المكتوبة) لعرضها في حوار
  /// التأكيد قبل الاعتماد - تنبيه فقط، لا يمنع الرفع.
  List<String> _invalidQuotaValues(List<CollegeRosterMember> members) {
    final lines = <String>[];
    for (final m in members) {
      final advising = m.advisingQuotaNote.trim();
      if (advising.isNotEmpty && !AdvisingLoadRules.validAdvisingQuotaValues.contains(advising)) {
        lines.add('${m.name} - نصاب الإرشاد: "$advising"');
      }
      final teaching = m.quotaReductionNote.trim();
      if (teaching.isNotEmpty && !TeachingLoadRegulation.validQuotaReductionValues.contains(teaching)) {
        lines.add('${m.name} - النصاب التدريسي: "$teaching"');
      }
    }
    return lines;
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final Uint8List bytes = result.files.single.bytes!;

    setState(() => _uploading = true);
    try {
      final members = CollegeRosterParserService.parse(bytes);
      if (members.isEmpty) {
        throw Exception(
          'لم يتم العثور على أي منسوب في الملف - تأكد من أنه الملف الرسمي '
          '(قالب_بيانات_منسوبي_الكلية_الرسمي.xlsx) بورقتيه الأصليتين.',
        );
      }

      final fileSavedAt = XlsxMetadataService.lastSavedAt(bytes);
      final currentSavedAt = await CollegeRosterRepository.currentLastSavedAt();
      if (fileSavedAt != null && currentSavedAt != null && !fileSavedAt.isAfter(currentSavedAt)) {
        final fmt = DateFormat('yyyy/MM/dd HH:mm');
        throw Exception(
          'تاريخ آخر حفظ لهذا الملف (${fmt.format(fileSavedAt)}) ليس أحدث من تاريخ آخر نسخة معتمدة '
          '(${fmt.format(currentSavedAt)}). تأكد من رفع أحدث نسخة محفوظة من الملف.',
        );
      }

      if (!mounted) return;
      final facultyCount = members.where((m) => m.type == CollegeMemberType.faculty).length;
      final adminCount = members.length - facultyCount;
      final invalidQuotaValues = _invalidQuotaValues(members);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الاعتماد'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تم استخراج ${members.length} منسوبًا من الملف ($facultyCount عضو هيئة تدريس، $adminCount إداري)'
                  '${fileSavedAt != null ? '\nتاريخ آخر حفظ للملف: ${DateFormat('yyyy/MM/dd HH:mm').format(fileSavedAt)}' : ''}.\n\n'
                  'سيستبدل هذا بيانات منسوبي الكلية المخزَّنة حاليًا بالكامل. هل تريد الاعتماد؟',
                ),
                if (invalidQuotaValues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'تنبيه: قيم غير معروفة في عمودي "نصاب الإرشاد"/"النصاب التدريسي" '
                    '(قد تكون خطأ إملائي - سيُتعامَل معها كأنها فارغة):',
                    style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...invalidQuotaValues.map((line) => Text('- $line', style: TextStyle(color: Colors.orange.shade800))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
          ],
        ),
      );
      if (confirmed != true) return;

      await CollegeRosterRepository.save(members, lastSavedAt: fileSavedAt);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد بيانات منسوبي الكلية بنجاح (${members.length} منسوب).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر قراءة الملف: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  List<CollegeRosterMember> get _typedMembers => _members.where((m) => m.type == _typeFilter).toList();

  List<String> get _departments =>
      _typedMembers.map((m) => m.department).where((d) => d.isNotEmpty).toSet().toList()..sort();

  // ترتيب مناصب الإداريين حسب تعليمات صريحة - الأكثر تحديدًا يُفحص أولًا.
  static const List<String> _adminTiers = [
    'مستشار',
    'مدير إدارة',
    'مدير مكتب',
    'مساعد مدير إدارة',
    'إدارة الكلية',
  ];

  int _adminTierIndex(CollegeRosterMember m) {
    final text = [m.position, m.position2, m.position3].join(' ');
    for (var i = 0; i < _adminTiers.length; i++) {
      if (text.contains(_adminTiers[i])) return i;
    }
    return _adminTiers.length;
  }

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
    } else {
      // فرز الإداريين: الجهة، ثم الشطر (طلاب قبل طالبات)، ثم مستوى المنصب
      // حسب ترتيب صريح، ثم الاسم.
      list.sort((a, b) {
        final d = a.department.compareTo(b.department);
        if (d != 0) return d;
        final s = FacultySortOrder.shatrRank(a.shatr).compareTo(FacultySortOrder.shatrRank(b.shatr));
        if (s != 0) return s;
        final t = _adminTierIndex(a).compareTo(_adminTierIndex(b));
        if (t != 0) return t;
        return a.name.compareTo(b.name);
      });
    }

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

  Widget _buildUploadBar() {
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: const Text('رفع ملف منسوبي الكلية'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
                if (_lastSavedAt != null)
                  IconButton(
                    tooltip: 'تفريغ البيانات (للاختبار)',
                    onPressed: _clearData,
                    icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade700),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _lastSavedAt != null ? 'آخر نسخة معتمدة: ${fmt.format(_lastSavedAt!)}' : 'لم يُرفع بعد',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
          // متاح الآن للإداريين أيضًا بعد إضافة عمود "الشطر" لورقتهم.
          DropdownMenu<String>(
            label: const Text('الشطر'),
            initialSelection: _shatrFilter,
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: _kAllShatr, label: _kAllShatr),
              DropdownMenuEntry(value: 'طلاب', label: 'طلاب'),
              DropdownMenuEntry(value: 'طالبات', label: 'طالبات'),
            ],
            onSelected: (v) => setState(() => _shatrFilter = v ?? _kAllShatr),
          ),
          DropdownMenu<String>(
            key: ValueKey(_typeFilter),
            label: const Text('القسم / الجهة'),
            initialSelection: _deptFilter,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: _kAllDepartments, label: _kAllDepartments),
              ..._departments.map((d) => DropdownMenuEntry(value: d, label: d)),
            ],
            onSelected: (v) => setState(() => _deptFilter = v ?? _kAllDepartments),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'بحث بالاسم',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
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
