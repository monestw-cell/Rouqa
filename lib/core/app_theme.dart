/// سمات التطبيق — App Theme
/// تصميم كامل لتطبيق رُقعة مع دعم العربية والوضعين المظلم والفاتح
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── الألوان المخصصة — Custom Colors ───────────────────────────────────────

/// اللون الأساسي: أخضر داكن
const Color kPrimaryGreen = Color(0xFF1B5E20);

/// اللون الأساسي الفاتح
const Color kPrimaryGreenLight = Color(0xFF4CAF50);

/// اللون الأساسي الداكن
const Color kPrimaryGreenDark = Color(0xFF0D3B0F);

/// لون الخلفية المظلمة
const Color kDarkBackground = Color(0xFF121212);

/// لون السطح المظلم
const Color kDarkSurface = Color(0xFF1E1E1E);

/// لون السطح المظلم المتغير
const Color kDarkSurfaceVariant = Color(0xFF2C2C2C);

// ─── ألوان تصنيفات الحركات — Move Classification Colors ────────────────────

/// لون الحركة الرائعة — ذهبي
const Color kBrilliantColor = Color(0xFFD4AF37);

/// لون الحركة الممتازة — أخضر فاتح
const Color kGreatMoveColor = Color(0xFF4CAF50);

/// لون أفضل حركة — أخضر
const Color kBestMoveColor = Color(0xFF2E7D32);

/// لون الحركة الجيدة — أزرق مخضر
const Color kGoodMoveColor = Color(0xFF5C9D5F);

/// لون حركة الكتاب — رمادي مزرق
const Color kBookMoveColor = Color(0xFF78909C);

/// لون عدم الدقة — أصفر
const Color kInaccuracyColor = Color(0xFFF5A623);

/// لون الخطأ — برتقالي
const Color kMistakeColor = Color(0xFFFF7043);

/// لون الخطأ الفادح — أحمر
const Color kBlunderColor = Color(0xFFE53935);

/// لون الحركة القسرية — رمادي
const Color kForcedMoveColor = Color(0xFF9E9E9E);

// ─── ألوان سمة اللوح — Board Theme Colors ──────────────────────────────────

/// ألوان السمة البنية (الكلاسيكية)
class BrownBoardTheme {
  static const Color lightSquare = Color(0xFFF0D9B5);
  static const Color darkSquare = Color(0xFFB58863);
  static const Color highlight = Color(0x4DFFFF00);
  static const Color lastMove = Color(0x66CED26B);
  static const String name = 'بني • Brown';
  static const String id = 'brown';
}

/// ألوان السمة الزرقاء
class BlueBoardTheme {
  static const Color lightSquare = Color(0xFFDEE3E6);
  static const Color darkSquare = Color(0xFF8CA2AD);
  static const Color highlight = Color(0x4DFFFF00);
  static const Color lastMove = Color(0x66CED26B);
  static const String name = 'أزرق • Blue';
  static const String id = 'blue';
}

/// ألوان السمة الخضراء
class GreenBoardTheme {
  static const Color lightSquare = Color(0xFFE8EDDF);
  static const Color darkSquare = Color(0xFF6B8E6B);
  static const Color highlight = Color(0x4DFFFF00);
  static const Color lastMove = Color(0x66CED26B);
  static const String name = 'أخضر • Green';
  static const String id = 'green';
}

/// ألوان السمة الداكنة
class DarkBoardTheme {
  static const Color lightSquare = Color(0xFF4B4B4B);
  static const Color darkSquare = Color(0xFF2D2D2D);
  static const Color highlight = Color(0x4DFFFFFF);
  static const Color lastMove = Color(0x66CED26B);
  static const String name = 'داكن • Dark';
  static const String id = 'dark';
}

/// قائمة سيمات اللوح
const List<Map<String, dynamic>> kBoardThemes = [
  {
    'id': BrownBoardTheme.id,
    'name': BrownBoardTheme.name,
    'lightSquare': BrownBoardTheme.lightSquare,
    'darkSquare': BrownBoardTheme.darkSquare,
  },
  {
    'id': BlueBoardTheme.id,
    'name': BlueBoardTheme.name,
    'lightSquare': BlueBoardTheme.lightSquare,
    'darkSquare': BlueBoardTheme.darkSquare,
  },
  {
    'id': GreenBoardTheme.id,
    'name': GreenBoardTheme.name,
    'lightSquare': GreenBoardTheme.lightSquare,
    'darkSquare': GreenBoardTheme.darkSquare,
  },
  {
    'id': DarkBoardTheme.id,
    'name': DarkBoardTheme.name,
    'lightSquare': DarkBoardTheme.lightSquare,
    'darkSquare': DarkBoardTheme.darkSquare,
  },
];

// ─── الخطوط — Typography ────────────────────────────────────────────────────

