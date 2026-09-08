import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'mobile_portal/app/advising_portal_app.dart';

/// نقطة دخول تطبيق "بوابة الإرشاد" (com.taif.cba.advisingportal) - الوحيدة
/// الآن بعد حذف تطبيق "CBA Advising" القديم بالكامل (2026-09-09)، بمعمارية
/// Mobile-First مستقلة تحت `lib/mobile_portal/`، ويشترك بنفس مشروع Firebase
/// (Firestore/Auth) ونفس خدمات منطق الأعمال (`lib/services/*`) - راجع
/// `DefaultFirebaseOptions.advisingPortal`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.advisingPortal);
  await initializeDateFormatting('ar', null);
  runApp(const AdvisingPortalApp());
}
