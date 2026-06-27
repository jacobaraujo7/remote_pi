import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';

/// Converte a linha JSON crua do stdout do `pi --mode rpc` em [RpcEvent]
/// tipado. **Único lugar** que conhece o wire format — nada acima da `data/`
/// vê `Map<String,dynamic>`.
///
/// Schema em `docs/rpc-protocol.md`. Tipos não mapeados viram [RpcUnknown]
/// (a UI os ignora) — assim novos eventos do pi nunca derrubam o cliente.
class RpcEventMapper {
  const RpcEventMapper();

  RpcEvent fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'agent_start':
        return const RpcAgentStart();
      case 'agent_end':
        return const RpcAgentEnd();
      case 'turn_start':
        return const RpcTurnStart();
      case 'turn_end':
        return const RpcTurnEnd();

      case 'response':
        return RpcCommandResponse(
          command: json['command'] as String? ?? '?',
          success: json['success'] == true,
          error: json['error'] as String?,
        );

      case 'tool_execution_start':
        return RpcToolStart(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '?',
          args: _asStringMap(json['args']),
        );

      case 'tool_execution_end':
        return RpcToolEnd(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '?',
          isError: json['isError'] == true,
          resultText: _extractContentText(json['result']),
        );

      case 'extension_ui_request':
        return _fromUiRequest(json);

      case 'message_update':
        return _fromMessageUpdate(json['assistantMessageEvent']);

      case 'message_start':
        final msg = json['message'];
        // Mensagem do usuário (eco local ou vinda do app/mesh) → bolha de input.
        if (msg is Map<String, dynamic> && msg['role'] == 'user') {
          return RpcUserMessage(_contentText(msg['content']));
        }
        return _fromCustomMessage(msg);

      case 'message_end':
        // Carrega o erro do turno quando o assistant falhou (provider fora do
        // ar, etc.). Os deltas não trazem isso — só a mensagem final.
        final error = _errorMessageOf(json['message']);
        return error != null
            ? RpcStreamError(error)
            : const RpcUnknown('message_end');

      case 'auto_retry_start':
        return RpcAutoRetry(
          attempt: (json['attempt'] as num?)?.toInt() ?? 0,
          maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 0,
          delayMs: (json['delayMs'] as num?)?.toInt() ?? 0,
          message: json['errorMessage'] as String? ?? 'transient error',
        );