/// خط عربي مناسب — Cairo
TextTheme _buildArabicTextTheme(TextTheme base) {
  return GoogleFonts.cairoTextTheme(base).copyWith(
    displayLarge: GoogleFonts.cairo(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
    ),
    displayMedium: GoogleFonts.cairo(
      fontSize: 45,
      fontWeight: FontWeight.w400,
    ),
    displaySmall: GoogleFonts.cairo(
      fontSize: 36,
      fontWeight: FontWeight.w400,
    ),
    headlineLarge: GoogleFonts.cairo(
      fontSize: 32,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: GoogleFonts.cairo(
      fontSize: 28,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: GoogleFonts.cairo(
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: GoogleFonts.cairo(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: GoogleFonts.cairo(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: GoogleFonts.cairo(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: GoogleFonts.cairo(
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: GoogleFonts.cairo(
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: GoogleFonts.cairo(
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: GoogleFonts.cairo(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: GoogleFonts.cairo(
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: GoogleFonts.cairo(
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );
}

// ─── السمة المظلمة — Dark Theme ─────────────────────────────────────────────

ThemeData buildDarkTheme() {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: kPrimaryGreen,
    brightness: Brightness.dark,
    primary: kPrimaryGreen,
    onPrimary: Colors.white,
    primaryContainer: kPrimaryGreenLight,
    onPrimaryContainer: kPrimaryGreenDark,
    secondary: kPrimaryGreenLight,
    onSecondary: Colors.white,
    surface: kDarkSurface,
    onSurface: Colors.white,
    surfaceContainerHighest: kDarkSurfaceVariant,
    error: kBlunderColor,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    textTheme: _buildArabicTextTheme(ThemeData.dark().textTheme),
    scaffoldBackgroundColor: kDarkBackground,

    // شريط التطبيق — AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: kDarkSurface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),

    // البطاقات — Cards
    cardTheme: CardTheme(
      color: kDarkSurface,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    // الأشرطة — Bottom Navigation
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kDarkSurface,
      selectedItemColor: kPrimaryGreenLight,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),

    // شريط التنقل — Navigation Bar
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kDarkSurface,
      indicatorColor: kPrimaryGreen.withAlpha(50),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kPrimaryGreenLight,
          );
        }
        return GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Colors.grey,
        );
      }),
    ),

    // الأزرار المرتفعة — Elevated Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // الأزرار الممتدة — Outlined Buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimaryGreenLight,
        side: const BorderSide(color: kPrimaryGreenLight),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // أزرار النص — Text Buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimaryGreenLight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // حقول الإدخال — Input Fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kDarkSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimaryGreenLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBlunderColor, width: 2),
      ),
      hintStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: Colors.grey.shade500,
      ),
      labelStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: Colors.grey.shade400,
      ),
    ),

    // شرائط التمرير — Sliders
    sliderTheme: SliderThemeData(
      activeTrackColor: kPrimaryGreenLight,
      inactiveTrackColor: Colors.grey.shade700,
      thumbColor: kPrimaryGreenLight,
      overlayColor: kPrimaryGreenLight.withAlpha(30),
    ),

    // شرائط التمرير — Switches
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return kPrimaryGreenLight;
        }
        return Colors.grey;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return kPrimaryGreen;
        }
        return Colors.grey.shade700;
      }),
    ),

    // حوار — Dialog
    dialogTheme: DialogTheme(
      backgroundColor: kDarkSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),

    // شريط التمرير — SnackBar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kDarkSurfaceVariant,
      contentTextStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // مقسم — Divider
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade800,
      thickness: 0.5,
      space: 0,
    ),

    // رقاقة — Chip
    chipTheme: ChipThemeData(
      backgroundColor: kDarkSurfaceVariant,
      selectedColor: kPrimaryGreen.withAlpha(80),
      labelStyle: GoogleFonts.cairo(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      side: BorderSide.none,
    ),

    // عائم — Floating Action Button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kPrimaryGreen,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    // تلميح — Tooltip
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: kDarkSurfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: GoogleFonts.cairo(
        fontSize: 12,
        color: Colors.white,
      ),
    ),
  );
}

// ─── السمة الفاتحة — Light Theme ────────────────────────────────────────────

