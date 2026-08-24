import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'mobile_portal/app/advising_portal_app.dart';

/// نقطة دخول منفصلة لتطبيق "بوابة الإرشاد" (com.taif.cba.advisingportal) -
/// تطبيق جوال جديد كليًا، مختلف عن نقطة دخول "CBA Advising" القديمة المجمَّدة
/// (`main_advising_app.dart`) بمعمارية Mobile-First مستقلة تحت `lib/mobile_portal/`،
/// لكنه يشترك بنفس مشروع Firebase (Firestore/Auth) ونفس خدمات منطق الأعمال
/// (`lib/services/*`) بمعرّف تطبيق Android مختلف فقط - راجع
/// `DefaultFirebaseOptions.advisingPortal`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.advisingPortal);
  await initializeDateFormatting('ar', null);
  runApp(const AdvisingPortalApp());
}
