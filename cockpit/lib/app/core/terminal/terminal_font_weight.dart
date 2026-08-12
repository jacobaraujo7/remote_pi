import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter/widgets.dart';

/// Abaixo disto a tela conta como baixa densidade. Fica no meio do caminho
/// entre 1.0 (monitor comum) e 2.0 (Retina), então nenhuma das duas famílias de
/// tela fica perto do limiar.
const _lowDensityThreshold = 1.5;

/// Traduz a preferência do usuário no peso concreto passado ao motor.
///
/// [TerminalFontWeight.auto] escolhe por densidade: em telas de DPR baixo o
/// antialiasing em cinza do Skia (sem hinting, sem subpixel) engorda os traços
/// verticais, e o texto lê como negrito mesmo em `w400`. Um degrau abaixo
/// devolve o peso *aparente* para perto do que o Retina mostra. Em alta
/// densidade não há o que compensar, então `auto` é `w400`.
///
/// Os valores fixos existem para quem discorda da heurística: escolher um peso
/// explícito desliga a compensação por completo.
FontWeight resolveTerminalFontWeight(
  TerminalFontWeight preference,
  double devicePixelRatio,
) => switch (preference) {
  TerminalFontWeight.auto =>
    devicePixelRatio < _lowDensityThreshold ? FontWeight.w300 : FontWeight.w400,
  TerminalFontWeight.light => FontWeight.w300,
  TerminalFontWeight.normal => FontWeight.w400,
  TerminalFontWeight.medium => FontWeight.w500,
  TerminalFontWeight.semiBold => FontWeight.w600,
};
