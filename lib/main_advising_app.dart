import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'web_portal/mobile_splash_screen.dart';

/// نقطة دخول منفصلة لتطبيق أندرويد "CBA Advising" - نفس قاعدة بيانات Firebase
/// وشاشات لوحة الإدارة/الإرشاد بـlib/web_portal، لكن بواجهة دخول ورئيسية
/// جوّالة أصلية ([MobileAdvisingRoot]) بدل عرض تصميم الموقع العريض
/// (`PublicLandingScreen`/`AdminWorkspaceScreen` كما هما) مباشرة كما كان
/// سابقًا - كان يبدو غير احترافي على شاشة جوال ضيقة (سليمان 2026-08-07).
/// أي عمل هنا ينعكس فورًا على الموقع sss-advising-tu.web.app والعكس صحيح،
/// لأنهما يشتركان في نفس مشروع Firebase (Firestore/Auth) بمعرّف تطبيق مختلف
/// فقط. تُثبَّت بجانب تطبيق الإدارة القديم (HomeShell) دون تعارض.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.androidAdvising);
  await initializeDateFormatting('ar', null);
  runApp(const CbaAdvisingApp());
}

class CbaAdvisingApp extends StatelessWidget {
  const CbaAdvisingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CBA Advising',
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
      // منطقة آمنة عامة أعلى الشاشة لكل صفحة/شاشة بالتطبيق بلا استثناء -
      // بدونها كانت شارة الهوية بـ`PortalHeader` (وأي محتوى آخر يبدأ من
      // Y=0) تُرسَم تحت شريط حالة الجهاز فتتراكب مع الساعة/الشبكة/البطارية
      // (سليمان 2026-08-08، لقطات فعلية من التطبيق). `bottom: false` لأن كل
      // شاشة تُدير حشوتها السفلية بنفسها (مثال: `PortalFooterBar`).
      builder: (context, child) => SafeArea(bottom: false, child: child!),
      home: const MobileSplashScreen(),
    );
  }
}
