import 'package:flutter/material.dart';

import '../models/advisor_roster_entry.dart';
import '../models/college_roster_member.dart';
import '../services/advisor_name_matching.dart';
import '../services/advisor_roster_service.dart';
import '../services/college_roster_repository.dart';
import '../services/excel_parser_service.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

/// شاشة إدارة "قائمة مرشدي القسم" الرسمية (مجموعة advisor_roster) - تحدد
/// أعضاء كل قسم/شطر ومن هو المنسّق فيه، حتى يعمل توزيع حالات المنسّق على
/// بقية المرشدين تلقائيًا عند بناء ملفات ZIP لكل قسم. بدون تعبئة هذه القائمة
/// بشكل صحيح (السلوك السابق: التعديل مباشرة في Firebase Console) تبقى حالات
/// المنسّق معه بدل توزيعها.
class AdvisorRosterScreen extends StatefulWidget {
  const AdvisorRosterScreen({super.key});

  @override
  State<AdvisorRosterScreen> createState() => _AdvisorRosterScreenState();
}

class _AdvisorRosterScreenState extends State<AdvisorRosterScreen> {
  String _shatr = ExcelParserService.shatrMale;
  String _department = ExcelParserService.departments.first;

  // المصدر الوحيد لاقتراحات الأسماء/الإيميلات وقائمة المنسّقين هو ملف
  // أعضاء هيئة التدريس المعتمد المرفوع عبر الموقع - لا قوائم ثابتة بالكود.
  List<CollegeRosterMember> _roster = [];

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    final roster = await CollegeRosterRepository.load();
    if (mounted) setState(() => _roster = roster);
  }

  Iterable<(String name, String email)> _searchRoster(String query) {
    final words = normalizeAdvisorNameForMatch(query);
    if (words.isEmpty) return const [];
    return _roster
        .where((m) => normalizeAdvisorNameForMatch(m.name).contains(words))
        .map((m) => (m.name, m.email))
        .take(15);
  }

  Future<void> _openEditor({AdvisorRosterEntry? entry}) async {
    final nameController = TextEditingController(text: entry?.name ?? '');
    final emailController = TextEditingController(text: entry?.email ?? '');
    TextEditingController? nameFieldController;
    var shatr = entry?.shatr ?? _shatr;
    var department = entry?.department ?? _department;
    var isCoordinator = entry?.isCoordinator ?? false;
    var isOnLeave = entry?.isOnLeave ?? false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(entry == null ? 'إضافة مرشد' : 'تعديل بيانات المرشد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Autocomplete<(String name, String email)>(
                  displayStringForOption: (o) => o.$1,
                  optionsBuilder: (value) => _searchRoster(value.text),
                  onSelected: (o) {
                    nameFieldController?.text = o.$1;
                    setDialogState(() => emailController.text = o.$2);
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                    nameFieldController = controller;
                    if (controller.text.isEmpty && nameController.text.isNotEmpty) {
                      controller.text = nameController.text;
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'اسم المرشد - اكتب جزءًا من الاسم لاقتراحات من دليل منسوبي الكلية',
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'البريد الجامعي الرسمي',
                    helperText: 'يُملأ تلقائيًا عند اختيار اسم من الاقتراحات، أو يمكن كتابته يدويًا',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: shatr,
                  decoration: const InputDecoration(
                    labelText: 'الشطر',
                    border: OutlineInputBorder(),
                  ),
                  items: [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => shatr = v!),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: department,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'القسم',
                    border: OutlineInputBorder(),
                  ),
                  items: ExcelParserService.departments
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => department = v!),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('منسّق هذا القسم/الشطر'),
                  subtitle: const Text('تُوزَّع حالاته تلقائيًا على بقية مرشدي نفس القسم/الشطر'),
                  value: isCoordinator,
                  onChanged: (v) => setDialogState(() => isCoordinator = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('في إجازة رسمية مؤقتًا'),
                  subtitle: const Text('تُوزَّع حالاته تلقائيًا على بقية مرشدي نفس القسم/الشطر لحين تحديث وضعه'),
                  value: isOnLeave,
                  onChanged: (v) => setDialogState(() => isOnLeave = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = (nameFieldController?.text ?? nameController.text).trim();
                if (name.isEmpty) return;
                final email = emailController.text.trim();
                if (entry == null) {
                  await AdvisorRosterService.add(
                    name: name,
                    department: department,
                    shatr: shatr,
                    isCoordinator: isCoordinator,
                    isOnLeave: isOnLeave,
                    email: email,
                  );
                } else {
                  await AdvisorRosterService.update(
                    entry.id,
                    name: name,
                    department: department,
                    shatr: shatr,
                    isCoordinator: isCoordinator,
                    isOnLeave: isOnLeave,
                    email: email,
                  );
                }
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importOfficialCoordinators() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استيراد المنسّقين الرسميين'),
        content: const Text(
          'سيتم إضافة كل من مسمّاه الوظيفي "منسّق قسم"/"منسّقة قسم" في ملف أعضاء '
          'هيئة التدريس المعتمد المرفوع عبر الموقع، مع تخطّي أي اسم مطابق لمرشد '
          'مُدرَج مسبقًا في نفس القسم/الشطر. متابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('استيراد')),
        ],
      ),
    );
    if (confirmed != true) return;

    final existing = await AdvisorRosterService.loadAll();
    final existingKeys = existing
        .map((e) => '${e.department}|${e.shatr}|${normalizeAdvisorNameForMatch(e.name)}')
        .toSet();

    var added = 0;
    for (final m in _roster) {
      final positions = [m.position, m.position2, m.position3];
      final isCoordinator = positions.any((p) => p.contains('منسق قسم') || p.contains('منسقة قسم'));
      if (!isCoordinator || m.department.isEmpty || m.shatr.isEmpty) continue;
      final key = '${m.department}|${m.shatr}|${normalizeAdvisorNameForMatch(m.name)}';
      if (existingKeys.contains(key)) continue;
      await AdvisorRosterService.add(
        name: m.name,
        department: m.department,
        shatr: m.shatr,
        isCoordinator: true,
        email: m.email,
      );
      added++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت إضافة $added منسّقًا جديدًا (تم تخطّي الموجود مسبقًا).')),
    );
  }

  Future<void> _confirmDelete(AdvisorRosterEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المرشد'),
        content: Text('هل تريد حذف "${entry.name}" من قائمة مرشدي القسم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) {
      await AdvisorRosterService.delete(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'قائمة مرشدي القسم',
      navItems: buildAdminNavItems(context, current: 'tools'),
      actions: [
          IconButton(
            tooltip: 'استيراد المنسّقين الرسميين',
            icon: const Icon(Icons.playlist_add_check_rounded),
            onPressed: _importOfficialCoordinators,
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة مرشد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _shatr,
                    decoration: const InputDecoration(labelText: 'الشطر', border: OutlineInputBorder()),
                    items: [ExcelParserService.shatrMale, ExcelParserService.shatrFemale]
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _shatr = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _department,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
                    items: ExcelParserService.departments
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => setState(() => _department = v!),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AdvisorRosterEntry>>(
              stream: AdvisorRosterService.watchAll(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!
                    .where((e) => e.shatr == _shatr && e.department == _department)
                    .toList()
                  ..sort((a, b) {
                    if (a.isCoordinator != b.isCoordinator) return a.isCoordinator ? -1 : 1;
                    if (a.isOnLeave != b.isOnLeave) return a.isOnLeave ? 1 : -1;
                    return a.name.compareTo(b.name);
                  });

                if (entries.isEmpty) {
                  return const Center(
                    child: Text('لا يوجد مرشدون مسجّلون لهذا القسم/الشطر بعد'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: entry.isOnLeave
                              ? Colors.grey.withValues(alpha: 0.18)
                              : entry.isCoordinator
                                  ? AppColors.gold.withValues(alpha: 0.18)
                                  : AppColors.green.withValues(alpha: 0.12),
                          child: Icon(
                            entry.isOnLeave
                                ? Icons.flight_takeoff_rounded
                                : entry.isCoordinator
                                    ? Icons.star_rounded
                                    : Icons.person_outline,
                            color: entry.isOnLeave
                                ? Colors.grey.shade700
                                : entry.isCoordinator
                                    ? AppColors.gold
                                    : AppColors.green,
                          ),
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          [
                            if (entry.isOnLeave)
                              'في إجازة رسمية مؤقتًا - تُوزَّع حالاته على البقية'
                            else if (entry.isCoordinator)
                              'منسّق القسم',
                            if (entry.email.isNotEmpty) entry.email,
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openEditor(entry: entry),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmDelete(entry),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
