import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/services/process_tree_resolver.dart';
import 'package:cockpit/app/core/data/diagnostics/performance_diagnostics.dart';

class SessionAnchor {
  final String sessionId;
  final int? Function() rootPid;
  final String? wslDistro;
  final void Function(HarnessKind? newHarness) onHarnessChanged;
  bool visible;
  DateTime lastActivity;

  SessionAnchor({
    required this.sessionId,
    required this.rootPid,
    this.wslDistro,
    required this.onHarnessChanged,
    this.visible = false,
    DateTime? lastActivity,
  }) : lastActivity = lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class TerminalHarnessMonitor {
  final ProcessTreeProvider provider;
  final Map<String, ProcessTreeProvider>? wslProvidersByDistro;
  final ProcessTreeProvider Function(String distro)? wslProviderForDistro;
  final Duration pollInterval;
  final Duration idlePollInterval;
  final Duration inactivePollInterval;
  final Duration activityPollInterval;
  final Duration urgentPollInterval;
  final Duration pendingPollDelay;
  final bool Function()? windowIsActive;

  Timer? _timer;
  bool _inFlight = false;
  bool _pendingPoll = false;
  bool _pendingUrgent = false;
  DateTime? _lastPollStartedAt;
  DateTime? _lastUrgentPollStartedAt;
  DateTime? _lastPollFinishedAt;
  final Map<String, SessionAnchor> _anchors = {};
  final Map<String, HarnessKind?> _lastKnownHarness = {};
  final Map<String, ProcessTreeProvider> _wslProviderCache = {};

  TerminalHarnessMonitor({
    required this.provider,
    this.wslProvidersByDistro,
    this.wslProviderForDistro,
    // Baseline safety net for silent exits / nested tools. Interactive
    // launches are kicked immediately from TerminalSession (Enter/output).
    Duration? pollInterval,
    Duration? idlePollInterval,
    Duration? inactivePollInterval,
    Duration? activityPollInterval,
    Duration? activityPollCooldown,
    this.urgentPollInterval = const Duration(milliseconds: 150),
    this.pendingPollDelay = const Duration(milliseconds: 40),
    this.windowIsActive,
  }) : activityPollInterval =
           activityPollInterval ??
           activityPollCooldown ??
           const Duration(seconds: 1),
       pollInterval =
           pollInterval ??
           (Platform.isWindows
               ? const Duration(seconds: 8)
               : const Duration(seconds: 2)),
       idlePollInterval =
           idlePollInterval ??
           (Platform.isWindows
               ? const Duration(seconds: 20)
               : const Duration(seconds: 5)),
       inactivePollInterval =
           inactivePollInterval ??
           (Platform.isWindows
               ? const Duration(seconds: 30)
               : const Duration(seconds: 10));

  bool get isRunning => _anchors.isNotEmpty && (_timer != null || _inFlight);
  Duration get activityPollCooldown => activityPollInterval;
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
      _scheduleNextPoll();
    }
    // Immediate poll on registration (and whenever a session is (re)bound).
    requestPoll(urgent: true);
  }

  void unregisterSession(String sessionId) {
    _anchors.remove(sessionId);
    _lastKnownHarness.remove(sessionId);

    if (_anchors.isEmpty) {
      _stopTimer();
      _pendingPoll = false;
      _pendingUrgent = false;
    }
  }

  /// Request a global scan. Output/title activity shares a one-second budget
  /// across sessions; submitted commands and registration get a fast scan.
  void requestPoll({String? sessionId, bool urgent = false}) {
    if (_anchors.isEmpty) return;
    if (sessionId != null) {
      _anchors[sessionId]?.lastActivity = DateTime.now();
    }
    _pendingPoll = true;
    _pendingUrgent |= urgent;
    if (_inFlight) {
      return;
    }
    _scheduleRequestedPoll();
  }

  void _scheduleRequestedPoll() {
    if (!_pendingPoll || _anchors.isEmpty || _inFlight) return;
    final now = DateTime.now();
    final last = _pendingUrgent ? _lastUrgentPollStartedAt : _lastPollStartedAt;
    final interval = _pendingUrgent ? urgentPollInterval : activityPollInterval;
    var due = last?.add(interval) ?? now;
    final finished = _lastPollFinishedAt;
    if (finished != null && due.isBefore(finished.add(pendingPollDelay))) {
      due = finished.add(pendingPollDelay);
    }
    _timer?.cancel();
    final delay = due.difference(now);
    if (delay <= Duration.zero) {
      _timer = null;
      unawaited(poll());
    } else {
      _timer = Timer(delay, () {
        _timer = null;
        unawaited(poll());
      });
    }
  }

  /// Informa se uma sessão tem superfície visível. A sessão e seu PTY
  /// continuam vivos; isto governa somente a frequência do safety poll.
  void setSessionVisible(String sessionId, bool visible) {
    final anchor = _anchors[sessionId];
    if (anchor == null || anchor.visible == visible) return;
    anchor.visible = visible;
    // Switching tabs or workspaces changes visibility, not the process tree.
    // On Windows an eager poll starts a full CIM scan for every switch.
    // Terminal input/output still calls requestPoll for real activity.
    if (visible) anchor.lastActivity = DateTime.now();
    if (!_inFlight && !_pendingPoll) _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    _timer?.cancel();
    if (_anchors.isEmpty) {
      _timer = null;
      return;
    }
    final windowActive = windowIsActive?.call() ?? true;
    final hasVisible = _anchors.values.any((anchor) => anchor.visible);
    final hasRecentActivity = _anchors.values.any(
      (anchor) =>
          DateTime.now().difference(anchor.lastActivity) < idlePollInterval,
    );
    final delay = !windowActive
        ? inactivePollInterval
        : (hasVisible || hasRecentActivity ? pollInterval : idlePollInterval);
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(poll());
    });
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
    _timer?.cancel();
    _timer = null;
    _inFlight = true;
    _lastPollStartedAt = DateTime.now();
    if (_pendingUrgent) _lastUrgentPollStartedAt = _lastPollStartedAt;
    _pendingPoll = false;
    _pendingUrgent = false;
    final stopwatch = Stopwatch()..start();

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
        final nativeRootPids = nativeAnchors
            .map((a) => a.rootPid())
            .whereType<int>()
            .toList();
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
        final rootPids = anchors
            .map((a) => a.rootPid())
            .whereType<int>()
            .toList();
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
      PerformanceDiagnostics.instance.record(PerfMetric.processScan, {
        PerfField.durationUs: stopwatch.elapsedMicroseconds,
        PerfField.sessions: _anchors.length,
      });
      _inFlight = false;
      _lastPollFinishedAt = DateTime.now();
      if (_pendingPoll && _anchors.isNotEmpty) {
        _scheduleRequestedPoll();
      } else {
        _scheduleNextPoll();
      }
    }
  }

  ProcessTreeProvider _resolveWslProvider(String distro) {
    final cached = _wslProviderCache[distro];
    if (cached != null) return cached;

    final resolved =
        wslProvidersByDistro?[distro] ??
        wslProviderForDistro?.call(distro) ??
        provider;
    _wslProviderCache[distro] = resolved;
    return resolved;
  }

  void _evaluateAnchor(SessionAnchor anchor, List<ProcessSnapshot> snapshots) {
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
    _pendingUrgent = false;
  }
}
