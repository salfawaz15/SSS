import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'portal_cards.dart';
import 'portal_header.dart';

/// شاشة "منسّق الوحدة" - بانتظار اعتماد التشكيل الرسمي، فقط رسالة ترحيبية
/// مؤقتة بلا أي وظيفة فعلية بعد (بطلب سليمان صراحةً 2026-08-09: "لا تبني
/// فيها أي شيء، فقط عبارة ترحيبية" - أبو يعقوب). الوظائف الفعلية (رفع
/// الملفات) تُضاف لاحقًا بعد اعتماد التشكيل.
///
/// **إضافة مؤقتة للاختبار فقط (2026-08-09)**: قسم `PortalStatCard`/
/// `PortalIconTileCard` أسفل الرسالة الترحيبية - يُستخدَم لاختبار هل هذين
/// المكوّنين يسبّبان صفحة بيضاء على جهاز سليمان بصفحة "غير مستخدَمة فعليًا"
/// (بلا مخاطرة على عمل حقيقي)، بعد أن نجحا بصفحة وفشلا بأخرى بلا سبب واضح.
/// يُحذَف هذا القسم بعد التجربة.
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
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 16),
            const Text('-- قسم اختبار مؤقّت --', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PortalStatCard(
                    icon: Icons.folder_shared_outlined,
                    value: '5',
                    label: 'رقم تجريبي 1',
                    accentColor: AppColors.greenDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PortalStatCard(
                    icon: Icons.trending_up_rounded,
                    value: '10%',
                    label: 'رقم تجريبي 2',
                    accentColor: AppColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 2,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisExtent: 118,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemBuilder: (context, i) {
                return PortalIconTileCard(
                  icon: i == 0 ? Icons.upload_file : Icons.download,
                  title: i == 0 ? 'أيقونة تجريبية 1' : 'أيقونة تجريبية 2',
                  background: i == 0 ? AppColors.greenDark : AppColors.gold,
                  foreground: Colors.white,
                  onTap: () {},
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
