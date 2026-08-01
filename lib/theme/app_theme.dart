import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ألوان الهوية البصرية لوحدة الإرشاد الأكاديمي والخريجين - جامعة الطائف
class AppColors {
  static const green = Color(0xFF154B36);
  static const greenDark = Color(0xFF0D3324);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE2C766);
}

/// سلوك تمرير مخصَّص يجعل شريط التمرير يلتصق تمامًا بالحافة اليسرى للنافذة
/// بلا أي فراغ (crossAxisMargin/radius صفر) - السلوك الافتراضي في Flutter
/// للويب/سطح المكتب يترك هامشًا صغيرًا حول الشريط يبدو وكأنه "عائم" بمعزل
/// عن حافة الصفحة. يُطبَّق عبر `MaterialApp(scrollBehavior: AppScrollBehavior())`
/// في كل نقاط دخول التطبيق حتى ينطبق على كل الشاشات دفعة واحدة.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      radius: Radius.zero,
      child: child,
    );
  }
}

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.light,
      secondary: AppColors.gold,
    );

    return _base(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.dark,
      secondary: AppColors.goldLight,
    );

    return _base(colorScheme);
  }

  static ThemeData _base(ColorScheme colorScheme) {
    final textTheme = GoogleFonts.cairoTextTheme(
      colorScheme.brightness == Brightness.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.brightness == Brightness.light
          ? const Color(0xFFF5F7F6)
          : null,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1.5,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.6),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: AppColors.gold,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      // شريط تمرير ملتصق تمامًا بحافة النافذة (بلا أي فراغ جانبي) - بدل
      // الهامش الافتراضي الذي يجعله يبدو عائمًا بمعزل عن حافة الصفحة.
      scrollbarTheme: const ScrollbarThemeData(
        crossAxisMargin: 0,
        mainAxisMargin: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.brightness == Brightness.light
            ? Colors.white
            : null,
        indicatorColor: AppColors.green.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.cairo(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.green : Colors.grey.shade600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.green : Colors.grey.shade500,
          );
        }),
      ),
    );
  }
}
