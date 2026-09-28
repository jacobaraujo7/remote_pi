// Plano 68: o próprio Cockpit como fonte da Telemetria. Um run por boot
// (`source: app`) recebe o que o `DiagnosticsLog` registra: erros dos
// handlers globais (`FlutterError.onError`, zona, isolates), `warn` dos
// fallbacks e as métricas de performance (quando ligadas). Local, sem envio
// para fora: é a base que o agente e o dono consultam com
// `cockpit telemetry --app`.

import 'dart:async';

import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';

import '../../domain/contracts/telemetry_ingest.dart';
import '../../domain/entities/telemetry_event.dart';
import 'line_parser/frames.dart';

class AppTelemetryBridge {
  AppTelemetryBridge._();

  static final AppTelemetryBridge instance = AppTelemetryBridge._();

  TelemetryIngestSession? _session;
  bool _starting = false;

  /// Run aberto (`null` antes do [start] ou depois do [close]).
  TelemetryIngestSession? get session => _session;

  /// Abre o run do app e liga o espelho do [DiagnosticsLog]. Idempotente.
  Future<void> start(TelemetryIngest ingest) async {
    if (_session != null || _starting) return;
    _starting = true;
    try {
      final version = DiagnosticsLog.instance.appVersion ?? 'dev';
      final s = await ingest.openAppRun(version: version);
      if (s == null) return;
      _session = s;
      DiagnosticsLog.instance.telemetrySink = _onRecord;
      // Contexto do boot, no run: quem for ler já sabe a versão e o SO.
      s.addEvents([
        _event(
          TelemetrySeverity.info,
          'boot',
          'Cockpit $version started',
          at: DateTime.now(),
        ),
      ]);
    } on Object catch (e, stack) {
      // Não passa pelo log: o sink ainda não existe e o log já é o fallback.
      DiagnosticsLog.instance.logError('telemetry-app', e, stack);
    } finally {
      _starting = false;
    }
  }

  /// Fecha o run (saída limpa). Best-effort com teto: o engine espera esta
  /// resposta para encerrar.
  Future<void> close() async {
    final s = _session;
    if (s == null) return;
    _session = null;
    DiagnosticsLog.instance.telemetrySink = null;
    try {
      await s.close(exitCode: 0).timeout(const Duration(seconds: 2));
    } on Object catch (_) {
      // Já estamos saindo; o run fica "vivo" na base e o próximo boot mostra
      // assim mesmo.
    }
  }

  /// Métrica numérica (passo 4): evento `info` com `metric` e campos nos
  /// atributos. Só números e nomes fixos entram aqui.
  void metric(String metric, Map<String, num> fields, {DateTime? at}) {
    final s = _session;
    if (s == null) return;
    s.addEvents([
      TelemetryEvent(
        runId: s.runId,
        ts: at ?? DateTime.now(),
        stream: TelemetryStream.otlp,
        severity: TelemetrySeverity.info,
        body: 'perf $metric',
        attrs: <String, Object?>{'metric': metric, ...fields},
      ),
    ]);
  }

  void _onRecord(DiagnosticsRecord r) {
    final s = _session;
    if (s == null) return;
    final severity = switch (r.level) {
      DiagnosticsLevel.info => TelemetrySeverity.info,
      DiagnosticsLevel.warn => TelemetrySeverity.warn,
      DiagnosticsLevel.error => TelemetrySeverity.error,
    };
    s.addEvents([
      _event(
        severity,
        r.tag,
        r.message,
        at: r.at,
        error: r.error,
        stack: r.stack,
      ),
    ]);
  }

  TelemetryEvent _event(
    TelemetrySeverity severity,
    String tag,
    String message, {
    required DateTime at,
    Object? error,
    StackTrace? stack,
  }) {
    final s = _session!;
    TelemetryError? err;
    if (severity.isProblem) {
      final stackText = stack?.toString();
      err = TelemetryError(
        type: error == null
            ? (severity == TelemetrySeverity.warn ? 'Warning' : 'Error')
            : _typeOf(error),
        message: message,
        stack: stackText,
        frames: stackText == null ? const [] : _frames(stackText),
      );
    }
    return TelemetryEvent(
      runId: s.runId,
      ts: at,
      stream: TelemetryStream.err,
      severity: severity,
      body: '[$tag] $message',
      attrs: <String, Object?>{'tag': tag},
      error: err,
    );
  }

  /// `FlutterError`, `StateError`, `ProcessException`... O `toString` de
  /// muitas exceções começa pelo tipo; o `runtimeType` é o que vale.
  static String _typeOf(Object error) {
    final name = error.runtimeType.toString();
    return name.startsWith('_') ? name.substring(1) : name;
  }

  /// Frames do stack do PRÓPRIO app: `package:cockpit/` é "do projeto"
  /// (fingerprint e location apontam pra ele), o resto é framework.
  static List<TelemetryFrame> _frames(String stack) {
    final out = <TelemetryFrame>[];
    for (final line in stack.split('\n')) {
      final f = parseFrame(line);
      if (f == null) continue;
      final file = f.file ?? '';
      final own = file.startsWith('package:cockpit/');
      out.add(
        TelemetryFrame(
          raw: f.raw,
          file: own ? 'lib/${file.substring('package:cockpit/'.length)}' : file,
          line: f.line,
          column: f.column,
          function: f.function,
          inProject: own,
        ),
      );
      if (out.length >= 40) break;
    }
    return out;
  }
}
