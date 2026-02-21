import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'app_colors.dart';
import 'responsive_helper.dart';

/// A utility class for managing app themes with platform-specific adaptations
class AppTheme {
  /// Get the primary app theme with platform-specific adjustments
  static ThemeData getAppTheme(BuildContext context) {
    // Common theme properties
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );

    // Use Poppins font family
    final textTheme = GoogleFonts.poppinsTextTheme();

    // Different settings based on platform
    if (Platform.isIOS) {
      return _getIOSTheme(context, colorScheme, textTheme);
    } else {
      return _getAndroidTheme(context, colorScheme, textTheme);
    }
  }

  /// Get iOS-specific theme
  static ThemeData _getIOSTheme(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return ThemeData(
      colorScheme: colorScheme,
      textTheme: textTheme,
      fontFamily: 'Poppins',
      platform: TargetPlatform.iOS,
      // iOS-specific AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: AppColors.primary,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.light,
        ),
      ),
      // iOS-specific Card theme
      cardTheme: CardThemeData(
        elevation: 1.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        shadowColor: Colors.black.withAlpha(26),
      ),
      // iOS-specific Button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          elevation: 0,
          minimumSize: const Size(88, 48),
        ),
      ),
      // iOS style text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      // iOS style icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: const CircleBorder(),
        ),
      ),
      // iOS style input fields
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: GoogleFonts.poppins(),
        labelStyle: GoogleFonts.poppins(),
        errorStyle: GoogleFonts.poppins(color: Colors.red),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      scaffoldBackgroundColor: Colors.white,
      // iOS style list
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 0,
        minVerticalPadding: 16,
      ),
      // iOS style dividers
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 0.5,
        color: Colors.grey[300],
      ),
      // iOS style checkbox
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: Colors.grey[400]!),
      ),
      // iOS-specific switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.grey[300];
        }),
      ),
      // iOS native page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Get Android-specific theme
  static ThemeData _getAndroidTheme(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return ThemeData(
      colorScheme: colorScheme,
      textTheme: textTheme,
      fontFamily: 'Poppins',
      platform: TargetPlatform.android,
      // Android-specific AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.light,
        ),
      ),
      // Android-specific Card theme
      cardTheme: CardThemeData(
        elevation: 2.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        shadowColor: Colors.black.withAlpha(51),
      ),
      // Android-specific Button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          elevation: 2,
          minimumSize: const Size(88, 48),
        ),
      ),
      // Android style text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      // Android style icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
      // Android style input fields
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: GoogleFonts.poppins(),
        labelStyle: GoogleFonts.poppins(),
        errorStyle: GoogleFonts.poppins(color: Colors.red),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      scaffoldBackgroundColor: AppColors.background,
      // Android style list
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 0,
        minVerticalPadding: 16,
      ),
      // Android style dividers
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: Colors.grey[300],
      ),
      // Android style checkbox
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        side: BorderSide(color: Colors.grey[600]!),
      ),
      // Android modern page transitions (Material 3 style)
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Get a theme that's optimized for tablet devices
  static ThemeData getTabletTheme(BuildContext context) {
    // Get the base theme for the platform
    final baseTheme = getAppTheme(context);

    // Modify it for tablet dimensions
    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.copyWith(
        // Slightly larger text for tablets
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
          fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * 1.1,
        ),
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
          fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * 1.1,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          fontSize: (baseTheme.textTheme.titleLarge?.fontSize ?? 22) * 1.1,
        ),
      ),
      // Larger touch targets for tablets
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
      ),
      // Larger padding for better spacing on tablets
      cardTheme: baseTheme.cardTheme.copyWith(margin: const EdgeInsets.all(12)),
    );
  }
}
