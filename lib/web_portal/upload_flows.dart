import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/advising_load_rules.dart';
import '../data/course_catalog.dart';
import '../data/faculty_sort_order.dart';
import '../data/teaching_load_regulation.dart';
import '../models/advising_case_record.dart';
import '../models/advising_schedule.dart';
import '../models/college_roster_member.dart';
import '../models/course_section_record.dart';
import '../services/advising_case_analyzer.dart';
import '../services/advising_report_parser_service.dart';
import '../services/advising_report_pdf_parser_service.dart';
import '../services/advising_report_repository.dart';
import '../services/advising_schedule_excel_service.dart';
import '../services/advising_schedule_repository.dart';
import '../services/advisor_correction_service.dart';
import '../services/advisor_movement_repository.dart';
import '../services/advisor_name_matching.dart';
import '../services/advisor_roster_service.dart';
import '../services/advisor_zip_service.dart';
import '../services/college_roster_parser_service.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_change_repository.dart';
import '../services/course_schedule_diff_service.dart';
import '../services/course_schedule_repository.dart';
import '../services/docx_schedule_parser_service.dart';
import '../services/pdf_schedule_parser_service.dart';
import '../services/escalation_file_service.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_ticket_service.dart';
import '../services/outside_course_repository.dart';
import '../services/unit_committee_repository.dart';
import '../services/web_download.dart';
import '../services/xlsx_metadata_service.dart';
import 'upload_dialogs.dart';

/// منطق رفع الملفات الثلاثة التي مصدرها المنظومة الداخلية للجامعة (كل
/// الكليات/ذوو الإعاقة/مواعيد الإرشاد) - مُستخرَج هنا كدالة واحدة لكل ملف
/// حتى تعمل **بلا أي تكرار للمنطق** من مكانين معًا: الصفحة الأصلية (متابعة
/// حالات الإرشاد/مواعيد الإرشاد) وصفحة "رفع ملفات" المركزية - بطلب سليمان
/// صراحةً (2026-08-17): "نقل كامل بدون مخاطرة، يبقى كما هو بنفس الصفحة
/// الأساسية وينقل إلى صفحة رفع الملفات" - أي: مصدر واحد للمنطق، يُستدعى من
/// مكانين، لا نسخ منفصلتين قد تتباعدان لاحقًا بلا قصد.
///
/// [onSuccess] يُستدعى بعد نجاح الحفظ ليُحدِّث كل صفحة بياناتها الخاصة (لا
/// يوجد استدعاء مشترك واحد لأن الصفحة الأصلية تُحدِّث جداول العرض الكاملة
/// بينما صفحة الرفع المركزية تحتاج فقط تاريخ آخر رفع).

/// عمود "الشطر" في ملف منسوبي الكلية نص حر تكتبه العمادة (لا قيمة ثابتة
/// مضمونة) - نتحقق من الكلمة المفتاحية بدل المطابقة التامة، والفحص عن
/// "طالبات" أولًا لأنها تحتوي حروف "طلاب" لكن بترتيب مختلف فلا تلتبس بها.
String? _shatrLabelFromFreeText(String raw) {
  if (raw.contains('طالبات')) return Shatr.female.label;
  if (raw.contains('طلاب')) return Shatr.male.label;
  return null;
}

