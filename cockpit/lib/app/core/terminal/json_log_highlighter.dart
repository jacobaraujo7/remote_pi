import 'dart:convert';

/// Realce de **logs estruturados JSON** no output das tasks.
///
/// O output da task não passa por widget nenhum: vai cru pro emulador VT
/// (Ghostty/xterm), que desenha o grid. Então o único ponto onde dá pra colorir
/// é o próprio texto — este transformador injeta SGR (`ESC [ n m`) nas linhas
/// que são JSON, antes do `write` no terminal.
///
/// **Por que SGR indexado (30-37 / 90-97) e não truecolor**: os índices são
/// resolvidos pelo emulador contra o `TerminalTheme` do tema ativo **na hora de
/// pintar**. Isso significa que o log usa a paleta do tema (inclusive tema
/// custom importado), e que trocar de tema repinta o buffer já escrito — sem
/// reprocessar nada e sem um `Color(0x…)` sequer no código.
///
/// **Não estraga o que já funciona**: uma linha só é transformada se decodifica
/// como objeto JSON *e* não contém nenhum byte ANSI. Output do Flutter/Vite (que
/// já vem colorido) e texto solto passam intactos, byte a byte.
///
/// Stateful por task: guarda a cauda de linha incompleta entre chunks.
class JsonLogHighlighter {
  /// Teto da cauda segurada entre chunks. Acima disso a cauda é solta crua —
  /// nada de segurar output indefinidamente esperando um `}` que não vem.
  static const int _maxPendingChars = 64 * 1024;

  /// Linha maior que isso nem tenta decodificar (JSON de log não tem esse porte
  /// e o `json.decode` custaria caro no caminho quente).
  static const int _maxLineChars = 32 * 1024;

  String _pending = '';

  /// Processa um chunk decodificado e devolve o texto a escrever no terminal.
  /// Pode devolver `''` quando o chunk inteiro virou cauda pendente.
  String process(String chunk) {
    if (chunk.isEmpty) return chunk;
    // Caminho quente: sem `{` e sem cauda pendente, nenhuma linha pode
    // qualificar nem virar cauda — devolve o chunk sem tocar.
    if (_pending.isEmpty && !chunk.contains('{')) return chunk;

    final text = _pending + chunk;
    _pending = '';

    final out = StringBuffer();
    var start = 0;
    while (true) {
      final nl = text.indexOf('\n', start);
      if (nl < 0) break;
      out
        ..write(_highlightLine(text.substring(start, nl)))
        ..write('\n');
      start = nl + 1;
    }

    final tail = text.substring(start);
    if (_shouldHold(tail)) {
      _pending = tail;
    } else {
      out.write(tail);
    }
    return out.toString();
  }

  /// Solta a cauda pendente **sem transformar** (linha incompleta). Chamado no
  /// fim do run, senão o último log sem `\n` sumiria com o processo.
  String flushPending() {
    if (_pending.isEmpty) return '';
    final out = _pending;
    _pending = '';
    return out;
  }

  /// Só segura a cauda quando ela pode virar uma linha JSON. Prompt
  /// interativo, barra de progresso com `\r` e texto solto saem na hora — o
  /// realce nunca pode atrasar output que o usuário está esperando ver.
  bool _shouldHold(String tail) {
    if (tail.isEmpty || tail.length > _maxPendingChars) return false;
    if (tail.contains('\x1b')) return false;
    final i = _firstNonSpace(tail);
    return i >= 0 && tail.codeUnitAt(i) == _lbrace;
  }

  /// Preserva o `\r` final (CRLF do Windows) fora da transformação.
  String _highlightLine(String raw) {
    if (raw.endsWith('\r')) {
      final painted = _paint(raw.substring(0, raw.length - 1));
      return painted == null ? raw : '$painted\r';
    }
    return _paint(raw) ?? raw;
  }

  /// `null` = a linha não é um log JSON; o chamador mantém o original.
  String? _paint(String line) {
    if (line.length > _maxLineChars) return null;
    if (line.contains('\x1b')) return null;

    final open = _firstNonSpace(line);
    if (open < 0 || line.codeUnitAt(open) != _lbrace) return null;
    final close = _lastNonSpace(line);
    if (close < open || line.codeUnitAt(close) != _rbrace) return null;

    final body = line.substring(open, close + 1);
    final Map<Object?, Object?> decoded;
    try {
      final value = json.decode(body);
      if (value is! Map) return null;
      decoded = value;
    } on FormatException {
      return null;
    }

    final out = StringBuffer(line.substring(0, open));
    _scan(body, out, _severityColor(decoded));
    out.write(line.substring(close + 1));
    return out.toString();
  }

