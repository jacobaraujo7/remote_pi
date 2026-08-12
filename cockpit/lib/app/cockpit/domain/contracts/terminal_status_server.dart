/// Atualização de status de um agente rodando numa aba de terminal, enviada
/// pelo helper `cockpit hook` (instalado nos hooks do Claude Code e do Codex
/// CLI) via socket.
class ClaudeStatusUpdate {
  const ClaudeStatusUpdate({
    required this.paneId,
    required this.status,
    this.event,
    this.sessionId,
    this.transcriptPath,
    this.harness,
  });

  /// Id da aba (vem do env `COCKPIT_PANE_ID` injetado na PTV — roteamento).
  final String paneId;

  /// `working` | `waiting` | `idle` (wire string).
  final String status;

  /// Nome cru do evento de hook do Claude Code (`UserPromptSubmit`, `PreToolUse`,
  /// `Stop`, ...), quando enviado pelo helper. Usado pra distinguir início de
  /// turno de atividade mid-turn e descartar `working` reordenado. `null` em
  /// helpers antigos (pré-`ev`).
  final String? event;

  /// session_id do agente (persistido pra retomar a sessão no restore da aba).
  final String? sessionId;

  /// Caminho do transcript `.jsonl` do agente.
  final String? transcriptPath;

  /// Quem emitiu o evento: `claude` | `codex`. Vem do `--harness` que o
  /// instalador grava no comando do hook; `null` em helpers antigos (que só
  /// existiam para o Claude — ver [AgentHarness.fromWire]).
  final String? harness;
}

/// Harness que roda numa aba de terminal. O Cockpit precisa distinguir para
/// **retomar a sessão** no restore: o `session_id` sozinho não diz de quem é, e
/// o comando de resume difere.
enum AgentHarness {
  claude('claude'),
  codex('codex');

  const AgentHarness(this.wire);

  /// Nome no wire (payload do hook) e no layout persistido.
  final String wire;

  /// Comando que reata a sessão [sessionId] num shell novo.
  String resumeCommand(String sessionId) => switch (this) {
    AgentHarness.claude => 'claude --resume $sessionId',
    AgentHarness.codex => 'codex resume $sessionId',
  };

  /// Converte o nome do wire. Desconhecido ou ausente cai em [claude]: layouts
  /// e helpers anteriores a esta distinção só podiam ser do Claude.
  static AgentHarness fromWire(String? wire) => AgentHarness.values.firstWhere(
    (h) => h.wire == wire,
    orElse: () => AgentHarness.claude,
  );
}

/// Comando enviado pela **CLI interna** `cockpit` (binário em `~/.cockpit/bin`)
/// pelo mesmo socket do status. Discriminado no wire por `type:"cmd"`.
class CockpitCommand {
  const CockpitCommand({required this.cmd, this.tabId, this.args = const {}});

  /// Verbo no wire: `write` (send/send-key) | `list-panes` | `list-workspaces`.
  final String cmd;

  /// Pane alvo (default = `$COCKPIT_PANE_ID` resolvido pela CLI). `null` só nos
  /// comandos que não miram pane (list-*).
  final String? tabId;

  /// Argumentos do comando (ex.: `{data: <base64 utf8>}` no `write`).
  final Map<String, dynamic> args;
}

/// Resultado de um [CockpitCommand], serializado de volta pra CLI como uma linha
/// JSON `{ok, data?|error?}`.
class CockpitCommandResult {
  const CockpitCommandResult.ok([this.data]) : ok = true, error = null;
  const CockpitCommandResult.fail(this.error) : ok = false, data = null;

  final bool ok;
  final Object? data;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ok': ok,
    if (data != null) 'data': data,
    if (error != null) 'error': error,
  };
}

/// Servidor local (socket Unix) que recebe os updates de status do `cockpit-hook`.
///
/// O Claude roda os hooks **sem terminal controlador**, então não dá pra emitir
/// OSC na PTY (write em `/dev/tty` falha com ENXIO). O helper, em vez disso,
/// conecta neste socket e manda o status; o roteamento pra aba certa vem do
/// `paneId` (env injetado no spawn da PTY).
///
/// O **mesmo socket** também serve a CLI interna `cockpit` (comandos `type:"cmd"`,
/// request/response): status é fire-and-forget (não responde); comando retém a
/// conexão e escreve uma linha de resposta.
abstract class TerminalStatusServer {
  /// Variáveis de ambiente que o helper `cockpit-hook` precisa pra reportar
  /// status, injetadas no PTY de cada aba. Disponível **após** [start].
  /// POSIX: `{COCKPIT_STATUS_SOCK}`. Windows: `{COCKPIT_STATUS_PORT,
  /// COCKPIT_STATUS_TOKEN}` (TCP loopback + token anti-spoof).
  Map<String, String> get hookEnv;

  /// Sobe o servidor; [onUpdate] é chamado a cada status recebido. [onCommand]
  /// (opcional) atende os comandos da CLI interna e devolve o resultado a
  /// escrever de volta no socket.
  Future<void> start(
    void Function(ClaudeStatusUpdate update) onUpdate, {
    Future<CockpitCommandResult> Function(CockpitCommand command)? onCommand,
  });

  /// Derruba o servidor (e remove o socket no POSIX).
  Future<void> stop();
}
