import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/course_catalog.dart';
import '../models/advising_schedule.dart';
import '../models/college_roster_member.dart';
import '../services/advising_schedule_excel_service.dart';
import '../services/advising_schedule_pdf_service.dart';
import '../services/advising_schedule_repository.dart';
import '../services/advising_schedule_signage_image_service.dart';
import '../services/college_roster_repository.dart';
import '../services/excel_parser_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import '../theme/filter_pills.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';
import 'upload_hub_screen.dart';

// دمج "عبد" مع الكلمة التالية بلا مسافة ("عبد الرحمن" -> "عبدالرحمن") قبل
// تقسيم الكلمات - وإلا تفشل المطابقة صامتًا بين ملف مصدر يكتبها بمسافة
// وملف آخر (منسوبي الكلية) يكتبها بلا مسافة، فيبقى المرشد في ترتيبه الأصلي
// غير المرتَّب بدل رتبته العلمية الصحيحة (سليمان 2026-08-10: "مازن عبد
// الرحمن المنجومي" لم يُطابَق فبقي بمكانه العشوائي رغم كونه معيدًا).
// توحيد التاء المربوطة/الهاء ("نورة" مقابل "نوره" لنفس الشخص بملفين
// مختلفين) - بدونه تفشل المطابقة صامتًا لأي اسم ينتهي بأحدهما بصيغة مغايرة
// عن الملف الآخر (اكتُشف 2026-08-10 أثناء تدقيق شامل: "نورة السفياني" و
// "لطيفة الزهراني" لم يُطابَقا رغم وجودهما فعليًا بجدول الإرشاد).
// "أبو X" نفس مشكلة "عبد X" بالضبط (مسافة بمصدر، بلا مسافة بآخر لنفس
// الشخص - مثال حقيقي: "عوض عمر أبو مالح" بجدول الإرشاد مقابل "عوض عمر علي
// ابومالح" بملف منسوبي الكلية).
// توحيد الألف المقصورة/الياء ("حلمى" مقابل "حلمي" لنفس الشخص بملفين
// مختلفين) - نفس فئة خلل التاء المربوطة/الهاء (اكتُشف 2026-08-10: "طارق
// حلمى" بملف منسوبي الكلية لم يُطابَق مع "طارق حلمي" بجدول الإرشاد رغم
// وجود فترة فعلية له).
// توحيد الهمزة على الياء (ئ) مع الياء العادية ("فائز" مقابل "فايز")، وحذف
// الهمزة المفردة (ء) خصوصًا بنهاية الاسم ("هناء" مقابل "هنا") - نفس فئة
// أخطاء التاء المربوطة/الألف المقصورة، اكتُشفت بمراجعة يدوية حرفًا بحرف
// لكل حالة "ناقصة" (سليمان 2026-08-10: "هذا موضوع حساس جدًا، يجب التطابق
// والتأكد" - راجعتُ كل اسم مقابل قائمة الموقع الحي كاملة قبل هذا الإصلاح).
String _normalizeArabic(String s) => s
    .trim()
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll('ئ', 'ي')
    .replaceAll('ء', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'عبد\s+'), 'عبد')
    .replaceAll(RegExp(r'ابو\s+'), 'ابو');

// كلمات صلة قد تُذكر بمصدر وتُحذَف بآخر لنفس الشخص تمامًا ("عبد الله بن
// مداري الحربي" بملف الإرشاد مقابل "عبد الله مداري عبدالله الحربي" بملف
// منسوبي الكلية بلا "بن") - تُستبعَد من كلا الجانبين قبل المطابقة، وإلا
// تفشل المطابقة صامتًا فيبقى المرشد بترتيب عشوائي بدل رتبته العلمية
// الصحيحة (سليمان 2026-08-10).
const _nameFillerWords = {'بن', 'بنت', 'ابن', 'آل', 'ال'};

