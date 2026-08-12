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
  AssistantTextEntry([String text = '']) {
    this.text = text;
  }

  final StringBuffer _buffer = StringBuffer();
  String? _snapshot;

  String get text => _snapshot ??= _buffer.toString();

  set text(String value) {
    _buffer
      ..clear()
      ..write(value);
    _snapshot = value;
  }

  void append(String delta) {
    if (delta.isEmpty) return;
    _buffer.write(delta);
    _snapshot = null;
  }
}

/// Bloco de raciocínio (`thinking_delta`).
final class ThinkingEntry extends AgentEntry {
  ThinkingEntry([String text = '']) {
    this.text = text;
  }

  final StringBuffer _buffer = StringBuffer();
  String? _snapshot;

  String get text => _snapshot ??= _buffer.toString();

  set text(String value) {
    _buffer
      ..clear()
      ..write(value);
    _snapshot = value;
  }

  void append(String delta) {
    if (delta.isEmpty) return;
    _buffer.write(delta);
    _snapshot = null;
  }
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

/// Aviso da extensão (`extension_ui_request` method `notify`) — não é resposta
/// do agente. `level`: 0 info, 1 warning, 2 error.
final class NoticeEntry extends AgentEntry {
  NoticeEntry(this.message, this.level);
  final String message;
  final int level;
}

/// Pedido interativo da extensão (`select`/`confirm`/`input`/`editor`).
/// Renderiza um card no transcript; ao responder, vira [resolved] com
/// [answerLabel] e o `extension_ui_response` é enviado. Mutável de propósito.
final class UiRequestEntry extends AgentEntry {
  UiRequestEntry({
    required this.id,
    required this.method,
    this.title,
    this.message,
    this.placeholder,
    this.defaultValue,
    this.options = const <String>[],
  });

  final String id;
  final String method; // select | confirm | input | editor
  final String? title;
  final String? message;
  final String? placeholder;
  final String? defaultValue;
  final List<String> options;

  bool resolved = false;
  String? answerLabel;
}
