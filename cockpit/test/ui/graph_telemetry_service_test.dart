import 'dart:async';
import 'dart:io';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import '../support/attachment_terminal_gateway.dart';

import 'package:cockpit/app/cockpit/ui/services/graph_telemetry_service.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:flutter_test/flutter_test.dart';

class _RemoteTerminal extends TerminalSession {
  _RemoteTerminal()
    : super(
        id: 'remote',
        projectId: 'remote-worktree',
        workingDirectory: '/host',
        attachmentsRemote: true,
        gateway: AttachmentTerminalGateway(),
        profile: const TerminalProfile(
          id: 'shell',
          label: 'Shell',
          executable: 'sh',
        ),
      );
  @override
  HarnessKind? get activeHarness => HarnessKind.claudeCode;
}

class _LocalTerminal extends TerminalSession {
  _LocalTerminal()
    : super(
        id: 'reused-id',
        projectId: 'worktree',
        workingDirectory: '/worktree',
        gateway: AttachmentTerminalGateway(),
        profile: const TerminalProfile(
          id: 'sh',
          label: 'Shell',
          executable: 'sh',
        ),
      );
  HarnessKind? harness = HarnessKind.claudeCode;
  @override
  HarnessKind? get activeHarness => harness;
}

class _DelayedTelemetry extends GraphTelemetryService {
  final result = Completer<GraphTelemetrySnapshot>();
  @override
  Future<GraphTelemetrySnapshot> readTranscript(
    String path,
    HarnessKind harness,
  ) => result.future;
}

void main() {
  test(
    'runtime keys distinguish conversations, harnesses, paths and replacement controllers',
    () async {
      final pane = _LocalTerminal()
        ..claudeSessionId = 'one'
        ..transcriptPath = '/one';
      final replacement = _LocalTerminal()
        ..claudeSessionId = 'one'
        ..transcriptPath = '/one';
      addTearDown(pane.dispose);
      addTearDown(replacement.dispose);
      final first = GraphTelemetryService.keyFor(pane);
      expect(GraphTelemetryService.keyFor(replacement), isNot(first));
      pane.applyGraphMetrics(50, 100);
      expect(GraphTelemetryService.keyFor(pane), first);
      pane.claudeSessionId = 'two';
      expect(GraphTelemetryService.keyFor(pane), isNot(first));
      pane.claudeSessionId = 'one';
      pane.transcriptPath = '/two';
      expect(GraphTelemetryService.keyFor(pane), isNot(first));
      pane.transcriptPath = '/one';
      pane.harness = HarnessKind.codex;
      expect(GraphTelemetryService.keyFor(pane), isNot(first));
    },
  );

  test(
    'a transcript finishing after a conversation change cannot supply its old token counts',
    () async {
      final pane = _LocalTerminal()
        ..claudeSessionId = 'one'
        ..transcriptPath = '/one';
      addTearDown(pane.dispose);
      final service = _DelayedTelemetry();
      final read = service.snapshot(pane);
      pane.claudeSessionId = 'two';
      pane.transcriptPath = '/two';
      service.result.complete(
        GraphTelemetrySnapshot(
          activity: GraphActivity.idle,
          activitySource: 'old transcript',
          contextTokens: GraphMetric(
            99,
            source: 'old',
            observedAt: DateTime.now(),
          ),
          contextWindow: GraphMetric(
            100,
            source: 'old',
            observedAt: DateTime.now(),
          ),
        ),
      );
      final value = await read;
      expect(value.contextTokens, isNull);
      expect(value.contextWindow, isNull);
      expect(value.contextPercent, isNull);
    },
  );

  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('graph_telemetry_'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'Claude counts latest assistant input including cache, without guessing window',
    () async {
      final file = File('${directory.path}/claude.jsonl');
      await file.writeAsString('''
{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":100,"cache_read_input_tokens":200,"cache_creation_input_tokens":50}}}
{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":40}}}
''');
      final value = await const GraphTelemetryService().readTranscript(
        file.path,
        HarnessKind.claudeCode,
      );
      expect(value.contextTokens?.value, 50);
      expect(value.contextWindow, isNull);
      expect(value.contextPercent, isNull);
    },
  );

  test(
    'Codex reads token event and context window, ignores invalid trailing line',
    () async {
      final file = File('${directory.path}/codex.jsonl');
      await file.writeAsString('''
{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1200,"total_tokens":1500},"total_token_usage":{"total_tokens":8400},"model_context_window":200000}}}
{"incomplete":
''');
      final value = await const GraphTelemetryService().readTranscript(
        file.path,
        HarnessKind.codex,
      );
      expect(value.contextTokens?.value, 1200);
      expect(value.totalTokens?.value, 8400);
      expect(value.contextWindow?.value, 200000);
      expect(value.contextPercent, 0.6);
    },
  );

  test(
    'remote transcript never reads a same-named local file; own hook metrics still work',
    () async {
      final file = File('${directory.path}/host-path.jsonl');
      await file.writeAsString(
        '{"message":{"role":"assistant","usage":{"input_tokens":9999}}}',
      );
      final remote = _RemoteTerminal()..transcriptPath = file.path;
      addTearDown(remote.dispose);
      final absent = await const GraphTelemetryService().snapshot(remote);
      expect(absent.contextTokens, isNull);
      remote.applyGraphMetrics(40, 100);
      final reported = await const GraphTelemetryService().snapshot(remote);
      expect(reported.contextTokens?.value, 40);
      expect(reported.contextWindow?.value, 100);
    },
  );

  test('unknown transcript yields unavailable metrics', () async {
    final value = await const GraphTelemetryService().readTranscript(
      '${directory.path}/missing.jsonl',
      HarnessKind.codex,
    );
    expect(value.contextTokens, isNull);
    expect(value.totalTokens, isNull);
  });
}
