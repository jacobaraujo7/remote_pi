import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/terminal_profile.dart';
import 'package:kyroon_pty/kyroon_pty.dart';

/// PTY nativo via `kyroon_pty`. Roda o `{executable, args}` do
/// [TerminalProfile] recebido num pseudo-terminal — **qual** shell abrir é
/// decisão do `TerminalProfileResolver` (plano 50), não daqui.
class PtyTerminalGateway implements TerminalGateway {
  Pty? _pty;

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {
    _pty = Pty.start(
      profile.executable,
      arguments: profile.args,
      workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
      environment: _terminalEnv(extraEnv),
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

  /// Ambiente do PTY: herda o do app e **anuncia as capacidades do terminal**
  /// que o emulador realmente tem, mas que ninguém declarava.
  ///
  /// - `TERM=xterm-256color`: o `xterm` (pacote Flutter) emula um xterm de 256
  ///   cores. Fixamos explícito em vez de depender do default do `kyroon_pty`
  ///   (que só preenche se ausente) — ao abrir pelo Finder, o `.app` não herda
  ///   `TERM` algum e TUIs ncurses degradam.
  /// - `COLORTERM=truecolor`: **a correção central pra "as cores saem um pouco
  ///   diferentes".** O emulador pinta RGB 24-bit (SGR `38;2;r;g;b`), mas sem
  ///   esta var os harnesses TUI (claude, codex, vim, lazygit…) assumem que o
  ///   terminal não tem truecolor e rebaixam pra aproximações de 256 cores —
  ///   exatamente o que iTerm/Terminal.app evitam ao anunciá-la.
  ///
  /// O `kyroon_pty` faz `addAll(environment)` por último, então estes overrides
  /// vencem o que veio herdado.
  Map<String, String> _terminalEnv(Map<String, String> extraEnv) => {
    ...Platform.environment,
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
    ...extraEnv,
  };
}
