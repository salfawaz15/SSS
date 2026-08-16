import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/unit_committee_member.dart';
import '../services/unit_committee_repository.dart';
import '../theme/app_theme.dart';
import '../utils/name_display.dart';

/// شاشة "عن الوحدة" الجوّالة الأصيلة - قائمة تشكيل الوحدة (نفس مصدر بيانات
/// قسم "أعضاء الوحدة" بالصفحة العامة `public_landing_screen.dart`، عبر
/// [UnitCommitteeRepository] مباشرة) بتخطيط عمودي بسيط مناسب لعرض جوال ضيق -
/// بلا الهيكل التنظيمي متعدد الأعمدة المصمَّم لعرض حاسوب (سبَّب فيضانًا
/// وتراكبًا حقيقيًا عند اختباره على الجوال، انظر mobile_advising_root.dart).
///
/// أُضيفت بطلب سليمان صراحةً (2026-08-16) بعد أن لاحظ عدم وجود أي وصول
/// لبيانات "الهيكل التنظيمي"/"تواصل معنا" من تطبيق الجوال الجديد.
class MobileAboutUnitScreen extends StatelessWidget {
  const MobileAboutUnitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: AppColors.greenDark,
        foregroundColor: Colors.white,
        title: const Text('عن الوحدة'),
      ),
      body: StreamBuilder<List<UnitCommitteeMember>>(
        stream: UnitCommitteeRepository.watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('تعذّر تحميل بيانات الوحدة: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = snapshot.data!;
          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لم يُعتمَد تشكيل الوحدة بعد.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final m = members[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xFFE7EFEA),
                      child: Icon(Icons.person_outline, color: AppColors.greenDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName(m.name), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(m.role, style: TextStyle(color: AppColors.green, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          if (m.department.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(m.department, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    if (m.email.isNotEmpty)
                      IconButton(
                        tooltip: 'مراسلة بالبريد',
                        icon: const Icon(Icons.mail_outline, color: AppColors.gold, size: 20),
                        onPressed: () => launchUrl(Uri.parse('mailto:${m.email}')),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
