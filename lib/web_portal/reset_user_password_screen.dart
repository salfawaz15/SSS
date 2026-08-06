import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/excel_parser_service.dart';
import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';

class _AccountEntry {
  final String label;
  final String email;

  const _AccountEntry(this.label, this.email);
}

/// صفحة "الحسابات وكلمات المرور" - حصرية على حساب المدير العام (salfawaz).
/// لا تعرض أي كلمة مرور (Firebase لا يخزّنها نصيًا أبدًا ولا يمكن لأي جهة
/// استرجاعها)، بل تسهّل فقط الوصول السريع لتعيين كلمة مرور جديدة لأي حساب
/// عبر فتح صفحة Authentication في Firebase Console مباشرة (مجانًا، بلا حاجة
/// لترقية خطة المشروع). بديل مؤقت لحين اعتماد الموقع رسميًا، حيث يمكن لاحقًا
/// استبدالها بتعيين كلمة المرور من ضغطة واحدة داخل هذه الصفحة نفسها عبر
/// Cloud Function (يتطلب حينها ترقية الخطة إلى Blaze).
class ResetUserPasswordScreen extends StatelessWidget {
  const ResetUserPasswordScreen({super.key});

  static const String _consoleUsersUrl =
      'https://console.firebase.google.com/project/sss-advising-tu/authentication/users';

  static List<_AccountEntry> _allAccounts() {
    final list = <_AccountEntry>[
      const _AccountEntry('إدارة وحدة الإرشاد الأكاديمي', PortalAccounts.adminEmail),
      const _AccountEntry('المدير العام (salfawaz)', PortalAccounts.superAdminEmail),
    ];
    for (final entry in PortalAccounts.viewerEmails.entries) {
      list.add(_AccountEntry(entry.key, entry.value));
    }
    for (final shatr in [
      ExcelParserService.shatrMale,
      ExcelParserService.shatrFemale,
    ]) {
      for (final department in ExcelParserService.departments) {
        final email = PortalAccounts.coordinatorEmail(shatr, department);
        if (email != null) {
          list.add(_AccountEntry('$department — $shatr', email));
        }
      }
    }
    return list;
  }

  Future<void> _openConsole(BuildContext context) async {
    final uri = Uri.parse(_consoleUsersUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الرابط تلقائيًا - انسخه وافتحه يدويًا')),
      );
    }
  }

  void _copyEmail(BuildContext context, String email) {
    Clipboard.setData(ClipboardData(text: email));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ البريد: $email')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _allAccounts();
    return PortalScaffold(
      title: 'الحسابات وكلمات المرور',
      navItems: buildAdminNavItems(context, current: 'tools'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'كيف تُعيّن كلمة مرور جديدة لأي حساب؟',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                const SizedBox(height: 8),
                const Text(
                  '١. اضغط "فتح Firebase Console" أدناه.\n'
                  '٢. سجّل الدخول بحساب Google الذي يملك المشروع (ليس بحساب salfawaz).\n'
                  '٣. ابحث عن بريد الحساب المطلوب في القائمة (انسخه من هنا بالزر بجانبه).\n'
                  '٤. اضغط النقاط الثلاث أمامه ثم "إعادة تعيين كلمة المرور".\n\n'
                  'ملاحظة: لا يمكن لأي جهة - بما فيها Google/Firebase نفسها - عرض '
                  'كلمة المرور الحالية لأي حساب؛ الممكن فقط هو تعيين كلمة جديدة.',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _openConsole(context),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح Firebase Console'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'كل الحسابات (${accounts.length})',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          ...accounts.map((a) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.green.withValues(alpha: 0.12),
                    child: const Icon(Icons.person_outline, color: AppColors.green, size: 18),
                  ),
                  title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: Text(a.email, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'نسخ البريد',
                    onPressed: () => _copyEmail(context, a.email),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
