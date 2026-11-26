import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/telemetry/app_telemetry_bridge.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements TelemetryIngestSession {
  final events = <TelemetryEvent>[];

  @override
  String get runId => 'r_test';
  @override
  String get workspaceId => kTelemetryAppWorkspaceId;
  @override
  String? get ownerId => null;
  @override
  String? get paneId => null;

  @override
  Map<String, String> get childEnvironment => const {};

  @override
  void add(String chunk, {TelemetryStream stream = TelemetryStream.out}) {}

  @override
  void addEvents(List<TelemetryEvent> list) => events.addAll(list);

  @override
  Future<void> close({int? exitCode}) async {}
}

class _FakeIngest implements TelemetryIngest {
  final session_ = _FakeSession();

  @override
  Stream<TelemetryErrorNotice> get notices => const Stream.empty();

  @override
  void registerWorkspace(TelemetryWorkspace workspace) {}

  @override
  Future<TelemetryIngestSession?> openWrapperRun({
    required String cwd,
    required String command,
    String? workspaceId,
    String? ownerId,
    String? name,
    String? paneId,
    int? pid,
  }) async => null;

  @override
  TelemetryIngestSession? session(String runId, {String? workspaceId}) =>
      session_;

  @override
  Future<TelemetryIngestSession?> openAppRun({required String version}) async =>
      session_;

  @override
  Future<int?> replay({
    required String workspaceId,
    required DateTime since,
    DateTime? until,
  }) async => null;

  @override
  Future<TelemetryIngestSession?> openTaskRun(
    TaskDefinition def, {
    required String command,
    int? pid,
    String? paneId,
  }) async => null;
}

void main() {
  test(
    'warn com exceção leva o texto da exceção na mensagem do erro',
    () async {
      final ingest = _FakeIngest();
      final bridge = AppTelemetryBridge.instance;
      await bridge.start(ingest);
      addTearDown(bridge.close);

      const e = ProcessException(
        '/bin/zsh',
        ['-lc', 'true'],
        'Resource temporarily unavailable',
        35,
      );
      DiagnosticsLog.instance.warn(
        'spawn',
        'shell spawn failed: /bin/zsh (errno ${e.errorCode})',
        error: e,
      );

      final ev = ingest.session_.events.last;
      expect(ev.error, isNotNull);
      expect(ev.error!.type, 'ProcessException');
      expect(ev.error!.message, contains('shell spawn failed: /bin/zsh'));
      expect(ev.error!.message, contains('Resource temporarily unavailable'));
      expect(ev.error!.message, contains('errno 35'));
    },
  );

  test('warn sem exceção mantém a mensagem como está', () async {
    final ingest = _FakeIngest();
    final bridge = AppTelemetryBridge.instance;
    await bridge.start(ingest);
    addTearDown(bridge.close);

    DiagnosticsLog.instance.warn('x', 'plain warning');
    final ev = ingest.session_.events.last;
    expect(ev.error!.type, 'Warning');
    expect(ev.error!.message, 'plain warning');
  });
}
