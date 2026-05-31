import 'package:app/domain/app_font_choice.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Design tokens from app/wareframe/screens.jsx
// All widgets MUST use these constants for visual consistency.

const kBg = Color(0xFF000000);
const kSurface = Color(0xFF0A0A0A);
const kBorder = Color(0xFF1A1A1A);
const kText = Color(0xFFFFFFFF);
const kMuted = Color(0xFF6B6B6B);
const kMuted2 = Color(0xFF8A8A8A);
const kAccent = Color(0xFF00D4FF);
const kHighlight = Color(0xFF9FE6FF); // code/file paths in agent messages
const kSuccess = Color(0xFF6CD28A); // ✓ in tool results
const kCodeBg = Color(0xFF050505);
const kUserBubble = Color(0xFF1A1A1A);
const kModelBadgeBg = Color(0xFF161616);
const kModelBadgeBorder = Color(0xFF1F1F1F);
const kDenyBorder = Color(0xFF2A2A2A);

// Typography
const kMono = 'Courier'; // fallback; JetBrains Mono via font if bundled
const kMonoStyle = TextStyle(
  fontFamily: kMono,
  fontSize: 12.5,
  color: Color(0xFFE6E6E6),
  height: 1.5,
  letterSpacing: 0,
);
const kMonoSmall = TextStyle(
  fontFamily: kMono,
  fontSize: 11.0,
  color: kMuted2,
  height: 1.4,
);
const kSansBody = TextStyle(
  fontSize: 14.0,
  color: kText,
  height: 1.35,
  letterSpacing: -0.1,
);

TextStyle _applyFontChoice(AppFontChoice font, TextStyle base) {
  switch (font) {
    case AppFontChoice.systemDefault:
      return base.copyWith(fontFamily: null);
    case AppFontChoice.robotoMono:
      return GoogleFonts.robotoMono(textStyle: base);
    case AppFontChoice.jetBrainsMono:
      return GoogleFonts.jetBrainsMono(textStyle: base);
    case AppFontChoice.sans:
      return base.copyWith(fontFamily: 'Arial');
    case AppFontChoice.serif:
      return base.copyWith(fontFamily: 'Times New Roman');
    case AppFontChoice.mono:
      return base.copyWith(fontFamily: 'Courier');
  }
}

// Shared ThemeData — used in MaterialApp
ThemeData buildAppTheme({AppFontChoice font = AppFontChoice.mono}) {
  final titleStyle = _applyFontChoice(
    font,
    const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: kText,
      letterSpacing: -0.2,
    ),
  );
  final bodyMedium = _applyFontChoice(font, kSansBody);
  final bodySmall = _applyFontChoice(font, kMonoSmall);
  final hint = _applyFontChoice(
    font,
    const TextStyle(color: kMuted, fontFamily: kMono, fontSize: 13),
  );

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      surface: kBg,
      primary: kAccent,
      onPrimary: Color(0xFF000000),
      secondary: kMuted,
      onSecondary: kText,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
      titleTextStyle: titleStyle,
    ),
    dividerColor: kBorder,
    textTheme: TextTheme(bodyMedium: bodyMedium, bodySmall: bodySmall),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0E0E0E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: const BorderSide(color: kAccent, width: 1.2),
      ),
      hintStyle: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
  );
}