// اسم جدول الإرشاد غالبًا مختصر مقارنة بالاسم الكامل في قاعدة بيانات
// المنسوبين - نعتبر تطابقًا لو كانت كل كلمات الاسم المختصر (بلا كلمات
// الصلة) موجودة ضمن كلمات الاسم الكامل.
bool _isSubsetMatch(String shortName, String fullName) {
  final shortWords = shortName.split(' ').where((w) => w.isNotEmpty && !_nameFillerWords.contains(w));
  final fullWords =
      fullName.split(' ').where((w) => w.isNotEmpty && !_nameFillerWords.contains(w)).toSet();
  if (shortWords.isEmpty) return false;
  return shortWords.every(fullWords.contains);
}

/// شاشة موحّدة لبناء جدول توزيع فترات الإرشاد الأكاديمي بهوية بصرية واحدة
/// لكل الأقسام - بديلة عن التصاميم المتفرّقة التي كان كل قسم يبنيها بنفسه.
class AdvisingScheduleAdminScreen extends StatefulWidget {
  const AdvisingScheduleAdminScreen({super.key});

  @override
  State<AdvisingScheduleAdminScreen> createState() => _AdvisingScheduleAdminScreenState();
}

const String _kAllDepartments = 'الكل';
const String _kAllShatr = 'الكل';

class _AdvisingScheduleAdminScreenState extends State<AdvisingScheduleAdminScreen> {
  String _department = _kAllDepartments;
  String _shatr = _kAllShatr;
  List<AdvisingScheduleSlot> _slots = [];
  Map<(String, String), List<AdvisingScheduleSlot>> _filteredData = {};
  bool _loading = false;

