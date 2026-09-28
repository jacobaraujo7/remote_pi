// Limpeza de escapes ANSI e detecção de alt-screen. Terminal cru traz cor,
// cursor e redraw de TUI; nada disso é telemetria.

final _csi = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]');
final _osc = RegExp(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)');
final _other = RegExp(r'\x1b[@-Z\\-_]');
final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// Remove CSI/OSC/ESC simples e controles (mantém `\t`).
String stripAnsi(String s) {
  if (!s.contains('\x1b') && !_controls.hasMatch(s)) return s;
  return s
      .replaceAll(_osc, '')
      .replaceAll(_csi, '')
      .replaceAll(_other, '')
      .replaceAll(_controls, '');
}

/// Sequências de entrada/saída do alternate screen (`?1049`, `?1047`, `?47`).
final _altEnter = RegExp(r'\x1b\[\?(?:1049|1047|47)h');
final _altExit = RegExp(r'\x1b\[\?(?:1049|1047|47)l');

/// Resultado de [scanAltScreen]: se a linha liga/desliga o alt-screen.
enum AltScreenToggle { none, enter, exit }

/// Detecta a última transição de alt-screen na linha (a última vence quando
/// a mesma linha entra e sai).
AltScreenToggle scanAltScreen(String raw) {
  if (!raw.contains('\x1b[?')) return AltScreenToggle.none;
  final enter = _altEnter.allMatches(raw).lastOrNull?.start ?? -1;
  final exit = _altExit.allMatches(raw).lastOrNull?.start ?? -1;
  if (enter < 0 && exit < 0) return AltScreenToggle.none;
  return enter > exit ? AltScreenToggle.enter : AltScreenToggle.exit;
}
