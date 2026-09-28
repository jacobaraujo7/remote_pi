// Parser incremental de stdout/stderr (plano 66, "Parser (ordem fixa)"):
//   1. strip ANSI, descarta alt-screen
//   2. unwrap de prefixos (flutter:, logcat, compose, concurrently, timestamp)
//   3. JSON Lines → evento estruturado
//   4. bloco de erro por runtime (várias linhas viram UM evento)
//   5. linha crua com severidade chutada
//
// Conservador de propósito: ruído estruturado é pior que ruído cru. Em
// dúvida a linha entra como `info`.

import '../../../domain/contracts/telemetry_line_parser.dart';
import '../../../domain/entities/telemetry_event.dart';
import '../fingerprint.dart';
import 'ansi.dart';
import 'frames.dart';
import 'jsonl.dart';
import 'prefix_unwrap.dart';

class TelemetryLineParserFactoryImpl implements TelemetryLineParserFactory {
  const TelemetryLineParserFactoryImpl();

  @override
  TelemetryLineParser create({
    required String runId,
    TelemetryParserConfig config = const TelemetryParserConfig(),
  }) => TelemetryLineParserImpl(runId: runId, config: config);
}

// ---- regexes de cabeçalho ---------------------------------------------------

final _flutterStart = RegExp(r'^[═=]+╡\s*EXCEPTION CAUGHT BY (.+?)\s*╞[═=]*');
final _flutterEnd = RegExp(r'^[═=]{8,}\s*$');
final _flutterThrown = RegExp(r'^The following (\S+) was thrown(.*?):?\s*$');
final _flutterStackHead = RegExp(
  r'^When the exception was thrown, this was the stack',
);
final _anotherException = RegExp(r'^Another exception was thrown:\s*(.+)$');
final _errorHead = RegExp(
  r'^(?:Unhandled (?:exception|Exception):\s*)?'
  r'([A-Z][\w.]*(?:Error|Exception|Warning|Failure|Fault))'
  r'(?:\s*\(([^)]*)\))?:\s*(.+)$',
);
final _unhandledOnly = RegExp(r'^Unhandled (?:exception|Exception):\s*$');
final _plainError = RegExp(r'^(Error|Exception|error|Fatal error):\s*(.+)$');
final _pythonStart = RegExp(r'^Traceback \(most recent call last\):\s*$');
final _pythonTail = RegExp(r'^([A-Za-z_][\w.]*)(?::\s*(.*))?$');
final _rustPanic = RegExp(
  r"^thread '(.+?)' panicked at (\S+?):(\d+):(\d+):?\s*(.*)$",
);
final _goPanic = RegExp(r'^panic:\s*(.+)$');
final _dartTestFail = RegExp(
  r'^\d{2}:\d{2} \+\d+(?: ~\d+)?(?: -\d+)?: (.+?) \[E\]\s*$',
);
final _jestFail = RegExp(r'^\s*● (.+)$');
final _pytestFail = RegExp(r'^FAILED (\S+)(?: - (.+))?$');
final _typeFromMsg = RegExp(
  r'^([A-Z][\w.]*(?:Error|Exception|Warning))(?:\s*\([^)]*\))?:\s*(.*)$',
);

final _sevFatal = RegExp(r'\b(fatal|panic(?:ked)?)\b', caseSensitive: false);
final _sevError = RegExp(
  r'(?<![\w-])(error|err|exception|failed|failure|unhandled|traceback|crash(?:ed)?|econnrefused|enoent)(?![\w-])',
  caseSensitive: false,
);
final _sevWarn = RegExp(
  r'\b(warn|warning|deprecat\w*)\b',
  caseSensitive: false,
);
final _sevDebug = RegExp(r'^\s*(?:\[?debug\]?|dbg)\b', caseSensitive: false);
final _zeroCount = RegExp(
  r'\b(0|no|zero)\s+(errors?|warnings?|failures?)\b',
  caseSensitive: false,
);

