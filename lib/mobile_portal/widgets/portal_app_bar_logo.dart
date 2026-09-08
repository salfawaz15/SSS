import 'package:flutter/material.dart';

import '../../services/portal_update_service.dart';
import '../../theme/app_theme.dart';
import '../services/portal_update_controller.dart';

/// الشعار الرسمي النظيف (خلفية مُفرَّغة فعليًا) - نفس شعار شاشة الدخول
/// بالضبط، ثابت أعلى يمين كل شاشات التطبيق (باتجاه RTL) بطلب سليمان صراحةً
/// (2026-08-23). يُستخدَم دومًا مع `AppBar(leadingWidth: kPortalAppBarLeadingWidth, leading: const PortalAppBarLogo())`.
///
/// يحمل الآن أيضًا نقطة إشعار صغيرة (سليمان صراحةً 2026-09-09) تظهر تلقائيًا
/// طالما هناك تحديث متاح - بصرف النظر عن رد المستخدم السابق ("لاحقًا"/"لا
/// تحدّث أبدًا")، والضغط عليها يعيد فتح حوار التحديث مباشرة (ويُلغي "لا
/// تحدّث أبدًا" إن كان مفعَّلاً). يُستمَع للحالة عبر [PortalUpdateController]
/// المشترك بدل فحص مستقل بكل نسخة من الشعار.
const kPortalAppBarLeadingWidth = 64.0;

class PortalAppBarLogo extends StatelessWidget {
  const PortalAppBarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PortalUpdateInfo?>(
      valueListenable: PortalUpdateController.instance.latest,
      builder: (context, updateInfo, _) {
        final logo = Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Image.asset(
            'assets/images/unit_logo_clean_transparent_cropped.png',
            fit: BoxFit.contain,
          ),
        );
        if (updateInfo == null) return logo;
        return GestureDetector(
          onTap: () => PortalUpdateController.instance.openDialogManually(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              logo,
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.errorRed,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