ThemeData buildLightTheme() {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: kPrimaryGreen,
    brightness: Brightness.light,
    primary: kPrimaryGreen,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFC8E6C9),
    onPrimaryContainer: kPrimaryGreenDark,
    secondary: kPrimaryGreenLight,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black87,
    surfaceContainerHighest: const Color(0xFFF5F5F5),
    error: kBlunderColor,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    textTheme: _buildArabicTextTheme(ThemeData.light().textTheme),
    scaffoldBackgroundColor: const Color(0xFFFAFAFA),

    // شريط التطبيق
    appBarTheme: AppBarTheme(
      backgroundColor: kPrimaryGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),

    // البطاقات
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    // شريط التنقل السفلي
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: kPrimaryGreen,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),

    // شريط التنقل
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kPrimaryGreen.withAlpha(30),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kPrimaryGreen,
          );
        }
        return GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Colors.grey,
        );
      }),
    ),

    // الأزرار المرتفعة
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // الأزرار الممتدة
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimaryGreen,
        side: const BorderSide(color: kPrimaryGreen),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // أزرار النص
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // حقول الإدخال
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBlunderColor, width: 2),
      ),
      hintStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: Colors.grey.shade500,
      ),
      labelStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: Colors.grey.shade700,
      ),
    ),

    // شرائط التمرير
    sliderTheme: SliderThemeData(
      activeTrackColor: kPrimaryGreen,
      inactiveTrackColor: Colors.grey.shade300,
      thumbColor: kPrimaryGreen,
      overlayColor: kPrimaryGreen.withAlpha(30),
    ),

    // مفاتيح التبديل
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return Colors.grey.shade400;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return kPrimaryGreen;
        }
        return Colors.grey.shade300;
      }),
    ),

    // حوار
    dialogTheme: DialogTheme(
      backgroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),

    // شريط الإشعارات
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kDarkSurface,
      contentTextStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // مقسم
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade300,
      thickness: 0.5,
      space: 0,
    ),

    // رقاقة
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF5F5F5),
      selectedColor: kPrimaryGreen.withAlpha(30),
      labelStyle: GoogleFonts.cairo(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      side: BorderSide.none,
    ),

    // زر عائم
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kPrimaryGreen,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    // تلميح
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: GoogleFonts.cairo(
        fontSize: 12,
        color: Colors.white,
      ),
    ),
  );
}

// ─── دوال مساعدة — Helper Functions ─────────────────────────────────────────

/// إرجاع لون التصنيف حسب النوع
Color getClassificationColor(String classification) {
  switch (classification) {
    case 'brilliant':
      return kBrilliantColor;
    case 'great':
      return kGreatMoveColor;
    case 'best':
      return kBestMoveColor;
    case 'good':
      return kGoodMoveColor;
    case 'book':
      return kBookMoveColor;
    case 'inaccuracy':
      return kInaccuracyColor;
    case 'mistake':
      return kMistakeColor;
    case 'blunder':
      return kBlunderColor;
    case 'forced':
      return kForcedMoveColor;
    default:
      return Colors.grey;
  }
}

/// إرجاع أيقونة التصنيف حسب النوع
IconData getClassificationIcon(String classification) {
  switch (classification) {
    case 'brilliant':
      return Icons.auto_awesome;
    case 'great':
      return Icons.trending_up;
    case 'best':
      return Icons.check_circle;
    case 'good':
      return Icons.check;
    case 'book':
      return Icons.menu_book;
    case 'inaccuracy':
      return Icons.warning_amber;
    case 'mistake':
      return Icons.error_outline;
    case 'blunder':
      return Icons.dangerous;
    case 'forced':
      return Icons.subdirectory_arrow_right;
    default:
      return Icons.help_outline;
  }
}

/// إرجاع اسم التصنيف بالعربية
String getClassificationNameAr(String classification) {
  switch (classification) {
    case 'brilliant':
      return 'رائعة!';
    case 'great':
      return 'ممتازة';
    case 'best':
      return 'أفضل';
    case 'good':
      return 'جيدة';
    case 'book':
      return 'كتابية';
    case 'inaccuracy':
      return 'غير دقيقة';
    case 'mistake':
      return 'خطأ';
    case 'blunder':
      return 'خطأ فادح!';
    case 'forced':
      return 'قسرية';
    default:
      return 'غير معروف';
  }
}

/// إرجاع رمز التصنيف القصير
String getClassificationSymbol(String classification) {
  switch (classification) {
    case 'brilliant':
      return '!!';
    case 'great':
      return '!;';
    case 'best':
      return '!';
    case 'good':
      return '✓';
    case 'book':
      return '📖';
    case 'inaccuracy':
      return '?!';
    case 'mistake':
      return '?!';
    case 'blunder':
      return '??';
    case 'forced':
      return '□';
    default:
      return '';
  }
}

/// إرجاع ألوان المربعات حسب معرف السمة
({Color light, Color dark}) getBoardColors(String themeId) {
  switch (themeId) {
    case BrownBoardTheme.id:
      return (
        light: BrownBoardTheme.lightSquare,
        dark: BrownBoardTheme.darkSquare,
      );
    case BlueBoardTheme.id:
      return (
        light: BlueBoardTheme.lightSquare,
        dark: BlueBoardTheme.darkSquare,
      );
    case GreenBoardTheme.id:
      return (
        light: GreenBoardTheme.lightSquare,
        dark: GreenBoardTheme.darkSquare,
      );
    case DarkBoardTheme.id:
      return (
        light: DarkBoardTheme.lightSquare,
        dark: DarkBoardTheme.darkSquare,
      );
    default:
      return (
        light: BrownBoardTheme.lightSquare,
        dark: BrownBoardTheme.darkSquare,
      );
  }
}
