import 'dart:async';

import 'package:flutter/services.dart';
import '../data/diagnostics/diagnostics_log.dart';

/// App-wide text writes. Reads and binary clipboard formats stay untouched.
/// Like shell_command, this core utility owns the platform boundary and exposes
/// injectable IO so ordering and failure recovery can be tested deterministically.
class TextClipboardService {
  TextClipboardService({
    Future<void> Function(String)? writer,
    Future<void> Function(Duration)? delay,
  }) : _writer = writer ?? _writePlatform,
       _delay = delay ?? Future<void>.delayed;

  static final instance = TextClipboardService();
  final Future<void> Function(String) _writer;
  final Future<void> Function(Duration) _delay;
  final _failures = StreamController<void>.broadcast();
  Stream<void> get failures => _failures.stream;
  final _queue =
      <
        ({
          String text,
          String operation,
          int generation,
          Completer<bool> result,
        })
      >[];
  bool _writing = false;
  int _generation = 0;

  static Future<void> _writePlatform(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// False means failed or superseded; callers must not announce success.
  Future<bool> write(String text, {required String operation}) {
    final generation = ++_generation;
    final result = Completer<bool>();
    _queue.add((
      text: text,
      operation: operation,
      generation: generation,
      result: result,
    ));
    if (!_writing) unawaited(_drain());
    return result.future;
  }

  Future<void> _drain() async {
    _writing = true;
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      final result = await _write(next.text, next.operation, next.generation);
      next.result.complete(result);
    }
    _writing = false;
  }

  Future<bool> _write(String text, String operation, int generation) async {
    const waits = [Duration(milliseconds: 50), Duration(milliseconds: 150)];
    for (var attempt = 0; attempt < 3; attempt++) {
      if (generation != _generation) return false;
      try {
        await _writer(text);
        return generation == _generation;
      } catch (error) {
        if (generation != _generation) return false;
        final retryable =
            error is PlatformException &&
            error.code == 'Clipboard error' &&
            error.message == 'Unable to open clipboard';
        if (retryable && attempt < waits.length) {
          await _delay(waits[attempt]);
          continue;
        }
        // Do not log text, exception messages/details, or user-derived paths.
        // Operation is a fixed identifier supplied by our call sites.
        final kind = error is PlatformException ? 'platform' : 'unexpected';
        DiagnosticsLog.instance.warn(
          'clipboard',
          'text write failed: operation=$operation kind=$kind attempts=${attempt + 1}',
        );
        _failures.add(null);
        return false;
      }
    }
    return false;
  }
}
