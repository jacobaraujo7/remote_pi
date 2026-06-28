import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';

/// Executa tasks num PTY, reusando a mecânica de spawn/stream/kill do cockpit.
/// Contrato no domínio; a impl (`data/`) usa `kyroon_pty`. A `ui/` só conhece
/// esta interface (via ViewModel).
abstract class TaskRunnerGateway {
  /// Stream de estados vivos de TODAS as tasks (uma emissão por transição).
  Stream<TaskRun> runs();

  /// Bytes do stdout/stderr de uma task — alimenta o CockpitTerminal dela.
  /// Stream vazio se a task não está rodando.
  Stream<List<int>> output(String taskId);

  /// Estado atual conhecido de uma task (idle se nunca rodou).
  TaskRun runOf(String taskId);

  /// Spawna [def] com o [profileName] escolhido (+ [adHocArgs] de uma execução
  /// só). Idempotente: se já roda, é no-op.
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
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
