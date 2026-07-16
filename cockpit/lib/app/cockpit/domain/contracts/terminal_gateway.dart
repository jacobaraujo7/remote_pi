import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';

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

  /// Bytes do stdout/stderr do shell.
  Stream<List<int>> get output;

  /// Escreve no stdin do shell (teclado).
  void write(List<int> data);

  /// Redimensiona o PTY.
  void resize(int rows, int columns);

  /// Mata o shell limpo (sem órfão).
  Future<void> kill();
}
