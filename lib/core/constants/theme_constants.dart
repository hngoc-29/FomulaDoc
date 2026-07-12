import 'package:flutter/material.dart';

/// Design tokens for the FormulaDoc theme.
///
/// Academic / scientific palette: deep blue primary, warm paper surfaces.
class ThemeConstants {
  ThemeConstants._();

  // ── Primary palette ───────────────────────────────────────────────────────
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color primaryBlueDark = Color(0xFF0D47A1);
  static const Color primaryBlueLight = Color(0xFF1976D2);
  static const Color accentTeal = Color(0xFF00796B);

  // ── Surface / paper ───────────────────────────────────────────────────────
  static const Color paperLight = Color(0xFFFAFAFA);
  static const Color paperDark = Color(0xFF1E1E1E);

  // ── Reading modes (viewer document surface only) ────────────────────────
  static const Color paperSepia        = Color(0xFFF4ECD8);
  static const Color textSepia         = Color(0xFF3E2F1C);
  static const Color paperHighContrast = Color(0xFFFFFFFF);
  static const Color textHighContrast  = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF252525);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF1A1A1A);
  static const Color textPrimaryDark = Color(0xFFEEEEEE);
  static const Color textSecondaryLight = Color(0xFF555555);
  static const Color textSecondaryDark = Color(0xFFAAAAAA);

  // ── Link / equation ───────────────────────────────────────────────────────
  static const Color linkColor = Color(0xFF1565C0);
  static const Color equationBorderLight = Color(0xFFBBDEFB);
  static const Color equationBorderDark = Color(0xFF1565C0);
  static const Color equationBgLight = Color(0xFFF3F8FF);
  static const Color equationBgDark = Color(0xFF0D2137);

  // ── Heading colors (light mode) ───────────────────────────────────────────
  static const Color h1Color = Color(0xFF0D47A1);
  static const Color h2Color = Color(0xFF1565C0);
  static const Color h3Color = Color(0xFF1976D2);
  static const Color hNColor = Color(0xFF1A1A1A);

  // ── Typography ────────────────────────────────────────────────────────────
  /// Base font sizes (logical px) matching common Word defaults.
  static const double fontSizeH1 = 28.0;
  static const double fontSizeH2 = 24.0;
  static const double fontSizeH3 = 20.0;
  static const double fontSizeH4 = 18.0;
  static const double fontSizeH5 = 16.0;
  static const double fontSizeH6 = 14.0;
  static const double fontSizeBody = 16.0;
  static const double fontSizeCaption = 13.0;

  // ── Spacing ───────────────────────────────────────────────────────────────
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // ── Border radius ─────────────────────────────────────────────────────────
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 16.0;
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(radiusMd));

  // ── Elevation ─────────────────────────────────────────────────────────────
  static const double cardElevation = 1.0;
  static const double modalElevation = 8.0;
}
