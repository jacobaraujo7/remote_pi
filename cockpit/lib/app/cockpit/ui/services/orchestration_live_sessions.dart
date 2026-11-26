import 'package:flutter/foundation.dart';

/// Rebinds session listeners when the workspace adds/removes terminals.
/// A merge built from a one-time session list misses later sessions.
class OrchestrationLiveSessions extends ChangeNotifier {
  OrchestrationLiveSessions({
    required this.sources,
    required this.sessions,
    this.schedule,
    this.sessionState,
  }) {
    for (final source in sources) {
      source.addListener(_sourceChanged);
    }
    _rebind();
  }
  final List<Listenable> sources;
  final Iterable<Listenable> Function() sessions;
  final void Function(VoidCallback callback)? schedule;
  final List<Object?> Function()? sessionState;
  List<Object?>? _lastSessionState;
  bool _queued = false;
  bool _disposed = false;
  Set<Listenable> _bound = {};
  void _notify() {
    if (_disposed) return;
    final defer = schedule;
    if (defer == null) {
      notifyListeners();
      return;
    }
    if (_queued) return;
    _queued = true;
    defer(() {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _rebind() {
    final next = sessions().toSet();
    for (final old in _bound.difference(next)) {
      old.removeListener(_sessionChanged);
    }
    for (final added in next.difference(_bound)) {
      added.addListener(_sessionChanged);
    }
    _bound = next;
    _lastSessionState = sessionState?.call();
  }

  void _sourceChanged() {
    _rebind();
    _notify();
  }

  void _sessionChanged() {
    final next = sessionState?.call();
    if (next != null && listEquals(next, _lastSessionState)) return;
    _lastSessionState = next;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final source in sources) {
      source.removeListener(_sourceChanged);
    }
    for (final session in _bound) {
      session.removeListener(_sessionChanged);
    }
    _bound.clear();
    super.dispose();
  }
}
