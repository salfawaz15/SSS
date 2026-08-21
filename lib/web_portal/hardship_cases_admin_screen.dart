import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/hardship_case.dart';
import '../services/hardship_case_service.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';

/// شاشة "حالات الظروف الخاصة" لإدارة الوحدة - قسم منفصل تمامًا عن تقارير
/// طلبات الإضافة/الحذف، يعرض كل الحالات من كل الأقسام مجتمعة، مع إمكانية
/// فتح مسار المتابعة الكامل لأي حالة لمعرفة ماذا تم بشأنها بمرور الوقت.
/// جزء من "لوحة الإرشاد" الموحَّدة - انظر `advising_workspace.dart` لهيدر
/// الصفحة/التنقّل الداخلي/الحالة الفارغة/نافذة مسار المتابعة المشتركة.
class HardshipCasesAdminScreen extends StatelessWidget {
  const HardshipCasesAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'حالات الظروف الخاصة',
      navItems: buildAdminNavItems(context, current: 'hardship'),
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.hardship, isSuperAdmin: isSuperAdmin),
          Expanded(
            child: Container(
              color: DashTokens.pageBg,
              child: StreamBuilder<List<HardshipCase>>(
                stream: HardshipCaseService.watchAllCases(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final cases = List<HardshipCase>.from(snapshot.data!)
                    ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AdvisingPageHeader(
                              breadcrumbTrail: 'متابعة حالات الظروف الخاصة',
                              title: 'متابعة حالات الظروف الخاصة',
                              description: 'كل الحالات المسجَّلة من كل الأقسام، مع مسار متابعة كامل لكل حالة.',
                              icon: Icons.volunteer_activism_outlined,
                            ),
                            const SizedBox(height: 18),
                            if (cases.isEmpty)
                              const AdvisingEmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'لا توجد حالات مسجَّلة',
                                description: 'لا توجد حاليًا حالات ظروف خاصة واردة من الأقسام.\nستظهر الحالات هنا تلقائيًا عند تسجيلها.',
                              )
                            else ...[
                              Text('إجمالي الحالات: ${cases.length}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashTokens.textSecondary)),
                              const SizedBox(height: 12),
                              for (final c in cases) AdvisingCaseCard(hardshipCase: c),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
