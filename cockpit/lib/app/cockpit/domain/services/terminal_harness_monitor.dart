import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/services/process_tree_resolver.dart';

class SessionAnchor {
  final String sessionId;
  final int? Function() rootPid;
  final String? wslDistro;
  final void Function(HarnessKind? newHarness) onHarnessChanged;

  SessionAnchor({
    required this.sessionId,
    required this.rootPid,
    this.wslDistro,
    required this.onHarnessChanged,
  });
}

class TerminalHarnessMonitor {
  final ProcessTreeProvider provider;
  final Map<String, ProcessTreeProvider>? wslProvidersByDistro;
  final ProcessTreeProvider Function(String distro)? wslProviderForDistro;
  final Duration pollInterval;

  Timer? _timer;
  bool _inFlight = false;
  bool _pendingPoll = false;
  final Map<String, SessionAnchor> _anchors = {};
  final Map<String, HarnessKind?> _lastKnownHarness = {};
  final Map<String, ProcessTreeProvider> _wslProviderCache = {};

  TerminalHarnessMonitor({
    required this.provider,
    this.wslProvidersByDistro,
    this.wslProviderForDistro,
    // Baseline safety net for silent exits / nested tools. Interactive
    // launches are kicked immediately from TerminalSession (Enter/output).
    this.pollInterval = const Duration(milliseconds: 250),
  });

  bool get isRunning => _timer != null;
  int get registeredCount => _anchors.length;

  void registerSession({
    required String sessionId,
    required int? Function() rootPid,
    String? wslDistro,
    required void Function(HarnessKind? newHarness) onHarnessChanged,
  }) {
    _anchors[sessionId] = SessionAnchor(
      sessionId: sessionId,
      rootPid: rootPid,
      wslDistro: wslDistro,
      onHarnessChanged: onHarnessChanged,
    );

    if (_timer == null && _anchors.isNotEmpty) {
      _startTimer();
    }
    // Immediate poll on registration (and whenever a session is (re)bound).
    requestPoll();
  }

  void unregisterSession(String sessionId) {
    _anchors.remove(sessionId);
    _lastKnownHarness.remove(sessionId);

    if (_anchors.isEmpty) {
      _stopTimer();
      _pendingPoll = false;
    }
  }

  /// Ask for a poll as soon as possible. Coalesces with an in-flight poll.
  void requestPoll() {
    if (_anchors.isEmpty) return;
    if (_inFlight) {
      _pendingPoll = true;
      return;
    }
    unawaited(poll());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => requestPoll());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poll() async {
    if (_inFlight || _anchors.isEmpty) {
      if (_inFlight) _pendingPoll = true;
      return;
    }
    _inFlight = true;
    _pendingPoll = false;

    try {
      // Group sessions into native host vs WSL by distro
      final nativeAnchors = <SessionAnchor>[];
      final wslAnchorsByDistro = <String, List<SessionAnchor>>{};

      for (final anchor in _anchors.values) {
        if (anchor.wslDistro != null && anchor.wslDistro!.isNotEmpty) {
          wslAnchorsByDistro
              .putIfAbsent(anchor.wslDistro!, () => [])
              .add(anchor);
        } else {
          nativeAnchors.add(anchor);
        }
      }

      // Collect native process snapshots
      if (nativeAnchors.isNotEmpty) {
        final nativeRootPids =
            nativeAnchors.map((a) => a.rootPid()).whereType<int>().toList();
        final snapshots = await provider.getProcessSnapshots(
          rootPids: nativeRootPids,
        );

        for (final anchor in nativeAnchors) {
          _evaluateAnchor(anchor, snapshots);
        }
      }

      // Collect WSL process snapshots per distro
      for (final entry in wslAnchorsByDistro.entries) {
        final distro = entry.key;
        final anchors = entry.value;
        final distroProvider = _resolveWslProvider(distro);
        final rootPids =
            anchors.map((a) => a.rootPid()).whereType<int>().toList();
        final snapshots = await distroProvider.getProcessSnapshots(
          rootPids: rootPids,
        );

        for (final anchor in anchors) {
          _evaluateAnchor(anchor, snapshots);
        }
      }
    } catch (_) {
      // Fallback silently on error
    } finally {
      _inFlight = false;
      if (_pendingPoll && _anchors.isNotEmpty) {
        _pendingPoll = false;
        scheduleMicrotask(requestPoll);
      }
    }
  }

  ProcessTreeProvider _resolveWslProvider(String distro) {
    final cached = _wslProviderCache[distro];
    if (cached != null) return cached;

    final resolved = wslProvidersByDistro?[distro] ??
        wslProviderForDistro?.call(distro) ??
        provider;
    _wslProviderCache[distro] = resolved;
    return resolved;
  }

  void _evaluateAnchor(
    SessionAnchor anchor,
    List<ProcessSnapshot> snapshots,
  ) {
    final rootPid = anchor.rootPid();
    if (rootPid == null) {
      _updateHarness(anchor, null);
      return;
    }

    final harness = ProcessTreeResolver.resolve(
      rootPid: rootPid,
      snapshots: snapshots,
    );

    _updateHarness(anchor, harness);
  }

  void _updateHarness(SessionAnchor anchor, HarnessKind? newHarness) {
    final previous = _lastKnownHarness[anchor.sessionId];
    if (previous != newHarness) {
      _lastKnownHarness[anchor.sessionId] = newHarness;
      anchor.onHarnessChanged(newHarness);
    }
  }

  void dispose() {
    _stopTimer();
    _anchors.clear();
    _lastKnownHarness.clear();
    _wslProviderCache.clear();
    _pendingPoll = false;
  }
}
