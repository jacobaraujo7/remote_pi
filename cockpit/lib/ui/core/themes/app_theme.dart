import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:cockpit/ui/core/themes/app_colors.dart';
import 'package:cockpit/ui/core/themes/app_typography.dart';
import 'package:cockpit/ui/core/themes/syntax_colors.dart';
import 'package:flutter/material.dart';

/// Monta o `ThemeData` do Cockpit (light ou dark, por [brightness]) a partir das
/// [settings] do usuário: paleta [AppColors], tipografia [AppTypography] (fontes
/// + tamanhos) e paleta de syntax [SyntaxColors] — todas instaladas como
/// extensions (consumidas via `context.colors`/`context.typo`/`context.syntax`).
ThemeData buildTheme({
  required Brightness brightness,
  AppSettings settings = const AppSettings(),
}) {
  final isDark = brightness == Brightness.dark;
  final colors = isDark ? AppColors.dark : AppColors.light;
  final typo = AppTypography.build(
    uiFont: settings.interfaceFont,
    monoFont: settings.codeFont,
    interfaceSize: settings.interfaceSize,
    codeSize: settings.codeSize,
  );
  // Syntax segue o brilho do app (cada família tem variante light/dark).
  final syntax = SyntaxColors.forId(settings.syntaxTheme, brightness);

  final base = isDark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: colors.bg,
    canvasColor: colors.panel,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      surface: colors.panel,
      primary: colors.accent,
      // Texto/ícone sobre o preenchimento accent (FilledButton etc.). O azul
      // pede branco em ambos os temas.
      onPrimary: Colors.white,
      error: colors.error,
      onError: Colors.white,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSoft,
      selectionHandleColor: colors.accent,
    ),
    // Botões secundários ("Cancelar" etc.) — fosco/neutro, **não** com a cor
    // primária (que faria parecer a ação principal). Pareiam com o FilledButton.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.text2,
        backgroundColor: colors.panel3,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    // Scrollbar fina. Cores via tokens → adaptam a light/dark. A visibilidade
    // permanente é aplicada por widget (transcript/rail) com controller — forçar
    // global quebra scrollviews sem controller (ex.: a tab strip horizontal).
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(6),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
      interactive: true,
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? colors.text4
            : colors.border2,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    extensions: <ThemeExtension<dynamic>>[colors, typo, syntax],
  );
}

/// Atalho de compatibilidade: o tema dark com os defaults.
ThemeData buildDarkTheme() => buildTheme(brightness: Brightness.dark);
