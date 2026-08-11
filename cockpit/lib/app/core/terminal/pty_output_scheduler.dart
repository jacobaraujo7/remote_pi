import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Orça o trabalho de todos os PTYs do app de forma global e justa.
///
/// Um cap por terminal não basta: com N terminais, N callbacks por frame ainda
/// podem consumir o isolate inteiro. Este scheduler usa uma fila round-robin e
/// limita o conjunto de todos os terminais por code units UTF-16 *e* por tempo
/// de CPU. Se a fila não couber no frame atual, o restante fica para o próximo
/// e o backpressure do PTY desacelera os produtores sem perder output.
final class PtyOutputScheduler {
  PtyOutputScheduler({
    this.maxCharsPerFrame = 64 * 1024,
    this.maxSliceChars = 4 * 1024,
    this.maxWorkPerFrame = const Duration(milliseconds: 4),
    void Function(VoidCallback drain)? scheduleFrame,
    int Function()? clockMicros,
  }) : assert(maxCharsPerFrame > 0),
       assert(maxSliceChars > 0),
       assert(maxWorkPerFrame > Duration.zero),
       _scheduleFrame = scheduleFrame ?? _scheduleOnNextFrame,
       _clockMicros = clockMicros ?? _monotonicMicros;

  /// Instância usada por terminais interativos e runners de task.
  static final PtyOutputScheduler shared = PtyOutputScheduler();

  /// Limite agregado de texto interpretado por frame, entre todos os PTYs.
  final int maxCharsPerFrame;

  /// Maior chamada individual ao parser VT. Limita o pior bloqueio indivisível.
  final int maxSliceChars;

  /// Parcela máxima do frame dedicada a parse/model/render invalidation.
  final Duration maxWorkPerFrame;

  final void Function(VoidCallback drain) _scheduleFrame;
  final int Function() _clockMicros;
  final ListQueue<PtyOutputCoalescer> _ready = ListQueue();
  bool _frameScheduled = false;
  bool _draining = false;
  int _pendingChars = 0;

  /// Output ainda aguardando parse, somado entre todas as fontes.
  @visibleForTesting
  int get pendingChars => _pendingChars;

  /// Quantidade de fontes prontas na fila round-robin.
  @visibleForTesting
  int get readySources => _ready.length;

  static final Stopwatch _clock = Stopwatch()..start();

  static int _monotonicMicros() => _clock.elapsedMicroseconds;

  static void _scheduleOnNextFrame(VoidCallback drain) {
    SchedulerBinding.instance.scheduleFrameCallback((_) => drain());
    SchedulerBinding.instance.scheduleFrame();
  }

  void _added(PtyOutputCoalescer source, int chars) {
    _pendingChars += chars;
    _enqueue(source);
  }

  void _removed(int chars) {
    _pendingChars -= chars;
    assert(_pendingChars >= 0);
  }

  void _enqueue(PtyOutputCoalescer source) {
    if (source._disposed || source._queued || !source._hasPending) return;
    source._queued = true;
    _ready.addLast(source);
    if (!_draining) _ensureFrame();
  }

  void _remove(PtyOutputCoalescer source) {
    if (!source._queued) return;
    _ready.remove(source);
    source._queued = false;
  }

  void _ensureFrame() {
    if (_frameScheduled || _ready.isEmpty) return;
    _frameScheduled = true;
    _scheduleFrame(_drainFrame);
  }

  void _drainFrame() {
    _frameScheduled = false;
    if (_ready.isEmpty) return;

    _draining = true;
    final startedAt = _clockMicros();
    final timeBudget = maxWorkPerFrame.inMicroseconds;
    var charBudget = maxCharsPerFrame;

    try {
      while (_ready.isNotEmpty && charBudget > 0) {
        final source = _ready.removeFirst();
        source._queued = false;
        if (source._disposed || !source._hasPending) continue;

        final processed = source._flushSlice(
          math.min(maxSliceChars, charBudget),
        );
        charBudget -= processed;

        // Reinsere no fim: mesmo uma fonte muito ruidosa não monopoliza o
        // frame enquanto outra aguarda.
        if (source._hasPending) _enqueue(source);

        // Sempre deixa ao menos um slice progredir. A granularidade do slice
        // limita o pequeno overshoot inevitável de uma chamada indivisível.
        if (_clockMicros() - startedAt >= timeBudget) break;
      }
    } finally {
      _draining = false;
      _ensureFrame();
    }
  }
}