Future<void> runUploadAllColleges({
  required BuildContext context,
  required ValueChanged<bool> setUploading,
  required VoidCallback onSuccess,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    withData: true,
  );
  if (result == null || result.files.single.bytes == null) return;
  final Uint8List bytes = result.files.single.bytes!;

  setUploading(true);
  try {
    showUploadProcessingDialog(
      context,
      'جاري معالجة ملف الإرشاد - قد يستغرق عدة دقائق. '
      'الرجاء الانتظار حتى الانتهاء من رفع الملف.',
    );
    // يضمن رسم النافذة فعليًا على الشاشة قبل بدء المعالجة الثقيلة (انظر
    // نفس الملاحظة بالكود الأصلي - `Future.delayed` بمدة حقيقية لا `endOfFrame`).
    await Future.delayed(const Duration(milliseconds: 300));

    final roster = await CollegeRosterRepository.load();
    final advisorShatrByName = {
      for (final m in roster)
        if (_shatrLabelFromFreeText(m.shatr) != null)
          normalizeAdvisorNameForMatch(m.name): _shatrLabelFromFreeText(m.shatr)!,
    };
    final knownAdvisorNameKeys = {for (final m in roster) normalizeAdvisorNameForMatch(m.name)};

    final AdvisingReportPdfParseResult r;
    try {
      r = await AdvisingReportPdfParserService.parseInBackground(
        bytes,
        advisorShatrByName: advisorShatrByName,
        knownAdvisorNameKeys: knownAdvisorNameKeys,
      );
    } finally {
      hideUploadProcessingDialog(context);
    }
    final records = r.records;
    final male = records.where((r) => r.shatr == Shatr.male.label).toList();
    final female = records.where((r) => r.shatr == Shatr.female.label).toList();

    if (r.unresolvedShatrRows.isNotEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${r.unresolvedShatrRows.length} حالة بمرشد من خارج كليتنا (تعذّر تحديد شطره)'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                'الحالات التالية مرشدها من خارج ملف منسوبي كليتنا (أو بلا اسم مرشد أصلًا) فتعذّر '
                'تحديد شطرها - ستظهر مؤقتًا تحت كلا الشطرين معًا حتى يُتاح مصدر أفضل لتحديد شطر '
                'مرشدي الكليات الأخرى:\n\n'
                '${r.unresolvedShatrRows.join('\n')}',
              ),
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا')),
          ],
        ),
      );
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد اعتماد ملف "كل الكليات"'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              records.isEmpty
                  ? 'الملف لا يحتوي أي بيانات. سيُعتمد كقائمة فارغة لكلا الشطرين. هل تريد الاعتماد؟'
                  : 'تم استخراج ${male.length} سجل لشطر الطلاب و${female.length} سجل لشطر الطالبات '
                      '(${records.length} إجمالًا، كل كليات الجامعة).\n\n'
                      'سيستبدل هذا آخر رفعة معتمدة، وتُحفَظ النسخة الحالية تلقائيًا كنسخة سابقة '
                      'لبناء "تقرير حركات الإرشاد". هل تريد الاعتماد؟',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (confirmed != true) return;

    Future<void> saveShatr(Shatr shatr, List<AdvisingCaseRecord> shatrRecords) async {
      final previouslyStored = await AdvisingReportRepository.load(shatr, kind: AdvisingReportKind.allColleges);
      final movements = AdvisingCaseAnalyzer.detectAdvisorMovements(previous: previouslyStored, current: shatrRecords);

      await AdvisingReportRepository.promoteAllCollegesToPrevious(shatr);
      await AdvisingReportRepository.save(shatr, shatrRecords, kind: AdvisingReportKind.allColleges);

      if (movements.isNotEmpty) {
        await AdvisorMovementRepository.appendMovements([
          for (final m in movements)
            AdvisorMovementLogEntry(
              studentId: m.student.studentId,
              studentName: m.student.studentName,
              department: m.student.department,
              shatr: m.student.shatr,
              fromAdvisorNameRaw: m.fromAdvisorNameRaw,
              toAdvisorNameRaw: m.toAdvisorNameRaw,
            ),
        ]);
      }
    }

    if (records.isEmpty) {
      await saveShatr(Shatr.male, const []);
      await saveShatr(Shatr.female, const []);
    } else {
      if (male.isNotEmpty) await saveShatr(Shatr.male, male);
      if (female.isNotEmpty) await saveShatr(Shatr.female, female);
    }

    onSuccess();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم اعتماد ملف "كل الكليات" بنجاح (${records.length} سجل).')),
    );
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر إتمام العملية', '$e');
  } finally {
    setUploading(false);
  }
}

