import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'web_portal/public_landing_screen.dart';

/// نقطة دخول منفصلة لتطبيق أندرويد "CBA Advising" - نسخة كاملة من بوابة
/// الوحدة (نفس شاشات lib/web_portal ونفس قاعدة بيانات Firebase)، تُثبَّت
/// بجانب تطبيق الإدارة القديم (HomeShell) دون تعارض. أي عمل هنا ينعكس
/// فورًا على الموقع sss-advising-tu.web.app والعكس صحيح، لأنهما يشتركان
/// في نفس مشروع Firebase (Firestore/Auth) بمعرّف تطبيق مختلف فقط.
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
      home: const PublicLandingScreen(),
    );
  }
}
