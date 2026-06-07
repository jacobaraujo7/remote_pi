import 'package:cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/domain/entities/transcript_message.dart';

/// Converte os `data` das respostas request/response do RPC em entidades de
/// domínio. Separado do [RpcEventMapper] (que cuida do stream de eventos);
/// aqui é o payload de `get_available_models`/`get_state`/`set_model`/
/// `get_session_stats`. Único lugar que vê esse wire format.
class RpcDataMapper {
  const RpcDataMapper();

  PiModel? model(Object? json) {
    if (json is! Map) return null;
    final id = json['id'] as String?;
    final provider = json['provider'] as String?;
    if (id == null || provider == null) return null;
    final input = json['input'];
    return PiModel(
      provider: provider,
      id: id,
      name: json['name'] as String? ?? id,
      reasoning: json['reasoning'] == true,
      supportsImages: input is List && input.contains('image'),
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      thinkingLevelMap: _thinkingLevelMap(json['thinkingLevelMap']),
    );
  }

  Map<String, String?> _thinkingLevelMap(Object? value) {
    if (value is! Map) return const <String, String?>{};
    return value.map(
      (key, v) => MapEntry(key.toString(), v is String ? v : null),
    );
  }

  List<PiModel> models(Object? data) {
    if (data is! Map || data['models'] is! List) return const <PiModel>[];
    return (data['models'] as List)
        .map(model)
        .whereType<PiModel>()
        .toList(growable: false);
  }

  /// `get_commands` → `{commands:[{name, description, source, ...}]}`.
  List<PiCommand> commands(Object? data) {
    if (data is! Map || data['commands'] is! List) return const <PiCommand>[];
    return (data['commands'] as List)
        .whereType<Map>()
        .map((c) {
          final name = c['name'] as String?;
          if (name == null || name.isEmpty) return null;
          return PiCommand(
            name: name,
            description: c['description'] as String? ?? '',
          );
        })
        .whereType<PiCommand>()
        .toList(growable: false);
  }

  AgentSnapshot state(Object? data) {
    final map = data is Map ? data : const <String, dynamic>{};
    return AgentSnapshot(
      model: model(map['model']),
      thinkingLevel: ThinkingLevel.fromWire(map['thinkingLevel'] as String?),
      isStreaming: map['isStreaming'] == true,
    );
  }

  ContextUsage? contextUsage(Object? data) {
    if (data is! Map) return null;
    final usage = data['contextUsage'];
    if (usage is! Map) return null;
    final window = (usage['contextWindow'] as num?)?.toInt();
    if (window == null) return null;
    return ContextUsage(
      tokens: (usage['tokens'] as num?)?.toInt(),
      contextWindow: window,
      percent: (usage['percent'] as num?)?.toDouble(),
    );
  }

  /// Converte `get_messages` (`{messages:[AgentMessage]}`) numa lista de
  /// [TranscriptMessage], resolvendo `toolResult` no `toolCall` correspondente.
  List<TranscriptMessage> transcriptMessages(Object? data) {
    if (data is! Map || data['messages'] is! List) {
      return const <TranscriptMessage>[];
    }
    final out = <TranscriptMessage>[];
    final toolsById = <String, TmTool>{};
    for (final raw in data['messages'] as List) {
      if (raw is! Map) continue;
      switch (raw['role']) {
        case 'user':
          final text = _contentText(raw['content']);
          if (text.isNotEmpty) out.add(TmUser(text));
        case 'assistant':
          final content = raw['content'];
          if (content is! List) break;
          for (final block in content) {
            if (block is! Map) continue;
            switch (block['type']) {
              case 'thinking':
                final t = block['thinking'] as String? ?? '';
                if (t.isNotEmpty) out.add(TmThinking(t));
              case 'text':
                final t = block['text'] as String? ?? '';
                if (t.isNotEmpty) out.add(TmAssistantText(t));
              case 'toolCall':
                final id = block['id'] as String? ?? '';
                final tool = TmTool(
                  callId: id,
                  name: block['name'] as String? ?? '?',
                  args: _asStringMap(block['arguments']),
                );
                toolsById[id] = tool;
                out.add(tool);
            }
          }
        case 'toolResult':
          final tool = toolsById[raw['toolCallId'] as String? ?? ''];
          if (tool != null) {
            tool.done = true;
            tool.isError = raw['isError'] == true;
            tool.resultText = _contentText(raw['content']);
          }
      }
    }
    return out;
  }

  String _contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String? ?? '')
          .join('\n');
    }
    return '';
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const <String, dynamic>{};
  }
}