  bool get _isAllDepartments => _department == _kAllDepartments;
  bool get _isAllShatr => _shatr == _kAllShatr;
  bool get _isFiltered => _isAllDepartments || _isAllShatr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// يجمع بيانات كل تركيبة (قسم، شطر) تطابق الفلتر الحالي - قسم واحد أو
  /// "الكل"، × شطر واحد أو "الكل" كلٌ على حدة (مثال: كل الأقسام لكن شطر
  /// الطلاب فقط) - مصدر واحد مشترك للعرض على الشاشة وبناء تقرير PDF معًا.
  Future<Map<(String, String), List<AdvisingScheduleSlot>>> _loadFilteredData() async {
    final departments = _isAllDepartments ? CourseCatalog.departments : [_department];
    final shatrList = _isAllShatr
        ? [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]
        : [_shatr];

    final all = <(String, String), List<AdvisingScheduleSlot>>{};
    for (final department in departments) {
      for (final shatr in shatrList) {
        final slots = await AdvisingScheduleRepository.load(department, shatr);
        if (slots.isNotEmpty) all[(department, shatr)] = slots;
      }
    }
    return all;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_isFiltered) {
      final data = await _loadFilteredData();
      if (!mounted) return;
      setState(() {
        _filteredData = data;
        _slots = [];
        _loading = false;
      });
      return;
    }
    final slots = await AdvisingScheduleRepository.load(_department, _shatr);
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _filteredData = {};
      _loading = false;
    });
  }

  bool _downloadingTemplate = false;

  /// يبني خريطة (قسم، شطر) ← (اسم ← رقم مكتب) لكل أعضاء هيئة التدريس - بلا
  /// أي استثناء لأصحاب المناصب (قد يترك أحدهم منصبه). الأسماء من ملف
  /// منسوبي الكلية المعتمد (يُطابَق قسمه الفعلي مع القوائم الخمس المعتمدة
  /// حتى لو اختلفت صياغة الهمزة)، ورقم المكتب (إن عُرف) من الجدول الحالي
  /// المرفوع عبر الموقع (مطابقة مرنة تتحمّل اختلاف صيغة الاسم بين الملفين).
  Future<Map<(String, String), Map<String, String>>> _buildMembersByDeptShatr() async {
    final roster = await CollegeRosterRepository.load();

    final knownOffices = <String, String>{}; // اسم مطبَّع من الجدول ← مكتب
    for (final department in CourseCatalog.departments) {
      for (final shatr in [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]) {
        final slots = await AdvisingScheduleRepository.load(department, shatr);
        for (final slot in slots) {
          for (final entry in slot.entries) {
            if (entry.office.isEmpty) continue;
            knownOffices.putIfAbsent(_normalizeArabic(entry.advisorName), () => entry.office);
          }
        }
      }
    }

    String officeFor(String name) {
      final normalized = _normalizeArabic(name);
      final direct = knownOffices[normalized];
      if (direct != null) return direct;
      final match = knownOffices.entries.firstWhere(
        (e) => _isSubsetMatch(e.key, normalized),
        orElse: () => const MapEntry('', ''),
      );
      return match.value;
    }

    final result = <(String, String), Map<String, String>>{
      for (final d in CourseCatalog.departments)
        for (final s in [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]) (d, s): <String, String>{},
    };
    for (final member in roster) {
      if (member.type != CollegeMemberType.faculty) continue;
      final deptKey = _normalizeArabic(member.department.replaceFirst(RegExp(r'^قسم\s+'), ''));
      final matchedDept = CourseCatalog.departments.firstWhere(
        (d) => _normalizeArabic(d.replaceFirst(RegExp(r'^قسم\s+'), '')).contains(deptKey) || deptKey.contains(_normalizeArabic(d.replaceFirst(RegExp(r'^قسم\s+'), ''))),
        orElse: () => '',
      );
      if (matchedDept.isEmpty) continue;
      final shatrKey = member.shatr.contains('طالبات') ? ExcelParserService.shatrFemale : ExcelParserService.shatrMale;
      result[(matchedDept, shatrKey)]![member.name] = officeFor(member.name);
    }
    return result;
  }

  Future<void> _downloadTemplate() async {
    setState(() => _downloadingTemplate = true);
    try {
      final membersByDeptShatr = await _buildMembersByDeptShatr();
      final bytes = AdvisingScheduleExcelService.buildTemplate(membersByDeptShatr: membersByDeptShatr);
      await downloadBytes(bytes, 'نموذج_توزيع_فترات_الإرشاد.xlsx');
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  /// يبني تقريرًا يغطّي أي تركيبة يختارها المستخدم: قسم واحد أو "الكل"، ×
  /// شطر واحد أو "الكل" - القسم و/أو الشطر قد يكونا "الكل" كلٌ على حدة
  /// (مثال: كل الأقسام لكن شطر الطلاب فقط)، بدل الاقتصار على "الكل" للقسم
  /// فقط.
  Future<Uint8List> _buildFilteredPdf({required bool signage}) async {
    final all = _isFiltered ? _filteredData : await _loadFilteredData();
    return AdvisingSchedulePdfService.buildAll(byDeptShatr: all, signage: signage);
  }

  /// يغلّف أي عملية PDF/طباعة بمعالجة أخطاء ظاهرة للمستخدم - بدونها كان أي
  /// استثناء (مثلاً فشل تحميل بيانات منسوبي الكلية) يفشل بصمت تام بلا أي
  /// رسالة، فيبدو للمستخدم وكأن الزر "لا يعمل" دون تفسير.
  Future<void> _runPdfAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      AppNotice.error(context, 'تعذّر إنشاء الملف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'توزيع فترات الإرشاد',
      navItems: buildAdminNavItems(context, current: 'advising-hub'),
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.schedule, isSuperAdmin: isSuperAdmin),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: AdvisingPageHeader(
                  breadcrumbTrail: 'توزيع فترات الإرشاد',
                  title: 'توزيع فترات الإرشاد',
                  description: 'عرض وتصدير جداول فترات الإرشاد حسب الشطر والقسم.',
                  icon: Icons.schedule_outlined,
                ),
              ),
            ),
          ),
          _buildToolbar(),
          _buildReportSection(),
          const Divider(height: 1),
          Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _buildPreview()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterResetChip(
                active: _shatr == _kAllShatr && _department == _kAllDepartments,
                onTap: () {
                  setState(() {
                    _shatr = _kAllShatr;
                    _department = _kAllDepartments;
                  });
                  _load();
                },
              ),
              FilterPillDropdown<String>(
                label: 'الشطر',
                value: _shatr == _kAllShatr ? null : _shatr,
                items: const [ExcelParserService.shatrMale, ExcelParserService.shatrFemale],
                itemLabel: (v) => v,
                onChanged: (v) {
                  setState(() => _shatr = v ?? _kAllShatr);
                  _load();
                },
              ),
              FilterPillDropdown<String>(
                label: 'القسم',
                value: _department == _kAllDepartments ? null : _department,
                items: CourseCatalog.departments,
                itemLabel: (v) => v,
                onChanged: (v) {
                  setState(() => _department = v ?? _kAllDepartments);
                  _load();
                },
              ),
              Container(width: 1, height: 34, color: Colors.grey.shade300),
              _ToolbarButton(
                onPressed: _downloadingTemplate ? null : _downloadTemplate,
                loading: _downloadingTemplate,
                icon: Icons.download_outlined,
                label: 'تنزيل نموذج Excel',
                color: AppColors.greenDark,
              ),
              _ToolbarButton(
                // رفع الجدول مركزي بصفحة "رفع وتنزيل الملفات" فقط - لا تنفيذ
                // رفع مستقل ثانٍ هنا لنفس البيانات (تجنّب تكرار منطق الرفع
                // والتحقق - سليمان 2026-08-22). هذا الزر ينقل فقط لتلك الصفحة.
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UploadHubScreen()),
                ),
                loading: false,
                icon: Icons.upload_file,
                label: 'الانتقال إلى رفع الملفات',
                color: AppColors.greenDark,
                filled: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportSection() {
    final deptLabel = _isAllDepartments ? 'كل الأقسام' : _department;
    final shatrLabel = _isAllShatr ? 'كل الشطرين' : _shatr;
    final fileTag = '${_isAllDepartments ? 'كل_الأقسام' : _department}_${_isAllShatr ? 'كل_الشطرين' : _shatr}';

    final card = _ReportCard(
      title: 'تقرير $deptLabel ($shatrLabel)',
      enabled: !_isFiltered ? _slots.isNotEmpty : true,
      onOfficialView: () => _runPdfAction(() async => Printing.sharePdf(
            bytes: await _buildFilteredPdf(signage: false),
            filename: 'توزيع_فترات_الإرشاد_$fileTag.pdf',
          )),
      onOfficialPrint: () =>
          _runPdfAction(() => Printing.layoutPdf(onLayout: (_) async => _buildFilteredPdf(signage: false))),
      onSignageView: () => _runPdfAction(() async => Printing.sharePdf(
            bytes: await _buildFilteredPdf(signage: true),
            filename: 'شاشات_العرض_توزيع_فترات_الإرشاد_$fileTag.pdf',
          )),
      onSignageImagesZip: () => _runPdfAction(() async {
        final all = _isFiltered ? _filteredData : await _loadFilteredData();
        final zipBytes = await AdvisingScheduleSignageImageService.buildZip(byDeptShatr: all);
        await downloadBytes(zipBytes, 'شاشات_العرض_$fileTag.zip');
      }),
    );

    return Container(
      width: double.infinity,
      color: const Color(0xFFF7F5EF),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [card],
      ),
    );
  }

  // ترتيب الأيام بترتيب الأسبوع الفعلي (لا بترتيب ورودها بالملف)، والفترات
  // داخل كل يوم بترتيب الوقت - بدونه كانت الفترات تظهر بترتيب عشوائي
  // (سليمان 2026-08-10).
  static int _dayOrder(String label) {
    final i = AdvisingScheduleExcelService.dayColumnLabels.indexOf(label);
    return i == -1 ? AdvisingScheduleExcelService.dayColumnLabels.length : i;
  }

  static int _periodOrder(String label) {
    final i = AdvisingScheduleExcelService.periodOptions.indexWhere(label.startsWith);
    return i == -1 ? AdvisingScheduleExcelService.periodOptions.length : i;
  }

  Widget _buildPreview() {
    if (_isFiltered) return _buildFilteredPreview();
    if (_slots.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: AdvisingEmptyState(
            icon: Icons.event_busy_outlined,
            title: 'لا يوجد جدول محفوظ',
            description: 'لا يوجد جدول محفوظ لهذا القسم/الشطر بعد.\nنزّل النموذج وارفعه بعد تعبئته من شريط الأدوات أعلاه.',
          ),
        ),
      );
    }

    final sortedSlots = [..._slots]
      ..sort((a, b) {
        final dayCompare = _dayOrder(a.dayLabel).compareTo(_dayOrder(b.dayLabel));
        if (dayCompare != 0) return dayCompare;
        return _periodOrder(a.periodLabel).compareTo(_periodOrder(b.periodLabel));
      });

    final byDay = <String, List<AdvisingScheduleSlot>>{};
    for (final s in sortedSlots) {
      byDay.putIfAbsent(s.dayLabel, () => []).add(s);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: byDay.entries.map((day) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.green)),
                  const Divider(),
                  for (final slot in day.value) ...[
                    Text('الفترة: ${AdvisingScheduleExcelService.periodDisplayLabel(slot.periodLabel)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: slot.entries
                          .map((e) => AdvisingAdvisorChip(label: '${e.advisorName} (مكتب ${e.office})'))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// عرض الشاشة عند اختيار "الكل" لأحد الفلترين (أو كليهما) - كان يظهر
  /// نص "اختر قسمًا وشطرًا محدَّدين" بلا أي بيانات (سليمان 2026-08-10: "لا
  /// يمكن اظهار الاسماء الا اذا اخترت قسم وشطر"). العرض الآن مبني حسب اليوم
  /// أولًا (بنفس منطق تقرير PDF الشامل)، وداخل كل يوم قسم فرعي لكل (قسم،
  /// شطر) له بيانات فعلية بذلك اليوم.
  Widget _buildFilteredPreview() {
    if (_filteredData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: AdvisingEmptyState(
            icon: Icons.event_busy_outlined,
            title: 'لا يوجد جدول محفوظ',
            description: 'لا يوجد أي جدول محفوظ ضمن هذا النطاق بعد.\nنزّل النموذج وارفعه بعد تعبئته من شريط الأدوات أعلاه.',
          ),
        ),
      );
    }

    final byDay = <String, List<(String department, String shatr, AdvisingScheduleSlot slot)>>{};
    for (final entry in _filteredData.entries) {
      final (department, shatr) = entry.key;
      for (final slot in entry.value) {
        byDay.putIfAbsent(slot.dayLabel, () => []).add((department, shatr, slot));
      }
    }
    final sortedDays = byDay.keys.toList()..sort((a, b) => _dayOrder(a).compareTo(_dayOrder(b)));
    for (final list in byDay.values) {
      // الشطر أولاً (كل الأقسام لشطر الطلاب من الإدارة إلى نظم المعلومات، ثم
      // كل الأقسام لشطر الطالبات) لا القسم أولاً - نفس ترتيب PDF الشامل.
      list.sort((a, b) {
        final shatrCompare =
            AdvisingScheduleExcelService.shatrOptions.indexOf(a.$2).compareTo(AdvisingScheduleExcelService.shatrOptions.indexOf(b.$2));
        if (shatrCompare != 0) return shatrCompare;
        final deptCompare = AdvisingScheduleExcelService.departmentOptions
            .indexOf(a.$1)
            .compareTo(AdvisingScheduleExcelService.departmentOptions.indexOf(b.$1));
        if (deptCompare != 0) return deptCompare;
        return _periodOrder(a.$3.periodLabel).compareTo(_periodOrder(b.$3.periodLabel));
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sortedDays.map((day) {
          final items = byDay[day]!;
          // تجميع فرعي حسب (قسم، شطر) داخل نفس اليوم - بلا فقد ترتيبها المرتَّب أعلاه
          final byDeptShatr = <(String, String), List<AdvisingScheduleSlot>>{};
          for (final (department, shatr, slot) in items) {
            byDeptShatr.putIfAbsent((department, shatr), () => []).add(slot);
          }
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.green)),
                  const Divider(),
                  for (final section in byDeptShatr.entries) ...[
                    Text(
                      '${section.key.$1.replaceFirst(RegExp(r'^قسم\s+'), '')} - ${section.key.$2}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.gold),
                    ),
                    const SizedBox(height: 6),
                    for (final slot in section.value) ...[
                      Text('الفترة: ${AdvisingScheduleExcelService.periodDisplayLabel(slot.periodLabel)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: slot.entries
                            .map((e) => AdvisingAdvisorChip(label: '${e.advisorName} (مكتب ${e.office})'))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// زر مضغوط بشكل موحّد لأزرار الشريط العلوي (بديل عن FilledButton/OutlinedButton
/// المتفرّقة بأنماط مختلفة كانت تجعل الشريط يبدو مبعثرًا).
class _ToolbarButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;

  const _ToolbarButton({
    required this.onPressed,
    required this.loading,
    required this.icon,
    required this.label,
    required this.color,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(icon, size: 17);
    return filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: child,
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: child,
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          );
  }
}

/// زر قائمة واحد يجمع 4 إجراءات (عرض/طباعة × رسمي/شاشات عرض) بدل 4 أزرار
/// متفرّقة لكل نطاق تقرير - يقلّل عدد الأزرار الظاهرة دفعة واحدة بشكل كبير.
/// بطاقة تقرير بنفس الهوية البصرية المعتمدة في بقية الموقع (عنوان بين
/// معينتين ذهبيتين وخط ذهبي، ثم أزرار PDF/طباعة) - بدل قائمة منسدلة غريبة
/// الشكل لا تحمل هوية بصرية واضحة.
class _ReportCard extends StatelessWidget {
  final String title;
  final bool enabled;
  final VoidCallback onOfficialView;
  final VoidCallback onOfficialPrint;
  final VoidCallback onSignageView;
  final VoidCallback onSignageImagesZip;

  const _ReportCard({
    required this.title,
    required this.enabled,
    required this.onOfficialView,
    required this.onOfficialPrint,
    required this.onSignageView,
    required this.onSignageImagesZip,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Card(
        elevation: 1,
        color: const Color(0xFFFBF9F3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('◆', style: TextStyle(color: AppColors.gold, fontSize: 9)),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 14),
              Container(width: 1, height: 20, color: AppColors.gold.withValues(alpha: 0.4)),
              const SizedBox(width: 10),
              _iconAction(enabled ? onOfficialView : null, Icons.picture_as_pdf_outlined, 'عرض PDF - رسمي', AppColors.green),
              _iconAction(enabled ? onOfficialPrint : null, Icons.print_outlined, 'طباعة - رسمي', AppColors.green),
              const SizedBox(width: 6),
              _iconAction(enabled ? onSignageView : null, Icons.tv_outlined, 'عرض PDF - شاشات العرض', AppColors.gold),
              _iconAction(
                  enabled ? onSignageImagesZip : null, Icons.image_outlined, 'تنزيل صور الشرائح (ZIP)', AppColors.gold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconAction(VoidCallback? onPressed, IconData icon, String tooltip, Color color) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        color: color,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(padding: const EdgeInsets.all(6)),
      ),
    );
  }
}