class TelemetryLineParserImpl implements TelemetryLineParser {
  TelemetryLineParserImpl({required this.runId, required this.config});

  final String runId;
  final TelemetryParserConfig config;

  bool _inAlt = false;
  _Block? _block;
  TelemetryError? _lastError;

  @override
  List<TelemetryEvent> feed(
    String line, {
    required TelemetryStream stream,
    required DateTime at,
    int? offset,
  }) {
    // 1. alt-screen + ANSI
    final toggle = scanAltScreen(line);
    if (toggle == AltScreenToggle.enter) _inAlt = true;
    if (toggle == AltScreenToggle.exit) {
      _inAlt = false;
      return const [];
    }
    if (_inAlt) return const [];
    final clean = stripAnsi(line).trimRight();

    // 2. prefixos
    final u = unwrapPrefixes(clean, extra: config.unwrap);
    final text = u.text;
    final ctx = _Ctx(
      stream: stream,
      at: at,
      offset: offset,
      service: u.service,
    );

    // bloco em andamento tenta consumir primeiro
    final out = <TelemetryEvent>[];
    if (_block != null) {
      if (_block!.consume(text, ctx)) {
        if (_block!.done) out.addAll(_emitBlock());
        return out;
      }
      out.addAll(_emitBlock());
    }
    if (text.trim().isEmpty) return out;

    // 4. cabeçalhos de bloco (antes do JSON: um `{` de ZodError não é log)
    final b = _startBlock(text, ctx);
    if (b != null) {
      _block = b;
      return out;
    }

    // "Another exception was thrown: X" (Flutter suprime o bloco repetido)
    final another = _anotherException.firstMatch(text);
    if (another != null) {
      out.add(
        _errorEvent(
          _errorFromMessage(another.group(1)!, reuseFrames: true),
          ctx,
        ),
      );
      return out;
    }

    // 3. JSON Lines
    final json = parseJsonLine(
      text,
      runId: runId,
      at: at,
      stream: stream,
      offset: offset,
      service: u.service,
      projectRoots: config.projectRoots,
      projectFrames: config.projectFrames,
    );
    if (json != null) {
      if (json.error != null) _lastError = json.error;
      out.add(json);
      return out;
    }

    // 5. linha crua
    out.add(_rawEvent(text, ctx));
    return out;
  }

  @override
  List<TelemetryEvent> flush() => _block == null ? const [] : _emitBlock();

  // ---- helpers ---------------------------------------------------------------

  List<TelemetryEvent> _emitBlock() {
    final b = _block!;
    _block = null;
    final err = b.build(this);
    if (err == null) return const [];
    return [_errorEvent(err, b.ctx)];
  }

  _Block? _startBlock(String text, _Ctx ctx) {
    RegExpMatch? m;
    if ((m = _flutterStart.firstMatch(text)) != null) {
      return _FlutterBlock(ctx, library: m!.group(1)!);
    }
    if (_pythonStart.hasMatch(text)) return _PythonBlock(ctx);
    if ((m = _rustPanic.firstMatch(text)) != null) {
      return _RustBlock(
        ctx,
        file: m!.group(2)!,
        line: int.parse(m.group(3)!),
        column: int.parse(m.group(4)!),
        inlineMessage: m.group(5)!.trim(),
      );
    }
    if ((m = _goPanic.firstMatch(text)) != null) {
      return _GoBlock(ctx, message: m!.group(1)!);
    }
    if ((m = _dartTestFail.firstMatch(text)) != null) {
      return _TestBlock(ctx, name: m!.group(1)!);
    }
    if ((m = _jestFail.firstMatch(text)) != null && text.startsWith('  ')) {
      return _TestBlock(ctx, name: m!.group(1)!);
    }
    if ((m = _pytestFail.firstMatch(text)) != null) {
      final b = _TestBlock(ctx, name: m!.group(1)!)..detail = m.group(2);
      b.done = true;
      return b;
    }
    if (_unhandledOnly.hasMatch(text)) {
      return _ErrorBlock(ctx, type: null, message: '');
    }
    if ((m = _errorHead.firstMatch(text)) != null) {
      return _ErrorBlock(ctx, type: m!.group(1)!, message: m.group(3)!);
    }
    if ((m = _plainError.firstMatch(text)) != null) {
      final t = m!.group(1)!;
      return _ErrorBlock(
        ctx,
        type: t == 'Fatal error'
            ? 'FatalError'
            : (t[0].toUpperCase() + t.substring(1)),
        message: m.group(2)!,
      );
    }
    return null;
  }

