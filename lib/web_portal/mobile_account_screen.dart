import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'change_password_dialog.dart';
import 'portal_role_gate.dart';
import 'staff_number_login_screen.dart';

/// عنوان ترحيب مختصر لكل دور.
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

/// شاشة "حسابي" - تُفتَح فقط عند ضغط زر تسجيل الدخول من الصفحة الرئيسية
/// العامة (`mobile_home_screen.dart`)، بلا تأثير على أول ما يفتح به التطبيق.
/// الدخول عبر [StaffNumberLoginScreen] (نظام رقم المنسوب الجديد) حصرًا -
/// لا شاشة الدخول القديمة بالبريد الحرفي (بطلب سليمان صراحةً 2026-08-16).
/// (بطلب سليمان الصريح 2026-08-16: "طبيعي عندما أدخل الموقع يفتح على
/// الصفحة الرئيسية، كذلك في التطبيق - بعدها لي الخيار أن أبقى بالصفحة
/// الرئيسية أو أذهب لتسجيل الدخول"). تعرض شاشة الدخول إن لم تكن هناك جلسة،
/// أو بطاقة الحساب (الاسم/الدور + تغيير كلمة المرور + خروج) إن كانت هناك
/// جلسة محفوظة - **الجلسة تبقى محفوظة طبيعيًا بين مرات فتح التطبيق**، لكن
/// الشاشة الأولى تبقى دائمًا الصفحة الرئيسية العامة لا هذه الشاشة.
class MobileAccountScreen extends StatelessWidget {
  const MobileAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalRoleGate(
      loginBuilder: (context) => const StaffNumberLoginScreen(),
      builder: (context, resolved) => Scaffold(
        backgroundColor: const Color(0xFFF5F7F6),
        appBar: AppBar(
          backgroundColor: AppColors.greenDark,
          foregroundColor: Colors.white,
          title: const Text('حسابي'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.person_outline, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _roleTitle(resolved.role),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('EEEE، d MMMM y', 'ar').format(DateTime.now()),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _AccountAction(
                  icon: Icons.lock_outline,
                  label: 'تغيير كلمة المرور',
                  onTap: () => showChangePasswordDialog(context),
                ),
                const SizedBox(height: 10),
                _AccountAction(
                  icon: Icons.logout,
                  label: 'تسجيل خروج',
                  color: Colors.red.shade700,
                  onTap: () {
                    FirebaseAuth.instance.signOut();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppColors.greenDark),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color ?? Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }
}
