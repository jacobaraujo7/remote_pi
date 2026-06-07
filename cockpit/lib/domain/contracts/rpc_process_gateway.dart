import 'package:cockpit/domain/contracts/service.dart';
import 'package:cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/domain/result.dart';

/// Contrato de baixo nível que esconde o `Process.start` do `pi --mode rpc`.
///
/// Declarado no domínio, implementado em `data/rpc/`. O domínio só conhece
/// **esta interface** — não sabe que existe `dart:io`, stdin/stdout ou JSON.
///
/// MVP (plano 37): um único processo por gateway — multiplexação (N panes) é
/// adiada. `events` é um stream broadcast que persiste pela vida do gateway
/// (sobrevive a `spawn`/`kill` sucessivos).
abstract class RpcProcessGateway implements Service {
  /// Stream tipado de eventos do stdout do agente. Broadcast: a `ui/` assina
  /// e re-assina entre spawns sem perder o controller.
  Stream<RpcEvent> get events;

  /// Há um agente vivo nesta sessão?
  bool get isRunning;

  /// Pasta do agente atual (cwd do child), ou `null` se nenhum.
  String? get workingDirectory;

  /// Sobe um `pi --mode rpc` puro em [workingDirectory]. Falha se já houver um
  /// agente vivo (dedup é responsabilidade de quem chama, no MVP single-pane).
  ///
  /// [environment] é **fundido** com o ambiente do processo pai — variáveis
  /// ausentes aqui são herdadas normalmente. Use para injetar
  /// `REMOTE_PI_DIRECT_CONFIG` sem perder PATH/HOME/etc.
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
  });

  /// Envia um prompt do usuário pelo stdin. Se [steerIfBusy], anexa
  /// `streamingBehavior: "steer"` para enfileirar durante streaming. [images]
  /// viram o campo `images` do comando (anexos de visão).
  Future<Result<void, RpcError>> sendPrompt(
    String message, {
    bool steerIfBusy = false,
    List<PromptImage> images = const <PromptImage>[],
  });

  /// Mata o child limpo: fecha o stdin (encerramento gracioso, code 0) e só
  /// escala para SIGTERM/SIGKILL se ele não sair. Sem processo órfão.
  Future<void> kill();

  // --- Comandos request/response (correlacionados por `id`) ----------------

  /// `get_available_models` — catálogo de modelos configurados.
  Future<Result<List<PiModel>, RpcError>> availableModels();

  /// `get_commands` — slash commands disponíveis (vêm das extensions).
  Future<Result<List<PiCommand>, RpcError>> commands();

  /// `get_state` — recorte do estado atual (modelo + effort + streaming).
  Future<Result<AgentSnapshot, RpcError>> state();

  /// `set_model` — troca o modelo ativo; devolve o modelo aplicado.
  Future<Result<PiModel, RpcError>> setModel(PiModel model);

  /// `set_thinking_level` — ajusta o effort de raciocínio.
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level);

  /// `abort` — interrompe o turno atual **sem** matar o processo.
  Future<Result<void, RpcError>> abort();

  /// `new_session` — começa uma sessão nova (zera a conversa do agente).
  Future<Result<void, RpcError>> newSession();

  /// `compact` — compacta o contexto da sessão atual.
  Future<Result<void, RpcError>> compact();

  /// `switch_session` — carrega uma sessão salva do pi (por caminho).
  Future<Result<void, RpcError>> switchSession(String sessionPath);

  /// `get_messages` — mensagens da sessão atual, já mapeadas pro transcript.
  Future<Result<List<TranscriptMessage>, RpcError>> getMessages();

  /// `get_session_stats` — uso da janela de contexto (pode ser `null`).
  Future<Result<ContextUsage?, RpcError>> sessionStats();
}
