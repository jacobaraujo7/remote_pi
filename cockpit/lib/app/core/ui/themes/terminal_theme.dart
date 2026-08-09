import 'package:flutter/widgets.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';
import 'package:cockpit/app/core/ui/themes/theme_codec.dart';

/// Tema **dark** do `TerminalView` (fundo `#18181B`, cursor accent, paleta ANSI
/// dark). O fundo e a paleta de 16 cores são do emulador (nossos) — o oh-my-zsh
/// só emite os códigos ANSI do prompt/`ls`; quem pinta é este tema.
const TerminalTheme cockpitTerminalThemeDark = TerminalTheme(
  cursor: Color(0xFF2F6FF0), // accent
  selection: Color(0x402F6FF0),
  foreground: Color(0xFFECECEF), // text
  background: Color(0xFF18181B), // panel (mesmo fundo do corpo do agente)
  black: Color(0xFF26262A),
  red: Color(0xFFE5484D),
  green: Color(0xFF3FB868),
  yellow: Color(0xFFE0A33A),
  blue: Color(0xFF2F6FF0),
  magenta: Color(0xFFC792EA),
  cyan: Color(0xFF1AA5A0),
  white: Color(0xFFC9C9CF),
  brightBlack: Color(0xFF6A6A73),
  brightRed: Color(0xFFFF6B6F),
  brightGreen: Color(0xFF82E0A5),
  brightYellow: Color(0xFFFFCB6B),
  brightBlue: Color(0xFF82AAFF),
  brightMagenta: Color(0xFFD6A0FF),
  brightCyan: Color(0xFF89DDFF),
  brightWhite: Color(0xFFECECEF),
  searchHitBackground: Color(0xFFE0A33A),
  searchHitBackgroundCurrent: Color(0xFF2F6FF0),
  searchHitForeground: Color(0xFF0D0D0F),
);

/// Tema **light** do terminal — fundo claro + paleta ANSI escurecida (estilo
/// GitHub light), legível sobre branco. Cores claras (yellow/white) viram tons
/// mais escuros pra não sumirem; prompts do oh-my-zsh ficam legíveis.
const TerminalTheme cockpitTerminalThemeLight = TerminalTheme(
  cursor: Color(0xFF2F6FF0), // accent
  selection: Color(0x222F6FF0),
  foreground: Color(0xFF1A1A1F), // text (dark)
  background: Color(0xFFFFFFFF), // panel (mesmo fundo do corpo do agente)
  black: Color(0xFF1A1A1F),
  red: Color(0xFFCF222E),
  green: Color(0xFF1A7F37),
  yellow: Color(0xFF9A6700),
  blue: Color(0xFF0969DA),
  magenta: Color(0xFF8250DF),
  cyan: Color(0xFF1B7C83),
  white: Color(0xFF6E7781),
  brightBlack: Color(0xFF57606A),
  brightRed: Color(0xFFA40E26),
  brightGreen: Color(0xFF116329),
  brightYellow: Color(0xFF7D4E00),
  brightBlue: Color(0xFF0550AE),
  brightMagenta: Color(0xFF6639BA),
  brightCyan: Color(0xFF3192AA),
  brightWhite: Color(0xFF24292F),
  searchHitBackground: Color(0xFFFFDF5D),
  searchHitBackgroundCurrent: Color(0xFF2F6FF0),
  searchHitForeground: Color(0xFFFFFFFF),
);

/// Tema do terminal conforme o brilho do app.
///
/// Fallback: só é o caminho certo fora da árvore com tema instalado. Dentro da
/// UI use `context.terminalTheme`, que respeita o tema ativo (built-in **ou**
/// custom) em vez de assumir a paleta padrão.
TerminalTheme cockpitTerminalThemeFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? cockpitTerminalThemeDark
    : cockpitTerminalThemeLight;

/// Lê a paleta do terminal de [json], herdando de [base] o não declarado.
///
/// `TerminalTheme` vem do xterm absorvido (não é nossa classe), então o codec
/// mora aqui como função em vez de `factory`.
TerminalTheme terminalThemeFromJson(
  Map<String, Object?> json, {
  required TerminalTheme base,
  String path = 'terminal',
}) {
  Color read(String key, Color fallback) =>
      colorOr(json, key, fallback, path: path);
  return TerminalTheme(
    cursor: read('cursor', base.cursor),
    selection: read('selection', base.selection),
    foreground: read('foreground', base.foreground),
    background: read('background', base.background),
    black: read('black', base.black),
    red: read('red', base.red),
    green: read('green', base.green),
    yellow: read('yellow', base.yellow),
    blue: read('blue', base.blue),
    magenta: read('magenta', base.magenta),
    cyan: read('cyan', base.cyan),
    white: read('white', base.white),
    brightBlack: read('brightBlack', base.brightBlack),
    brightRed: read('brightRed', base.brightRed),
    brightGreen: read('brightGreen', base.brightGreen),
    brightYellow: read('brightYellow', base.brightYellow),
    brightBlue: read('brightBlue', base.brightBlue),
    brightMagenta: read('brightMagenta', base.brightMagenta),
    brightCyan: read('brightCyan', base.brightCyan),
    brightWhite: read('brightWhite', base.brightWhite),
    searchHitBackground: read('searchHitBackground', base.searchHitBackground),
    searchHitBackgroundCurrent: read(
      'searchHitBackgroundCurrent',
      base.searchHitBackgroundCurrent,
    ),
    searchHitForeground: read('searchHitForeground', base.searchHitForeground),
  );
}

Map<String, Object?> terminalThemeToJson(TerminalTheme t) => {
  'cursor': encodeHexColor(t.cursor),
  'selection': encodeHexColor(t.selection),
  'foreground': encodeHexColor(t.foreground),
  'background': encodeHexColor(t.background),
  'black': encodeHexColor(t.black),
  'red': encodeHexColor(t.red),
  'green': encodeHexColor(t.green),
  'yellow': encodeHexColor(t.yellow),
  'blue': encodeHexColor(t.blue),
  'magenta': encodeHexColor(t.magenta),
  'cyan': encodeHexColor(t.cyan),
  'white': encodeHexColor(t.white),
  'brightBlack': encodeHexColor(t.brightBlack),
  'brightRed': encodeHexColor(t.brightRed),
  'brightGreen': encodeHexColor(t.brightGreen),
  'brightYellow': encodeHexColor(t.brightYellow),
  'brightBlue': encodeHexColor(t.brightBlue),
  'brightMagenta': encodeHexColor(t.brightMagenta),
  'brightCyan': encodeHexColor(t.brightCyan),
  'brightWhite': encodeHexColor(t.brightWhite),
  'searchHitBackground': encodeHexColor(t.searchHitBackground),
  'searchHitBackgroundCurrent': encodeHexColor(t.searchHitBackgroundCurrent),
  'searchHitForeground': encodeHexColor(t.searchHitForeground),
};