Future<void> runUploadHealth({
  required BuildContext context,
  required ValueChanged<bool> setUploading,
  required VoidCallback onSuccess,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['docx'],
    withData: true,
  );
  if (result == null || result.files.single.bytes == null) return;
  final Uint8List bytes = result.files.single.bytes!;

  setUploading(true);
  try {
    showUploadProcessingDialog(context, 'جاري معالجة الملف...');
    await Future.delayed(const Duration(milliseconds: 300));
    List<AdvisingCaseRecord> records;
    var exclusionCounts = <String, int>{};
    try {
      try {
        records = AdvisingReportParserService.parse(
          bytes,
          requireDepartment: false,
          isHealthReport: true,
          exclusionCounts: exclusionCounts,
        );
      } finally {
        hideUploadProcessingDialog(context);
      }
    } on ShatrRequiredException {
      if (!context.mounted) return;
      final chosen = await showDialog<Shatr>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تحديد الشطر'),
          content: const Text('ملف "طلبة ذوي الإعاقة" هذا لا يحتوي عمود "الجنس" فلا يمكن فرزه تلقائيًا - '
              'حدّد الشطر الذي يمثّله هذا الملف بالكامل.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, Shatr.male), child: const Text('شطر الطلاب')),
            TextButton(onPressed: () => Navigator.pop(context, Shatr.female), child: const Text('شطر الطالبات')),
          ],
        ),
      );
      if (chosen == null) return;
      exclusionCounts = <String, int>{};
      records = AdvisingReportParserService.parse(
        bytes,
        shatr: chosen,
        requireDepartment: false,
        isHealthReport: true,
        exclusionCounts: exclusionCounts,
      );
    }

    final male = records.where((r) => r.shatr == Shatr.male.label).toList();
    final female = records.where((r) => r.shatr == Shatr.female.label).toList();

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد اعتماد ملف "طلبة ذوي الإعاقة"'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              records.isEmpty
                  ? 'الملف لا يحتوي أي بيانات. سيُعتمد كقائمة فارغة لكلا الشطرين. هل تريد الاعتماد؟'
                  : 'تم استخراج ${male.length} سجل لشطر الطلاب و${female.length} سجل لشطر الطالبات '
                      '(${records.length} إجمالًا).\n\n'
                      'سيستبدل هذا آخر نسخة معتمدة لكل شطر ظهر في الملف. هل تريد الاعتماد؟',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (records.isEmpty) {
      await AdvisingReportRepository.save(Shatr.male, const [], kind: AdvisingReportKind.health);
      await AdvisingReportRepository.save(Shatr.female, const [], kind: AdvisingReportKind.health);
    } else {
      if (male.isNotEmpty) await AdvisingReportRepository.save(Shatr.male, male, kind: AdvisingReportKind.health);
      if (female.isNotEmpty) {
        await AdvisingReportRepository.save(Shatr.female, female, kind: AdvisingReportKind.health);
      }
    }

    onSuccess();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم اعتماد ملف "طلبة ذوي الإعاقة" بنجاح (${records.length} سجل).')),
    );
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر إتمام العملية', '$e');
  } finally {
    setUploading(false);
  }
}

// ==================== جدول مواعيد الإرشاد ====================

// دمج "عبد" مع الكلمة التالية بلا مسافة، توحيد التاء المربوطة/الهاء، الألف
// المقصورة/الياء، الهمزة على الياء - نفس منطق مطابقة الأسماء الأصلي بالضبط
// (انظر التعليقات المفصَّلة الأصلية بـ advising_schedule_admin_screen.dart).
String _normalizeArabicName(String s) => s
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

const _nameFillerWords = {'بن', 'بنت', 'ابن', 'آل', 'ال'};

bool _isSubsetNameMatch(String shortName, String fullName) {
  final shortWords = shortName.split(' ').where((w) => w.isNotEmpty && !_nameFillerWords.contains(w));
  final fullWords = fullName.split(' ').where((w) => w.isNotEmpty && !_nameFillerWords.contains(w)).toSet();
  return shortWords.isNotEmpty && shortWords.every(fullWords.contains);
}

/// يرتّب مرشدي كل فترة حسب الرتبة العلمية ثم تاريخ التعيين (الأقدم أولاً).
List<AdvisingScheduleSlot> _sortSlotsByRank(List<AdvisingScheduleSlot> slots, List<CollegeRosterMember> roster) {
  CollegeRosterMember? memberFor(String name) {
    final normalized = _normalizeArabicName(name);
    for (final m in roster) {
      if (_normalizeArabicName(m.name) == normalized) return m;
    }
    for (final m in roster) {
      if (_isSubsetNameMatch(normalized, _normalizeArabicName(m.name))) return m;
    }
    return null;
  }

  return slots.map((slot) {
    final sortedEntries = [...slot.entries]
      ..sort((a, b) {
        final ma = memberFor(a.advisorName);
        final mb = memberFor(b.advisorName);
        if (ma != null && mb != null) return FacultySortOrder.compareByRankThenAppointment(ma, mb);
        if (ma != null) return -1;
        if (mb != null) return 1;
        return 0;
      });
    return AdvisingScheduleSlot(dayLabel: slot.dayLabel, periodLabel: slot.periodLabel, entries: sortedEntries);
  }).toList();
}

