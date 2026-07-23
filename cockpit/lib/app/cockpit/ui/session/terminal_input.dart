import 'package:cockpit/app/core/terminal/xterm/xterm.dart';

/// Rastreia se o *kitty keyboard protocol* está ativo, observando a saída do
/// programa em primeiro plano (claude, codex, pi, ...).
///
/// Apps que suportam o protocolo "empurram" flags via `CSI > flags u` ao iniciar
/// e as removem via `CSI < n u` (ou um reset) ao sair. Enquanto há flags ativas,
/// o terminal deve codificar teclas modificadas (ex.: Shift+Enter) no formato
/// CSI-u em vez do encoding legado.
///
/// **Não** implementamos o protocolo inteiro — só detectamos se ele está ligado,
/// pra escolher o byte certo do Shift+Enter (ver [ShiftEnterInputHandler]). Todas
/// as outras teclas continuam no encoding legado do xterm, exatamente como hoje
/// (o `pi`, que já empurra flags kitty, prova que isso funciona). Por isso só
/// observamos passivamente: nunca anunciamos suporte (não respondemos à query
/// `CSI ? u`), pra não fazer um app habilitar o protocolo e quebrar outras teclas
/// que continuariam legadas.
class KittyKeyboardTracker {
  final List<int> _stack = <int>[];
  String _carry = '';

  /// Verdadeiro quando o app em primeiro plano habilitou o protocolo (há flags
  /// não-nulas no topo da pilha).
  bool get active => _stack.isNotEmpty && _stack.last > 0;

  /// Alimenta um pedaço da saída do PTY (já decodificado — as sequências de
  /// controle são ASCII puro, então a decodificação UTF-8 não as altera).
  void feed(String chunk) {
    // Uma sequência kitty pode chegar partida entre dois reads do PTY; por isso
    // guardamos uma pequena cauda (sufixo não casado) entre chamadas.
    final s = _carry + chunk;
    var consumedEnd = 0;
    for (final m in _seqPattern.allMatches(s)) {
      _apply(m.group(0)!);
      consumedEnd = m.end;
    }
    final keepFrom = (s.length - _maxSeqLen) > consumedEnd
        ? s.length - _maxSeqLen
        : consumedEnd;
    _carry = keepFrom < s.length ? s.substring(keepFrom) : '';
  }

  void _apply(String seq) {
    if (seq == '\x1bc') {
      _stack.clear(); // RIS: reset total do terminal.
      return;
    }
    // seq = ESC [ <marker> <0-9;>* u
    final marker = seq.codeUnitAt(2);
    final body = seq.substring(3, seq.length - 1);
    switch (marker) {
      case 0x3e: // '>' push: novo nível com estas flags.
        _stack.add(_firstInt(body));
      case 0x3c: // '<' pop: remove n níveis (default 1).
        var n = _firstInt(body, fallback: 1);
        if (n < 1) n = 1;
        for (var i = 0; i < n && _stack.isNotEmpty; i++) {
          _stack.removeLast();
        }
      case 0x3d: // '=' set: flags ; mode (1=set, 2=or, 3=and-not; default 1).
        final parts = body.split(';');
        final flags = _intOr(parts.isNotEmpty ? parts[0] : '', 0);
        final mode = parts.length > 1 ? _intOr(parts[1], 1) : 1;
        final current = _stack.isEmpty ? 0 : _stack.removeLast();
        _stack.add(switch (mode) {
          2 => current | flags,
          3 => current & ~flags,
          _ => flags,
        });
      case 0x3f: // '?' query: app só pergunta o suporte. Passivo: ignoramos.
        break;
    }
  }

  static int _firstInt(String body, {int fallback = 0}) =>
      _intOr(body.split(';').first, fallback);

  static int _intOr(String s, int fallback) => int.tryParse(s) ?? fallback;

  static const _maxSeqLen = 16;

  /// `CSI <marker> <0-9;>* u` (marker ∈ `> < = ?`) ou RIS (`ESC c`).
  static final _seqPattern = RegExp(r'\x1b\[[<>=?][0-9;]*u|\x1bc');
}

/// Faz o **Shift+Enter** inserir uma quebra de linha em vez de submeter, nos
/// harnesses TUI (claude, codex, pi).
///
/// O xterm 4.0 mapeia Shift+Enter pra `ESC O M` (`\x1bOM`), que esses apps
/// ignoram — então a quebra nunca acontece. Aqui interceptamos antes do
/// [defaultInputHandler] e emitimos o byte que o app entende:
///
/// - app com kitty keyboard ATIVO (pi, codex): `CSI 13 ; 2 u` (`\x1b[13;2u`),
///   o encoding canônico de Shift+Enter no protocolo kitty;
/// - caso contrário (claude em modo legado, shells, REPLs): um line feed `\n` —
///   claude/pi tratam como nova linha e o shell trata como Enter, sem o lixo
///   `[13;2u` que o CSI-u deixaria num programa sem kitty.
///
/// Só o Shift+Enter muda; qualquer outra tecla cai no handler padrão.
class ShiftEnterInputHandler implements TerminalInputHandler {
  const ShiftEnterInputHandler(this._kitty);

  final KittyKeyboardTracker _kitty;

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.key != TerminalKey.enter ||
        !event.shift ||
        event.ctrl ||
        event.alt) {
      return null; // não é Shift+Enter "puro" — deixa o handler padrão decidir.
    }
    return _kitty.active ? '\x1b[13;2u' : '\n';
  }
}
