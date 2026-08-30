import 'dart:io';

import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';

/// Dialeto POSIX (macOS/Linux) — o bootstrap que existia antes do plano 61,
/// extraído do `RemoteHostConnector` sem mudança de comportamento.
class PosixHostShell extends HostShell {
  PosixHostShell({required super.probe, required super.exec});

  static const _serverDir = r'$HOME/.cockpit/server';

  @override
  String get serverBinaryPath => '$_serverDir/bin/cockpit-server';

  @override
  String get bootLogPath => r'$HOME/.cockpit/server-boot.log';

  /// Caminho do socket, com o `$HOME` deixado para o shell do host expandir.
  static const _socketPath = r'$HOME/.cockpit/cockpit-server.sock';

  @override
  bool get installsFromHostBundle => false;

  /// Determinístico a partir da home já resolvida no probe — sem SSH extra.
  ///
  /// "Não há servidor" NÃO é decidido aqui: quem descobre é o túnel, que falha
  /// ao conectar e leva ao bootstrap. É assim desde o plano 58, e manter
  /// preserva a latência de abertura do caminho POSIX.
  @override
  Future<RemoteEndpoint?> readEndpoint() async =>
      UnixSocketEndpoint('${probe.home}/.cockpit/cockpit-server.sock');

  @override
  Future<RemoteEndpoint?> awaitEndpoint() async {
    // O socket UNIX aparece quando o servidor faz bind. `test -S` é o sinal
    // exato: arquivo comum com o mesmo nome não serviria.
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 150 + attempt * 100));
      final (code, out, _) = await exec(
        'test -S $_socketPath && echo up || echo down',
      );
      if (code == 0 && out.trim().endsWith('up')) return readEndpoint();
    }
    return null;
  }

  @override
  Future<bool> serverInstalled() async {
    final (code, out, _) = await exec(
      'test -x $serverBinaryPath && echo yes || echo no',
    );
    return code == 0 && out.trim().endsWith('yes');
  }

  @override
  Future<String?> serverSha256() async {
    final (code, out, _) = await exec(
      'sha256sum $serverBinaryPath 2>/dev/null || '
      'shasum -a 256 $serverBinaryPath 2>/dev/null',
    );
    if (code != 0) return null;
    final token = out.trim().split(RegExp(r'\s+')).firstOrNull;
    return (token != null && token.length == 64) ? token.toLowerCase() : null;
  }

  @override
  Future<void> killServer() async {
    await exec('pkill -f "$serverBinaryPath" || true');
  }

  @override
  Future<void> installFromClient(ClientBundle bundle) async {
    Future<void> push(String local, String remote) async {
      final bytes = await File(local).readAsBytes();
      final (code, _, err) = await exec(
        'mkdir -p ~/.cockpit/server/bin ~/.cockpit/server/lib && '
        'cat > $remote && chmod +x $remote',
        stdinBytes: bytes,
      );
      if (code != 0) throw HostShellException(err);
    }

    await push(bundle.serverBinary, '~/.cockpit/server/bin/cockpit-server');

    final libDir = Directory('${bundle.root}/lib');
    if (libDir.existsSync()) {
      for (final f in libDir.listSync().whereType<File>()) {
        await push(f.path, '~/.cockpit/server/lib/${_basename(f.path)}');
      }
    }

    // CLI ao lado do servidor: o servidor põe a pasta dela no PATH das PTYs, e
    // é o que faz `cockpit …` responder num terminal remoto. Vai junto em toda
    // (re)instalação, senão ficaria mais velha que o servidor que a invoca.
    final cli = File('${bundle.root}/bin/cockpit');
    if (cli.existsSync()) {
      await push(cli.path, '~/.cockpit/server/bin/cockpit');
      // Alias curto: symlink, que no POSIX custa zero em disco.
      await exec('ln -sf cockpit ~/.cockpit/server/bin/ck');
    }
  }

  @override
  Future<bool> installFromHost() async => false;

  @override
  Future<void> startServer({required int idleSeconds}) async {
    final ptyLib = probe.os == 'darwin'
        ? 'libcockpit_pty.dylib'
        : 'libcockpit_pty.so';
    // nohup + redirects: o servidor sobrevive ao fim desta sessão ssh. A saída
    // vai pra um LOG, não pro /dev/null: um servidor que morre no arranque
    // (arquitetura errada, dylib faltando) precisa deixar rastro — sem isso o
    // `echo started` saía 0 e a falha chegava na UI como silêncio.
    final (code, _, err) = await exec(
      'COCKPIT_PTY_DYLIB=\$HOME/.cockpit/server/lib/$ptyLib '
      'nohup $serverBinaryPath '
      '--socket $_socketPath '
      '--exit-on-idle $idleSeconds '
      '--idle-keeps-sessions '
      '>$bootLogPath 2>&1 & echo started',
    );
    if (code != 0) throw HostShellException(err);
  }

  @override
  Future<String> tailBootLog({int bytes = 2000}) async {
    final (_, out, _) = await exec(
      'tail -c $bytes $bootLogPath 2>/dev/null || true',
    );
    return out;
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}

/// Falha crua do host (stderr de terceiros). Vira `detail` de um
/// `RemoteHostException` tipado na borda — nunca frase de usuário.
class HostShellException implements Exception {
  const HostShellException(this.detail);
  final String detail;

  @override
  String toString() => 'HostShellException($detail)';
}
