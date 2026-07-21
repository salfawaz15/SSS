import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/excel_parser_service.dart';
import '../services/mail_service.dart';

class ImportDistributionScreen extends StatefulWidget {
  const ImportDistributionScreen({super.key});

  @override
  State<ImportDistributionScreen> createState() =>
      _ImportDistributionScreenState();
}

class _ImportDistributionScreenState extends State<ImportDistributionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, List<Map<String, dynamic>>> _groups = {};
  bool _isLoading = false;
  final Set<String> _sendingKeys = {};
  final Set<String> _sentKeys = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _pickAndImportFile() async {
    setState(() => _isLoading = true);

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
    final tickets = ExcelParserService.parseTickets(bytes);
    final groups = ExcelParserService.groupByShatrAndDepartment(tickets);

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

  Future<void> _sendGroup(String key) async {
    final parts = key.split('|');
    final shatr = parts[0];
    final department = parts.length > 1 ? parts[1] : '';
    final tickets = _groups[key] ?? [];

    setState(() => _sendingKeys.add(key));

    final success = await MailService.sendDepartmentReport(
      shatr: shatr,
      department: department,
      cycleId: DateTime.now().toString().substring(0, 10),
      tickets: tickets,
    );

    setState(() {
      _sendingKeys.remove(key);
      if (success) _sentKeys.add(key);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'تم الإرسال بنجاح: $department - $shatr'
              : 'فشل الإرسال: $department - $shatr'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupsForShatr(
      String shatr) {
    return _groups.entries.where((e) => e.key.startsWith('$shatr|')).toList();
  }

  Widget _buildDepartmentCard(
      MapEntry<String, List<Map<String, dynamic>>> entry) {
    final key = entry.key;
    final department = key.split('|').length > 1 ? key.split('|')[1] : '';
    final tickets = entry.value;
    final priorityCount = tickets
        .where((t) =>
            t['expected_graduate'] == true || t['has_disability'] == true)
        .length;
    final isSending = _sendingKeys.contains(key);
    final isSent = _sentKeys.contains(key);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(department.isEmpty ? '(بدون قسم)' : department,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('عدد الحالات: ${tickets.length}'),
                  if (priorityCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('أولوية: $priorityCount',
                            style: TextStyle(
                                color: Colors.orange.shade900, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: isSending || isSent ? null : () => _sendGroup(key),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSent ? Colors.grey : null,
              ),
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isSent ? 'تم الإرسال' : 'إرسال للمنسّق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShatrList(String shatr) {
    final entries = _groupsForShatr(shatr);
    if (entries.isEmpty) {
      return const Center(child: Text('لا توجد بيانات مستوردة بعد'));
    }
    return ListView(
      children: entries.map(_buildDepartmentCard).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استيراد وفرز طلبات الحذف والإضافة'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'شطر الطلاب'),
            Tab(text: 'شطر الطالبات'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildShatrList(ExcelParserService.shatrMale),
                _buildShatrList(ExcelParserService.shatrFemale),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndImportFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('استيراد ملف Excel'),
      ),
    );
  }
}