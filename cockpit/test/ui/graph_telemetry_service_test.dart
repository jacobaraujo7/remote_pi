import 'dart:io';

import 'package:cockpit/app/cockpit/ui/services/graph_telemetry_service.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('unknown transcript yields unavailable metrics', () async {
    final value = await const GraphTelemetryService().readTranscript(
      '${directory.path}/missing.jsonl',
      HarnessKind.codex,
    );
    expect(value.contextTokens, isNull);
    expect(value.totalTokens, isNull);
  });
}
