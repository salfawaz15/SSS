import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'change_password_dialog.dart';
import 'mobile_about_unit_screen.dart';
import 'mobile_bottom_nav_bar.dart';
import 'portal_role_gate.dart';

/// عنوان ترحيب مختصر لكل دور - يُعرَض بالشاشة الرئيسية الجوّالة الموحَّدة.
String _roleTitle(PortalRole role) => switch (role) {
      PortalRole.superAdmin => 'المدير العام',
      PortalRole.admin => 'إدارة الوحدة',
      PortalRole.ameen => 'أمين الوحدة',
      PortalRole.unitCoordinator => 'منسّق الوحدة',
      PortalRole.collegeCoordinator => 'منسّق الكلية',
      PortalRole.deptCoordinator => 'منسّق القسم',
      PortalRole.trackCoordinator => 'منسّق المسار',
      PortalRole.unknown => 'حسابك',
    };

/// الشاشة الرئيسية الجوّالة الموحَّدة لكل الأدوار - **إعادة بناء كاملة من
/// الصفر** (2026-08-16) بعد أن كشف اختبار سليمان الحي أن دفع شاشات الموقع
/// العريضة (`AdminWorkspaceScreen`, `CoordinatorWorkspaceScreen`...) مباشرة
/// على الجوال ينتج صفحات مكسورة (رسوم بيانية تفيض، أشرطة علوية مزدحمة) -
/// هذه الشاشات لم تُختبَر على عرض جوال ضيق من قبل إطلاقًا. القرار: التوقف
/// عن الاعتماد عليها كليًا بالجوال، والبدء بشاشة واحدة نظيفة فقط بطلب
/// سليمان الصريح ("يبدأ بالصفحة الرئيسية فقط") قبل إضافة أي وجهة حقيقية
/// أخرى - كل وجهة قادمة ستُبنى جوّالة أصيلة من الصفر لاحقًا، لا نافذة لعرض
/// شاشة حاسوب.
///
/// تبويبا "إدارة الطلبات"/"التقارير" بالشريط السفلي معطَّلان مؤقتًا (رسالة
/// "قيد التطوير") بدل فتح شاشة عريضة مكسورة - سيُستبدَلان بشاشات جوّالة
/// حقيقية واحدة تلو الأخرى بجلسات قادمة.
class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({super.key, required this.role});

  final PortalRole role;

  void _showComingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label - قيد التطوير، قريبًا بإذن الله')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _roleTitle(role);
    final today = DateFormat('EEEE، d MMMM y', 'ar').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(0xFFE7EFEA),
                  child: Icon(Icons.person_outline, color: AppColors.greenDark),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'تغيير كلمة المرور',
                  icon: const Icon(Icons.lock_outline, color: AppColors.greenDark),
                  onPressed: () => showChangePasswordDialog(context),
                ),
                IconButton(
                  tooltip: 'تسجيل خروج',
                  icon: const Icon(Icons.logout, color: AppColors.greenDark),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.greenDark),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.greenDark, AppColors.green],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Text('👋', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'أهلاً بك',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          today,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MobileAboutUnitScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_outlined, color: AppColors.green),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('عن الوحدة - الهيكل التنظيمي والتواصل', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                      const Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.gold),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'واجهة الجوال الجديدة قيد الإنشاء تدريجيًا - المزيد من الأقسام قريبًا هنا.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MobileBottomNavBar(
        currentIndex: 0,
        tabs: [
          MobileNavTab(icon: Icons.home_outlined, label: 'الرئيسية', onTap: () {}),
          MobileNavTab(
            icon: Icons.fact_check_outlined,
            label: 'إدارة الطلبات',
            onTap: () => _showComingSoon(context, 'إدارة الطلبات'),
          ),
          MobileNavTab(
            icon: Icons.assessment_outlined,
            label: 'التقارير',
            onTap: () => _showComingSoon(context, 'التقارير'),
          ),
        ],
      ),
    );
  }
}
