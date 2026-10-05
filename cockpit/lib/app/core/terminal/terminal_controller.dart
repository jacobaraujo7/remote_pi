import 'dart:convert';

import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/ghostty_sgr_weight_normalizer.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:libghostty/libghostty.dart' show FormatterFormat;

typedef TerminalResizeCallback = void Function(int columns, int rows);

/// API comum entre o xterm absorvido e o libghostty.
///
/// O modelo concreto continua exposto nos adapters para as views específicas;
/// sessão, task store e CLI usam apenas esta superfície.
sealed class CockpitTerminalController {
  TerminalEngine get engine;

  ValueChanged<Uint8List>? onOutput;
  TerminalResizeCallback? onResize;
  ValueChanged<String>? onTitleChanged;

  void write(String data);
  void restore(String data);
  void paste(String text);
  List<String> plainLines();

  /// Conteúdo textual renderizado, sem ANSI e sem as linhas vazias que existem
  /// apenas para completar a grade do terminal.
  String plainText();

  /// Limpa tela e scrollback localmente, sem enviar input para o processo.
  void clearBuffer();

  /// Texto atualmente selecionado, ou vazio se não há seleção.
  ///
  /// Serve o botão de copiar da barra de teclas do mobile, que não tem como
  /// alcançar a view. No xterm absorvido a seleção vive no controller da
  /// **view** (`CockpitTerminal`), fora do alcance da sessão — lá devolve vazio.
  String selectedText();

  void dispose();
}

final class XtermTerminalController implements CockpitTerminalController {
  XtermTerminalController({xterm.TerminalInputHandler? inputHandler})
    : terminal = xterm.Terminal(maxLines: 10000, inputHandler: inputHandler) {
    terminal.onOutput = (data) => onOutput?.call(utf8.encode(data));
    terminal.onResize = (columns, rows, _, _) => onResize?.call(columns, rows);
    terminal.onTitleChange = (title) => onTitleChanged?.call(title);
  }

  final xterm.Terminal terminal;

  @override
  TerminalEngine get engine => TerminalEngine.xterm;

  @override
  ValueChanged<Uint8List>? onOutput;

  @override
  TerminalResizeCallback? onResize;

  @override
  ValueChanged<String>? onTitleChanged;

  @override
  void write(String data) => terminal.write(data);

  @override
  void restore(String data) => write(data);

  @override
  void paste(String text) => terminal.paste(text);

  @override
  List<String> plainLines() {
    final lines = terminal.buffer.lines;
    return [for (var i = 0; i < lines.length; i++) lines[i].getText()];
  }

  @override
  String plainText() => terminal.buffer
      .getText(
        xterm.BufferRangeLine(
          const xterm.CellOffset(0, 0),
          xterm.CellOffset(terminal.viewWidth, terminal.buffer.height - 1),
        ),
      )
      .trimRight();

  @override
  void clearBuffer() => terminal.write('\x1b[H\x1b[2J\x1b[3J');

  /// A seleção do xterm pertence ao controller da view (`CockpitTerminal`), que
  /// a sessão não enxerga — o motor em si não guarda seleção. Copiar por aqui
  /// só existe no Ghostty (o padrão dos buffers novos, inclusive no mobile).
  @override
  String selectedText() => '';

  @override
  void dispose() {}
}

final class GhosttyTerminalController implements CockpitTerminalController {
  GhosttyTerminalController()
    : controller = ghost.TerminalController(
        config: const ghost.TerminalConfig(
          cols: 80,
          rows: 25,
          // Renomeado no upstream (flterm main): scrollbackLimit -> scrollbackMaxBytes.
          // Mantemos 10 MB explicito; o novo default e apenas 10 KB.
          scrollbackMaxBytes: 10 * 1024 * 1024,
        ),
      ) {
    controller.onOutput = (data) {
      // Durante o replay do scrollback (restore) o emulador responde às queries
      // embutidas no histórico (Primary DA, DECRQM de modos como 2026 etc.);
      // essas respostas NÃO podem ir pro PTG, senão viram lixo no prompt do
      // shell (`?62;...c`, `?2026;2$y`...) — a resposta já foi tratada ao vivo
      // na sessão original. Ver [_replayNow].
      if (_replaying) return;
      onOutput?.call(data);
    };
    controller.onResize = _handleControllerResize;
    controller.onTitleChanged = () => onTitleChanged?.call(controller.title);
  }

