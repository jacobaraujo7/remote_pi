import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';

/// A value is present only when it came from the owning agent's telemetry.
/// [observedAt] is the file modification time or the time of the Pi RPC read;
/// it is never a claim that a stale value is current.
class GraphMetric {
  const GraphMetric(
    this.value, {
    required this.source,
    required this.observedAt,
  });

  final int value;
  final String source;
  final DateTime observedAt;
}

enum GraphActivity { working, waiting, idle, starting, stopped, unknown }

class GraphTelemetrySnapshot {
  const GraphTelemetrySnapshot({
    required this.activity,
    required this.activitySource,
    this.contextTokens,
    this.contextWindow,
    this.totalTokens,
  });

  final GraphActivity activity;
  final String activitySource;
  final GraphMetric? contextTokens;
  final GraphMetric? contextWindow;
  final GraphMetric? totalTokens;

  double? get contextPercent {
    final used = contextTokens?.value;
    final window = contextWindow?.value;
    if (used == null || window == null || window <= 0) return null;
    return used * 100 / window;
  }
}

/// Snapshot adapter for graph boxes. It does not execute CLI commands in a
/// terminal or infer token counts from screen output or process CPU use.
class GraphTelemetryService {
  const GraphTelemetryService();

  Future<GraphTelemetrySnapshot> snapshot(PaneItem pane) async {
    if (pane is TerminalSession) {
      final activity = switch (pane.status) {
        TerminalStatus.working => GraphActivity.working,
        TerminalStatus.waiting => GraphActivity.waiting,
        TerminalStatus.idle => GraphActivity.idle,
      };
      final harness = pane.activeHarness;
      if (harness != HarnessKind.claudeCode && harness != HarnessKind.codex) {
        return GraphTelemetrySnapshot(
          activity: activity,
          activitySource: harness == null ? 'terminal' : 'process monitor',
        );
      }
      final at = pane.reportedContextAt;
      if (harness == HarnessKind.claudeCode &&
          at != null &&
          DateTime.now().difference(at) < const Duration(minutes: 2) &&
          pane.reportedContextTokens != null &&
          pane.reportedContextWindow != null) {
        return GraphTelemetrySnapshot(
          activity: activity,
          activitySource: 'agent hook',
          contextTokens: GraphMetric(
            pane.reportedContextTokens!,
            source: 'Claude status line',
            observedAt: at,
          ),
          contextWindow: GraphMetric(
            pane.reportedContextWindow!,
            source: 'Claude status line',
            observedAt: at,
          ),
        );
      }
      final path = pane.transcriptPath;
      if (path == null || path.isEmpty) {
        return GraphTelemetrySnapshot(
          activity: activity,
          activitySource: 'agent hook',
        );
      }
      final usage = await readTranscript(path, harness!);
      return GraphTelemetrySnapshot(
        activity: activity,
        activitySource: 'agent hook',
        contextTokens: usage.contextTokens,
        contextWindow: usage.contextWindow,
        totalTokens: usage.totalTokens,
      );
    }
    return const GraphTelemetrySnapshot(
      activity: GraphActivity.unknown,
      activitySource: 'unavailable',
    );
  }

  /// Reads only the tail of the transcript, so a long session cannot block the
  /// UI by loading its complete history. A missing or unfamiliar field stays
  /// unavailable rather than becoming an estimate.
  Future<GraphTelemetrySnapshot> readTranscript(
    String path,
    HarnessKind harness,
  ) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return _emptyTranscript;
      final raf = await file.open();
      try {
        final length = await raf.length();
        const maxBytes = 512 * 1024;
        final start = length > maxBytes ? length - maxBytes : 0;
        await raf.setPosition(start);
        final bytes = await raf.read(length - start);
        final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
        if (start > 0 && lines.isNotEmpty) lines.removeAt(0);
        GraphMetric? contextTokens;
        GraphMetric? contextWindow;
        GraphMetric? totalTokens;
        for (final line in lines) {
          if (line.isEmpty) continue;
          final Object? decoded;
          try {
            decoded = jsonDecode(line);
          } catch (_) {
            continue;
          }
          if (decoded is! Map) continue;
          if (harness == HarnessKind.claudeCode) {
            final message = decoded['message'];
            if (message is! Map || message['role'] != 'assistant') continue;
            final usage = message['usage'];
            if (usage is! Map) continue;
            final input = _nonnegative(usage['input_tokens']);
            final cacheRead =
                _nonnegative(usage['cache_read_input_tokens']) ?? 0;
            final cacheWrite =
                _nonnegative(usage['cache_creation_input_tokens']) ?? 0;
            if (input != null) {
              contextTokens = GraphMetric(
                input + cacheRead + cacheWrite,
                source: 'Claude transcript: latest assistant input',
                observedAt: stat.modified,
              );
            }
          } else if (harness == HarnessKind.codex) {
            if (decoded['type'] != 'event_msg') continue;
            final payload = decoded['payload'];
            if (payload is! Map || payload['type'] != 'token_count') continue;
            final info = payload['info'];
            if (info is! Map) continue;
            final last = info['last_token_usage'];
            final total = info['total_token_usage'];
            final used = last is Map
                ? _nonnegative(last['input_tokens'])
                : null;
            final cumulative = total is Map
                ? _nonnegative(total['total_tokens'])
                : null;
            final window = _nonnegative(info['model_context_window']);
            if (used != null) {
              contextTokens = GraphMetric(
                used,
                source: 'Codex rollout: last input tokens',
                observedAt: stat.modified,
              );
            }
            if (cumulative != null) {
              totalTokens = GraphMetric(
                cumulative,
                source: 'Codex rollout: cumulative token usage',
                observedAt: stat.modified,
              );
            }
            if (window != null && window > 0) {
              contextWindow = GraphMetric(
                window,
                source: 'Codex rollout: model context window',
                observedAt: stat.modified,
              );
            }
          }
        }
        return GraphTelemetrySnapshot(
          activity: GraphActivity.unknown,
          activitySource: 'transcript',
          contextTokens: contextTokens,
          contextWindow: contextWindow,
          totalTokens: totalTokens,
        );
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return _emptyTranscript;
    }
  }

  static int? _nonnegative(Object? value) {
    if (value is! num || !value.isFinite || value < 0) return null;
    return value.toInt();
  }

  static const _emptyTranscript = GraphTelemetrySnapshot(
    activity: GraphActivity.unknown,
    activitySource: 'transcript unavailable',
  );
}
