import 'package:flutter/material.dart';

import '../../../data/academic_department_names.dart';
import '../../../models/coordinator.dart';
import '../../../services/escalation_file_service.dart';
import '../../../services/excel_parser_service.dart';
import '../../../services/firestore_coordinator_service.dart';
import '../../../services/firestore_ticket_service.dart';
import '../../../services/mail_service.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/mobile_empty_state.dart';
import '../../widgets/mobile_error_state.dart';
import '../../widgets/mobile_loading_state.dart';
import '../../widgets/portal_app_bar_logo.dart';

/// إرسال ملف "مرحلة المنسّق" (كل حالات القسم مدمجة بملف واحد) بالبريد
/// الإلكتروني الحقيقي لمنسّق/ة القسم مباشرة من التطبيق - بديل لنفس الميزة
/// بالموقع (`admin_workspace_screen.dart`) التي تفشل هناك بسبب قيود CORS
/// (المتصفح يمنع اتصال JS مباشر بـSendGrid)؛ التطبيق لا يخضع لهذا القيد
/// (سليمان صراحةً 2026-08-30: "هل يمكن من خلال التطبيق؟" بعد فشل زر الموقع).
/// نفس منطق البحث المتسامح عن بريد المنسّق (`normalizeDepartmentName`) الذي
/// أُصلح بالموقع - القسم بالتذكرة قد يختلف بصورة الهمزة عن النص المخزَّن
/// بشاشة "بيانات منسقي الأقسام".
class CoordinatorEmailScreen extends StatefulWidget {
  const CoordinatorEmailScreen({super.key});

  @override
  State<CoordinatorEmailScreen> createState() => _CoordinatorEmailScreenState();
}

class _CoordinatorEmailScreenState extends State<CoordinatorEmailScreen> {
  Map<String, Coordinator> _coordinatorContacts = {};
  final Set<String> _sendingKeys = {};

  @override
  void initState() {
    super.initState();
    FirestoreCoordinatorService.watchAll().first.then((c) {
      if (mounted) setState(() => _coordinatorContacts = c);
    });
  }

  Coordinator? _findCoordinator(String shatr, String department) {
    final normalizedTarget = normalizeDepartmentName(department);
    for (final c in _coordinatorContacts.values) {
      if (c.shatr == shatr && normalizeDepartmentName(c.department) == normalizedTarget) {
        return c;
      }
    }
    return null;
  }

  Future<void> _send(String key, List<Map<String, dynamic>> tickets, String shatr, String department) async {
    final coordinator = _findCoordinator(shatr, department);
    if (coordinator == null || coordinator.email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يوجد بريد محفوظ لمنسّق قسم "$department" - أضفه أولاً من شاشة "بيانات منسقي الأقسام" بالموقع'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    setState(() => _sendingKeys.add(key));
    try {
      final bytes = await EscalationFileService.buildStage2File(tickets);
      final shatrLabel = shatr == ExcelParserService.shatrMale ? 'male' : 'female';
      final success = await MailService.sendPrebuiltAttachment(
        toEmail: coordinator.email.trim(),
        toName: coordinator.name,
        subject: 'حالات الحذف والإضافة - $department - $shatr',
        bodyText:
            'السلام عليكم ورحمة الله وبركاته\n'
            'مرفق لكم حالات الحذف والإضافة لتعميمها على المرشدين الأكاديميين\n'
            'وحدة الإرشاد الأكاديمي والخريجين',
        xlsxBytes: bytes,
        attachmentFilename: '${department}_${shatrLabel}_مرحلة_المنسق.xlsx',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'تم إرسال البريد لمنسّق/ة "$department" بنجاح' : 'تعذّر إرسال البريد - حاول مرة أخرى'),
            backgroundColor: success ? null : Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر إرسال البريد: $e')));
      }
    } finally {
      if (mounted) setState(() => _sendingKeys.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: kPortalAppBarLeadingWidth,
        leading: const PortalAppBarLogo(),
        title: const Text('إرسال بريد لمنسّقي الأقسام'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreTicketService.watchAllTickets(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MobileErrorState(onRetry: () => setState(() {}));
          }
          if (!snapshot.hasData) {
            return const MobileLoadingState();
          }
          final tickets = snapshot.data!;
          if (tickets.isEmpty) {
            return const MobileEmptyState(message: 'لا توجد حالات مرفوعة بعد', icon: Icons.mail_outline);
          }
          final groups = ExcelParserService.groupByShatrAndDepartment(tickets);
          final entries = groups.entries.where((e) => e.value.isNotEmpty).toList();
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final parts = entry.key.split('|');
              final shatr = parts[0];
              final department = parts.length > 1 ? parts[1] : '';
              final isSending = _sendingKeys.contains(entry.key);
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.green.withValues(alpha: 0.12),
                    child: const Icon(Icons.apartment_outlined, color: AppColors.green),
                  ),
                  title: Text(department.isEmpty ? '(بدون قسم)' : department),
                  subtitle: Text('$shatr - عدد الحالات: ${entry.value.length}'),
                  trailing: isSending
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          tooltip: 'إرسال ملف مرحلة المنسّق بالبريد',
                          icon: const Icon(Icons.mail_outline, color: Colors.teal),
                          onPressed: () => _send(entry.key, entry.value, shatr, department),
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
