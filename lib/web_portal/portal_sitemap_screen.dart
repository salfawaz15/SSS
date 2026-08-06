import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';

/// عنصر واحد في خريطة صفحات الموقع: اسم الشاشة والدور الذي يفتحها.
class _SitemapEntry {
  final String title;
  final IconData icon;
  const _SitemapEntry(this.title, this.icon);
}

class _SitemapGroup {
  final String role;
  final IconData icon;
  final List<_SitemapEntry> pages;
  const _SitemapGroup({required this.role, required this.icon, required this.pages});
}

/// خريطة مرجعية بصرية لصفحات البوابة مصنَّفة حسب الدور الذي يفتح كل صفحة -
/// قائمة مرجعية للمدير العام لفهم بنية الموقع ككل، وليست بديلاً عن نظام
/// توجيه (Router) فعلي - كل صفحة تُفتح حاليًا من داخل شاشتها الأصلية.
const _kSitemap = [
  _SitemapGroup(
    role: 'الدخول',
    icon: Icons.login,
    pages: [
      _SitemapEntry('الصفحة العامة (قبل الدخول)', Icons.public),
      _SitemapEntry('تسجيل الدخول (إدارة/منسّق/منسّق كلية)', Icons.vpn_key_outlined),
      _SitemapEntry('الدخول السري للمدير العام', Icons.lock_person_outlined),
    ],
  ),
  _SitemapGroup(
    role: 'الإدارة',
    icon: Icons.admin_panel_settings_outlined,
    pages: [
      _SitemapEntry('لوحة الإدارة الرئيسية', Icons.dashboard_outlined),
      _SitemapEntry('التقارير', Icons.assessment_outlined),
      _SitemapEntry('تنزيل ملفات الحالات', Icons.folder_zip_outlined),
      _SitemapEntry('متابعة حالات الظروف الخاصة', Icons.volunteer_activism_outlined),
      _SitemapEntry('متابعة حالات الدعم النفسي والاجتماعي', Icons.favorite_border),
      _SitemapEntry('بيانات منسوبي الكلية (مدير عام)', Icons.badge_outlined),
      _SitemapEntry('توزيع فترات الإرشاد (مدير عام)', Icons.schedule_outlined),
      _SitemapEntry('تسكين المقررات وشعبها (مدير عام)', Icons.event_note_outlined),
      _SitemapEntry('الجدول الدراسي لأعضاء هيئة التدريس (مدير عام)', Icons.person_search_outlined),
      _SitemapEntry('بيانات منسّقي الأقسام (مدير عام)', Icons.contact_mail_outlined),
      _SitemapEntry('قائمة مرشدي القسم (مدير عام)', Icons.groups_outlined),
      _SitemapEntry('الحسابات وكلمات المرور (مدير عام)', Icons.vpn_key_outlined),
    ],
  ),
  _SitemapGroup(
    role: 'منسّق القسم',
    icon: Icons.groups_2_outlined,
    pages: [
      _SitemapEntry('لوحة منسّق القسم', Icons.dashboard_outlined),
      _SitemapEntry('متابعة حالات الظروف الخاصة (منسّق)', Icons.volunteer_activism_outlined),
      _SitemapEntry('متابعة حالات الدعم النفسي والاجتماعي (منسّق)', Icons.favorite_border),
    ],
  ),
  _SitemapGroup(
    role: 'منسّق الكلية',
    icon: Icons.apartment_outlined,
    pages: [
      _SitemapEntry('لوحة منسّق الكلية', Icons.dashboard_outlined),
    ],
  ),
  _SitemapGroup(
    role: 'عرض فقط (أمين/سكرتير الوحدة)',
    icon: Icons.visibility_outlined,
    pages: [
      _SitemapEntry('تقرير شامل (عرض/تصدير/طباعة فقط)', Icons.receipt_long_outlined),
    ],
  ),
];

class PortalSitemapScreen extends StatelessWidget {
  const PortalSitemapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'خريطة صفحات الموقع',
      navItems: buildAdminNavItems(context, current: 'sitemap'),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _kSitemap.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final group = _kSitemap[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.green.withValues(alpha: 0.12),
                        child: Icon(group.icon, color: AppColors.green),
                      ),
                      const SizedBox(width: 10),
                      Text(group.role, style: AppTextStyles.h3()),
                    ],
                  ),
                  const Divider(height: 24),
                  for (final page in group.pages)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(page.icon, size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(child: Text(page.title, style: AppTextStyles.body())),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
