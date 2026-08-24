import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../utils/mailto.dart';
import '../../../web_portal/change_password_dialog.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/portal_app_bar_logo.dart';

/// شاشة "المزيد" - المرحلة الأولى تقتصر على تسجيل الخروج + بطاقة الدعم
/// الفني (القسم 17: تسجيل الخروج ضمن "المزيد" لا تبويبًا مستقلًا)؛ بقية
/// العناصر (البحث/حالة البيانات/سجل العمليات/فتح النظام الكامل...) تُضاف
/// بمراحل تالية.
class PortalMoreScreen extends StatelessWidget {
  const PortalMoreScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من "بوابة الإرشاد"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) await authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: kPortalAppBarLeadingWidth,
        leading: const PortalAppBarLogo(),
        title: const Text('المزيد'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: AppColors.green),
                  title: const Text('تغيير كلمة المرور'),
                  onTap: () => showChangePasswordDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.errorRed),
                  title: const Text('تسجيل الخروج'),
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text('بقية الخيارات (البحث، سجل العمليات، فتح النظام الكامل...) قيد التطوير - المرحلة التالية.', style: AppTextStyles.caption(color: Colors.black45)),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SupportCard(),
        ],
      ),
    );
  }
}

/// بطاقة "الدعم الفني" - نفس تصميم `_UnitLeaderCard` بصفحة "تواصل" بالموقع
/// حرفيًا (تدرّج أخضر داكن، أيقونة دائرية بيضاء شفافة، اسم ذهبي، بريد
/// قابل للنقر) بطلب سليمان صراحةً (2026-08-23: "يكون هناك مع تسجيل الخروج
/// مثل الصورة").
class _SupportCard extends StatelessWidget {
  const _SupportCard();

  static const _email = 'salfawaz@tu.edu.sa';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الدعم الفني', style: AppTextStyles.h3()),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.greenDark, AppColors.green],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.build_outlined, color: AppColors.goldLight, size: 21),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'الدعم الفني للموقع',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'سليمان مفوز سليم الفواز',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.goldLight),
                      ),
                      const SizedBox(height: 3),
                      InkWell(
                        onTap: () => openMailto(_email),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.email_outlined, size: 13, color: AppColors.goldLight),
                            SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.goldLight,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.goldLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
