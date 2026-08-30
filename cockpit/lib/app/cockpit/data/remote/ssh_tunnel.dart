import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';

/// Túnel SSH para o socket do `cockpit-server` de um host remoto (plano 58,
/// Wave 2, decisão G): usa o binário `ssh` DO SISTEMA — nada de biblioteca
/// SSH nem crypto nossa. `~/.ssh/config`, chaves, agent e ProxyJump valem de
/// graça; se `ssh <target>` funciona no terminal do usuário, funciona aqui.
///
/// O forward é de socket UDS→UDS: o servidor remoto escuta só em localhost
/// (nunca expõe porta de rede) e este túnel materializa aquele socket num
/// path local. Pro cliente, o resultado é indistinguível do loopback.
/// UTF-8 que não estoura em byte inválido — ver o comentário em [capture].
const _lenientUtf8 = Utf8Decoder(allowMalformed: true);

class SshTunnel {
  SshTunnel._(
    this._process,
    this.localSocketPath,
    this.target, {
    this.localPort,
  });

  final Process _process;

  /// Socket local que espelha o socket remoto do cockpit-server. Vazio quando
  /// a ponta local é TCP (Windows — ver [localPort]).
  final String localSocketPath;

  /// Porta de loopback que espelha o socket remoto, no Windows.
  ///
  /// O OpenSSH do Windows não faz forward de socket UNIX na ponta LOCAL, e o
  /// caminho nem chega a ser parseado: `-L C:\...\x.sock:/home/u/y.sock` morre
  /// em `Bad local forwarding specification`, porque o `C:` já é um separador
  /// pro parser. A forma suportada é `-L 127.0.0.1:<porta>:<socket remoto>` —
  /// TCP local → UDS remoto, que o OpenSSH faz desde a 6.7. O lado REMOTO
  /// continua sendo o socket UNIX de sempre: nada muda no host.
  final int? localPort;

  /// A ponta local é TCP (Windows) em vez de socket UNIX.
  bool get usesTcpEndpoint => localPort != null;
  final String target;

  final Completer<void> _closed = Completer();

  /// Completa quando o túnel cair (queda de rede, ssh morto). Quem observa
  /// decide reconectar (banner "reconnecting" na UI, decisão de UX da W2).
  Future<void> get closed => _closed.future;

  bool get isOpen => !_closed.isCompleted;

