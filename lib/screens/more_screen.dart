import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MoreScreen extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const MoreScreen({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionLabel('إدارة الطلبات'),
                const SizedBox(height: 10),
                _MenuTile(
                  icon: Icons.people_alt_outlined,
                  title: 'بيانات المنسقين',
                  subtitle: 'أسماء وبريد منسّق كل قسم',
                  color: AppColors.green,
                  onTap: onOpenSettings,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'تم تطوير هذا التطبيق بواسطة سليمان الفواز',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12.5,
        color: Colors.grey.shade600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}
