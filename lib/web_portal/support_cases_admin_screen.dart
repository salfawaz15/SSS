import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/hardship_case.dart';
import '../services/support_case_service.dart';
import '../theme/dashboard_tokens.dart';
import 'admin_nav.dart';
import 'advising_workspace.dart';
import 'portal_accounts.dart';
import 'portal_header.dart';

/// شاشة "حالات الدعم النفسي والاجتماعي" لإدارة الوحدة - قسم منفصل تمامًا عن
/// حالات الظروف الخاصة وعن تقارير طلبات الإضافة/الحذف، يعرض كل الحالات من
/// كل الأقسام مجتمعة، مع إمكانية فتح مسار المتابعة الكامل لأي حالة. جزء من
/// "لوحة الإرشاد" الموحَّدة - انظر `advising_workspace.dart`.
class SupportCasesAdminScreen extends StatelessWidget {
  const SupportCasesAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = FirebaseAuth.instance.currentUser?.email == PortalAccounts.superAdminEmail ||
        PortalAccounts.isCurrentSessionSuperAdmin;

    return PortalScaffold(
      title: 'حالات الدعم النفسي والاجتماعي',
      navItems: buildAdminNavItems(context, current: 'support'),
      body: Column(
        children: [
          AdvisingSubNavigation(current: AdvisingSection.support, isSuperAdmin: isSuperAdmin),
          Expanded(
            child: Container(
              color: DashTokens.pageBg,
              child: StreamBuilder<List<HardshipCase>>(
                stream: SupportCaseService.watchAllCases(),
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
                            const AdvisingPageHeader(
                              breadcrumbTrail: 'متابعة حالات الدعم النفسي والاجتماعي',
                              title: 'متابعة حالات الدعم النفسي والاجتماعي',
                              description: 'متابعة الحالات الواردة ومسار التعامل معها حتى الإغلاق.',
                              icon: Icons.favorite_border,
                            ),
                            const SizedBox(height: 18),
                            if (cases.isEmpty)
                              const AdvisingEmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'لا توجد حالات مسجَّلة',
                                description: 'لا توجد حاليًا حالات دعم نفسي واجتماعي واردة من الأقسام.\nستظهر الحالات هنا تلقائيًا عند تسجيلها.',
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