  /// Sobe o túnel e espera o socket local ficar conectável.
  ///
  /// Auth por CHAVE (default, [password] null): `BatchMode=yes` — falha alto se
  /// o ssh precisar de senha (a UI mostra o erro tipado). Auth por SENHA
  /// ([password] setado, plano 60 Wave C): injeta a senha via `SSH_ASKPASS`
  /// (helper efêmero 0600) e aceita host key nova (`accept-new`); nada de senha
  /// em argv nem em variável de ambiente.
  ///
  /// [remote] descreve a PONTA REMOTA, já resolvida pelo dialeto do host
  /// (`HostShell.readEndpoint`): socket UNIX num host POSIX, porta de loopback
  /// num host Windows. As duas pontas são independentes — as quatro
  /// combinações existem, e um cliente Windows falando com host Windows é TCP
  /// dos dois lados.
  static Future<SshTunnel> open({
    required String target,
    required RemoteEndpoint remote,
    int port = 22,
    String? password,
    String? identityFile,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Ponta local: socket UNIX no POSIX; porta de loopback no Windows.
    final useTcp = Platform.isWindows;
    final localPath = useTcp
        ? ''
        : '${Directory.systemTemp.path}/cockpit-ssh-'
              '${DateTime.now().microsecondsSinceEpoch}.sock';
    // Porta livre pedida ao SO e devolvida na hora. Há uma janela em que outro
    // processo pode tomá-la; `ExitOnForwardFailure=yes` faz o ssh morrer alto
    // nesse caso, em vez de fingir que o túnel subiu.
    final localTcpPort = useTcp ? await _freeLoopbackPort() : null;

    final askpass = await _Askpass.create(password);
    final authOpts = _authOpts(
      port: port,
      usingPassword: password != null,
      identityFile: identityFile,
    );

    try {
      // Ponta remota, no formato que o `-L` espera. O `$HOME` já vem resolvido
      // de fora: o forward streamlocal do OpenSSH NÃO expande `~`/`$HOME`, e
      // resolvê-lo aqui custava um `Process.run` extra que, num host Windows,
      // ainda estourava `FormatException` ao decodificar o erro do `cmd` em
      // CP-850 (o `systemEncoding` do macOS/Linux é UTF-8 estrito).
      final remoteSpec = switch (remote) {
        UnixSocketEndpoint(:final path) => path,
        TcpEndpoint(:final port) => '127.0.0.1:$port',
      };

      final process = await Process.start('ssh', [
        '-N', // só forward, sem shell
        ...authOpts,
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=10',
        '-o', 'ServerAliveCountMax=3',
        // Só faz sentido com socket UNIX local (remove o inode órfão).
        if (!useTcp) ...['-o', 'StreamLocalBindUnlink=yes'],
        '-L',
        useTcp
            ? '127.0.0.1:$localTcpPort:$remoteSpec'
            : '$localPath:$remoteSpec',
        target,
      ], environment: askpass?.env);

      final stderrBuffer = StringBuffer();
      process.stderr.transform(_lenientUtf8).listen(stderrBuffer.write);
      unawaited(process.stdout.drain<void>());

      final tunnel = SshTunnel._(
        process,
        localPath,
        target,
        localPort: localTcpPort,
      );
      unawaited(
        process.exitCode.then((_) {
          if (!tunnel._closed.isCompleted) tunnel._closed.complete();
        }),
      );

      // Pronto = socket local existe E o ssh não morreu. Não dá pra "testar"
      // conectando aqui: o forward UDS só valida o lado remoto na 1ª conexão
      // de verdade, então erros de destino aparecem na conexão do protocolo.
      final deadline = DateTime.now().add(timeout);
      while (!await _tunnelReady(localPath, localTcpPort)) {
        if (tunnel._closed.isCompleted) {
          throw SshTunnelException(stderrBuffer.toString().trim());
        }
        if (DateTime.now().isAfter(deadline)) {
          process.kill();
          throw SshTunnelException(
            'timeout waiting for tunnel; ${stderrBuffer.toString().trim()}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return tunnel;
    } finally {
      // Auth já ocorreu (o socket apareceu, ou falhou/estourou) — o helper de
      // senha não é mais necessário. Removê-lo evita deixar a senha no disco.
      await askpass?.dispose();
    }
  }

  /// O forward já está de pé? No POSIX basta o socket local existir; no
  /// Windows, o sinal equivalente é a porta aceitar conexão (o ssh só binda
  /// depois de autenticar). Nos dois casos o destino remoto só é validado na
  /// primeira conexão de verdade, feita pelo protocolo.
  static Future<bool> _tunnelReady(String localPath, int? port) async {
    if (port == null) return File(localPath).existsSync();
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      probe.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  /// Porta de loopback livre: abre em `:0`, lê a porta e fecha.
  static Future<int> _freeLoopbackPort() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    return port;
  }

  /// Teto do connect TCP de QUALQUER invocação do ssh daqui.
  ///
  /// Sem isto, um host desligado cujo pacote é DESCARTADO (em vez de recusado)
  /// deixa o `ssh` pendurado sem limite prático — e o `Process.run` que resolve
  /// a `$HOME` remota, por acontecer ANTES do laço com deadline lá em [open],
  /// travava a abertura para sempre: a UI ficava eternamente em "conectando",
  /// sem nunca falhar nem entrar no ciclo de retry.
  static const int _connectTimeoutSeconds = 10;

  /// Opções de auth comuns aos execs/forward: porta custom + teto de connect +
  /// BatchMode (chave) ou aceite de host key novo (senha, via SSH_ASKPASS).
  static List<String> _authOpts({
    required int port,
    required bool usingPassword,
    String? identityFile,
  }) => [
    if (port != 22) ...['-p', '$port'],
    // Chave escolhida no cadastro: `IdentitiesOnly` impede o ssh de oferecer
    // também as do agent/config antes dela — numa máquina com muitas chaves
    // isso estoura o `MaxAuthTries` do servidor e a conexão morre em "too many
    // authentication failures" sem nunca ter tentado a certa.
    if (identityFile != null && identityFile.isNotEmpty) ...[
      '-i',
      identityFile,
      '-o',
      'IdentitiesOnly=yes',
    ],
    '-o',
    'ConnectTimeout=$_connectTimeoutSeconds',
    if (usingPassword) ...[
      '-o',
      'StrictHostKeyChecking=accept-new',
      // Senha escolhida no cadastro = senha É o método, não o fallback.
      //
      // Sem isto o ssh tenta publickey ANTES (agent + `~/.ssh/id_*` + o que o
      // `~/.ssh/config` mandar) e o `SSH_ASKPASS` nunca chega a ser chamado:
      // ou uma chave qualquer entra (e o host conecta como outro usuário do
      // que o cadastro diz), ou as tentativas estouram o `MaxAuthTries` do
      // servidor e a conexão morre em "Too many authentication failures" /
      // "Permission denied (publickey)" — com a senha guardada intacta,
      // nunca oferecida. Era exatamente o caso de quem cadastra com senha
      // JUSTAMENTE porque a chave não serve.
      '-o',
      'PubkeyAuthentication=no',
      '-o',
      'PreferredAuthentications=password,keyboard-interactive',
      // O helper devolve sempre a MESMA senha: repetir 3x só atrasa o erro
      // (e conta 3 falhas no log/fail2ban do host).
      '-o',
      'NumberOfPasswordPrompts=1',
    ] else ...[
      '-o',
      'BatchMode=yes',
    ],
  ];

  /// Executa um comando no host remoto pelo MESMO ssh do sistema (usado pelo
  /// bootstrap "Install server"). Retorna (exitCode, stderr).
  static Future<(int, String)> run(
    String target,
    String command, {
    List<int>? stdinBytes,
    int port = 22,
    String? password,
    String? identityFile,
  }) async {
    final (code, _, stderrText) = await capture(
      target,
      command,
      stdinBytes: stdinBytes,
      port: port,
      password: password,
      identityFile: identityFile,
    );
    return (code, stderrText);
  }

  /// Igual a [run], mas devolve TAMBÉM o stdout do comando remoto — precisa
  /// dele quem interroga o host (`uname -sm` na escolha do binário do
  /// bootstrap) ou lê o log de um servidor que não subiu.
  static Future<(int, String, String)> capture(
    String target,
    String command, {
    List<int>? stdinBytes,
    int port = 22,
    String? password,
    String? identityFile,
  }) async {
    final askpass = await _Askpass.create(password);
    try {
      final process = await Process.start('ssh', [
        ..._authOpts(
          port: port,
          usingPassword: password != null,
          identityFile: identityFile,
        ),
        target,
        command,
      ], environment: askpass?.env);
      if (stdinBytes != null) {
        process.stdin.add(stdinBytes);
      }
      await process.stdin.close();
      // Os dois streams em paralelo: ler um de cada vez trava se o outro
      // encher o pipe (o `cat` do push manda MBs pelo canal).
      // Decodificação TOLERANTE: um host Windows responde na codepage local
      // (CP850/CP1252), não em UTF-8 — a mensagem acentuada do cmd ("'uname'
      // não é reconhecido…") estourava `FormatException: Missing extension
      // byte` e escondia o erro de verdade atrás de um erro de decodificação.
      final outFuture = process.stdout.transform(_lenientUtf8).join();
      final errFuture = process.stderr.transform(_lenientUtf8).join();
      final stdoutText = await outFuture;
      final stderrText = await errFuture;
      final code = await process.exitCode;
      return (code, stdoutText.trim(), stderrText.trim());
    } finally {
      await askpass?.dispose();
    }
  }

  Future<void> close() async {
    _process.kill();
    await _closed.future;
    if (localSocketPath.isEmpty) return; // ponta TCP: nada a remover.
    try {
      File(localSocketPath).deleteSync();
    } catch (_) {
      // já removido.
    }
  }
}

/// Injeção de senha no `ssh` do sistema via `SSH_ASKPASS` (plano 60, Wave C).
/// Escreve a senha num arquivo temporário 0600 e um helper 0700 que faz `cat`
/// dele; o ssh chama o helper quando pede a senha. `SSH_ASKPASS_REQUIRE=force`
/// (OpenSSH 8.4+) dispensa tty/DISPLAY. A senha nunca vai pra argv nem env — só
/// pro arquivo protegido, apagado em [dispose] após a autenticação.
class _Askpass {
  _Askpass._(this._pwFile, this._helper, this.env);

  final File _pwFile;
  final File _helper;
  final Map<String, String> env;

  static Future<_Askpass?> create(String? password) async {
    if (password == null || password.isEmpty) return null;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = Directory.systemTemp.path;
    final pwFile = File('$base/cockpit-ssh-pw-$stamp');
    await pwFile.writeAsString(password, flush: true);
    final helper = File('$base/cockpit-ssh-askpass-$stamp.sh');
    await helper.writeAsString(
      '#!/bin/sh\ncat "${pwFile.path}"\n',
      flush: true,
    );
    await Process.run('chmod', ['600', pwFile.path]);
    await Process.run('chmod', ['700', helper.path]);
    return _Askpass._(pwFile, helper, {
      'SSH_ASKPASS': helper.path,
      'SSH_ASKPASS_REQUIRE': 'force',
      // Fallback pra OpenSSH < 8.4 (que exige DISPLAY setado pra usar askpass).
      'DISPLAY': ':0',
    });
  }

  Future<void> dispose() async {
    try {
      if (_pwFile.existsSync()) _pwFile.deleteSync();
      if (_helper.existsSync()) _helper.deleteSync();
    } catch (_) {
      // já removido.
    }
  }
}

/// Erro de transporte SSH. `detail` é stderr cru do ssh — exibido
/// interpolado na frase traduzida da UI, nunca traduzido (regra de i18n).
class SshTunnelException implements Exception {
  const SshTunnelException(this.detail);
  final String detail;

  @override
  String toString() => 'SshTunnelException($detail)';
}