  void _handleControllerResize(int columns, int rows) {
    final isInitialResize = !_hasInitialResize;
    _hasInitialResize = true;
    if (isInitialResize &&
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      // flterm reports its grid size from performLayout. Restored OSC state
      // can notify TerminalView, so applying it here would call setState
      // while the render tree is still being laid out.
      _deferWritesUntilPostFrame = true;
    }
    onResize?.call(columns, rows);

    if (!isInitialResize) return;
    if (_deferWritesUntilPostFrame) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _flushPendingWrites();
      });
    } else {
      _flushPendingWrites();
    }
  }

  /// Drives the controller's resize handling directly.
  ///
  /// In production flterm's `TerminalView` reports its measured grid through
  /// the (setter-only) `controller.onResize`. Tests have no view, so this hook
  /// simulates that report to exercise the initial-resize replay flush.
  @visibleForTesting
  void handleResize(int columns, int rows) =>
      _handleControllerResize(columns, rows);

  final ghost.TerminalController controller;

  @override
  TerminalEngine get engine => TerminalEngine.ghostty;

  @override
  ValueChanged<Uint8List>? onOutput;

  @override
  TerminalResizeCallback? onResize;

  @override
  ValueChanged<String>? onTitleChanged;

  final GhosttySgrWeightNormalizer _weightNormalizer =
      GhosttySgrWeightNormalizer();
  bool _hasInitialResize = false;
  bool _deferWritesUntilPostFrame = false;
  bool _disposed = false;
  bool _replaying = false;
  // Filas separadas durante o defer (até o 1º resize): `_pendingReplay` é o
  // scrollback restaurado (respostas suprimidas); `_pendingLive` é saída viva do
  // shell que chegou cedo (respostas normais). Separadas porque a supressão de
  // `onOutput` vale só pro replay — misturar dropava resposta de query viva.
  List<String>? _pendingReplay;
  List<String>? _pendingLive;

  @override
  void write(String data) {
    if (_deferWritesUntilPostFrame ||
        (!_hasInitialResize && _pendingReplay != null)) {
      (_pendingLive ??= <String>[]).add(data);
      return;
    }
    _writeNow(data);
  }

  @override
  void restore(String data) {
    if (_hasInitialResize && !_deferWritesUntilPostFrame) {
      _replayNow(data);
      return;
    }
    (_pendingReplay ??= <String>[]).add(data);
  }

  void _flushPendingWrites() {
    if (_disposed) return;
    _deferWritesUntilPostFrame = false;
    final replay = _pendingReplay;
    final live = _pendingLive;
    _pendingReplay = null;
    _pendingLive = null;
    if (replay != null) {
      for (final data in replay) {
        _replayNow(data);
      }
    }
    if (live != null) {
      for (final data in live) {
        _writeNow(data);
      }
    }
  }

  /// Escreve conteúdo de REPLAY suprimindo o `onOutput` — ver o comentário no
  /// wiring do `onOutput`. Sem isso, as queries do histórico geram respostas que
  /// vazam pro PTG e sujam o prompt (chegou a criar um arquivo via `>|` redirect).
  void _replayNow(String data) {
    _replaying = true;
    try {
      _writeNow(data);
    } finally {
      _replaying = false;
    }
  }

  void _writeNow(String data) {
    final normalized = _weightNormalizer.add(data);
    if (normalized.isEmpty) return;
    controller.write(Uint8List.fromList(utf8.encode(normalized)));
  }

  @override
  void paste(String text) => controller.paste(text);

  @override
  List<String> plainLines() {
    final formatter = controller.createFormatter(
      format: FormatterFormat.plain,
      unwrap: false,
      trim: false,
    );
    try {
      return const LineSplitter().convert(formatter.format());
    } finally {
      formatter.dispose();
    }
  }

  @override
  String plainText() {
    final formatter = controller.createFormatter(
      format: FormatterFormat.plain,
      unwrap: true,
      trim: true,
    );
    try {
      return formatter.format().trimRight();
    } finally {
      formatter.dispose();
    }
  }

  @override
  void clearBuffer() => _replayNow('\x1bc');

  @override
  String selectedText() =>
      controller.hasSelection ? controller.selectedText() : '';

  @override
  void dispose() {
    _disposed = true;
    controller.dispose();
  }
}

/// Se o seletor de engine aparece nas Settings e a escolha é honrada.
///
/// O Windows já ficou travado no xterm porque o `flterm` engolia teclas (view
/// id nulo no text input) e o scroll interno de TUI não funcionava. Com os
/// fixes do fork (text input #114 + wheel/trackpad) isso foi resolvido, então o
/// Ghostty voltou a ser selecionável em todas as plataformas — em teste no
/// Windows via a branch/override do fork.
bool get terminalEngineIsSelectable => true;

/// Resolve o engine efetivo pra plataforma — hoje passa direto (sem gate de
/// plataforma). Mantido como ponto único caso precise re-travar alguma engine.
///
/// Histórico: o mobile chegou a ser travado no xterm por um `EXC_BAD_ACCESS` na
/// init do Ghostty no iOS. A causa era mismatch de ABI do enum de options entre
/// `flterm 0.0.4` e `libghostty 0.0.11` (versões descasadas), não um bug de
/// iOS. Com o pin casado (`cockpit-pin-flterm-ios-recover`: flterm 0.0.5 +
/// libghostty 0.0.12 na mesma ref) o Ghostty voltou a rodar no iOS, então o
/// gate saiu.
///
/// 2026-09-09: o gate foi reintroduzido por um dia pra comparar os motores no
/// touch e removido de novo — o xterm no mobile ficou pior que o Ghostty.
TerminalEngine resolveTerminalEngine(TerminalEngine engine) => engine;

CockpitTerminalController createTerminalController(
  TerminalEngine engine, {
  xterm.TerminalInputHandler? xtermInputHandler,
}) => switch (resolveTerminalEngine(engine)) {
  TerminalEngine.ghostty => GhosttyTerminalController(),
  TerminalEngine.xterm => XtermTerminalController(
    inputHandler: xtermInputHandler,
  ),
};
