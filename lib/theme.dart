import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF5B3CF5);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const neutralLight = Color(0xFFF5F5F5);
  static const neutralDark = Color(0xFF262626);
}

class LightModeColors {
  static const lightPrimary = Color(0xFF5B3CF5);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFEDE9FE);
  static const lightOnPrimaryContainer = Color(0xFF2E1065);
  static const lightSecondary = Color(0xFF6B7280);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightTertiary = Color(0xFF8B5CF6);
  static const lightOnTertiary = Color(0xFFFFFFFF);
  static const lightError = Color(0xFFEF4444);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFEE2E2);
  static const lightOnErrorContainer = Color(0xFF7F1D1D);
  static const lightInversePrimary = Color(0xFFA78BFA);
  static const lightShadow = Color(0xFF000000);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnSurface = Color(0xFF1F2937);
  static const lightAppBarBackground = Color(0xFFFFFFFF);
}

class DarkModeColors {
  static const darkPrimary = Color(0xFFA78BFA);
  static const darkOnPrimary = Color(0xFF2E1065);
  static const darkPrimaryContainer = Color(0xFF4C1D95);
  static const darkOnPrimaryContainer = Color(0xFFEDE9FE);
  static const darkSecondary = Color(0xFF9CA3AF);
  static const darkOnSecondary = Color(0xFF1F2937);
  static const darkTertiary = Color(0xFFC4B5FD);
  static const darkOnTertiary = Color(0xFF3730A3);
  static const darkError = Color(0xFFFCA5A5);
  static const darkOnError = Color(0xFF7F1D1D);
  static const darkErrorContainer = Color(0xFFB91C1C);
  static const darkOnErrorContainer = Color(0xFFFEE2E2);
  static const darkInversePrimary = Color(0xFF5B3CF5);
  static const darkShadow = Color(0xFF000000);
  static const darkSurface = Color(0xFF1F2937);
  static const darkOnSurface = Color(0xFFF9FAFB);
  static const darkAppBarBackground = Color(0xFF1F2937);
}

class FontSizes {
  static const double displayLarge = 57.0;
  static const double displayMedium = 45.0;
  static const double displaySmall = 36.0;
  static const double headlineLarge = 32.0;
  static const double headlineMedium = 24.0;
  static const double headlineSmall = 22.0;
  static const double titleLarge = 22.0;
  static const double titleMedium = 18.0;
  static const double titleSmall = 16.0;
  static const double labelLarge = 16.0;
  static const double labelMedium = 14.0;
  static const double labelSmall = 12.0;
  static const double bodyLarge = 16.0;
  static const double bodyMedium = 14.0;
  static const double bodySmall = 12.0;
}

