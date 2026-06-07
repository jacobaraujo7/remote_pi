import 'package:cockpit/ui/core/themes/app_colors.dart';
import 'package:cockpit/ui/core/themes/app_typography.dart';
import 'package:cockpit/ui/core/themes/syntax_colors.dart';
import 'package:flutter/material.dart';

/// Acesso ergonômico aos tokens do tema a partir de qualquer widget.
///
/// ```dart
/// Container(color: context.colors.surface);
/// Text('hi', style: context.typo.mono.copyWith(color: context.colors.accent));
/// ```
///
/// Se um widget for construído fora da árvore com tema (ex.: teste que monta um
/// `MaterialApp` cru), os getters caem no dark — o visual padrão — sem lançar.
/// Fallback de tipografia (caso um widget seja montado fora da árvore com tema,
/// ex.: teste). Construído uma vez.
final AppTypography _fallbackTypo = AppTypography.build();

extension AppThemeX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;

  AppTypography get typo =>
      Theme.of(this).extension<AppTypography>() ?? _fallbackTypo;

  SyntaxColors get syntax =>
      Theme.of(this).extension<SyntaxColors>() ?? SyntaxColors.dark;
}
