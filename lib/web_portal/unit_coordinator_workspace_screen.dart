import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'portal_header.dart';

/// شاشة "منسّق الوحدة" - بانتظار اعتماد التشكيل الرسمي، فقط رسالة ترحيبية
/// مؤقتة بلا أي وظيفة فعلية بعد (بطلب سليمان صراحةً 2026-08-09: "لا تبني
/// فيها أي شيء، فقط عبارة ترحيبية" - أبو يعقوب). الوظائف الفعلية (رفع
/// الملفات) تُضاف لاحقًا بعد اعتماد التشكيل.
class UnitCoordinatorWorkspaceScreen extends StatelessWidget {
  const UnitCoordinatorWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'منسّق الوحدة',
      showBackButton: false,
      actions: [
        TextButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: Icon(Icons.logout, color: Colors.red.shade700),
          label: Text('تسجيل الخروج', style: TextStyle(color: Colors.red.shade700)),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'مرحباً أبو يعقوب',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.greenDark),
            ),
            const SizedBox(height: 16),
            Text(
              'في انتظار اعتماد التشكيل وإظهار البيانات وبدء العمل',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            Text(
              'الصفحة قيد البناء',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
