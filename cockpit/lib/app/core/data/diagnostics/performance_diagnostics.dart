import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Métricas de performance do app (plano 68). Nomes fixos: a API só aceita
/// enums fechados, então nenhum caller consegue inserir comando, path ou
/// output aqui. Só números.
enum PerfMetric {
  /// Resumo por janela de flush: `frames`, `jankFrames` (> 16,7 ms),
  /// `p95Us`, `maxUs`.
  frame,

  /// Um frame individual acima de 50 ms (`durationUs`, `buildUs`, `rasterUs`).
  slowFrame,
  eventLoop,
  memory,
  pty,
  processScan,
  gitRefresh,

  /// `start()` → workspace pronto (`durationUs`).
  boot,

  /// Restauração de layout de um workspace (`durationUs`, `tabs`).
  restore,

  /// Troca de workspace → próximo frame pintado (`durationUs`).
  workspaceSwitch,

  /// Troca de aba → próximo frame pintado (`durationUs`).
  tabSwitch,

  /// `Process.start` → processo vivo (`durationUs`, `failed`).
  spawn,
}

enum PerfField {
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
  frames,
  jankFrames,
  p95Us,
  maxUs,
  tabs,
}

/// Amostra pronta pro sink: nome da métrica + campos numéricos.
typedef PerfSink = void Function(String metric, Map<String, num> fields);

/// Telemetria de performance **opt-in de desenvolvedor**: liga com
/// `COCKPIT_PERF=1` (alias legado `COCKPIT_PERF_DIAGNOSTICS=1`) em qualquer
/// SO. Desligada em produção por decisão (plano 68): sem envio para fora, o
/// número só serve a quem consegue lê-lo, e quem lê é o dono na própria
/// máquina, medindo o `.dmg` instalado.
///
/// Custo quando ligada: um callback de timings por frame (soma e compara),
/// dois timers de 1 s, e um flush a cada 30 s fora do frame. Tudo agregado em
/// memória antes de sair: frames viram UM resumo por janela.
final class PerformanceDiagnostics {
  PerformanceDiagnostics({
    bool? enabled,
    this.maxEntries = 256,
    this.minSampleInterval = const Duration(seconds: 1),
    PerfSink? sink,
    this.flushEvery = const Duration(seconds: 30),
  }) : enabled = enabled ?? _envEnabled(),
       sink = sink ?? _defaultSink;

  static final PerformanceDiagnostics instance = PerformanceDiagnostics();

  /// `COCKPIT_PERF=1` (ou o alias legado) no ambiente do processo.
  static bool get envEnabled => _envEnabled();

  static bool _envEnabled() {
    final env = Platform.environment;
    return env['COCKPIT_PERF'] == '1' || env['COCKPIT_PERF_DIAGNOSTICS'] == '1';
  }

  /// Ligada por env no boot ou por [enable] (modo desenvolvedor).
  bool enabled;
  final int maxEntries;
  final Duration minSampleInterval;
  final Duration flushEvery;

  /// Destino das amostras. O default escreve no [DiagnosticsLog]; a página
  /// do Cockpit troca pelo run do app na Telemetria (`AppTelemetryBridge`).
  PerfSink sink;

  final List<_Entry> _entries = [];
  final Map<PerfMetric, DateTime> _lastSample = {};
  Timer? _watchdog;
  Timer? _flushTimer;
  DateTime? _expectedWatchdog;
  bool _started = false;
  final Stopwatch _sinceStart = Stopwatch();
  bool _bootRecorded = false;

  // Janela de frames (agregada no flush).
  final List<int> _frameUs = [];
  int _jank = 0;

  @visibleForTesting
  List<Map<String, Object>> get entries => [
    for (final e in _entries)
      {
        'at': e.at.toUtc().toIso8601String(),
        'metric': e.metric.name,
        for (final f in e.fields.entries) f.key.name: f.value,
      },
  ];

