import 'dart:typed_data';

/// Item renderizável do transcript de um agente — modelo de UI derivado dos
/// [RpcEvent] tipados. Mutável de propósito (deltas crescem em lugar).
sealed class AgentEntry {
  AgentEntry();
}

/// Prompt enviado pelo usuário (eco local). [images] são as imagens anexadas
/// (PNG já normalizado), exibidas no balão.
final class UserEntry extends AgentEntry {
  UserEntry(this.text, {this.images = const <Uint8List>[]});
  final String text;
  final List<Uint8List> images;
}

/// Texto do assistant, crescendo via `text_delta`.
final class AssistantTextEntry extends AgentEntry {
  AssistantTextEntry([this.text = '']);
  String text;
}

/// Bloco de raciocínio (`thinking_delta`).
final class ThinkingEntry extends AgentEntry {
  ThinkingEntry([this.text = '']);
  String text;
}

/// Tool call: começa em `tool_execution_start`, fecha em `..._end`.
final class ToolEntry extends AgentEntry {
  ToolEntry({
    required this.toolCallId,
    required this.toolName,
    required this.args,
  });

  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> args;

  bool done = false;
  bool isError = false;
  String resultText = '';
}

/// Linha de ciclo de vida (ACK de erro, stderr, saída do processo).
final class InfoEntry extends AgentEntry {
  InfoEntry(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// Marca o fim de um turno com quanto tempo o agente trabalhou.
final class WorkedEntry extends AgentEntry {
  WorkedEntry(this.duration);
  final Duration duration;
}