  TelemetryFrame? _frame(String line) => parseFrame(
    line,
    projectRoots: config.projectRoots,
    projectFrames: config.projectFrames,
  );

  /// `RangeError (index): msg` → (RangeError, msg). Sem tipo → `Error`.
  TelemetryError _errorFromMessage(String raw, {bool reuseFrames = false}) {
    final m = _typeFromMsg.firstMatch(raw);
    final type = m?.group(1) ?? 'Error';
    final message = m?.group(2) ?? raw;
    var frames = const <TelemetryFrame>[];
    final last = _lastError;
    if (reuseFrames &&
        last != null &&
        last.type == type &&
        normalizeMessage(last.message) == normalizeMessage(message)) {
      frames = last.frames;
    }
    return TelemetryError(type: type, message: message, frames: frames);
  }

  TelemetryEvent _errorEvent(TelemetryError err, _Ctx ctx) {
    _lastError = err;
    final sev = err.type.endsWith('Warning')
        ? TelemetrySeverity.warn
        : (err.type == 'Panic' || err.type == 'FatalError'
              ? TelemetrySeverity.fatal
              : TelemetrySeverity.error);
    return TelemetryEvent(
      runId: runId,
      ts: ctx.at,
      stream: ctx.stream,
      severity: sev,
      body: err.message,
      attrs: {'service': ?ctx.service},
      error: err,
      fingerprint: fingerprintOf(err),
      rawLineOffset: ctx.offset,
    );
  }

  TelemetryEvent _rawEvent(String text, _Ctx ctx) {
    TelemetrySeverity sev;
    if (_sevFatal.hasMatch(text)) {
      sev = TelemetrySeverity.fatal;
    } else if (_sevError.hasMatch(text) && !_zeroCount.hasMatch(text)) {
      sev = TelemetrySeverity.error;
    } else if (_sevWarn.hasMatch(text) && !_zeroCount.hasMatch(text)) {
      sev = TelemetrySeverity.warn;
    } else if (_sevDebug.hasMatch(text)) {
      sev = TelemetrySeverity.debug;
    } else {
      sev = TelemetrySeverity.info;
    }
    return TelemetryEvent(
      runId: runId,
      ts: ctx.at,
      stream: ctx.stream,
      severity: sev,
      body: text.trim(),
      attrs: {'service': ?ctx.service},
      rawLineOffset: ctx.offset,
    );
  }
}

class _Ctx {
  const _Ctx({
    required this.stream,
    required this.at,
    this.offset,
    this.service,
  });
  final TelemetryStream stream;
  final DateTime at;
  final int? offset;
  final String? service;
}

// ---- blocos -----------------------------------------------------------------

abstract class _Block {
  _Block(this.ctx);
  final _Ctx ctx;
  bool done = false;
  int lines = 0;
  static const maxLines = 400;

  /// `true` se a linha pertence ao bloco (foi consumida).
  bool consume(String text, _Ctx c) {
    if (lines++ > maxLines) return false;
    return accept(text);
  }

  bool accept(String text);
  TelemetryError? build(TelemetryLineParserImpl p);
}

/// `Type: msg` seguido de frames (Dart/Node) e, no Node, propriedades
/// indentadas (`  code: 'ECONNREFUSED'`).
class _ErrorBlock extends _Block {
  _ErrorBlock(super.ctx, {required this.type, required this.message});
  String? type;
  String message;
  final frameLines = <String>[];
  final detail = <String>[];
  int _extraMsg = 0;

