import 'dart:async';

/// Serializa operações por chave. Uma rajada durante a execução corrente é
/// reduzida ao callback mais recente e produz no máximo um rerun.
class CoalescingSingleFlight<K> {
  final Map<K, _Flight> _flights = <K, _Flight>{};

  /// Wait for discovery already running, including keys added while waiting.
  /// This observes flights without requesting another operation or rerun.
  Future<void> settle() async {
    while (_flights.isNotEmpty) {
      await Future.wait(_flights.values.map((flight) => flight.done.future));
    }
  }

  Future<void> run(K key, Future<void> Function() operation) {
    final current = _flights[key];
    if (current != null) {
      current
        ..rerunRequested = true
        ..nextOperation = operation;
      return current.done.future;
    }

    final flight = _Flight(operation);
    _flights[key] = flight;
    unawaited(_execute(key, flight));
    return flight.done.future;
  }

  Future<void> _execute(K key, _Flight flight) async {
    try {
      await flight.nextOperation();
      if (flight.rerunRequested) {
        flight.rerunRequested = false;
        final rerun = flight.nextOperation;
        await rerun();
      }
      flight.done.complete();
    } on Object catch (error, stack) {
      flight.done.completeError(error, stack);
    } finally {
      _flights.remove(key);
    }
  }
}

class _Flight {
  _Flight(this.nextOperation);

  final Completer<void> done = Completer<void>();
  Future<void> Function() nextOperation;
  bool rerunRequested = false;
}