/// Buffer limitado de uma fonte de output, consumido pelo scheduler global.
///
/// O PTY nativo entrega no máximo um chunk por acknowledgement. Enquanto o
/// buffer passa de [maxPendingChars], o acknowledgement fica suspenso; quando
/// cai abaixo de [resumePendingChars], um ack religa o produtor. Nenhum texto é
/// descartado durante a vida normal da fonte.
final class PtyOutputCoalescer {
  PtyOutputCoalescer({
    required this.onFlush,
    required this.onAcknowledge,
    this.maxPendingChars = 16 * 1024,
    int? resumePendingChars,
    PtyOutputScheduler? scheduler,
  }) : assert(maxPendingChars > 0),
       resumePendingChars = resumePendingChars ?? maxPendingChars ~/ 2,
       _scheduler = scheduler ?? PtyOutputScheduler.shared {
    if (this.resumePendingChars < 0 ||
        this.resumePendingChars >= maxPendingChars) {
      throw ArgumentError.value(
        this.resumePendingChars,
        'resumePendingChars',
        'must be >= 0 and < maxPendingChars',
      );
    }
  }

  final int maxPendingChars;
  final int resumePendingChars;
  final ValueChanged<String> onFlush;
  final VoidCallback onAcknowledge;
  final PtyOutputScheduler _scheduler;

  final ListQueue<String> _pending = ListQueue();
  int _headOffset = 0;
  int _pendingLength = 0;
  bool _ackPaused = false;
  bool _queued = false;
  bool _disposed = false;
  Completer<void>? _drainedCompleter;

  int get pendingLength => _pendingLength;
  bool get ackPaused => _ackPaused;
  bool get _hasPending => _pendingLength > 0;

  /// Completa quando tudo que já entrou foi entregue ao consumidor.
  Future<void> get drained {
    if (!_hasPending) return Future<void>.value();
    return (_drainedCompleter ??= Completer<void>()).future;
  }

  void add(String data) {
    if (_disposed || data.isEmpty) return;
    _pending.addLast(data);
    _pendingLength += data.length;
    _scheduler._added(this, data.length);

    if (!_ackPaused && _pendingLength < maxPendingChars) {
      onAcknowledge();
    } else if (_pendingLength >= maxPendingChars) {
      _ackPaused = true;
    }
  }

  int _flushSlice(int maxChars) {
    if (_disposed || !_hasPending || maxChars <= 0) return 0;
    final batch = _take(maxChars);
    final processed = batch.length;
    _scheduler._removed(processed);

    try {
      onFlush(batch);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'cockpit terminal output scheduler',
          context: ErrorDescription('while consuming PTY output'),
        ),
      );
      dispose();
      return processed;
    }

    if (_ackPaused && _pendingLength <= resumePendingChars) {
      _ackPaused = false;
      onAcknowledge();
    }
    if (!_hasPending) {
      final completer = _drainedCompleter;
      _drainedCompleter = null;
      if (completer != null && !completer.isCompleted) completer.complete();
    }
    return processed;
  }

  String _take(int limit) {
    if (_pendingLength <= limit) {
      final out = StringBuffer();
      var first = true;
      for (final chunk in _pending) {
        out.write(first ? chunk.substring(_headOffset) : chunk);
        first = false;
      }
      final result = out.toString();
      _pending.clear();
      _headOffset = 0;
      _pendingLength = 0;
      return result;
    }

    final out = StringBuffer();
    var remaining = limit;
    while (remaining > 0 && _pending.isNotEmpty) {
      final head = _pending.first;
      final available = head.length - _headOffset;
      var take = math.min(available, remaining);

      // String.length mede UTF-16. Não corte entre os dois code units de um
      // surrogate pair; parsers incrementais toleram escape ANSI partido, mas
      // um code point Unicode partido corromperia o texto.
      final boundary = _headOffset + take;
      if (boundary < head.length &&
          take > 0 &&
          _isHighSurrogate(head.codeUnitAt(boundary - 1)) &&
          _isLowSurrogate(head.codeUnitAt(boundary))) {
        take--;
      }
      if (take == 0) {
        // O limite caiu exatamente entre um par. O slice ultrapassa em um code
        // unit para manter o caractere íntegro; o teto temporal continua sendo
        // protegido pela granularidade pequena de [maxSliceChars].
        take = math.min(2, available);
      }

      out.write(head.substring(_headOffset, _headOffset + take));
      _headOffset += take;
      _pendingLength -= take;
      remaining -= take;
      if (_headOffset == head.length) {
        _pending.removeFirst();
        _headOffset = 0;
      }
    }
    return out.toString();
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  static bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  /// Para de consumir e descarta somente o que pertencia à fonte encerrada.
  ///
  /// Fechar uma aba ruidosa nunca faz parse síncrono de dezenas de KB no gesto
  /// de fechar. Se o produtor estava pausado, um ack final libera a thread
  /// nativa para observar o EOF depois do kill.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduler._remove(this);
    if (_pendingLength > 0) _scheduler._removed(_pendingLength);
    _pending.clear();
    _pendingLength = 0;
    _headOffset = 0;
    if (_ackPaused) onAcknowledge();
    _ackPaused = false;
    final completer = _drainedCompleter;
    _drainedCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}
