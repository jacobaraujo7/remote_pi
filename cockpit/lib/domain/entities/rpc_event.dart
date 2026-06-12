/// Versão de domínio do stream de stdout do `pi --mode rpc`.
///
/// A `ui/` e o domínio **nunca** veem o wire format cru (`Map<String,dynamic>`).
/// O parse das linhas JSON acontece em `data/adapters/` e produz estes tipos.
/// Schema real documentado em `docs/rpc-protocol.md` (descoberto empiricamente
/// no spike do plano 37, pi 0.78.1).
sealed class RpcEvent {
  const RpcEvent();
}

/// `agent_start` — o agente começou a processar um prompt.
final class RpcAgentStart extends RpcEvent {
  const RpcAgentStart();
}

/// `agent_end` — o agente terminou o turno (volta a ficar ocioso).
final class RpcAgentEnd extends RpcEvent {
  const RpcAgentEnd();
}

/// `turn_start` — começou uma rodada (resposta do assistant + tools).
final class RpcTurnStart extends RpcEvent {
  const RpcTurnStart();
}

/// `turn_end` — a rodada terminou.
final class RpcTurnEnd extends RpcEvent {
  const RpcTurnEnd();
}

/// `message_update` com `assistantMessageEvent.type == "text_delta"`.
final class RpcTextDelta extends RpcEvent {
  const RpcTextDelta(this.delta);
  final String delta;
}

/// `message_update` com `assistantMessageEvent.type == "text_end"`.
final class RpcTextEnd extends RpcEvent {
  const RpcTextEnd(this.content);
  final String content;
}

/// `message_start` com `role == "user"` — uma mensagem do usuário adicionada à
/// sessão. Acontece tanto no envio local (eco do que digitamos) quanto quando
/// a mensagem vem **de fora** (app/mesh). A UI usa pra mostrar a bolha das
/// mensagens remotas; as locais já entram otimisticamente e são deduplicadas.
final class RpcUserMessage extends RpcEvent {
  const RpcUserMessage(this.text);
  final String text;
}

/// `message_update` com `assistantMessageEvent.type == "thinking_delta"`.
/// (deepseek/raciocinadores emitem isto pelo RPC mesmo com thinking oculto na TUI.)
final class RpcThinkingDelta extends RpcEvent {
  const RpcThinkingDelta(this.delta);
  final String delta;
}

/// `tool_execution_start` — uma tool começou a executar.
final class RpcToolStart extends RpcEvent {
  const RpcToolStart({
    required this.toolCallId,
    required this.toolName,
    required this.args,
  });
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> args;
}

/// `tool_execution_end` — uma tool terminou (com o texto do resultado).
final class RpcToolEnd extends RpcEvent {
  const RpcToolEnd({
    required this.toolCallId,
    required this.toolName,
    required this.isError,
    required this.resultText,
  });
  final String toolCallId;
  final String toolName;
  final bool isError;
  final String resultText;
}

/// `response` — ACK (ou erro) de um comando que mandamos pelo stdin.
final class RpcCommandResponse extends RpcEvent {
  const RpcCommandResponse({
    required this.command,
    required this.success,
    this.error,
  });
  final String command;
  final bool success;
  final String? error;
}

/// Falha do turno reportada via `stopReason: "error"` na mensagem do assistant
/// (ex.: `errorMessage: "Connection error."` quando o provider está fora do ar).
/// Vem nos eventos `message_end`/`agent_end`, não nos deltas.
final class RpcStreamError extends RpcEvent {
  const RpcStreamError(this.message);
  final String message;
}

/// `auto_retry_start` — o pi vai retentar após um erro transitório
/// (overloaded, rate-limit, 5xx, conexão recusada). `delayMs` é o backoff.
final class RpcAutoRetry extends RpcEvent {
  const RpcAutoRetry({
    required this.attempt,
    required this.maxAttempts,
    required this.delayMs,
    required this.message,
  });
  final int attempt;
  final int maxAttempts;
  final int delayMs;
  final String message;
}

/// Texto cru do stderr do child (warnings do pi, ex.: "model not found").
/// **Não** é protocolo — é diagnóstico, mantido separado do stdout JSONL.
final class RpcDiagnostic extends RpcEvent {
  const RpcDiagnostic(this.text);
  final String text;
}

/// O child process terminou (saída limpa ou crash). `code == 0` é encerramento
/// gracioso (fechar o stdin já basta — ver spike).
final class RpcProcessExit extends RpcEvent {
  const RpcProcessExit(this.code);
  final int code;
}

/// Nível de um [RpcNotice] (`extension_ui_request` method `notify`).
enum RpcNoticeLevel { info, warning, error }

/// `extension_ui_request` method `notify` — aviso fire-and-forget da extensão
/// (status do mesh, "QR ready", erros). Não espera resposta.
final class RpcNotice extends RpcEvent {
  const RpcNotice(this.message, this.level);
  final String message;
  final RpcNoticeLevel level;
}

/// `extension_ui_request` interativo (`select` / `confirm` / `input` / `editor`)
/// — a extensão pede uma escolha ao usuário e **espera** um
/// `extension_ui_response` com o mesmo [id] no stdin. Sem resposta, a extensão
/// fica pendurada (ou resolve no timeout dela).
final class RpcUiRequest extends RpcEvent {
  const RpcUiRequest({
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
  final String? message; // confirm
  final String? placeholder; // input/editor — hint
  final String? defaultValue; // input/editor — valor inicial (prefill)
  final List<String> options; // select
}

/// Estado da conexão do relay para [RpcRelayState].
enum RelayStatus { connected, reconnecting, disconnected }

/// `message_start` com `role:"custom"` e `customType:"remote-pi:relay-state"`.
///
/// Emitido em toda transição do relay (liga, queda → reconnecting, desliga,
/// reconexão) e em resposta ao controle `relay:status`.
final class RpcRelayState extends RpcEvent {
  const RpcRelayState({required this.status, required this.connected});

  final RelayStatus status;
  final bool connected;
}

/// `message_start` com `role:"custom"` e `customType:"remote-pi:name-assigned"`.
///
/// Emitido pelo broker ao entrar no mesh: o broker pode ter atribuído um nome
/// diferente do pedido (`agent_name`) para evitar colisão (ex.: "Proj" → "Proj#2").
/// Quando [changed] é `false`, [assigned] == o nome original — sem ação necessária.
final class RpcNameAssigned extends RpcEvent {
  const RpcNameAssigned({required this.assigned, required this.changed});

  /// Nome efetivo atribuído pelo broker (o que aparece no mesh).
  final String assigned;

  /// `true` quando o broker mudou o nome pedido por colisão.
  final bool changed;
}

/// Qualquer evento ainda não mapeado (compaction, retry, queue_update, deltas
/// de toolcall, message_start/end, setStatus/setTitle...). A UI ignora com
/// segurança — nunca crasha.
final class RpcUnknown extends RpcEvent {
  const RpcUnknown(this.type, [this.raw = '']);
  final String type;
  final String raw;
}
