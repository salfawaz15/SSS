import 'dart:typed_data';

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

  /// بريد منسّق/ة الكلية الحقيقي (المستوى الثالث) - يُطابَق بمفتاح
  /// `shatr|الكلية` مباشرة (لا حاجة لتطبيع أسماء أقسام هنا، ليس قسمًا).
  Coordinator? _findCollegeCoordinator(String shatr) {
    return _coordinatorContacts['$shatr|${Coordinator.collegeMarker}'];
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red.shade700 : null),
    );
  }

  Future<void> _send({
    required String key,
    required Coordinator? coordinator,
    required String missingLabel,
    required Future<Uint8List> Function() buildFile,
    required String subject,
    required String attachmentFilename,
  }) async {
    if (coordinator == null || coordinator.email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يوجد بريد محفوظ لـ"$missingLabel" - أضفه أولاً من شاشة "بيانات منسقي الأقسام" بالموقع'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    setState(() => _sendingKeys.add(key));
    try {
      final bytes = await buildFile();
      final success = await MailService.sendPrebuiltAttachment(
        toEmail: coordinator.email.trim(),
        toName: coordinator.name,
        subject: subject,
        bodyText:
            'السلام عليكم ورحمة الله وبركاته\n'
            'مرفق لكم حالات الحذف والإضافة لتعميمها على المرشدين الأكاديميين\n'
            'وحدة الإرشاد الأكاديمي والخريجين',
        xlsxBytes: bytes,
        attachmentFilename: attachmentFilename,
      );
      _showSnack(
        success ? 'تم إرسال البريد لـ"$missingLabel" بنجاح' : 'تعذّر إرسال البريد - حاول مرة أخرى',
        isError: !success,
      );
    } catch (e) {
      _showSnack('تعذّر إرسال البريد: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingKeys.remove(key));
    }
  }

  Future<void> _sendDepartment(String key, List<Map<String, dynamic>> tickets, String shatr, String department) {
    final shatrLabel = shatr == ExcelParserService.shatrMale ? 'male' : 'female';
    return _send(
      key: key,
      coordinator: _findCoordinator(shatr, department),
      missingLabel: 'منسّق قسم "$department"',
      buildFile: () => EscalationFileService.buildStage2File(tickets),
      subject: 'حالات الحذف والإضافة - $department - $shatr',
      attachmentFilename: '${department}_${shatrLabel}_مرحلة_المنسق.xlsx',
    );
  }

  Future<void> _sendCollege(String key, List<Map<String, dynamic>> shatrTickets, String shatr) {
    final shatrLabel = shatr == ExcelParserService.shatrMale ? 'male' : 'female';
    return _send(
      key: key,
      coordinator: _findCollegeCoordinator(shatr),
      missingLabel: 'منسّق/ة الكلية - $shatr',
      buildFile: () => EscalationFileService.buildStage3File(shatrTickets),
      subject: 'حالات الحذف والإضافة - منسّق الكلية - $shatr',
      attachmentFilename: 'الكلية_${shatrLabel}_مرحلة_منسق_الكلية.xlsx',
    );
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
          final shatrs = [ExcelParserService.shatrMale, ExcelParserService.shatrFemale];

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('منسّقو الكلية (المرحلة 3)', style: AppTextStyles.h3()),
              const SizedBox(height: AppSpacing.sm),
              for (final shatr in shatrs) ...[
                _buildRow(
                  key: 'college|$shatr',
                  icon: Icons.school_outlined,
                  iconColor: AppColors.gold,
                  title: 'منسّق/ة الكلية',
                  subtitle: '$shatr - عدد الحالات: ${tickets.where((t) => (t['shatr'] ?? '') == shatr).length}',
                  onSend: () => _sendCollege(
                    'college|$shatr',
                    tickets.where((t) => (t['shatr'] ?? '') == shatr).toList(),
                    shatr,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.md),
              Text('منسّقو الأقسام (المرحلة 2)', style: AppTextStyles.h3()),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in entries) ...[
                Builder(builder: (context) {
                  final parts = entry.key.split('|');
                  final shatr = parts[0];
                  final department = parts.length > 1 ? parts[1] : '';
                  return _buildRow(
                    key: entry.key,
                    icon: Icons.apartment_outlined,
                    iconColor: AppColors.green,
                    title: department.isEmpty ? '(بدون قسم)' : department,
                    subtitle: '$shatr - عدد الحالات: ${entry.value.length}',
                    onSend: () => _sendDepartment(entry.key, entry.value, shatr, department),
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow({
    required String key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onSend,
  }) {
    final isSending = _sendingKeys.contains(key);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.12), child: Icon(icon, color: iconColor)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: isSending
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                tooltip: 'إرسال بالبريد',
                icon: const Icon(Icons.mail_outline, color: Colors.teal),
                onPressed: onSend,
              ),
      ),
    );
  }
}