  @override
  bool accept(String text) {
    if (type == null) {
      // "Unhandled exception:" sozinho: a próxima linha é o "Type: msg"
      final m = _errorHead.firstMatch(text) ?? _typeFromMsg.firstMatch(text);
      if (m != null) {
        type = m.group(1);
        message = m.groupCount >= 3
            ? (m.group(3) ?? m.group(2) ?? '')
            : (m.group(2) ?? '');
        return true;
      }
      if (text.trim().isEmpty) return true;
      type = 'Error';
      message = text.trim();
      return true;
    }
    if (looksLikeStackLine(text)) {
      frameLines.add(text);
      return true;
    }
    if (text.trim().isEmpty) {
      return frameLines.isEmpty && _extraMsg < 3 && ++_extraMsg > 0;
    }
    if (frameLines.isEmpty &&
        _extraMsg < 6 &&
        (text.startsWith(' ') ||
            text.startsWith('\t') ||
            text.startsWith('{') ||
            text.startsWith('['))) {
      message = '$message\n${text.trimRight()}';
      _extraMsg++;
      return true;
    }
    if (frameLines.isNotEmpty &&
        (text.startsWith(' ') || text.startsWith('\t') || text == '}')) {
      detail.add(text.trim());
      return true;
    }
    return false;
  }

  @override
  TelemetryError build(TelemetryLineParserImpl p) => TelemetryError(
    type: type ?? 'Error',
    message: message.trim(),
    stack: frameLines.isEmpty ? null : frameLines.join('\n'),
    frames: [for (final l in frameLines) ?p._frame(l)],
  );
}

/// `══╡ EXCEPTION CAUGHT BY X ╞══ ... ════`
class _FlutterBlock extends _Block {
  _FlutterBlock(super.ctx, {required this.library});
  final String library;
  String? type;
  final msg = <String>[];
  final frameLines = <String>[];
  bool _inStack = false;
  bool _inMsg = false;

  @override
  bool accept(String text) {
    if (_flutterEnd.hasMatch(text)) {
      done = true;
      return true;
    }
    final t = _flutterThrown.firstMatch(text);
    if (t != null) {
      type = t.group(1);
      _inMsg = true;
      return true;
    }
    if (_flutterStackHead.hasMatch(text)) {
      _inStack = true;
      _inMsg = false;
      return true;
    }
    if (_inStack) {
      if (looksLikeStackLine(text)) frameLines.add(text);
      if (text.trim().isEmpty && frameLines.isNotEmpty) _inStack = false;
      return true;
    }
    if (_inMsg) {
      if (text.trim().isEmpty) {
        _inMsg = msg.isEmpty;
      } else {
        msg.add(text.trim());
      }
    }
    return true;
  }

  @override
  TelemetryError build(TelemetryLineParserImpl p) {
    var t = type ?? 'FlutterError';
    var m = msg.join(' ');
    // "RangeError (index): msg" dentro da mensagem
    final inner = _typeFromMsg.firstMatch(m);
    if (inner != null) {
      t = inner.group(1)!;
      m = inner.group(2)!;
    }
    if (m.isEmpty) m = 'Exception caught by $library';
    return TelemetryError(
      type: t,
      message: m,
      stack: frameLines.isEmpty ? null : frameLines.join('\n'),
      frames: [for (final l in frameLines) ?p._frame(l)],
    );
  }
}

/// `Traceback ...` até a linha `Type: msg` sem indentação.
class _PythonBlock extends _Block {
  _PythonBlock(super.ctx);
  final frameLines = <String>[];
  String? type;
  String? message;

  @override
  bool accept(String text) {
    if (text.startsWith(' ') || text.startsWith('\t')) {
      if (parseFrame(text) != null) frameLines.add(text);
      return true;
    }
    if (text.trim().isEmpty) return true;
    final m = _pythonTail.firstMatch(text);
    if (m != null) {
      type = m.group(1)!.split('.').last;
      message = m.group(2) ?? '';
      done = true;
      return true;
    }
    return false;
  }