      default:
        return RpcUnknown(type ?? '<none>');
    }
  }

  /// `message_start` com `role:"custom"` — despacha para o handler do tipo
  /// customizado. Outros roles (ou role ausente) viram [RpcUnknown].
  RpcEvent _fromCustomMessage(Object? message) {
    if (message is! Map<String, dynamic>) {
      return const RpcUnknown('message_start');
    }
    if (message['role'] != 'custom') return const RpcUnknown('message_start');

    final customType = message['customType'] as String?;
    final details = message['details'];

    switch (customType) {
      case 'remote-pi:relay-state':
        if (details is! Map<String, dynamic>) {
          return const RpcUnknown('message_start:relay-state:no-details');
        }
        final statusStr = details['status'] as String?;
        return RpcRelayState(
          status: switch (statusStr) {
            'connected' => RelayStatus.connected,
            'reconnecting' => RelayStatus.reconnecting,
            _ => RelayStatus.disconnected,
          },
          connected: details['connected'] == true,
        );
      case 'remote-pi:name-assigned':
        if (details is! Map<String, dynamic>) {
          return const RpcUnknown('message_start:name-assigned:no-details');
        }
        final assigned = details['assigned'] as String?;
        if (assigned == null) {
          return const RpcUnknown('message_start:name-assigned:no-assigned');
        }
        return RpcNameAssigned(
          assigned: assigned,
          changed: details['changed'] == true,
        );
      default:
        return RpcUnknown('message_start:custom:${customType ?? "?"}');
    }
  }

  /// Extrai o texto de um `content` de mensagem do pi: string crua, ou lista de
  /// partes (`{type:"text", text:"..."}`; partes não-texto, ex.: imagem, são
  /// ignoradas). Junta as partes de texto com espaço.
  String _contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final p in content) {
        if (p is String) {
          parts.add(p);
        } else if (p is Map && p['type'] == 'text' && p['text'] is String) {
          parts.add(p['text'] as String);
        }
      }
      return parts.join(' ');
    }
    return '';
  }

  /// `errorMessage` de uma mensagem com `stopReason == "error"`, ou `null`.
  String? _errorMessageOf(Object? message) {
    if (message is Map && message['stopReason'] == 'error') {
      final error = message['errorMessage'];
      if (error is String && error.isNotEmpty) return error;
      return 'erro desconhecido';
    }
    return null;
  }

  /// `extension_ui_request`: `notify` (fire-and-forget) vira [RpcNotice]; os
  /// interativos (`select`/`confirm`/`input`/`editor`) viram [RpcUiRequest]; o
  /// resto (setStatus/setTitle/setWidget/set_editor_text) é chrome de TUI →
  /// ignorado.
  RpcEvent _fromUiRequest(Map<String, dynamic> json) {
    final method = json['method'] as String?;
    switch (method) {
      case 'notify':
        return RpcNotice(
          _str(json['message']) ?? '',
          switch (json['notifyType']) {
            'warning' => RpcNoticeLevel.warning,
            'error' => RpcNoticeLevel.error,
            _ => RpcNoticeLevel.info,
          },
        );
      case 'select':
      case 'confirm':
      case 'input':
      case 'editor':
        final id = _str(json['id']);
        if (id == null) return const RpcUnknown('extension_ui_request:no-id');
        final rawOptions = json['options'];
        // `placeholder` pode vir como string (hint) OU objeto
        // `{defaultValue: "..."}` (valor inicial). Nada de `as String` cru —
        // um cast errado derrubaria o evento inteiro pra <parse-error>.
        return RpcUiRequest(
          id: id,
          method: method!,
          title: _str(json['title']),
          message: _str(json['message']),
          placeholder: _str(json['placeholder']),
          defaultValue: _defaultValue(json),
          options: rawOptions is List
              ? rawOptions.map((o) => o.toString()).toList(growable: false)
              : const <String>[],
        );
      default:
        return RpcUnknown('extension_ui_request:${method ?? "?"}');
    }
  }

  /// Coerção segura pra String (nunca lança): não-string vira `null`.
  String? _str(Object? v) => v is String ? v : null;

  /// Valor inicial do campo: `placeholder.defaultValue`, `defaultValue` ou
  /// `prefill`. Cobre o `ui.input(title, {defaultValue})` do remote-pi.
  String? _defaultValue(Map<String, dynamic> json) {
    final p = json['placeholder'];
    if (p is Map && p['defaultValue'] is String) {
      return p['defaultValue'] as String;
    }
    return _str(json['defaultValue']) ?? _str(json['prefill']);
  }

  RpcEvent _fromMessageUpdate(Object? assistantMessageEvent) {
    if (assistantMessageEvent is! Map) {
      return const RpcUnknown('message_update');
    }
    final eventType = assistantMessageEvent['type'] as String?;
    switch (eventType) {
      case 'text_delta':
        return RpcTextDelta(assistantMessageEvent['delta'] as String? ?? '');
      case 'thinking_delta':
        return RpcThinkingDelta(
          assistantMessageEvent['delta'] as String? ?? '',
        );
      case 'text_end':
        return RpcTextEnd(assistantMessageEvent['content'] as String? ?? '');
      default:
        // text_start/thinking_start/toolcall_*/done/error — ignorados no MVP.
        return RpcUnknown('message_update:${eventType ?? "?"}');
    }
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const {};
  }

  /// Extrai o texto concatenado de um `{content: [{type:"text", text:...}]}`.
  String _extractContentText(Object? result) {
    if (result is Map && result['content'] is List) {
      return (result['content'] as List)
          .whereType<Map>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'] as String? ?? '')
          .join('\n');
    }
    return '';
  }
}
