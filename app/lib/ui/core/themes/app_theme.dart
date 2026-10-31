import 'package:flutter/material.dart';

import 'package:app/ui/core/themes/app_colors.dart';
import 'package:app/ui/core/themes/app_markdown_theme.dart';
import 'package:app/ui/core/themes/app_typography.dart';

/// Builds the [ThemeData] for a given [AppColors] / [AppTypography] pair.
///
/// Wires the semantic tokens into both the standard Material [ColorScheme]
/// (so framework widgets — dialogs, switches, progress indicators, text
/// fields — render correctly per brightness) AND attaches [AppColors] /
/// [AppTypography] as theme extensions (so app widgets read
/// `context.colors.*` / `context.typo.*`).
///
/// The markdown heading styles ride along as a [GptMarkdownThemeData]
/// extension (issue #184): `gpt_markdown` reads it from the theme, which is
/// what keeps chat headings proportional to [AppTypography.mono] instead of
/// falling back to Material's much larger `TextTheme`.
ThemeData _buildTheme({
  required Brightness brightness,
  required AppColors colors,
  required AppTypography typo,
}) {
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      surface: colors.bg,
      onSurface: colors.text,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.muted,
      onSecondary: colors.text,
      error: colors.error,
      onError: colors.onAccent,
      outline: colors.border,
    ),
    dividerColor: colors.border,
    extensions: <ThemeExtension<dynamic>>[
      colors,
      typo,
      buildMarkdownTheme(typo: typo, brightness: brightness),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bg,
      foregroundColor: colors.text,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: kSansFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: colors.text,
        letterSpacing: -0.2,
      ),
    ),
    textTheme: TextTheme(
      bodyMedium: typo.sansBody,
      bodySmall: typo.monoSmall,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: colors.accent, width: 1.2),
      ),
      hintStyle: TextStyle(
        color: colors.muted,
        fontFamily: kMonoFamily,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
  );
}

/// Dark theme — the app's original look.
ThemeData buildDarkTheme() => _buildTheme(
      brightness: Brightness.dark,
      colors: AppColors.dark,
      typo: AppTypography.dark,
    );

/// Light theme — derived palette (tune hexes in `app_colors.dart`).
ThemeData buildLightTheme() => _buildTheme(
      brightness: Brightness.light,
      colors: AppColors.light,
      typo: AppTypography.light,
    );