Future<void> runUploadAdvisingSchedule({
  required BuildContext context,
  required ValueChanged<bool> setUploading,
  required VoidCallback onSuccess,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
    allowMultiple: true,
  );
  if (result == null || result.files.isEmpty) return;

  setUploading(true);
  try {
    final okItems = <({String fileName, String department, String shatr, List<AdvisingScheduleSlot> slots})>[];
    final failedItems = <({String fileName, String error})>[];

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        failedItems.add((fileName: file.name, error: 'تعذّرت قراءة محتوى الملف.'));
        continue;
      }
      try {
        final parsed = AdvisingScheduleExcelService.parseTemplate(bytes);
        if (parsed.department.isEmpty || parsed.shatr.isEmpty) {
          throw Exception('لم يتم اختيار القسم/الشطر أعلى النموذج.');
        }
        if (parsed.slots.isEmpty) {
          throw Exception('لم يتم العثور على أي فترة إرشاد بالملف.');
        }
        okItems.add((fileName: file.name, department: parsed.department, shatr: parsed.shatr, slots: parsed.slots));
      } catch (e) {
        failedItems.add((fileName: file.name, error: '$e'));
      }
    }

    if (okItems.isNotEmpty) {
      final roster = await CollegeRosterRepository.load();
      for (var i = 0; i < okItems.length; i++) {
        okItems[i] = (
          fileName: okItems[i].fileName,
          department: okItems[i].department,
          shatr: okItems[i].shatr,
          slots: _sortSlotsByRank(okItems[i].slots, roster),
        );
      }
    }

    if (!context.mounted) return;
    if (okItems.isEmpty) {
      throw Exception('تعذّرت قراءة كل الملفات المختارة:\n${failedItems.map((f) => '- ${f.fileName}: ${f.error}').join('\n')}');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(okItems.length > 1 ? 'تأكيد اعتماد ${okItems.length} ملفات' : 'تأكيد الاعتماد'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('سيستبدل هذا الجدول السابق لنفس القسم/الشطر بالكامل لكل ملف أدناه:'),
              const SizedBox(height: 10),
              for (final item in okItems) ...[
                Builder(builder: (context) {
                  final total = item.slots.fold<int>(0, (s, slot) => s + slot.entries.length);
                  final conflicts = _findOfficeConflicts(item.slots);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.department} (${item.shatr}): ${item.slots.length} فترة، $total مرشدًا — ${item.fileName}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        if (conflicts.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, right: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('⚠ اختلاف رقم مكتب نفس المرشد بين يوم وآخر:',
                                    style: TextStyle(color: Colors.orange, fontSize: 11.5)),
                                for (final c in conflicts)
                                  Text('- ${c.name}: ${c.offices.join(' / ')}', style: const TextStyle(fontSize: 11.5)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
              if (failedItems.isNotEmpty) ...[
                const Divider(),
                Text('تعذّرت قراءة ${failedItems.length} ملف(ات) (لن تُرفَع):',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12.5)),
                for (final f in failedItems) Text('- ${f.fileName}: ${f.error}', style: const TextStyle(fontSize: 11.5)),
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

    for (final item in okItems) {
      await AdvisingScheduleRepository.save(item.department, item.shatr, item.slots);
    }
    onSuccess();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          okItems.length > 1
              ? 'تم اعتماد ${okItems.length} جداول بنجاح.'
              : 'تم اعتماد جدول ${okItems.first.department} (${okItems.first.shatr}) بنجاح.',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر قراءة النموذج', '$e');
  } finally {
    setUploading(false);
  }
}

/// تعارضات رقم المكتب لنفس المرشد بين يوم وآخر - تحذير فقط، لا يمنع الاعتماد.
List<({String name, List<String> offices})> _findOfficeConflicts(List<AdvisingScheduleSlot> slots) {
  final officesByName = <String, Set<String>>{};
  for (final slot in slots) {
    for (final entry in slot.entries) {
      if (entry.office.trim().isEmpty) continue;
      officesByName.putIfAbsent(entry.advisorName, () => {}).add(entry.office.trim());
    }
  }
  return [
    for (final e in officesByName.entries)
      if (e.value.length > 1) (name: e.key, offices: e.value.toList()..sort()),
  ];
}

/// يفحص عمودي "نصاب الإرشاد" و"النصاب التدريسي" لكل عضو مقابل القيم
/// المعتمدة فقط - بديل عن قائمة منسدلة داخل ملف الإكسل (لا يدعمها قارئ
/// الموقع). يُرجع سطرًا تحذيريًا لكل قيمة غريبة لعرضها بحوار التأكيد قبل
/// الاعتماد - تنبيه فقط، لا يمنع الرفع.
List<String> _invalidRosterQuotaValues(List<CollegeRosterMember> members) {
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

/// رفع ملف "منسوبي الكلية" الرسمي - نُقل من صفحة "بيانات منسوبي الكلية"
/// المستقلة إلى صفحة "رفع وتنزيل الملفات" الموحَّدة لكل رفعات الموقع (سليمان
/// 2026-08-22: "قم بإزالة الرفع من هنا، يوجد مكان للرفع" - المكان الموحَّد).
Future<void> runUploadCollegeRoster({
  required BuildContext context,
  required ValueChanged<bool> setUploading,
  required VoidCallback onSuccess,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
  );
  if (result == null || result.files.single.bytes == null) return;
  final Uint8List bytes = result.files.single.bytes!;

  setUploading(true);
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

    if (!context.mounted) return;
    final facultyCount = members.where((m) => m.type == CollegeMemberType.faculty).length;
    final adminCount = members.length - facultyCount;
    final invalidQuotaValues = _invalidRosterQuotaValues(members);
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

    // ورقة "تشكيل الوحدة" مستقلة تمامًا عن بيانات منسوبي الكلية أعلاه - لا
    // تُحدَّث إلا إن وُجدت فعليًا بالملف المرفوع (خلاف ذلك يبقى التشكيل
    // المعتمد سابقًا كما هو، لا يُمسح).
    final committee = CollegeRosterParserService.parseUnitCommittee(bytes);
    if (committee.isNotEmpty) {
      await UnitCommitteeRepository.save(committee);
    }

    onSuccess();
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر قراءة الملف', '$e');
  } finally {
    setUploading(false);
  }
}

/// يسأل الأدمن أولًا: هل هذا أول رفع في دورة حذف وإضافة جديدة (يمسح كل
/// شيء - بداية نظيفة)، أم رفعة يوم تالٍ من نفس الدورة (الاثنين/الثلاثاء -
/// تصدير Microsoft Forms تراكمي، فيُضاف الجديد فقط بلا مسح أي شيء حتى لا
/// يُفقَد عمل المرشدين/المنسّقين على حالات الأيام السابقة).
Future<bool?> _confirmFormsUploadMode(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('اختر نوع الرفع'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('رفعة يوم تالٍ (إضافة فقط)'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text('رفع جديد (بداية دورة - يمسح القديم)'),
        ),
      ],
    ),
  );
}

/// رفع ملف طلبات الحذف/الإضافة (مصدره Microsoft Forms) - **مُستخرَجة من
/// `upload_hub_screen.dart` (`_pickAndUploadFormsFile`/`_confirmFormsUploadMode`)
/// بلا أي تغيير بالمنطق** لتُستدعى أيضًا من تطبيق "بوابة الإرشاد" الجوّالة
/// (سليمان 2026-08-23) - نفس مصدر واحد للمنطق كبقية دوال هذا الملف.
/// [onMessage] يعرض رسالة النجاح النهائية بأسلوب كل واجهة الخاص بها (شريط
/// إشعار أخضر بالموقع، قد يختلف شكله بالجوال).
Future<void> runUploadForms({
  required BuildContext context,
  required ValueChanged<bool> setUploading,
  required VoidCallback onSuccess,
  required ValueChanged<String> onMessage,
}) async {
  final isNewCycle = await _confirmFormsUploadMode(context);
  if (isNewCycle == null) return;

  setUploading(true);

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );

  if (result == null || result.files.single.bytes == null) {
    setUploading(false);
    return;
  }

  try {
    final Uint8List bytes = result.files.single.bytes!;
    var rawTickets = ExcelParserService.parseTickets(bytes);

    // تنظيف اسم/رمز مقرر "حذف"/"تعديل" (بلا قائمة منسدلة بالنموذج لهما) وفق
    // جدول المقررات الفعلي (الحويّة) المرفوع بالموقع - يبقى النص كما كتبه
    // الطالب لو تعذّر تحميل الجدول أو كان فارغًا (لا كسر للرفع بسبب هذا).
    try {
      final courseSections = [
        ...await CourseScheduleRepository.loadSchedule(Shatr.male),
        ...await CourseScheduleRepository.loadSchedule(Shatr.female),
      ];
      final catalog = courseSections
          .map((s) => (code: s.courseCode, name: s.courseName))
          .toList();
      rawTickets = ExcelParserService.enrichWithCourseCatalog(rawTickets, catalog);
    } catch (_) {
      // تجاهل - يبقى النص الحر كما هو لو تعذّرت قراءة جدول المقررات
    }

    final advisingRecords = [
      ...await AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
      ...await AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
    ];
    final tickets = AdvisorCorrectionService.applyAdvisorCorrection(rawTickets, advisingRecords);

    String message;
    if (isNewCycle) {
      final skippedNoId = await FirestoreTicketService.replaceAllTickets(tickets);
      final savedCount = tickets.length - skippedNoId;
      message = 'تم رفع $savedCount حالة بنجاح (دورة جديدة)';
      if (skippedNoId > 0) {
        message += ' - تنبيه: تم تجاهل $skippedNoId حالة بلا رقم جامعي صالح '
            '(غالبًا بريد الطالب لم يُسجَّل بحساب جامعي حقيقي عند تعبئة النموذج).';
      }
    } else {
      var skippedNoId = 0;
      final addedCount = await FirestoreTicketService.addNewTickets(
        tickets,
        onSkippedNoId: (n) => skippedNoId = n,
      );
      message = 'تمت إضافة $addedCount حالة جديدة (من أصل ${tickets.length} في الملف - '
          'الباقي موجود مسبقًا وتم تجاهله حفاظًا على عمل المرشدين/المنسّقين)';
      if (skippedNoId > 0) {
        message += ' - تنبيه: تم تجاهل $skippedNoId حالة بلا رقم جامعي صالح '
            '(غالبًا بريد الطالب لم يُسجَّل بحساب جامعي حقيقي عند تعبئة النموذج).';
      }
    }

    setUploading(false);
    onSuccess();
    if (!context.mounted) return;
    onMessage(message);
  } catch (e) {
    setUploading(false);
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر رفع ملف الفورم', '$e');
  }
}

/// تنزيل ملف مضغوط بداخله ملف Excel خام منفصل لكل قسم/شطر (10 ملفات: 5
/// أقسام × شطرين) من "الملف الأساسي" الحالي كما هو - بلا أي فرز حسب مرشد -
/// ليتمكّن سليمان من إرساله يدويًا (بريد/واتساب) لأي منسّق قسم يتعذّر عليه
/// الدخول للموقع نفسه. **مُستخرَجة من `upload_hub_screen.dart`
/// (`_downloadFormsFileZip`) بلا أي تغيير بالمنطق** - `downloadBytes` (من
/// `web_download.dart`) يعمل تلقائيًا بشكل صحيح على كل من الويب (تنزيل
/// متصفح) والجوال (حفظ بمجلد مؤقت ثم فتح/مشاركة عبر `OpenFilex`) بلا أي
/// كود إضافي خاص بالجوال.
Future<void> runDownloadFormsZip({
  required BuildContext context,
  required ValueChanged<bool> setDownloading,
  required ValueChanged<String> onMessage,
}) async {
  setDownloading(true);
  try {
    final tickets = await FirestoreTicketService.watchAllTickets().first;
    if (tickets.isEmpty) {
      throw Exception('لا توجد بيانات "الملف الأساسي" مرفوعة بعد لتنزيلها.');
    }

    final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
    final archive = Archive();
    for (final entry in groups.entries) {
      final parts = entry.key.split('|');
      final shatr = parts[0];
      final department = parts.length > 1 ? parts[1] : 'قسم';
      final shatrLabel = shatr == ExcelParserService.shatrMale ? 'شطر_الطلاب' : 'شطر_الطالبات';
      // ملف يُرسَل يدويًا لمنسّق القسم (لا فرز حسب مرشد) - يجب أن يحمل نفس
      // حماية/قائمة "حالة الإنجاز من قبل منسق القسم" المستخدَمة بمسار
      // التصعيد الفعلي (EscalationFileService)، لا نسخة خام بلا حماية.
      final bytes = EscalationFileService.buildStage2File(entry.value);
      final safeName = '${department.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}_$shatrLabel';
      archive.addFile(ArchiveFile('$safeName.xlsx', bytes.length, bytes));
    }

    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive) ?? <int>[]);
    await downloadBytes(zipBytes, 'الملف_الأساسي_طلبات_الحذف_والإضافة.zip');

    if (!context.mounted) return;
    onMessage('تم تنزيل ${groups.length} ملفًا (قسم/شطر) بنجاح');
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر تنزيل الملف', '$e');
  } finally {
    setDownloading(false);
  }
}