  /// Liga em runtime (Settings → Developer mode) e sobe os timers. Desligar
  /// para de gravar mas mantém o que já foi medido até o próximo flush.
  void enable(bool value) {
    if (enabled == value) return;
    enabled = value;
    if (value) {
      start();
    } else {
      flush();
    }
  }

  void start() {
    if (!enabled || _started) return;
    _started = true;
    _sinceStart.start();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _expectedWatchdog = DateTime.now().add(const Duration(seconds: 1));
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final expected = _expectedWatchdog!;
      final delay = now.difference(expected);
      _expectedWatchdog = now.add(const Duration(seconds: 1));
      record(PerfMetric.eventLoop, {
        PerfField.delayUs: delay.isNegative ? 0 : delay.inMicroseconds,
      });
      record(PerfMetric.memory, {PerfField.rssBytes: ProcessInfo.currentRss});
    });
    _flushTimer = Timer.periodic(flushEvery, (_) => flush());
  }

  /// Amostra de [metric]. Throttle por métrica ([minSampleInterval]) salvo
  /// [force]; ring buffer de [maxEntries] até o flush.
  void record(
    PerfMetric metric,
    Map<PerfField, num> values, {
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
    _entries.add(_Entry(now, metric, Map.unmodifiable(values)));
  }

  /// `start()` → agora, uma vez por processo (workspace pronto).
  void markBootReady() {
    if (!enabled || _bootRecorded) return;
    _bootRecorded = true;
    record(PerfMetric.boot, {
      PerfField.durationUs: _sinceStart.elapsedMicroseconds,
    }, force: true);
  }

  /// Mede de agora até o PRÓXIMO frame pintado (troca de aba/workspace: o
  /// custo real é o rebuild que a troca dispara, não o setState).
  void timeToNextFrame(PerfMetric metric) {
    if (!enabled) return;
    final sw = Stopwatch()..start();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      record(metric, {
        PerfField.durationUs: sw.elapsedMicroseconds,
      }, force: true);
    });
  }

  /// Entrega as amostras acumuladas ao [sink] e zera. O resumo de frames da
  /// janela sai junto.
  void flush() {
    if (!enabled) return;
    if (_frameUs.isNotEmpty) {
      final sorted = List<int>.of(_frameUs)..sort();
      _entries.add(
        _Entry(DateTime.now(), PerfMetric.frame, {
          PerfField.frames: sorted.length,
          PerfField.jankFrames: _jank,
          PerfField.p95Us: sorted[((sorted.length - 1) * 0.95).round()],
          PerfField.maxUs: sorted.last,
        }),
      );
      _frameUs.clear();
      _jank = 0;
    }
    if (_entries.isEmpty) return;
    final batch = List<_Entry>.of(_entries);
    _entries.clear();
    for (final e in batch) {
      try {
        sink(e.metric.name, {
          for (final f in e.fields.entries) f.key.name: f.value,
        });
      } on Object catch (_) {
        // Sink de diagnóstico nunca derruba o app.
      }
    }
  }

  static const _jankUs = 16667;
  static const _slowUs = 50000;

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final durationUs = timing.totalSpan.inMicroseconds;
      _frameUs.add(durationUs);
      if (durationUs > _jankUs) _jank++;
      if (durationUs >= _slowUs) {
        record(PerfMetric.slowFrame, {
          PerfField.buildUs: timing.buildDuration.inMicroseconds,
          PerfField.rasterUs: timing.rasterDuration.inMicroseconds,
          PerfField.durationUs: durationUs,
        }, force: true);
      }
    }
  }

  static void _defaultSink(String metric, Map<String, num> fields) =>
      DiagnosticsLog.instance.log(
        'perf',
        jsonEncode({'metric': metric, ...fields}),
      );

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

class _Entry {
  const _Entry(this.at, this.metric, this.fields);
  final DateTime at;
  final PerfMetric metric;
  final Map<PerfField, num> fields;
}
