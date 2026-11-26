import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';

/// Pseudo-terminal nativo (PTY) rodando um shell. Contrato no domínio; a impl
/// (`data/terminal/`) usa `flutter_pty` (forkpty no macOS/Linux, ConPTY no
/// Windows). A `ui/` (TerminalSession) só conhece esta interface.
abstract class TerminalGateway {
  /// Sobe o [profile] num PTY na pasta [workingDirectory]. [extraEnv] é fundido
  /// ao ambiente do PTY (ex.: `COCKPIT_PANE_ID`/`COCKPIT_STATUS_SOCK` pra que o
  /// `cockpit-hook` do claude reporte status de volta).
  ///
  /// O gateway **não** sabe o que é "WSL"/"PowerShell"/login shell: só executa o
  /// `{executable, args}` do [profile], montado pelo `TerminalProfileResolver`
  /// (plano 50).
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  });

  /// Pasta em que o shell de fato nasceu, disponível depois de [start].
  /// `fellBack == true` quando o [workingDirectory] pedido não existia; a `ui/`
  /// usa pra avisar em vez de o usuário achar que abriu no lugar certo.
  /// `null` = gateway que não spawna processo (fakes de teste).
  SpawnDirectory? get spawnDirectory => null;

  /// PID do processo raiz do PTY (geralmente o shell), disponível após [start].
  /// `null` em gateways que não iniciam processo real ou antes de [start].
  int? get rootProcessId => null;

  /// PID inside the selected WSL distro, if the gateway can establish one.
  /// This is a different PID namespace from [rootProcessId], which is the
  /// Windows `wsl.exe` PID for a WSL terminal.
  int? get wslProcessId => null;


  /// Bytes do stdout/stderr do shell.
  Stream<List<int>> get output;

  /// Escreve no stdin do shell (teclado).
  void write(List<int> data);

  /// Redimensiona o PTY.
  void resize(int rows, int columns);

  /// Mata o shell limpo (sem órfão).
  Future<void> kill();

  /// Libera o próximo chunk do PTY quando o spawn usa backpressure (`ackRead`).
  /// Fakes / gateways sem flow control devem implementar como no-op.
  void acknowledgeOutput();
}

/// Optional capability for a gateway whose PTY runs on another machine.
abstract interface class RemoteProcessMetricsGateway {
  Future<ProcessMetricsSnapshot> readRemoteProcessMetrics();
}
