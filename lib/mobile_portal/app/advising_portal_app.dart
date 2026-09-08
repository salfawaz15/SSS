import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../theme/app_theme.dart';
import '../services/portal_update_controller.dart';
import 'auth_gate.dart';

/// جذر تطبيق "بوابة الإرشاد" - رفيق تشغيلي خفيف منفصل تمامًا عن تطبيق
/// "CBA Advising" القديم (حُذف بالكامل 2026-09-09)، لكن يشترك بنفس مشروع
/// Firebase/Firestore ونفس خدمات منطق الأعمال (القسم 3).
///
/// `StatefulWidget` (بدل `StatelessWidget` سابقًا) لبدء/إيقاف
/// [PortalUpdateController] بدورة حياة التطبيق (فحص فور الفتح، ثم كل 6
/// ساعات دوريًا - سليمان صراحةً 2026-09-09). `navigatorKey` يتيح للمُنسِّق
/// عرض حوار التحديث التلقائي بلا حاجة لـBuildContext محلي بأي شاشة.
class AdvisingPortalApp extends StatefulWidget {
  const AdvisingPortalApp({super.key});

  @override
  State<AdvisingPortalApp> createState() => _AdvisingPortalAppState();
}

class _AdvisingPortalAppState extends State<AdvisingPortalApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    PortalUpdateController.instance.start(_navigatorKey);
  }

  @override
  void dispose() {
    PortalUpdateController.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
