import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../theme/app_theme.dart';
import 'auth_gate.dart';

/// جذر تطبيق "بوابة الإرشاد" - رفيق تشغيلي خفيف منفصل تمامًا عن تطبيق
/// "CBA Advising" القديم المجمَّد (`lib/main_advising_app.dart`)، لكن يشترك
/// معه بنفس مشروع Firebase/Firestore ونفس خدمات منطق الأعمال (القسم 3).
class AdvisingPortalApp extends StatelessWidget {
  const AdvisingPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بوابة الإرشاد',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) => SafeArea(bottom: false, child: child!),
      home: const AuthGate(),
    );
  }
}
