import 'dart:async';

import 'package:flutter/services.dart';
import '../data/diagnostics/diagnostics_log.dart';

/// The outcome of one request; supersession is not a platform failure.
enum TextClipboardResult { copied, failed, superseded }

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
          Completer<TextClipboardResult> result,
        })
      >[];
  bool _writing = false;
  int _generation = 0;

  // pasteboard 0.4.0's IO implementation delegates writeText to this exact
  // Flutter call on Windows, Linux and macOS. Await it here: Pasteboard.writeText
  // returns void and discards the Future, hiding asynchronous platform errors.
  // Keep terminal text reads and image/file handling on their existing backend.
  static Future<void> _writePlatform(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// Only [TextClipboardResult.copied] permits a copied-success indicator.
  /// A completed platform write stays copied if another request arrived while
  /// it was in flight; serialization still writes the newer text afterwards.
  Future<TextClipboardResult> write(String text, {required String operation}) {
    final generation = ++_generation;
    final result = Completer<TextClipboardResult>();
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

  Future<TextClipboardResult> _write(
    String text,
    String operation,
    int generation,
  ) async {
    const waits = [Duration(milliseconds: 50), Duration(milliseconds: 150)];
    for (var attempt = 0; attempt < 3; attempt++) {
      if (generation != _generation) return TextClipboardResult.superseded;
      try {
        await _writer(text);
        return TextClipboardResult.copied;
      } catch (error) {
        if (generation != _generation) return TextClipboardResult.superseded;
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
        return TextClipboardResult.failed;
      }
    }
    return TextClipboardResult.failed;
  }
}
