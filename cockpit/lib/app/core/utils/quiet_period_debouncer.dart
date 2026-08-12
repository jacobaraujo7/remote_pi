import 'dart:async';

/// Debounce de quietude que mantém no máximo um [Timer] ativo.
///
/// Cancelar e recriar um timer a cada chunk é barato para eventos humanos, mas
/// vira churn relevante quando dezenas de terminais entregam batches a cada
/// frame. Aqui cada [trigger] só atualiza o instante da última atividade. O
/// timer existente acorda, calcula o tempo restante e se rearma apenas quando
/// necessário.
final class QuietPeriodDebouncer {
  QuietPeriodDebouncer({
    required this.delay,
    required this.onQuiet,
    int Function()? clockMicros,
  }) : assert(delay > Duration.zero),
       _clockMicros = clockMicros ?? _monotonicMicros;

  final Duration delay;
  final void Function() onQuiet;

  final int Function() _clockMicros;
  Timer? _timer;
  int _lastTriggerMicros = 0;
  bool _disposed = false;

  static final Stopwatch _clock = Stopwatch()..start();

  static int _monotonicMicros() => _clock.elapsedMicroseconds;

  bool get isPending => _timer != null;

  void trigger() {
    if (_disposed) return;
    _lastTriggerMicros = _clockMicros();
    _timer ??= Timer(delay, _check);
  }

  void _check() {
    _timer = null;
    if (_disposed) return;
    final quietMicros = _clockMicros() - _lastTriggerMicros;
    final remainingMicros = delay.inMicroseconds - quietMicros;
    if (remainingMicros > 0) {
      _timer = Timer(Duration(microseconds: remainingMicros), _check);
      return;
    }
    onQuiet();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
  }
}
