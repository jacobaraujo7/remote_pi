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
  void dispose() {}
}

final class GhosttyTerminalController implements CockpitTerminalController {
  GhosttyTerminalController()
    : controller = ghost.TerminalController(
        config: const ghost.TerminalConfig(
          cols: 80,
          rows: 25,
          scrollbackLimit: 10 * 1024 * 1024,
        ),
      ) {
    controller.onOutput = (data) => onOutput?.call(data);
    controller.onResize = (columns, rows) {
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
    };
    controller.onTitleChanged = () => onTitleChanged?.call(controller.title);
  }

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
  List<String>? _pendingRestore;

  @override
  void write(String data) {
    if (_deferWritesUntilPostFrame ||
        (!_hasInitialResize && _pendingRestore != null)) {
      (_pendingRestore ??= <String>[]).add(data);
      return;
    }
    _writeNow(data);
  }

  @override
  void restore(String data) {
    if (_hasInitialResize && !_deferWritesUntilPostFrame) {
      _writeNow(data);
      return;
    }
    (_pendingRestore ??= <String>[]).add(data);
  }

  void _flushPendingWrites() {
    if (_disposed) return;
    _deferWritesUntilPostFrame = false;
    final pending = _pendingRestore;
    _pendingRestore = null;
    if (pending == null) return;
    for (final data in pending) {
      _writeNow(data);
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
  void dispose() {
    _disposed = true;
    controller.dispose();
  }
}

CockpitTerminalController createTerminalController(
  TerminalEngine engine, {
  xterm.TerminalInputHandler? xtermInputHandler,
}) => switch (engine) {
  TerminalEngine.ghostty => GhosttyTerminalController(),
  TerminalEngine.xterm => XtermTerminalController(
    inputHandler: xtermInputHandler,
  ),
};