/// تنزيل ملف مضغوط رئيسي واحد بمجلدات متداخلة (شطر > قسم > ملف Excel محمي
/// مستقل لكل مرشد أكاديمي) لكل الأقسام والشطرين دفعة واحدة - بخلاف
/// [runDownloadFormsZip] (ملف خام واحد لكل قسم بلا فرز حسب مرشد، لإرسال
/// المنسّق يدويًا)، هذا مقسَّم فعليًا لكل مرشد كملف "مرحلة 1" العادي، لكن
/// الكل بضغطة واحدة بدل قسم/شطر بكل مرة (سليمان صراحةً 2026-08-25).
Future<void> runDownloadAllAdvisorsZip({
  required BuildContext context,
  required ValueChanged<bool> setDownloading,
  required ValueChanged<String> onMessage,
}) async {
  setDownloading(true);
  try {
    final tickets = await FirestoreTicketService.watchAllTickets().first;
    if (tickets.isEmpty) {
      throw Exception('لا توجد بيانات "الملف الأساسي" مرفوعة بعد لتنزيلها.');
    }
    final roster = await AdvisorRosterService.loadAll();

    final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
    final archive = Archive();
    var fileCount = 0;
    for (final entry in groups.entries) {
      final parts = entry.key.split('|');
      final shatr = parts[0];
      final department = parts.length > 1 ? parts[1] : 'قسم';
      final shatrFolder = shatr == ExcelParserService.shatrMale ? 'شطر_الطلاب' : 'شطر_الطالبات';
      final departmentFolder = department.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final advisorFiles = AdvisorZipService.buildAdvisorFiles(entry.value, roster: roster);
      for (final fileEntry in advisorFiles.entries) {
        archive.addFile(
          ArchiveFile('$shatrFolder/$departmentFolder/${fileEntry.key}', fileEntry.value.length, fileEntry.value),
        );
        fileCount++;
      }
    }

    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive) ?? <int>[]);
    await downloadBytes(zipBytes, 'ملفات_المرشدين_الأكاديميين.zip');

    if (!context.mounted) return;
    onMessage('تم تنزيل $fileCount ملفًا (لكل مرشد أكاديمي) بنجاح');
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر تنزيل الملفات', '$e');
  } finally {
    setDownloading(false);
  }
}

