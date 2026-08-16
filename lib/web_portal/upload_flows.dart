import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/faculty_sort_order.dart';
import '../models/advising_case_record.dart';
import '../models/advising_schedule.dart';
import '../models/college_roster_member.dart';
import '../services/advising_case_analyzer.dart';
import '../services/advising_report_parser_service.dart';
import '../services/advising_report_pdf_parser_service.dart';
import '../services/advising_report_repository.dart';
import '../services/advising_schedule_excel_service.dart';
import '../services/advising_schedule_repository.dart';
import '../services/advisor_movement_repository.dart';
import '../services/advisor_name_matching.dart';
import '../services/college_roster_repository.dart';
import '../services/course_schedule_repository.dart' show Shatr, ShatrLabel;
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
      'جاري معالجة ملف "كل الكليات" - يغطي الجامعة كاملة فقد يستغرق عدة دقائق. '
      'الرجاء عدم إغلاق الصفحة أو تحديث المتصفح حتى الانتهاء.',
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
