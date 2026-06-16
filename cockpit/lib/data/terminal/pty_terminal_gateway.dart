import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/domain/contracts/terminal_gateway.dart';
import 'package:kyroon_pty/kyroon_pty.dart';

/// PTY nativo via `kyroon_pty`. Roda o shell real do SO num pseudo-terminal.
class PtyTerminalGateway implements TerminalGateway {
  Pty? _pty;

  @override
  void start({
    required String workingDirectory,
    int rows = 25,
    int columns = 80,
  }) {
    _pty = Pty.start(
      _shell(),
      arguments: _shellArgs(),
      workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
      environment: Map<String, String>.of(Platform.environment),
      rows: rows,
      columns: columns,
    );
  }

  @override
  Stream<List<int>> get output =>
      _pty?.output ?? const Stream<List<int>>.empty();

  @override
  void write(List<int> data) =>
      _pty?.write(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void resize(int rows, int columns) => _pty?.resize(rows, columns);

  @override
  Future<void> kill() async {
    try {
      _pty?.kill();
    } catch (_) {
      // já encerrado.
    }
  }

  /// Shell por plataforma.
  String _shell() {
    if (Platform.isWindows) {
      // ARM: mantém cmd.exe (o spawn de PTY do powershell ainda é instável no
      // Windows ARM). Demais Windows (x64): powershell.exe como default.
      if (_isWindowsArm) return Platform.environment['COMSPEC'] ?? 'cmd.exe';
      return 'powershell.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }

  /// Argumentos do shell.
  ///
  /// macOS/Linux: `-l` (**login shell**), igual ao Terminal.app/iTerm. Sem isso
  /// um app GUI aberto pelo Finder/Dock herda só o PATH mínimo
  /// (`/usr/bin:/bin:/usr/sbin:/sbin`) e um shell não-login carrega apenas o
  /// `.zshrc` — perdendo o `.zprofile`/`/etc/zprofile` (onde `path_helper` lê
  /// `/etc/paths.d/*` e o `brew shellenv`/Docker/.NET injetam seus diretórios).
  /// Resultado: `node`, `npm`, `dotnet`, `docker` "não encontrados". Como o PTY
  /// já anexa um tty, o shell também é interativo → o `.zshrc` (nvm) entra junto.
  ///
  /// Windows: cmd/powershell herdam o PATH do registro mesmo via GUI — sem flag.
  List<String> _shellArgs() {
    if (Platform.isWindows) return const [];
    return const ['-l'];
  }

  /// Arquitetura do build (ex.: `... on "windows_arm64"`) — fonte confiável da
  /// arch do app nativo, ao contrário de `PROCESSOR_ARCHITECTURE` (que reporta
  /// emulação WOW). Casa `arm`/`arm64`.
  bool get _isWindowsArm => Platform.version.toLowerCase().contains('arm');
}
