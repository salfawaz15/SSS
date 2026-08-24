import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:google_fonts/google_fonts.dart';

/// ألوان الهوية البصرية لوحدة الإرشاد الأكاديمي والخريجين - جامعة الطائف
class AppColors {
  static const green = Color(0xFF154B36);
  static const greenDark = Color(0xFF0D3324);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE2C766);

  // ألوان كانت متكررة يدويًا داخل شاشات متفرقة (خلفية، تنبيه، دخول سري) -
  // مجمَّعة هنا كمرجع واحد بدل تكرار قيم Hex مباشرة في كل ملف.
  static const background = Color(0xFFF5F7F6);
  static const errorRed = Color(0xFFB3261E);
  static const surfaceDark = Color(0xFF20261F);
}

/// مقاسات خط موحّدة بخط Cairo - بديل عن كتابة TextStyle يدويًا في كل شاشة
/// (كان مصدر تكرار كبير وتفاوت غير مقصود في الأحجام/الأوزان عبر الملفات).
class AppTextStyles {
  static TextStyle h1({Color color = AppColors.greenDark}) =>
      GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.w700, color: color);
  static TextStyle h2({Color color = AppColors.greenDark}) =>
      GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w700, color: color);
  static TextStyle h3({Color color = AppColors.greenDark}) =>
      GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600, color: color);
  static TextStyle body({Color color = Colors.black87}) =>
      GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w400, color: color);
  static TextStyle caption({Color color = Colors.black54}) =>
      GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w400, color: color);
}

/// زوايا استدارة موحّدة - بديل عن كتابة BorderRadius.circular(..) بأرقام
/// متفرقة (12/14/16...) يدويًا في كل شاشة.
class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}

/// مسافات حشو/تباعد موحّدة - بديل عن أرقام Padding/SizedBox المتكررة يدويًا.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// تنبيهات موحّدة الهوية البصرية (بديل SnackBar الأحمر الافتراضي المزعج) -
/// بطاقة عائمة داكنة بشريط جانبي ملوّن وأيقونة، بدل شريط كامل العرض بلون
/// صارخ. تُستخدم في كل الشاشات بدل `ScaffoldMessenger.showSnackBar` مباشرة.
class AppNotice {
  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
  }) {
    final color = isError ? const Color(0xFFB3261E) : AppColors.green;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF20261F),
        elevation: 6,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: isError ? 6 : 3),
        content: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)))),
              const SizedBox(width: 12),
              Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.5)),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  static void error(BuildContext context, String message) => show(context, message: message, isError: true);
  static void success(BuildContext context, String message) => show(context, message: message, isError: false);
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
        // أيقونات شريط حالة الجهاز (الساعة/الشبكة/البطارية) فاتحة (بيضاء)
        // صراحةً بدل الاعتماد على تخمين Flutter التلقائي لسطوع الخلفية - كانت
        // تظهر داكنة على نفس لون الخلفية الداكنة (AppColors.green) فتختفي
        // عمليًا على تطبيق "بوابة الإرشاد" الجوّالة (سليمان 2026-08-23).
        systemOverlayStyle: SystemUiOverlayStyle.light,
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
      // خلفية بيضاء صريحة لكل قوائم الفلاتر المنسدلة (DropdownButton/
      // DropdownMenu) بدل الأخضر الفاتح الذي يفرضه Material 3 افتراضيًا
      // (تظليل سطحي بلون ColorScheme.primary) - سليمان لاحظ صراحةً
      // (2026-08-20) أنه يخالف الهوية البصرية (الأبيض هو لون السطح الموحَّد).
      canvasColor: Colors.white,
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
