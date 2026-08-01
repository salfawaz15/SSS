import 'package:flutter/material.dart';

import '../models/coordinator.dart';
import '../services/excel_parser_service.dart';
import '../theme/app_theme.dart';

const _departmentIcons = <String, IconData>{
  'نظم المعلومات الإدارية': Icons.dns_outlined,
  'المحاسبة': Icons.calculate_outlined,
  'إدارة الأعمال': Icons.business_center_outlined,
  'التسويق': Icons.campaign_outlined,
  'التمويل': Icons.account_balance_outlined,
};

IconData _iconForDepartment(String department) {
  for (final entry in _departmentIcons.entries) {
    if (department.contains(entry.key)) return entry.value;
  }
  return Icons.apartment_outlined;
}

/// شاشة "الاستيراد والفرز" - مدفوعة بالكامل بالبيانات القادمة من HomeShell
/// (لا تملك حالتها الخاصة عدا تبويب شطر الطلاب/الطالبات المحلي).
class ImportSortScreen extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> groups;
  final Map<String, Coordinator> coordinators;
  final Set<String> sendingKeys;
  final Set<String> sentKeys;
  final bool isLoading;
  final VoidCallback onPickFile;
  final void Function(String key) onPreviewAndSend;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenImportProcessedFiles;
  final VoidCallback? onClearData;

  const ImportSortScreen({
    super.key,
    required this.groups,
    required this.coordinators,
    required this.sendingKeys,
    required this.sentKeys,
    required this.isLoading,
    required this.onPickFile,
    required this.onPreviewAndSend,
    required this.onOpenSettings,
    required this.onOpenImportProcessedFiles,
    this.onClearData,
  });

  @override
  State<ImportSortScreen> createState() => _ImportSortScreenState();
}

class _ImportSortScreenState extends State<ImportSortScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupsForShatr(
    String shatr,
  ) {
    return widget.groups.entries
        .where((e) => e.key.startsWith('$shatr|'))
        .toList();
  }

  Widget _buildDepartmentCard(
    MapEntry<String, List<Map<String, dynamic>>> entry,
  ) {
    final key = entry.key;
    final department = key.split('|').length > 1 ? key.split('|')[1] : '';
    final tickets = entry.value;
    final priorityCount = tickets
        .where(
          (t) => t['expected_graduate'] == true || t['has_disability'] == true,
        )
        .length;

    var totalActions = 0;
    var completedActions = 0;
    for (final t in tickets) {
      final actions = (t['actions'] as List?) ?? [];
      for (final a in actions) {
        totalActions++;
        if ((a as Map<String, dynamic>)['status'] == 'تم الإنجاز') {
          completedActions++;
        }
      }
    }

    final isSending = widget.sendingKeys.contains(key);
    final isSent = widget.sentKeys.contains(key);
    final coordinator = widget.coordinators[key];
    final hasCoordinatorEmail =
        coordinator != null && coordinator.email.isNotEmpty;

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isSending || isSent ? null : () => widget.onPreviewAndSend(key),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.green.withValues(alpha: 0.12),
                child: Icon(
                  _iconForDepartment(department),
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      department.isEmpty ? '(بدون قسم)' : department,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'عدد الحالات: ${tickets.length}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (priorityCount > 0)
                          _Badge(
                            text: 'أولوية: $priorityCount',
                            color: AppColors.gold,
                          ),
                        if (totalActions > 0)
                          _Badge(
                            text: 'منجز: $completedActions/$totalActions',
                            color: AppColors.green,
                          ),
                        if (!hasCoordinatorEmail)
                          _Badge(
                            text: 'بلا بريد منسّق',
                            color: Colors.red.shade700,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: isSending || isSent
                    ? null
                    : () => widget.onPreviewAndSend(key),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSent ? Colors.grey : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: isSending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(isSent ? Icons.check_circle : Icons.send, size: 18),
                label: Text(isSent ? 'تم الإرسال' : 'معاينة وإرسال'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShatrList(String shatr) {
    final entries = _groupsForShatr(shatr);
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 20),
              Text(
                'لا توجد بيانات مستوردة بعد',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'استورد ملف Excel من الزر أسفل الشاشة',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: entries.map(_buildDepartmentCard).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الطلبات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'استيراد الملفات المعالجة',
            onPressed: widget.onOpenImportProcessedFiles,
          ),
          if (widget.onClearData != null)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'تفريغ البيانات المستوردة',
              onPressed: widget.onClearData,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'شطر الطلاب'),
            Tab(text: 'شطر الطالبات'),
          ],
        ),
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildShatrList(ExcelParserService.shatrMale),
                _buildShatrList(ExcelParserService.shatrFemale),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onPickFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('استيراد ملف Excel'),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class DepartmentPreviewDialog extends StatelessWidget {
  final String shatr;
  final String department;
  final List<Map<String, dynamic>> tickets;
  final Coordinator? coordinator;
  final VoidCallback onOpenSettings;

  const DepartmentPreviewDialog({
    super.key,
    required this.shatr,
    required this.department,
    required this.tickets,
    required this.coordinator,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final hasEmail = coordinator != null && coordinator!.email.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                department.isEmpty ? '(بدون قسم)' : department,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(shatr, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: hasEmail
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasEmail ? Icons.email_outlined : Icons.warning_amber,
                      color: hasEmail
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasEmail
                            ? 'سيُرسل إلى: ${coordinator!.name.isNotEmpty ? '${coordinator!.name} — ' : ''}${coordinator!.email}'
                            : 'لا يوجد بريد منسّق محفوظ لهذا القسم',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (!hasEmail)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(false);
                          onOpenSettings();
                        },
                        child: const Text('إضافة'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'عدد الحالات: ${tickets.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الاسم')),
                        DataColumn(label: Text('نوع الإجراء')),
                        DataColumn(label: Text('المقرر')),
                        DataColumn(label: Text('أولوية')),
                      ],
                      rows: tickets.map((t) {
                        final actions = (t['actions'] as List?) ?? [];
                        final firstAction = actions.isNotEmpty
                            ? actions.first as Map<String, dynamic>
                            : null;
                        final isPriority =
                            t['expected_graduate'] == true ||
                            t['has_disability'] == true;
                        return DataRow(
                          cells: [
                            DataCell(Text(t['name']?.toString() ?? '')),
                            DataCell(
                              Text(
                                firstAction?['action_type']?.toString() ?? '',
                              ),
                            ),
                            DataCell(
                              Text(firstAction?['course']?.toString() ?? ''),
                            ),
                            DataCell(
                              isPriority
                                  ? const Icon(
                                      Icons.star,
                                      size: 16,
                                      color: AppColors.gold,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: hasEmail
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('تأكيد الإرسال'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
