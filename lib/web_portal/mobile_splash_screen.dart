import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mobile_advising_root.dart';

/// شاشة ترحيب/شعار تظهر دائمًا أول ما يُفتح التطبيق (قبل فحص حالة الدخول) -
/// بطلب سليمان صراحةً (2026-08-16): كان التطبيق يفتح مباشرة على شاشة الدخول
/// بلا أي شاشة ترحيبية تسبقها، ويريدها ثابتة تظهر دائمًا (بغضّ النظر عن
/// وجود جلسة محفوظة من عدمه) قبل الانتقال لـ[MobileAdvisingRoot] (الذي
/// يحسم بعدها الدخول/الوجهة الفعلية).
///
/// **تسجيل خروج إجباري عند كل فتح للتطبيق من الصفر** - بطلب سليمان صراحةً
/// (2026-08-16): "اطلب كلمة المرور دائمًا عند فتح التطبيق". Firebase Auth
/// يحفظ الجلسة محليًا بشكل دائم افتراضيًا على أندرويد (سلوك قياسي بمعظم
/// التطبيقات)، فكان من سبق له تسجيل الدخول يدخل مباشرة بلا كلمة مرور عند
/// كل فتح - هذا الودجت هو نقطة الدخول الوحيدة للتطبيق (`home:` بـ
/// main_advising_app.dart) فتسجيل الخروج هنا يضمن طلب كلمة المرور في كل
/// فتح فعلي للتطبيق، بلا أثر على الجلسة أثناء الاستخدام العادي (تبديل
/// الشاشات داخل التطبيق نفسه لا يمر بهذا الودجت مجددًا).
class MobileSplashScreen extends StatefulWidget {
  const MobileSplashScreen({super.key});

  @override
  State<MobileSplashScreen> createState() => _MobileSplashScreenState();
}

class _MobileSplashScreenState extends State<MobileSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () async {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MobileAdvisingRoot()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greenDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 110,
                height: 110,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(28)),
                  alignment: Alignment.center,
                  child: const Text('TU', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'وحدة الإرشاد الأكاديمي والخريجين',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'كلية إدارة الأعمال - جامعة الطائف',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}
