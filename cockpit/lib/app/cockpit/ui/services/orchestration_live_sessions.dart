import 'package:flutter/foundation.dart';

/// Rebinds session listeners when the workspace adds/removes terminals.
/// A merge built from a one-time session list misses later sessions.
class OrchestrationLiveSessions extends ChangeNotifier {
  OrchestrationLiveSessions({required this.sources, required this.sessions}) {
    for (final source in sources) {
      source.addListener(_sourceChanged);
    }
    _rebind();
  }
  final List<Listenable> sources;
  final Iterable<Listenable> Function() sessions;
  Set<Listenable> _bound = {};
  void _rebind() {
    final next = sessions().toSet();
    for (final old in _bound.difference(next)) {
      old.removeListener(_sessionChanged);
    }
    for (final added in next.difference(_bound)) {
      added.addListener(_sessionChanged);
    }
    _bound = next;
  }

  void _sourceChanged() {
    _rebind();
    notifyListeners();
  }

  void _sessionChanged() => notifyListeners();
  @override
  void dispose() {
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