/// رفع المقررات الدراسية (الحويّة) بملف واحد يحوي الشطرين معًا - يحدَّد شطر
/// كل شعبة تلقائيًا من حقل "المقر". يقبل Word (.docx) أو PDF مباشرة (سليمان
/// صراحةً 2026-08-24: اعتماد PDF لأن رافع الملف مستقبلاً قد لا يعرف تحويله
/// إلى Word) - مع تنبيه تلقائي عند اكتشاف شعب بمواعيد أسبوعية غير معتادة
/// (مؤشر خلل استدلال محتمل بقارئ PDF تحديدًا).
Future<void> runUploadCourses({
  required BuildContext context,
  required ValueChanged<bool> setUploading,
  required VoidCallback onSuccess,
  required ValueChanged<String> onMessage,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['docx', 'pdf'],
    withData: true,
  );
  if (result == null || result.files.single.bytes == null) return;
  final Uint8List bytes = result.files.single.bytes!;
  final fileName = result.files.single.name.toLowerCase();
  final isPdf = fileName.endsWith('.pdf');
  // ملف .docx الحقيقي هو أرشيف ZIP يبدأ دائمًا بالتوقيع "PK"، وملف .pdf
  // الحقيقي يبدأ دائمًا بالتوقيع "%PDF" - إن لم يطابق أيًا منهما فهو على
  // الأغلب حُفظ بصيغة أخرى (.doc القديمة مثلًا) أو تالف.
  final looksValid = isPdf
      ? (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46)
      : (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B);
  if (!looksValid) {
    if (!context.mounted) return;
    showUploadErrorDialog(
      context,
      isPdf ? 'الملف ليس PDF صالحًا' : 'الملف ليس Word صالحًا',
      isPdf
          ? 'الملف المختار لا يبدو ملف PDF حقيقيًا أو أنه تالف - أعد المحاولة بملف PDF أصلي.'
          : 'الملف المختار لا يبدو ملف Word (.docx) حقيقيًا (قد يكون محفوظًا فعليًا بصيغة .doc القديمة أو تالفًا). '
              'يمكنك أيضًا رفع ملف PDF مباشرة بلا حاجة للتحويل إلى Word.',
    );
    return;
  }

  setUploading(true);
  try {
    final sections = isPdf
        ? PdfScheduleParserService.parseSectionsWithShatr(bytes)
        : DocxScheduleParserService.parseSectionsWithShatr(bytes);
    if (sections.isEmpty) {
      throw Exception('لم يتم العثور على أي شعبة في الملف - تأكد من أنه ملف المقررات الدراسية الشامل الصحيح.');
    }

    // موعد أسبوعي ثالث أو أكثر لشعبة واحدة (نظري أو عملي) نادر جدًا فعليًا -
    // مؤشر قوي على خلل استدلال بقارئ PDF (يلتقط أحيانًا موعدًا وهميًا إضافيًا
    // من صف مجاور) - سليمان صراحةً (2026-08-24): بدل مطاردة هذا الخلل البنيوي
    // بالكود (~1% من الشعب، غير مضمون الحل الكامل مستقبلاً)، يُنبَّه الرافع
    // تلقائيًا لمراجعة الشعب المشبوهة يدويًا قبل الاعتماد النهائي.
    final suspiciousSections = sections
        .where((s) => s.record.meetings.length >= 3 || s.record.practicalMeetings.length >= 3)
        .toList();
    if (suspiciousSections.isNotEmpty) {
      if (!context.mounted) return;
      final proceedDespiteWarning = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تنبيه: شعب بمواعيد غير معتادة'),
          content: SingleChildScrollView(
            child: Text(
              'وُجدت ${suspiciousSections.length} شعبة بـ3 مواعيد أسبوعية أو أكثر (نادر فعليًا، قد يكون خللًا '
              'باستخراج الملف):\n\n'
              '${suspiciousSections.map((s) => '• ${s.record.courseCode} - ${s.record.courseName} (تسلسل ${s.record.sequence})').join('\n')}\n\n'
              'يُنصَح بمراجعة هذه الشعب بالملف الأصلي قبل المتابعة. هل تريد المتابعة رغم ذلك؟',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة رغم ذلك')),
          ],
        ),
      );
      if (proceedDespiteWarning != true) return;
    }

    final ourSections = sections.where((s) => s.beneficiary.contains('كلية إدارة الأعمال')).toList();
    final outsideCodes = CourseCatalog.outsideCollegeCourses.map(CourseCatalog.outsideCourseCode).toSet();

    ({
      List<CourseSectionRecord> ownRecords,
      List<String> outsideOptions,
      List<CourseSectionRecord> outsideRecords,
    }) buildForShatr(Shatr shatr) {
      final shatrSections = ourSections.where((s) => s.shatr == shatr).toList();
      final ownRecords =
          shatrSections.where((s) => !outsideCodes.contains(s.record.courseCode)).map((s) => s.record).toList();
      final outsideSections = shatrSections.where((s) => outsideCodes.contains(s.record.courseCode)).toList();
      final offeredOutsideCodes = outsideSections.map((s) => s.record.courseCode).toSet();
      final outsideOptions = CourseCatalog.filterOutsideCoursesByOfferedCodes(offeredOutsideCodes);
      final outsideRecords = outsideSections.map((s) => s.record).toList()
        ..sort((a, b) {
          final c = a.courseCode.compareTo(b.courseCode);
          return c != 0 ? c : a.sequence.compareTo(b.sequence);
        });
      return (ownRecords: ownRecords, outsideOptions: outsideOptions, outsideRecords: outsideRecords);
    }

    final male = buildForShatr(Shatr.male);
    final female = buildForShatr(Shatr.female);

    if (male.ownRecords.isEmpty && female.ownRecords.isEmpty) {
      throw Exception(
        'لم يُعثر على أي شعبة "المستفيد" منها كلية إدارة الأعمال ضمن ${sections.length} سطر بالملف. '
        'تأكد أن الملف يحوي عمود "المستفيد" فعليًا وأن نص الكلية مطابق.',
      );
    }

    final previousMale = await CourseScheduleRepository.loadSchedule(Shatr.male);
    final previousFemale = await CourseScheduleRepository.loadSchedule(Shatr.female);
    final changesMale = CourseScheduleDiffService.diff(
      shatrLabel: Shatr.male.label,
      previous: previousMale,
      current: male.ownRecords,
    );
    final changesFemale = CourseScheduleDiffService.diff(
      shatrLabel: Shatr.female.label,
      previous: previousFemale,
      current: female.ownRecords,
    );

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاعتماد'),
        content: Text(
          'من إجمالي ${sections.length} سطر بالملف:\n\n'
          '• ${male.ownRecords.length} شعبة لشطر الطلاب (${male.outsideOptions.length} مادة خارج الكلية).\n'
          '• ${female.ownRecords.length} شعبة لشطر الطالبات (${female.outsideOptions.length} مادة خارج الكلية).\n'
          'سيستبدل هذا آخر نسخة معتمدة للشطرين بالكامل. هل تريد الاعتماد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (confirmed != true) return;

    await CourseScheduleRepository.saveSchedule(Shatr.male, male.ownRecords);
    await CourseScheduleRepository.saveSchedule(Shatr.female, female.ownRecords);
    await OutsideCourseRepository.save(Shatr.male, male.outsideOptions, male.outsideRecords);
    await OutsideCourseRepository.save(Shatr.female, female.outsideOptions, female.outsideRecords);
    if (previousMale.isNotEmpty) await CourseScheduleChangeRepository.appendChanges(changesMale);
    if (previousFemale.isNotEmpty) await CourseScheduleChangeRepository.appendChanges(changesFemale);
    onSuccess();
    if (!context.mounted) return;
    onMessage('تم رفع الملف بنجاح');
  } catch (e) {
    if (!context.mounted) return;
    showUploadErrorDialog(context, 'تعذّر قراءة الملف', '$e');
  } finally {
    setUploading(false);
  }
}