ThemeData get lightTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.light(
    primary: LightModeColors.lightPrimary,
    onPrimary: LightModeColors.lightOnPrimary,
    primaryContainer: LightModeColors.lightPrimaryContainer,
    onPrimaryContainer: LightModeColors.lightOnPrimaryContainer,
    secondary: LightModeColors.lightSecondary,
    onSecondary: LightModeColors.lightOnSecondary,
    tertiary: LightModeColors.lightTertiary,
    onTertiary: LightModeColors.lightOnTertiary,
    error: LightModeColors.lightError,
    onError: LightModeColors.lightOnError,
    errorContainer: LightModeColors.lightErrorContainer,
    onErrorContainer: LightModeColors.lightOnErrorContainer,
    inversePrimary: LightModeColors.lightInversePrimary,
    shadow: LightModeColors.lightShadow,
    surface: LightModeColors.lightSurface,
    onSurface: LightModeColors.lightOnSurface,
  ),
  brightness: Brightness.light,
  appBarTheme: AppBarTheme(
    backgroundColor: LightModeColors.lightAppBarBackground,
    foregroundColor: LightModeColors.lightOnPrimaryContainer,
    elevation: 0,
  ),
  textTheme: TextTheme(
    displayLarge: GoogleFonts.poppins(fontSize: FontSizes.displayLarge, fontWeight: FontWeight.w700),
    displayMedium: GoogleFonts.poppins(fontSize: FontSizes.displayMedium, fontWeight: FontWeight.w600),
    displaySmall: GoogleFonts.poppins(fontSize: FontSizes.displaySmall, fontWeight: FontWeight.w600),
    headlineLarge: GoogleFonts.poppins(fontSize: FontSizes.headlineLarge, fontWeight: FontWeight.w600),
    headlineMedium: GoogleFonts.poppins(fontSize: FontSizes.headlineMedium, fontWeight: FontWeight.w600),
    headlineSmall: GoogleFonts.poppins(fontSize: FontSizes.headlineSmall, fontWeight: FontWeight.w600),
    titleLarge: GoogleFonts.poppins(fontSize: FontSizes.titleLarge, fontWeight: FontWeight.w500),
    titleMedium: GoogleFonts.poppins(fontSize: FontSizes.titleMedium, fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.poppins(fontSize: FontSizes.titleSmall, fontWeight: FontWeight.w500),
    labelLarge: GoogleFonts.poppins(fontSize: FontSizes.labelLarge, fontWeight: FontWeight.w500),
    labelMedium: GoogleFonts.poppins(fontSize: FontSizes.labelMedium, fontWeight: FontWeight.w500),
    labelSmall: GoogleFonts.poppins(fontSize: FontSizes.labelSmall, fontWeight: FontWeight.w500),
    bodyLarge: GoogleFonts.poppins(fontSize: FontSizes.bodyLarge, fontWeight: FontWeight.normal),
    bodyMedium: GoogleFonts.poppins(fontSize: FontSizes.bodyMedium, fontWeight: FontWeight.normal),
    bodySmall: GoogleFonts.poppins(fontSize: FontSizes.bodySmall, fontWeight: FontWeight.normal),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: LightModeColors.lightPrimaryContainer.withValues(alpha: 0.3),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
);

ThemeData get darkTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: DarkModeColors.darkPrimary,
    onPrimary: DarkModeColors.darkOnPrimary,
    primaryContainer: DarkModeColors.darkPrimaryContainer,
    onPrimaryContainer: DarkModeColors.darkOnPrimaryContainer,
    secondary: DarkModeColors.darkSecondary,
    onSecondary: DarkModeColors.darkOnSecondary,
    tertiary: DarkModeColors.darkTertiary,
    onTertiary: DarkModeColors.darkOnTertiary,
    error: DarkModeColors.darkError,
    onError: DarkModeColors.darkOnError,
    errorContainer: DarkModeColors.darkErrorContainer,
    onErrorContainer: DarkModeColors.darkOnErrorContainer,
    inversePrimary: DarkModeColors.darkInversePrimary,
    shadow: DarkModeColors.darkShadow,
    surface: DarkModeColors.darkSurface,
    onSurface: DarkModeColors.darkOnSurface,
  ),
  brightness: Brightness.dark,
  appBarTheme: AppBarTheme(
    backgroundColor: DarkModeColors.darkAppBarBackground,
    foregroundColor: DarkModeColors.darkOnPrimaryContainer,
    elevation: 0,
  ),
  textTheme: TextTheme(
    displayLarge: GoogleFonts.poppins(fontSize: FontSizes.displayLarge, fontWeight: FontWeight.w700),
    displayMedium: GoogleFonts.poppins(fontSize: FontSizes.displayMedium, fontWeight: FontWeight.w600),
    displaySmall: GoogleFonts.poppins(fontSize: FontSizes.displaySmall, fontWeight: FontWeight.w600),
    headlineLarge: GoogleFonts.poppins(fontSize: FontSizes.headlineLarge, fontWeight: FontWeight.w600),
    headlineMedium: GoogleFonts.poppins(fontSize: FontSizes.headlineMedium, fontWeight: FontWeight.w600),
    headlineSmall: GoogleFonts.poppins(fontSize: FontSizes.headlineSmall, fontWeight: FontWeight.w600),
    titleLarge: GoogleFonts.poppins(fontSize: FontSizes.titleLarge, fontWeight: FontWeight.w500),
    titleMedium: GoogleFonts.poppins(fontSize: FontSizes.titleMedium, fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.poppins(fontSize: FontSizes.titleSmall, fontWeight: FontWeight.w500),
    labelLarge: GoogleFonts.poppins(fontSize: FontSizes.labelLarge, fontWeight: FontWeight.w500),
    labelMedium: GoogleFonts.poppins(fontSize: FontSizes.labelMedium, fontWeight: FontWeight.w500),
    labelSmall: GoogleFonts.poppins(fontSize: FontSizes.labelSmall, fontWeight: FontWeight.w500),
    bodyLarge: GoogleFonts.poppins(fontSize: FontSizes.bodyLarge, fontWeight: FontWeight.normal),
    bodyMedium: GoogleFonts.poppins(fontSize: FontSizes.bodyMedium, fontWeight: FontWeight.normal),
    bodySmall: GoogleFonts.poppins(fontSize: FontSizes.bodySmall, fontWeight: FontWeight.normal),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: DarkModeColors.darkPrimaryContainer.withValues(alpha: 0.3),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
);
