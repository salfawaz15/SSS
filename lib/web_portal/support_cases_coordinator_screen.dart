import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/hardship_case.dart';
import '../services/support_case_service.dart';
import '../theme/app_theme.dart';

/// شاشة "حالات الدعم النفسي والاجتماعي" لدى المنسّق - يسجّل حالة جديدة بعد اعتماد
/// نموذج طلب الدعم النفسي والاجتماعي الورقي، ويحدّث مسار متابعتها بمرور
/// الوقت. مجموعة Firestore منفصلة عن حالات الظروف الخاصة لحساسية طبيعتها،
/// رغم اشتراكهما في نفس آلية التتبع. يرى فقط
/// حالات قسمه/شطره (Firestore rules تمنع أي وصول لغير ذلك بنيويًا).
class SupportCasesCoordinatorScreen extends StatefulWidget {
  final String shatr;
  final String department;

  const SupportCasesCoordinatorScreen({
    super.key,
    required this.shatr,
    required this.department,
  });

  @override
  State<SupportCasesCoordinatorScreen> createState() => _SupportCasesCoordinatorScreenState();
}

class _SupportCasesCoordinatorScreenState extends State<SupportCasesCoordinatorScreen> {
  String get _currentEmail => FirebaseAuth.instance.currentUser?.email ?? '';

  Future<void> _openAddCaseDialog() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تسجيل حالة جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم الطالب/ـة'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: 'الرقم الجامعي'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'وصف موجز للحالة',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty || idCtrl.text.trim().isEmpty) {
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      await SupportCaseService.addCase(
                        studentName: nameCtrl.text.trim(),
                        universityId: idCtrl.text.trim(),
                        department: widget.department,
                        shatr: widget.shatr,
                        description: descCtrl.text.trim(),
                        createdBy: _currentEmail,
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFollowUpDialog(HardshipCase c) async {
    HardshipStatus selected = c.status;
    final notesCtrl = TextEditingController();
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('متابعة حالة: ${c.studentName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<HardshipStatus>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'حالة المتابعة'),
                  items: HardshipStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selected = v ?? selected),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات هذا التحديث',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      await SupportCaseService.addFollowUp(
                        caseId: c.id,
                        status: selected,
                        notes: notesCtrl.text.trim(),
                        updatedBy: _currentEmail,
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ التحديث'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistory(HardshipCase c) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('مسار المتابعة: ${c.studentName}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: c.history.reversed.map((h) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.status.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (h.notes.isNotEmpty) Text(h.notes, style: const TextStyle(fontSize: 12.5)),
                      Text(
                        h.updatedAt != null ? h.updatedAt.toString().substring(0, 16) : '',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Color _statusColor(HardshipStatus s) {
    switch (s) {
      case HardshipStatus.newCase:
        return Colors.blueGrey;
      case HardshipStatus.underReview:
        return AppColors.gold;
      case HardshipStatus.contactedStudent:
      case HardshipStatus.contactedFamily:
        return Colors.teal;
      case HardshipStatus.referred:
        return Colors.deepOrange;
      case HardshipStatus.improved:
        return AppColors.green;
      case HardshipStatus.needsOngoingFollowUp:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حالات الدعم النفسي والاجتماعي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddCaseDialog,
        icon: const Icon(Icons.add),
        label: const Text('تسجيل حالة جديدة'),
      ),
      body: StreamBuilder<List<HardshipCase>>(
        stream: SupportCaseService.watchDepartmentCases(
          shatr: widget.shatr,
          department: widget.department,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cases = snapshot.data!;
          if (cases.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'لا توجد حالات دعم مسجَّلة بعد لقسمك.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: cases.length,
            itemBuilder: (context, index) {
              final c = cases[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.studentName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(c.status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              c.status.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(c.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('الرقم الجامعي: ${c.universityId}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      if (c.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(c.description, style: const TextStyle(fontSize: 12.5)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _showHistory(c),
                            icon: const Icon(Icons.history, size: 16),
                            label: const Text('مسار المتابعة'),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: () => _openFollowUpDialog(c),
                            icon: const Icon(Icons.edit_note, size: 16),
                            label: const Text('تحديث الحالة'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
