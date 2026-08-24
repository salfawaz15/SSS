import 'package:flutter/material.dart';

import '../screens/admin_summary/admin_summary_screen.dart';
import '../screens/course_schedules/course_schedules_screen.dart';
import '../screens/home/portal_home_screen.dart';
import '../screens/more/portal_more_screen.dart';
import '../screens/uploads/portal_uploads_screen.dart';

/// إطار التنقّل الرئيسي - تنقّل سفلي ثابت بخمس وجهات (القسم 8)، لا شريط
/// جانبي (Sidebar) كسطح المكتب. المرحلة الأولى: "الرئيسية" فعّالة بالكامل،
/// وباقي التبويبات شاشات مؤقتة تُستبدَل بالمراحل التالية دون تغيير هذا الإطار.
class PortalShell extends StatefulWidget {
  const PortalShell({super.key});

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  int _index = 0;

  static const _screens = [
    PortalHomeScreen(),
    AdminSummaryScreen(),
    PortalUploadsScreen(),
    CourseSchedulesScreen(),
    PortalMoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'لوحة الإدارة'),
          NavigationDestination(icon: Icon(Icons.upload_file_outlined), selectedIcon: Icon(Icons.upload_file), label: 'رفع الملفات'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'الجداول الدراسية'),
          NavigationDestination(icon: Icon(Icons.more_horiz_outlined), selectedIcon: Icon(Icons.more_horiz), label: 'المزيد'),
        ],
      ),
    );
  }
}