  @override
  TelemetryError build(TelemetryLineParserImpl p) {
    // Python: último frame é o mais interno; invertemos pra o [0] ser o topo.
    final frames = [for (final l in frameLines.reversed) ?p._frame(l)];
    return TelemetryError(
      type: type ?? 'Exception',
      message: message ?? '',
      stack: frameLines.join('\n'),
      frames: frames,
    );
  }
}

/// `thread 'main' panicked at src/x.rs:12:5:` + mensagem + backtrace.
class _RustBlock extends _Block {
  _RustBlock(
    super.ctx, {
    required this.file,
    required this.line,
    required this.column,
    required this.inlineMessage,
  });
  final String file;
  final int line;
  final int column;
  final String inlineMessage;
  final msg = <String>[];
  final frameLines = <String>[];

  @override
  bool accept(String text) {
    if (text.startsWith('note:') || text.startsWith('stack backtrace:')) {
      return true;
    }
    if (RegExp(r'^\s+\d+:\s').hasMatch(text)) return true; // "   0: fn"
    if (parseFrame(text) != null) {
      frameLines.add(text);
      return true;
    }
    if (text.trim().isEmpty) return msg.isEmpty && inlineMessage.isEmpty;
    if (msg.isEmpty && inlineMessage.isEmpty && !text.startsWith(' ')) {
      msg.add(text.trim());
      return true;
    }
    return false;
  }

  @override
  TelemetryError build(TelemetryLineParserImpl p) {
    final head = TelemetryFrame(
      raw: '$file:$line:$column',
      file: normalizeProjectPath(file, p.config.projectRoots),
      line: line,
      column: column,
      inProject: isProjectFile(
        file,
        projectRoots: p.config.projectRoots,
        projectFrames: p.config.projectFrames,
      ),
    );
    return TelemetryError(
      type: 'Panic',
      message: inlineMessage.isNotEmpty ? inlineMessage : msg.join(' '),
      stack: frameLines.isEmpty ? null : frameLines.join('\n'),
      frames: [head, for (final l in frameLines) ?p._frame(l)],
    );
  }
}

/// `panic: msg` + `goroutine N [running]:` + pares função/arquivo.
class _GoBlock extends _Block {
  _GoBlock(super.ctx, {required this.message});
  final String message;
  final frameLines = <String>[];
  bool _started = false;

  @override
  bool accept(String text) {
    if (text.trim().isEmpty) return !_started;
    if (text.startsWith('goroutine ')) {
      _started = true;
      return true;
    }
    if (parseFrame(text) != null) {
      frameLines.add(text);
      return true;
    }
    // linha da função (`main.run(...)`) entre frames
    return _started && !text.startsWith(' ') && text.contains('(');
  }

  @override
  TelemetryError build(TelemetryLineParserImpl p) => TelemetryError(
    type: 'Panic',
    message: message,
    stack: frameLines.isEmpty ? null : frameLines.join('\n'),
    frames: [for (final l in frameLines) ?p._frame(l)],
  );
}

/// Falha de teste (dart test `[E]`, jest `●`, pytest `FAILED`): linhas
/// indentadas até a próxima linha "solta".
class _TestBlock extends _Block {
  _TestBlock(super.ctx, {required this.name});
  final String name;
  String? detail;
  final frameLines = <String>[];

  @override
  bool accept(String text) {
    if (text.trim().isEmpty) return true;
    if (!(text.startsWith(' ') || text.startsWith('\t'))) return false;
    if (parseFrame(text) != null) {
      frameLines.add(text);
    } else {
      detail ??= text.trim();
    }
    return true;
  }

  @override
  TelemetryError build(TelemetryLineParserImpl p) => TelemetryError(
    type: 'Test failed',
    message: detail == null ? name : '$name: $detail',
    stack: frameLines.isEmpty ? null : frameLines.join('\n'),
    frames: [for (final l in frameLines) ?p._frame(l)],
  );
}
