import 'package:flutter/material.dart';

import '../models/coordinator.dart';
import '../services/college_roster_lookup_service.dart';
import '../services/college_roster_repository.dart';
import '../services/excel_parser_service.dart';
import '../services/firestore_coordinator_service.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

/// شاشة "بيانات منسقي الأقسام" في بوابة الويب/تطبيق CBA Advising - نفس
/// تصميم الشاشة المحلية في التطبيق القديم (lib/screens/coordinators_settings_screen.dart)
/// لكن مخزَّنة في Firestore (coordinator_contacts) بدل SharedPreferences، حتى
/// تُقرأ فورًا من الصفحة الرئيسية العامة ومن كل من الموقع والتطبيق. الوصول
/// إليها مقصور على حساب الإدارة الكامل (admin/salfawaz) عبر قواعد أمان
/// Firestore وعبر عدم وجود زر يقود إليها إلا من لوحة الإدارة.
class CoordinatorsContactsScreen extends StatefulWidget {
  const CoordinatorsContactsScreen({super.key});

  @override
  State<CoordinatorsContactsScreen> createState() =>
      _CoordinatorsContactsScreenState();
}

class _CoordinatorsContactsScreenState
    extends State<CoordinatorsContactsScreen> {
  static final List<MapEntry<String, String>> _pairs = [
    for (final shatr in [
      ExcelParserService.shatrMale,
      ExcelParserService.shatrFemale,
    ]) ...[
      for (final department in ExcelParserService.departments)
        MapEntry(shatr, department),
      MapEntry(shatr, Coordinator.collegeMarker),
    ],
  ];

  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, TextEditingController> _emailControllers = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    for (final pair in _pairs) {
      final key = '${pair.key}|${pair.value}';
      _nameControllers[key] = TextEditingController();
      _emailControllers[key] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final saved = await FirestoreCoordinatorService.watchAll().first;
    for (final pair in _pairs) {
      final key = '${pair.key}|${pair.value}';
      final existing = saved[key];
      _nameControllers[key]!.text = existing?.name ?? '';
      _emailControllers[key]!.text = existing?.email ?? '';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// يعبّئ تلقائيًا من ملف أعضاء هيئة التدريس المعتمد المرفوع عبر الموقع -
  /// المصدر الوحيد المسموح به لهذي البيانات (بدل قائمة ثابتة قديمة بالكود
  /// مصدرها ملف من مجلد المرفقات).
  Future<void> _fillFromOfficialList() async {
    final roster = await CollegeRosterRepository.load();
    if (!mounted) return;
    var filledCount = 0;
    for (final pair in _pairs) {
      final shatr = pair.key;
      final department = pair.value;
      final member = CollegeRosterLookupService.coordinatorMemberFor(roster, department, shatr);
      if (member == null) continue;
      final key = '$shatr|$department';
      _nameControllers[key]!.text = member.name;
      _emailControllers[key]!.text = member.email;
      filledCount++;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          filledCount == 0
              ? 'لا يوجد أي منسّق في ملف أعضاء هيئة التدريس المعتمد بعد - ارفعه أولاً من شاشة "بيانات منسوبي الكلية"'
              : 'تمت تعبئة $filledCount منسّق/ة من ملف أعضاء هيئة التدريس المعتمد - اضغط "حفظ" لاعتمادها',
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ البيانات'),
        content: const Text(
          'سيتم تفريغ كل حقول الاسم والبريد في هذه الشاشة (لن يُحفظ التفريغ إلا بعد الضغط على "حفظ"). متابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('تفريغ')),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final pair in _pairs) {
      final key = '${pair.key}|${pair.value}';
      _nameControllers[key]!.clear();
      _emailControllers[key]!.clear();
    }
    setState(() {});
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    final updated = <String, Coordinator>{};
    for (final pair in _pairs) {
      final key = '${pair.key}|${pair.value}';
      updated[key] = Coordinator(
        shatr: pair.key,
        department: pair.value,
        name: _nameControllers[key]!.text.trim(),
        email: _emailControllers[key]!.text.trim(),
      );
    }
    await FirestoreCoordinatorService.saveAll(updated);
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بيانات المنسّقين، وستظهر فورًا في الصفحة الرئيسية')),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _emailControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'بيانات منسقي الأقسام',
      navItems: buildAdminNavItems(context, current: 'tools'),
      actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add_check_rounded),
            tooltip: 'تعبئة تلقائية من القائمة الرسمية',
            onPressed: _isLoading || _isSaving ? null : _fillFromOfficialList,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'تفريغ كل الحقول',
            onPressed: _isLoading || _isSaving ? null : _clearAll,
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            tooltip: 'حفظ',
            onPressed: _isLoading || _isSaving ? null : _saveAll,
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pairs.length,
              itemBuilder: (context, index) {
                final pair = _pairs[index];
                final key = '${pair.key}|${pair.value}';
                final isCollege = pair.value == Coordinator.collegeMarker;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: (isCollege ? AppColors.gold : AppColors.green).withValues(alpha: 0.12),
                              child: Icon(
                                isCollege ? Icons.school_outlined : Icons.apartment_outlined,
                                size: 15,
                                color: isCollege ? AppColors.gold : AppColors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isCollege ? 'منسّق/ة الكلية — ${pair.key}' : '${pair.value} — ${pair.key}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameControllers[key],
                          decoration: const InputDecoration(
                            labelText: 'اسم المنسّق/المنسّقة',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _emailControllers[key],
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني الرسمي',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading || _isSaving ? null : _saveAll,
        icon: const Icon(Icons.save),
        label: const Text('حفظ البيانات'),
      ),
    );
  }
}
