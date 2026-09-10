import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum LinuxPerfMetric { frame, eventLoop, memory, pty, processScan, gitRefresh }

enum LinuxPerfField {
  durationUs,
  buildUs,
  rasterUs,
  delayUs,
  rssBytes,
  pending,
  sources,
  sessions,
  active,
  queued,
  failed,
}

/// Telemetria local opt-in estritamente numérica. A API aceita somente enums
/// fechados, portanto callers não conseguem inserir comandos, paths ou output.
final class LinuxPerformanceDiagnostics {
  LinuxPerformanceDiagnostics({
    bool? enabled,
    this.maxEntries = 128,
    this.minSampleInterval = const Duration(seconds: 1),
    void Function(String line)? sink,
  }) : enabled =
           enabled ??
           (Platform.isLinux &&
               Platform.environment['COCKPIT_PERF_DIAGNOSTICS'] == '1'),
       _sink = sink ?? _defaultSink;

  static final LinuxPerformanceDiagnostics instance =
      LinuxPerformanceDiagnostics();

  final bool enabled;
  final int maxEntries;
  final Duration minSampleInterval;
  final void Function(String line) _sink;
  final List<Map<String, Object>> _entries = [];
  final Map<LinuxPerfMetric, DateTime> _lastSample = {};
  Timer? _watchdog;
  Timer? _flushTimer;
  DateTime? _expectedWatchdog;
  bool _started = false;

  @visibleForTesting
  List<Map<String, Object>> get entries => List.unmodifiable(_entries);

  void start() {
    if (!enabled || _started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _expectedWatchdog = DateTime.now().add(const Duration(seconds: 1));
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final expected = _expectedWatchdog!;
      final delay = now.difference(expected);
      _expectedWatchdog = now.add(const Duration(seconds: 1));
      record(LinuxPerfMetric.eventLoop, {
        LinuxPerfField.delayUs: delay.isNegative ? 0 : delay.inMicroseconds,
      });
      record(LinuxPerfMetric.memory, {
        LinuxPerfField.rssBytes: ProcessInfo.currentRss,
      });
    });
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  void record(
    LinuxPerfMetric metric,
    Map<LinuxPerfField, num> values, {
    bool force = false,
  }) {
    if (!enabled || values.isEmpty) return;
    final now = DateTime.now();
    final previous = _lastSample[metric];
    if (!force &&
        previous != null &&
        now.difference(previous) < minSampleInterval) {
      return;
    }
    _lastSample[metric] = now;
    if (_entries.length == maxEntries) _entries.removeAt(0);
    _entries.add({
      'at': now.toUtc().toIso8601String(),
      'metric': metric.name,
      for (final value in values.entries) value.key.name: value.value,
    });
  }

  String snapshotJson() => jsonEncode(_entries);

  void flush() {
    if (!enabled || _entries.isEmpty) return;
    _sink(snapshotJson());
    _entries.clear();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final durationUs = timing.totalSpan.inMicroseconds;
      record(LinuxPerfMetric.frame, {
        LinuxPerfField.buildUs: timing.buildDuration.inMicroseconds,
        LinuxPerfField.rasterUs: timing.rasterDuration.inMicroseconds,
        LinuxPerfField.durationUs: durationUs,
      }, force: durationUs >= 50000);
    }
  }

  static void _defaultSink(String line) =>
      DiagnosticsLog.instance.log('linux-perf', line);

  void dispose() {
    if (_started) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    }
    _watchdog?.cancel();
    _flushTimer?.cancel();
    flush();
    _started = false;
  }
}
