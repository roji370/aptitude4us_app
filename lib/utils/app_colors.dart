import 'package:flutter/material.dart';

/// Design tokens from the Stitch "Aptitude 4 Us Prototype" design system.
/// 
/// Color palette follows Material 3 tonal structure with a clinical
/// Navy + Teal accent scheme designed for healthcare/nursing education.
class AppColors {
  // ── Primary (Deep Academy Navy) ──────────────────────────────────────
  static const Color primary = Color(0xFF002046);
  static const Color primaryContainer = Color(0xFF1B365D);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF87A0CD);
  static const Color primaryFixed = Color(0xFFD6E3FF);
  static const Color primaryFixedDim = Color(0xFFAEC7F7);

  // ── Secondary (Clinical Teal) ────────────────────────────────────────
  static const Color secondary = Color(0xFF006B5F);
  static const Color secondaryContainer = Color(0xFF76F4E0);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF006F63);

  // ── Tertiary (Deep Cyan-Teal) ────────────────────────────────────────
  static const Color tertiary = Color(0xFF00252A);
  static const Color tertiaryContainer = Color(0xFF003C44);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFF4BABBC);

  // ── Error ────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF93000A);

  // ── Surface & Background ─────────────────────────────────────────────
  static const Color surface = Color(0xFFF8F9FF);
  static const Color surfaceDim = Color(0xFFCBDBF5);
  static const Color surfaceBright = Color(0xFFF8F9FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color surfaceContainer = Color(0xFFE5EEFF);
  static const Color surfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color surfaceContainerHighest = Color(0xFFD3E4FE);
  static const Color surfaceVariant = Color(0xFFD3E4FE);
  static const Color surfaceTint = Color(0xFF465F88);

  static const Color onSurface = Color(0xFF0B1C30);
  static const Color onSurfaceVariant = Color(0xFF44474E);
  static const Color onBackground = Color(0xFF0B1C30);
  static const Color background = Color(0xFFF8F9FF);

  // ── Outline & Borders ────────────────────────────────────────────────
  static const Color outline = Color(0xFF74777F);
  static const Color outlineVariant = Color(0xFFC4C6CF);

  // ── Inverse ──────────────────────────────────────────────────────────
  static const Color inverseSurface = Color(0xFF213145);
  static const Color inverseOnSurface = Color(0xFFEAF1FF);
  static const Color inversePrimary = Color(0xFFAEC7F7);

  // ── Legacy aliases (for backward compatibility) ──────────────────────
  static const Color accent = primaryContainer;
}