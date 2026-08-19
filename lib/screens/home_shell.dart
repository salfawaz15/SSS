import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/coordinator.dart';
import '../services/advising_report_repository.dart';
import '../services/advisor_correction_service.dart';
import '../services/coordinator_service.dart';
import '../services/course_schedule_repository.dart' show Shatr;
import '../services/excel_parser_service.dart';
import '../services/mail_service.dart';
import '../services/ticket_repository.dart';
import '../theme/app_page_route.dart';
import 'coordinators_settings_screen.dart';
import 'dashboard_home_screen.dart';
import 'import_processed_files_screen.dart';
import 'import_sort_screen.dart';
import 'more_screen.dart';
import 'reports_screen.dart';

/// الحاوية الرئيسية للتطبيق: ترفع كل بيانات الدفعة الحالية (تذاكر، منسقون،
/// حالة الإرسال) لتُشارك بين تبويبات التنقّل السفلي الأربعة.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  Map<String, List<Map<String, dynamic>>> _groups = {};
  Map<String, Coordinator> _coordinators = {};
  bool _isLoading = false;
  final Set<String> _sendingKeys = {};
  final Set<String> _sentKeys = {};

  @override
  void initState() {
    super.initState();
    _loadCoordinators();
    _loadPersistedTickets();
  }

  Future<void> _loadCoordinators() async {
    final coordinators = await CoordinatorService.loadAll();
    if (mounted) setState(() => _coordinators = coordinators);
  }

  Future<void> _loadPersistedTickets() async {
    final tickets = await TicketRepository.loadAll();
    if (tickets.isEmpty) return;
    final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _pickAndImportFile() async {
    setState(() {
      _isLoading = true;
      _currentIndex = 1;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      setState(() => _isLoading = false);
      return;
    }

    final Uint8List bytes = result.files.single.bytes!;
    final rawTickets = ExcelParserService.parseTickets(bytes);

    final advisingRecords = [
      ...await AdvisingReportRepository.load(Shatr.male, kind: AdvisingReportKind.allColleges),
      ...await AdvisingReportRepository.load(Shatr.female, kind: AdvisingReportKind.allColleges),
    ];
    final tickets =
        AdvisorCorrectionService.applyAdvisorCorrection(rawTickets, advisingRecords);
    final groups = ExcelParserService.groupByShatrAndDepartment(tickets);

    await TicketRepository.saveAll(tickets);

    setState(() {
      _groups = groups;
      _sentKeys.clear();
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استيراد ${tickets.length} حالة بنجاح')),
      );
    }
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفريغ البيانات المستوردة'),
        content: const Text(
          'سيتم مسح كل الحالات المستوردة وحالات الإرسال الحالية من الشاشة. '
          'هذا لا يحذف بيانات منسقي الأقسام المحفوظة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('تفريغ البيانات'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await TicketRepository.clear();

      setState(() {
        _groups = {};
        _sentKeys.clear();
        _sendingKeys.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفريغ البيانات المستوردة')),
        );
      }
    }
  }

  /// قائمة ثابتة بكل الأقسام العشرة (5 أقسام × شطرين) بترتيب ثابت، بصرف
  /// النظر عن وجود بيانات مستوردة، حتى يمكن تعبئة بيانات المنسقين مسبقًا
  static List<MapEntry<String, String>> _fixedShatrDepartmentPairs() {
    return [
      for (final shatr in [
        ExcelParserService.shatrMale,
        ExcelParserService.shatrFemale,
      ])
        for (final department in ExcelParserService.departments)
          MapEntry(shatr, department),
    ];
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      fadeSlideRoute(
        CoordinatorsSettingsScreen(
          shatrDepartmentPairs: _fixedShatrDepartmentPairs(),
        ),
      ),
    );
    await _loadCoordinators();
  }

  Future<void> _openImportProcessedFiles() async {
    await Navigator.of(context)
        .push(fadeSlideRoute(const ImportProcessedFilesScreen()));
    await _loadPersistedTickets();
  }

  void _openPreviewAndSend(String key) async {
    final parts = key.split('|');
    final shatr = parts[0];
    final department = parts.length > 1 ? parts[1] : '';
    final tickets = _groups[key] ?? [];
    final coordinator = _coordinators[key];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DepartmentPreviewDialog(
        shatr: shatr,
        department: department,
        tickets: tickets,
        coordinator: coordinator,
        onOpenSettings: _openSettings,
      ),
    );

    if (confirmed == true) {
      await _sendGroup(key);
    }
  }

  Future<void> _sendGroup(String key) async {
    final parts = key.split('|');
    final shatr = parts[0];
    final department = parts.length > 1 ? parts[1] : '';
    final tickets = _groups[key] ?? [];
    final coordinator = _coordinators[key];

    if (coordinator == null || coordinator.email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يوجد بريد منسّق محفوظ لقسم "$department" — أضفه من شاشة الإعدادات أولاً',
          ),
          backgroundColor: Colors.orange.shade800,
          action: SnackBarAction(label: 'الإعدادات', onPressed: _openSettings),
        ),
      );
      return;
    }

    setState(() => _sendingKeys.add(key));

    final success = await MailService.sendDepartmentReport(
      shatr: shatr,
      department: department,
      cycleId: DateTime.now().toString().substring(0, 10),
      tickets: tickets,
      coordinatorEmail: coordinator.email,
      coordinatorName: coordinator.name,
    );

    setState(() {
      _sendingKeys.remove(key);
      if (success) _sentKeys.add(key);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'تم الإرسال بنجاح: $department - $shatr'
                : 'فشل الإرسال: $department - $shatr',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  int get _totalCases =>
      _groups.values.fold(0, (sum, tickets) => sum + tickets.length);

  int get _totalDepartments => _groups.length;

  void _goToTab(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardHomeScreen(
        totalCases: _totalCases,
        totalDepartments: _totalDepartments,
      ),
      ImportSortScreen(
        groups: _groups,
        coordinators: _coordinators,
        sendingKeys: _sendingKeys,
        sentKeys: _sentKeys,
        isLoading: _isLoading,
        onPickFile: _pickAndImportFile,
        onPreviewAndSend: _openPreviewAndSend,
        onOpenSettings: _openSettings,
        onOpenImportProcessedFiles: _openImportProcessedFiles,
        onClearData: _groups.isNotEmpty ? _confirmClearData : null,
      ),
      const ReportsScreen(),
      MoreScreen(onOpenSettings: _openSettings),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _goToTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'إدارة الطلبات',
          ),
          NavigationDestination(
            icon: Icon(Icons.summarize_outlined),
            selectedIcon: Icon(Icons.summarize),
            label: 'التقارير',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'المزيد',
          ),
        ],
      ),
    );
  }
}
