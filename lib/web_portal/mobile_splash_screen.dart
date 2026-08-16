import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mobile_advising_root.dart';

/// شاشة ترحيب/شعار تظهر دائمًا أول ما يُفتح التطبيق (قبل فحص حالة الدخول) -
/// بطلب سليمان صراحةً (2026-08-16)، ثم الانتقال مباشرة لـ[MobileAdvisingRoot]
/// الذي يحسم الوجهة الفعلية: صفحة الدخول إن لم تكن هناك جلسة محفوظة، أو
/// الصفحة الرئيسية مباشرة إن كانت هناك جلسة سابقة على نفس الجهاز - **بلا
/// تسجيل خروج إجباري** (جُرِّب سابقًا بطلبه ثم تراجع عنه صراحةً 2026-08-16:
/// "غير منطقي، أريد فتح التطبيق يذهب للصفحة الرئيسية مباشرة" - يتعارض مع
/// طلب "اطلب كلمة المرور دائمًا" السابق، وهذا هو الأحدث والمُرجَّح).
class MobileSplashScreen extends StatefulWidget {
  const MobileSplashScreen({super.key});

  @override
  State<MobileSplashScreen> createState() => _MobileSplashScreenState();
}

class _MobileSplashScreenState extends State<MobileSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
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
