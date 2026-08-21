import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';
import 'web_portal/hidden_admin_login_screen.dart';
import 'web_portal/portal_root.dart';
import 'web_portal/public_landing_screen.dart';

/// المسار السرّي لدخول المدير العام (salfawaz) - غير ظاهر أو مرتبط بأي زر
/// في الموقع؛ يُفتح فقط بكتابة الرابط كاملاً في المتصفح:
/// https://sss-advising-tu.web.app/#su-portal-2026
const String _hiddenAdminPath = 'su-portal-2026';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (kIsWeb) {
      // إصلاح تعليق الرفع/الاستعلامات بلا نهاية (بلا خطأ ولا نجاح) على بعض
      // الشبكات (جامعية/شركات) التي تمنع قناة البث المباشرة WebChannel
      // (بروكسي/جدار حماية/فحص TLS) - سليمان لاحظه فعليًا 2026-08-09 عند
      // رفع ملف معالج بصفحة المنسّق. الحل الرسمي من Firebase: يكتشف تلقائيًا
      // إن كانت الشبكة تحتاج Long-Polling كبديل ويستخدمه بدل التعليق الصامت.
      FirebaseFirestore.instance.settings = const Settings(
        webExperimentalAutoDetectLongPolling: true,
      );
    }
  } catch (e) {
    // بوابة الويب (Firestore/Auth) تعتمد على Firebase - تطبيق الأندرويد
    // (HomeShell) لا يعتمد عليها إطلاقًا، فلا يتأثر لو فشلت التهيئة هنا.
    debugPrint('تعذّر تهيئة Firebase: $e');
  }
  await initializeDateFormatting('ar', null);
  runApp(const SulaimanApp());
}

class SulaimanApp extends StatelessWidget {
  const SulaimanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وحدة الإرشاد الأكاديمي',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      scrollBehavior: AppScrollBehavior(),
      // منطقة آمنة عامة أعلى الشاشة لكل صفحة بالموقع بلا استثناء - بدونها
      // شارة الهوية بـ`PortalHeader` (وأي محتوى آخر يبدأ من Y=0، مثل
      // `_TopUtilityBar` بالصفحة العامة) تُرسَم تحت شريط حالة الجهاز على
      // الجوال فتتراكب مع الساعة/الشبكة/البطارية (سليمان 2026-08-08). على
      // الحاسوب/الويب بلا حزّ (notch) هذا بلا أي أثر مرئي (padding = صفر).
      // `bottom: false` لأن كل شاشة تُدير حشوتها السفلية بنفسها.
      builder: (context, child) => SafeArea(bottom: false, child: child!),
      home: kIsWeb
          ? (Uri.base.fragment == _hiddenAdminPath
              ? const HiddenAdminLoginScreen()
              : const _WebEntryGate())
          : const HomeShell(),
    );
  }
}

/// نقطة دخول موقع الويب (بلا الرابط السرّي) - تفحص أولاً إن كانت هناك جلسة
/// نشطة محفوظة بالمتصفح (`Persistence.LOCAL`، انظر staff_number_login_screen.dart)
/// قبل عرض أي شيء: لو نشطة توجّه مباشرة للوحة صاحبها [PortalRoot] بدل
/// الصفحة العامة. حل سريع لإزعاج تحديث الصفحة (F5) داخل أي شاشة بالبوابة كان
/// يرمي المستخدم دائمًا للصفحة العامة رغم أنه لا يزال مسجّلاً دخوله فعليًا
/// (سليمان 2026-08-21) - لا يُعيده لنفس الصفحة الفرعية بالضبط (فقط لجذر
/// لوحته)، فالحل الكامل (روابط URL مستقلة لكل صفحة) مؤجَّل عمدًا لمشروع
/// مستقبلي منفصل.
class _WebEntryGate extends StatelessWidget {
  const _WebEntryGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data != null ? const PortalRoot() : const PublicLandingScreen();
      },
    );
  }
}
