import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';

/// Executa tasks num PTY, reusando a mecânica de spawn/stream/kill do cockpit.
/// Contrato no domínio; a impl (`data/`) usa `kyroon_pty`. A `ui/` só conhece
/// esta interface (via ViewModel).
/// URL de preview detectada no output de uma task (plano 58) — o shell abre o
/// navegador embutido nela (ou o browser do SO, sem webview inline).
class TaskPreviewUrl {
  const TaskPreviewUrl(this.taskId, this.url);
  final String taskId;
  final String url;
}

/// URL de sessão de uma execução (DevTools etc.). [url] vazia invalida a
/// sessão desta task — stop, restart ou uma execução que ainda não anunciou
/// o serviço. Não abre sozinha; a UI oferece a ação.
class TaskSessionUrl {
  const TaskSessionUrl(this.taskId, this.url);
  final String taskId;
  final String url;
}

abstract class TaskRunnerGateway {
  /// Stream de estados vivos de TODAS as tasks (uma emissão por transição).
  Stream<TaskRun> runs();

  /// Primeira URL local detectada no output de cada run (ou a `previewUrl`
  /// fixa da task, no start). No máximo uma emissão por execução; tasks com
  /// `preview: false` nunca emitem.
  Stream<TaskPreviewUrl> previewUrls();

  /// URL de sessão por task. Emite de novo quando a URL muda e emite [url]
  /// vazia quando a execução acaba ou recomeça. O runner remoto não emite:
  /// o endereço é o loopback do host.
  Stream<TaskSessionUrl> sessionUrls();

  /// URL de sessão corrente, se esta execução ainda a tem. Null depois do
  /// stop/restart até o output novo anunciar outra.
  String? sessionUrlOf(String taskId);

  /// Texto decodificado do stdout/stderr de uma task — alimenta o terminal.
  /// Stream vazio se a task não está rodando.
  Stream<String> output(String taskId);

  /// Estado atual conhecido de uma task (idle se nunca rodou).
  TaskRun runOf(String taskId);

  /// Spawna [def] com o [profileName] escolhido (+ [adHocArgs] de uma execução
  /// só). Idempotente: se já roda, é no-op.
  ///
  /// [argsOverride], quando não-nulo, substitui o argv resolvido (profile +
  /// ad-hoc) pelo que o preparador de ferramenta já montou. [restart] reusa
  /// o argv desta execução — o device não muda no meio do processo.
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
    List<String>? argsOverride,
  });

  /// Mata a task limpo (SIGTERM → timeout → SIGKILL).
  Future<void> stop(String taskId);

  /// Stop + start com o mesmo profile.
  Future<void> restart(String taskId);

  /// Escreve uma [InteractiveKey.key] no stdin do PTY (ex.: `"r"` no Flutter).
  void sendKey(String taskId, String key);

  /// Começa a observar os arquivos de [def] (`def.watch`) e, a cada mudança
  /// (com debounce), dispara a ação `onChange` — a tecla interativa de mesmo
  /// label, ou um restart. No-op se `def.watch` é null ou já observa. É o
  /// "reload ao salvar" que o `flutter run` CLI não faz sozinho.
  void startWatch(TaskDefinition def);

  /// Para de observar os arquivos da task (toggle off, stop ou exit).
  void stopWatch(String taskId);

  /// Redimensiona o PTY da task (o terminal informa linhas/colunas).
  void resize(String taskId, int rows, int columns);

  /// Mata tudo e libera recursos (chamado no dispose do app).
  Future<void> disposeAll();
}

/// Optional capability implemented by local runners that can reconcile
/// processes not parented by Cockpit. Keeping it separate preserves source
/// compatibility for third-party and remote [TaskRunnerGateway] implementors.
abstract interface class ReconciledTaskRunnerGateway {
  Future<void> reconcileDefinitions(List<TaskDefinition> definitions);
  Future<void> attachOutput(String taskId);
}