  /// Varre o **texto original** (não o `Map` decodificado) pra preservar ordem,
  /// espaçamento e escapes exatamente como o logger emitiu.
  void _scan(String s, StringBuffer out, int? severity) {
    // 0 = dentro de objeto, 1 = dentro de array.
    final stack = <int>[];
    var expectKey = false;
    String? key; // última chave do nível 1

    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '{' || c == '[') {
        _emit(out, _cPunct, c);
        stack.add(c == '{' ? 0 : 1);
        expectKey = c == '{';
        i++;
      } else if (c == '}' || c == ']') {
        _emit(out, _cPunct, c);
        if (stack.isNotEmpty) stack.removeLast();
        expectKey = false;
        i++;
      } else if (c == ',') {
        _emit(out, _cPunct, c);
        expectKey = stack.isNotEmpty && stack.last == 0;
        i++;
      } else if (c == ':') {
        _emit(out, _cPunct, c);
        expectKey = false;
        i++;
      } else if (c == '"') {
        final end = _stringEnd(s, i);
        final token = s.substring(i, end);
        final topLevel = stack.length == 1;
        if (expectKey) {
          final name = _unquote(token);
          key = topLevel ? name : null;
          _emit(out, topLevel ? _keyColor(name, severity) : _cKey, token);
        } else {
          _emit(
            out,
            _valueColor(topLevel ? key : null, severity, _cString),
            token,
          );
        }
        i = end;
      } else if (c == ' ' || c == '\t') {
        out.write(c);
        i++;
      } else {
        final end = _literalEnd(s, i);
        final token = s.substring(i, end);
        final base = _isNumberStart(token) ? _cNumber : _cLiteral;
        _emit(
          out,
          _valueColor(stack.length == 1 ? key : null, severity, base),
          token,
        );
        i = end;
      }
    }
  }

  void _emit(StringBuffer out, int color, String token) =>
      out.write('\x1b[${color}m$token\x1b[0m');

  /// Chave de nível 1: a intenção é **destacar só o que importa** — nível,
  /// mensagem e erro saltam; timestamp/caller recuam; o resto é neutro.
  int _keyColor(String name, int? severity) {
    final n = name.toLowerCase();
    if (_levelKeys.contains(n)) return severity ?? _cKey;
    if (_errorKeys.contains(n)) return _cError;
    if (_timeKeys.contains(n)) return _cMuted;
    return _cKey;
  }

  int _valueColor(String? key, int? severity, int fallback) {
    if (key == null) return fallback;
    final n = key.toLowerCase();
    if (_levelKeys.contains(n)) return severity ?? fallback;
    if (_errorKeys.contains(n)) return _cError;
    if (_msgKeys.contains(n)) return _cMessage;
    if (_timeKeys.contains(n)) return _cMuted;
    return fallback;
  }

  /// Cor do nível a partir do `Map` já decodificado — resolvida antes da varredura
  /// pra que a **chave** possa ser pintada com a cor do valor (o `level` inteiro
  /// fica vermelho num erro, não só o `"error"`).
  int? _severityColor(Map<Object?, Object?> m) {
    for (final entry in m.entries) {
      final k = entry.key;
      if (k is! String || !_levelKeys.contains(k.toLowerCase())) continue;
      final v = entry.value;
      if (v is String) return _severityOfName(v);
      // Níveis numéricos (pino/bunyan): 50 error, 40 warn, 30 info, ≤20 debug.
      if (v is num) {
        if (v >= 50) return _cError;
        if (v >= 40) return _cWarn;
        if (v >= 30) return _cInfo;
        return _cMuted;
      }
    }
    return null;
  }

  int? _severityOfName(String raw) => switch (raw.toLowerCase()) {
    'error' || 'err' || 'fatal' || 'panic' || 'critical' || 'crit' => _cError,
    'warn' || 'warning' => _cWarn,
    'info' || 'notice' => _cInfo,
    'debug' || 'trace' || 'verbose' => _cMuted,
    _ => null,
  };

  // --- scanner ------------------------------------------------------------

  int _stringEnd(String s, int start) {
    var i = start + 1;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == _backslash) {
        i += 2;
        continue;
      }
      if (c == _quote) return i + 1;
      i++;
    }
    return s.length;
  }

  int _literalEnd(String s, int start) {
    var i = start;
    while (i < s.length && !_isDelimiter(s.codeUnitAt(i))) {
      i++;
    }
    return i == start ? start + 1 : i;
  }

  bool _isDelimiter(int c) =>
      c == 0x2C || // ,
      c == 0x3A || // :
      c == _lbrace ||
      c == _rbrace ||
      c == 0x5B || // [
      c == 0x5D || // ]
      c == 0x20 ||
      c == 0x09 ||
      c == _quote;

  bool _isNumberStart(String token) {
    if (token.isEmpty) return false;
    final c = token.codeUnitAt(0);
    return c == 0x2D || (c >= 0x30 && c <= 0x39); // '-' ou dígito
  }

  String _unquote(String token) {
    if (token.length < 2) return token;
    final inner = token.substring(1, token.length - 1);
    if (!inner.contains(r'\')) return inner;
    try {
      final decoded = json.decode(token);
      return decoded is String ? decoded : inner;
    } on FormatException {
      return inner;
    }
  }

  int _firstNonSpace(String s) {
    for (var i = 0; i < s.length; i++) {
      if (!_isSpace(s.codeUnitAt(i))) return i;
    }
    return -1;
  }

  int _lastNonSpace(String s) {
    for (var i = s.length - 1; i >= 0; i--) {
      if (!_isSpace(s.codeUnitAt(i))) return i;
    }
    return -1;
  }

  bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0D;
}

// --- paleta (índices ANSI: quem pinta é o TerminalTheme do tema ativo) ------

const int _cPunct = 90; // brightBlack — estrutura recua
const int _cKey = 36; // cyan
const int _cString = 32; // green
const int _cNumber = 33; // yellow
const int _cLiteral = 35; // magenta — true/false/null
const int _cError = 91; // brightRed
const int _cWarn = 93; // brightYellow
const int _cInfo = 94; // brightBlue
const int _cMuted = 90; // brightBlack
const int _cMessage = 97; // brightWhite — a mensagem lê primeiro

const int _lbrace = 0x7B;
const int _rbrace = 0x7D;
const int _quote = 0x22;
const int _backslash = 0x5C;

const Set<String> _levelKeys = {
  'level',
  'lvl',
  'severity',
  'sev',
  'loglevel',
  'log.level',
};

/// Cobre logger que reporta falha sem campo `level` (ex.: `{"error": "..."}`).
const Set<String> _errorKeys = {'error', 'err', 'exception', 'stack'};

const Set<String> _msgKeys = {'msg', 'message'};

const Set<String> _timeKeys = {
  'time',
  'ts',
  'timestamp',
  '@timestamp',
  'caller',
};
