import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import 'package:cockpit/app/cockpit/data/remote/dartssh_host_connection.dart';
import 'package:cockpit/app/cockpit/data/remote/ssh_channel_duplex.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/posix_host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/windows_host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/ssh_known_hosts.dart';
import 'package:cockpit/app/cockpit/data/remote/ssh_tunnel.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
// O motor de túnel de BANCO também exporta `SshTunnel`/`SshTunnelException`,
// e este arquivo tem os seus próprios (o túnel do HOST remoto, outra coisa).
// Esconde os do banco: aqui só interessam os tipos de host key.
import 'package:cockpit_core/cockpit_core.dart'
    hide SshTunnel, SshTunnelImpl, SshTunnelException;
import 'package:cockpit_remote/cockpit_remote.dart';

/// Estado observável da conexão com um host (badge/telas da UI, plano 58).
enum RemoteHostPhase {
  idle,
  openingTunnel,
  installingServer,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// Falha tipada da abertura (a frase nasce na UI via context.t; `detail` é
/// texto cru de terceiros: stderr do ssh, mensagem de socket).
enum RemoteHostErrorKind {
  sshUnreachable,
  serverInstallFailed,
  versionMismatch,
  protocol,

  /// Host nunca visto e o humano não confiou na chave (recusou, ou não havia
  /// ninguém pra perguntar). Antes disto o `ssh` só dizia `Host key
  /// verification failed` e não havia caminho nenhum pela GUI.
  hostKeyUnknown,

  /// Host Windows sem Cockpit instalado. Lá a instalação do servidor é cópia
  /// LOCAL do `cockpit-server-bundle` que o app deixa (decisão D2 do plano
  /// 61) — nenhum binário viaja pelo SSH, e por isso um cliente macOS instala
  /// num host Windows. Sem o app no host, não há o que copiar.
  hostBundleMissing,

  /// Não foi possível identificar o sistema do host: nem `uname` nem o probe
  /// de PowerShell responderam. Normalmente shell restrito ou conta sem shell.
  hostUnknownOs,

  /// O host apresenta chave diferente da que está no `known_hosts`. Não existe
  /// aceite inline: ou é troca legítima de servidor (o usuário edita o
  /// known_hosts) ou é ataque.
  hostKeyChanged,
}

class RemoteHostException implements Exception {
  const RemoteHostException(this.kind, [this.detail]);
  final RemoteHostErrorKind kind;
  final String? detail;

  @override
  String toString() => 'RemoteHostException(${kind.name}: $detail)';
}

/// Conecta a um [RemoteHost] via túnel SSH e entrega o [TerminalService]
/// remoto daquele host (plano 58, Wave 2).
///
/// Fluxo de abertura (as fases alimentam o loading progressivo da UI):
/// 1. túnel SSH pro socket do cockpit-server remoto;
/// 2. conexão + handshake; se o servidor não existe lá, **bootstrap pelo
///    próprio SSH** (Install server): sobe binário + dylib do bundle local e
///    inicia o servidor remoto;
/// 3. serviço pronto. Queda do túnel → [phase] = reconnecting e retry com
///    backoff; sessões sobrevivem no servidor remoto (semântica tmux).
class RemoteHostConnector {
  RemoteHostConnector(
    this.host, {
    required this.localServerBinaryResolver,
    this.passwordResolver,
    this.hostKeyPrompt,
    this.knownHosts = const SshKnownHosts(),
  });

  final RemoteHost host;

  /// Resolve o binário local do cockpit-server (o mesmo do sidecar) usado como
  /// fonte do bootstrap, para a arquitetura pedida (`arm64` | `x64`). Quem
  /// manda é o `uname -sm` DO HOST, não a arquitetura desta máquina: um bundle
  /// macOS traz as duas fatias, e mandar a errada instalava um binário que o
  /// host não executa — falha que só aparecia como "não conectou".
  final String? Function({String? arch}) localServerBinaryResolver;

  /// Resolve a senha SSH do host (auth por senha), lida do Keychain sob
  /// demanda. `null` = auth por chave (default). Plano 60, Wave C.
  final Future<String?> Function()? passwordResolver;

  /// Pergunta ao humano se confia na host key de um destino novo (TOFU),
  /// mostrando o fingerprint. `null` = ninguém pra perguntar (testes, CLI) →
  /// host novo falha com [RemoteHostErrorKind.hostKeyUnknown] em vez de ser
  /// aceito em silêncio.
  final HostKeyPrompt? hostKeyPrompt;

  /// Acesso ao `known_hosts` do usuário (injetável nos testes).
  final SshKnownHosts knownHosts;

  SshTunnel? _tunnel;
  DartSshHostConnection? _dartConn;

  /// Status de turno (spinner/chime) vindo do host pelo protocolo (Wave G).
  /// Reassina a cada (re)conexão; broadcast pra o controller repassar à VM.
  final _turnStatus = StreamController<RemoteTurnStatus>.broadcast();
  StreamSubscription<RemoteTurnStatus>? _turnSub;
  Stream<RemoteTurnStatus> get turnStatus => _turnStatus.stream;

  /// Comandos da CLI `cockpit` rodando no host, encaminhados pelo servidor.
  /// Mesmo caminho do [turnStatus]: reassina a cada (re)conexão.
  final _cliCommands = StreamController<RemoteCliCommand>.broadcast();
  StreamSubscription<RemoteCliCommand>? _cliSub;
  Stream<RemoteCliCommand> get cliCommands => _cliCommands.stream;

  void _bindTurnStatus() {
    _turnSub?.cancel();
    _turnSub = _service?.turnStatus.listen(_turnStatus.add);
    _cliSub?.cancel();
    _cliSub = _service?.cliCommands.listen(_cliCommands.add);
  }

  /// Senha resolvida na abertura atual (auth por senha); só em memória.
  String? _password;
  RemoteConnection? _connection;
  RemoteTerminalService? _service;
  Future<RemoteTerminalService>? _inflight;

  final StreamController<RemoteHostPhase> _phases =
      StreamController.broadcast();
  RemoteHostPhase phase = RemoteHostPhase.idle;

  Stream<RemoteHostPhase> get phases => _phases.stream;

  void _setPhase(RemoteHostPhase value) {
    phase = value;
    _phases.add(value);
  }

  /// Serviço de terminais do host, abrindo (ou reabrindo) a conexão se
  /// preciso. Lança [RemoteHostException] tipada em falha de abertura.
  Future<RemoteTerminalService> ensure() {
    final connection = _connection;
    if (connection != null && connection.isOpen) {
      return Future.value(_service!);
    }
    return _inflight ??= _open()
        .then((service) {
          // TODA reabertura bem-sucedida anuncia o serviço novo — não só a que
          // vem do retry/botão. Os gateways de terminal dependem deste evento
          // pra trocar o serviço e re-anexar; quando ele só saía pelo caminho
          // do retry, uma reconexão disparada por qualquer outra ação deixava as
          // abas presas ao serviço morto (teclado mudo).
          _retryStep = 0;
          if (!_disposed) _reconnected.add(service);
          return service;
        })
        .catchError((Object e) {
          // Falha de ABERTURA (host offline, SSH recusado, server ausente)
          // também entra no ciclo de retry. Sem isto, só a queda de um túnel já
          // estabelecido reagendava — e o caso mais comum, tentar abrir um host
          // que está fora do ar, ficava parado em `failed` para sempre.
          _scheduleRetry();
          throw e;
        })
        .whenComplete(() => _inflight = null);
  }

  /// Serviço de arquivos do host (mesma conexão dos terminais). Conecta se
  /// preciso; usado pelo picker de pasta remota.
  Future<RemoteFileService> fileService() async {
    await ensure();
    return RemoteFileService(_connection!);
  }

  /// Serviço git do host (mesma conexão). Conecta se preciso.
  Future<RemoteGitService> gitService() async {
    await ensure();
    return RemoteGitService(_connection!);
  }

  /// Serviço de DB do host (mesma conexão). Conecta se preciso.
  Future<RemoteDbService> dbService() async {
    await ensure();
    return RemoteDbService(_connection!);
  }

  Future<RemoteTerminalService> _open() async {
    _setPhase(
      phase == RemoteHostPhase.connected
          ? RemoteHostPhase.reconnecting
          : RemoteHostPhase.openingTunnel,
    );
    // Senha (auth por senha) lida do Keychain uma vez por abertura; null =
    // auth por chave. Guardada só em memória, pro bootstrap reusar.
    _password = await passwordResolver?.call();
    // Mobile (plano 59): transporte dartssh2 (Dart puro), sem binário `ssh` nem
    // bootstrap (decisão D — não instala server). Desktop segue no system-ssh.
    if (isMobilePlatform) return _openMobile();
    // Host key ANTES do túnel: com `BatchMode=yes` o ssh não pode perguntar
    // nada, então um destino novo morria em "Host key verification failed" sem
    // caminho pela GUI. Aqui o humano vê o fingerprint e decide.
    await _ensureHostKeyTrusted();

    // Dialeto do host (plano 61). O probe substitui o `printf %s "$HOME"` que
    // o `SshTunnel.open` fazia por conta própria, então o caminho POSIX não
    // paga round-trip novo — só mudou quem pergunta.
    final shell = await _hostShell();

    // Servidor já de pé? No POSIX o endpoint é determinístico e a ausência é
    // descoberta pelo túnel (comportamento de antes); no Windows é o arquivo
    // de rendezvous que responde, e sem ele nem adianta abrir forward.
    var endpoint = await shell.readEndpoint();
    if (endpoint != null) {
      final service = await _connectVia(shell, endpoint);
      if (service != null) return service;
    }

    // Servidor ausente/parado/desatualizado no host: bootstrap pelo SSH.
    _setPhase(RemoteHostPhase.installingServer);
    await _installAndStartServer(shell);
    endpoint = await shell.awaitEndpoint();
    if (endpoint == null) {
      _setPhase(RemoteHostPhase.failed);
      final log = await shell.tailBootLog();
      throw RemoteHostException(
        RemoteHostErrorKind.serverInstallFailed,
        log.isEmpty ? 'server did not start on the host' : log,
      );
    }
    final service = await _connectVia(shell, endpoint, attempts: 20);
    if (service != null) return service;
    _setPhase(RemoteHostPhase.failed);
    throw const RemoteHostException(RemoteHostErrorKind.serverInstallFailed);
  }

  /// Abre o túnel para [endpoint] e completa o handshake. `null` = não havia
  /// servidor atendendo (ou ele estava desatualizado), e o chamador deve
  /// partir para o bootstrap.
  Future<RemoteTerminalService?> _connectVia(
    HostShell shell,
    RemoteEndpoint endpoint, {
    int attempts = 1,
  }) async {
    final SshTunnel tunnel;
    try {
      tunnel = await SshTunnel.open(
        target: host.sshTarget,
        remote: endpoint,
        port: host.port,
        password: _password,
        identityFile: host.effectiveIdentityFile,
      );
    } on SshTunnelException catch (e) {
      _setPhase(RemoteHostPhase.failed);
      // "Host key verification failed" não é host inalcançável: a máquina
      // respondeu, o que falhou foi a confiança. Distinguir importa porque a
      // ação do usuário é outra (conferir o fingerprint, não ligar a máquina).
      if (e.detail.contains('Host key verification failed')) {
        throw RemoteHostException(await _classifyHostKeyFailure(), e.detail);
      }
      throw RemoteHostException(RemoteHostErrorKind.sshUnreachable, e.detail);
    }
    _tunnel = tunnel;
    unawaited(tunnel.closed.then((_) => _onTunnelClosed()));

    _setPhase(RemoteHostPhase.connecting);
    var connection = await _tryProtocol(
      tunnel,
      token: endpoint.token,
      attempts: attempts,
    );
    // Servidor VELHO respondendo: sem esta checagem o cliente conectava nele e
    // pronto — o bootstrap só rodava quando ninguém atendia, então um host
    // instalado uma vez ficava congelado para sempre naquela versão. Uma vez
    // por host por sessão (a comparação custa um SSH).
    if (connection != null && !_serverFreshnessChecked) {
      _serverFreshnessChecked = true;
      if (await _remoteServerIsStale(shell)) {
        _staleServer = true;
        await connection.close();
        connection = null;
      }
    }
    if (connection == null) {
      await tunnel.close();
      _tunnel = null;
      return null;
    }
    _connection = connection;
    _service = RemoteTerminalService(connection);
    _bindTurnStatus();
    _setPhase(RemoteHostPhase.connected);
    return _service!;
  }

  /// Dialeto do host, resolvido uma vez por conector — o sistema de uma máquina
  /// não muda entre reconexões, e o probe custa um SSH.
  HostShell? _shell;

  Future<HostShell> _hostShell() async {
    final cached = _shell;
    if (cached != null) return cached;
    Future<(int, String, String)> exec(
      String command, {
      List<int>? stdinBytes,
    }) => SshTunnel.capture(
      host.sshTarget,
      command,
      stdinBytes: stdinBytes,
      port: host.port,
      password: _password,
      identityFile: host.effectiveIdentityFile,
    );

    final probe = await probeHost(exec);
    if (probe == null) {
      _setPhase(RemoteHostPhase.failed);
      throw const RemoteHostException(RemoteHostErrorKind.hostUnknownOs);
    }
    return _shell = switch (probe.family) {
      HostOsFamily.posix => PosixHostShell(probe: probe, exec: exec),
      HostOsFamily.windows => WindowsHostShell(probe: probe, exec: exec),
    };
  }

  /// Abertura no mobile: conecta via dartssh2, resolve `$HOME` do host e
  /// encaminha pro socket UNIX remoto. Sem bootstrap — se o server não está lá,
  /// falha com erro claro (o mobile não instala server, decisão D).
  Future<void> _ensureHostKeyTrusted() async {
    // Auth por senha já roda com `accept-new` no ssh (o canal de senha é o
    // próprio aceite); não duplicamos a pergunta.
    if (_password != null) return;
    final status = await knownHosts.lookup(host.host, host.port);
    if (status != SshHostKeyStatus.unknown) return;

    final keys = await knownHosts.scan(host.host, host.port);
    // Ninguém respondeu ao scan: não é problema de confiança, é host fora do
    // ar — deixa o ssh falhar e reportar o motivo real.
    if (keys.isEmpty) return;
    final prompt = hostKeyPrompt;
    final fingerprint = await knownHosts.fingerprintOf(keys);
    if (prompt == null || fingerprint == null) {
      _setPhase(RemoteHostPhase.failed);
      throw const RemoteHostException(RemoteHostErrorKind.hostKeyUnknown);
    }
    final verdict = await prompt(
      SshKnownHosts.targetOf(host.host, host.port),
      fingerprint,
    );
    if (verdict != HostKeyVerdict.trust) {
      _setPhase(RemoteHostPhase.failed);
      throw const RemoteHostException(RemoteHostErrorKind.hostKeyUnknown);
    }
    await knownHosts.trust(keys);
  }

  /// `Host key verification failed` COM entrada no `known_hosts` significa
  /// chave trocada — o caso que nunca se aceita inline. Sem entrada, é host
  /// novo que o passo de confiança não cobriu (scan sem resposta).
  Future<RemoteHostErrorKind> _classifyHostKeyFailure() async {
    final status = await knownHosts.lookup(host.host, host.port);
    return status == SshHostKeyStatus.known
        ? RemoteHostErrorKind.hostKeyChanged
        : RemoteHostErrorKind.hostKeyUnknown;
  }

  Future<RemoteTerminalService> _openMobile() async {
    // sshTarget é `user@host` (sem porta); a porta vive em host.port.
    if (host.user.isEmpty || host.host.isEmpty) {
      _setPhase(RemoteHostPhase.failed);
      throw const RemoteHostException(
        RemoteHostErrorKind.sshUnreachable,
        'ssh_target_no_user',
      );
    }
    final endpoint = SshEndpoint(host.user, host.host, host.port);
    final conn = DartSshHostConnection(endpoint, password: _password);
    try {
      await conn.connect();
    } on DartSshException catch (e) {
      _setPhase(RemoteHostPhase.failed);
      throw RemoteHostException(
        RemoteHostErrorKind.sshUnreachable,
        e.detail ?? e.code,
      );
    }
    _dartConn = conn;
    unawaited(conn.done.then((_) => _onTunnelClosed()));

    _setPhase(RemoteHostPhase.connecting);
    try {
      // Mesmo dialeto do desktop (plano 61), sobre o canal do dartssh2: o
      // mobile não instala servidor (decisão D do plano 58), mas precisa saber
      // ONDE ele escuta — e isso difere por família (socket UNIX vs porta+token).
      // `runDetailed`, e não `run`: o `run` do dartssh2 mescla stderr no stdout
      // e esconde o exit code, o que fazia o probe ler o erro do `cmd.exe` como
      // se fosse a resposta de um POSIX. Ver o comentário em [runDetailed].
      Future<(int, String, String)> exec(
        String command, {
        List<int>? stdinBytes,
      }) => conn.runDetailed(command);

      final probe = await probeHost(exec);
      if (probe == null) {
        throw const RemoteHostException(RemoteHostErrorKind.hostUnknownOs);
      }
      final shell = switch (probe.family) {
        HostOsFamily.posix => PosixHostShell(probe: probe, exec: exec),
        HostOsFamily.windows => WindowsHostShell(probe: probe, exec: exec),
      };
      final remote = await shell.readEndpoint();
      if (remote == null) {
        throw const RemoteHostException(
          RemoteHostErrorKind.serverInstallFailed,
        );
      }
      // Socket UNIX num host POSIX; porta de loopback num host Windows — o
      // `forwardLocal` do dartssh2 cobre os dois, o `forwardLocalUnix` não.
      // O rendezvous anuncia onde o servidor ESTAVA, não que ele ainda está:
      // um servidor remoto que saiu por ociosidade deixa o arquivo pra trás,
      // e no Windows ele é arquivo comum — não some com o processo. O desktop
      // se recupera sozinho (falhou, faz bootstrap); o mobile não instala
      // servidor (decisão D do plano 58), então aqui a única saída é dizer com
      // todas as letras que não há ninguém atendendo, em vez de deixar vazar um
      // `SSHChannelOpenError(2: open failed)` cru, que não diz nada a quem lê.
      final channel =
          await switch (remote) {
            UnixSocketEndpoint(:final path) => conn.forwardUnix(path),
            TcpEndpoint(:final port) => conn.forwardTcp(port),
          }.onError<Object>((e, _) {
            throw RemoteHostException(
              RemoteHostErrorKind.serverInstallFailed,
              'o host anunciou um servidor que não responde mais (rendezvous obsoleto): \$e',
            );
          });
      final connection = await RemoteConnection.connectOn(
        SshChannelDuplex(channel),
        clientName: 'cockpit-ipad',
        token: remote.token,
      );
      _connection = connection;
      _service = RemoteTerminalService(connection);
      _bindTurnStatus();
      _setPhase(RemoteHostPhase.connected);
      return _service!;
    } on TerminalException catch (e) {
      _setPhase(RemoteHostPhase.failed);
      if (e.detail == 'version_mismatch') {
        throw const RemoteHostException(RemoteHostErrorKind.versionMismatch);
      }
      // Server ausente no host: mobile não instala (decisão D).
      throw RemoteHostException(
        RemoteHostErrorKind.serverInstallFailed,
        e.detail,
      );
    } catch (e) {
      _setPhase(RemoteHostPhase.failed);
      throw RemoteHostException(RemoteHostErrorKind.protocol, '$e');
    }
  }

  Future<RemoteConnection?> _tryProtocol(
    SshTunnel tunnel, {
    String? token,
    int attempts = 1,
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(Duration(milliseconds: 100 + i * 50));
      }
      try {
        // PONTA LOCAL de um `ssh -L`: o rendezvous não existe deste lado, então
        // o token não se resolve aqui — ele vem do endpoint REMOTO, lido pelo
        // dialeto do host. Host POSIX não tem token (o socket UNIX já nasce
        // protegido pelas permissões do `~/.cockpit`); host Windows tem, e o
        // servidor de lá recusa o `Hello` sem ele.
        final port = tunnel.localPort;
        return await RemoteConnection.connectOn(
          port != null
              ? SocketRemoteDuplex(
                  await Socket.connect(InternetAddress.loopbackIPv4, port),
                )
              : await SocketRemoteDuplex.connectUnix(tunnel.localSocketPath),
          clientName: 'cockpit-gui-ssh',
          token: token,
        );
      } on TerminalException catch (e) {
        // Handshake respondeu com erro = servidor existe mas incompatível.
        if (e.detail == 'version_mismatch') {
          _setPhase(RemoteHostPhase.failed);
          throw RemoteHostException(RemoteHostErrorKind.versionMismatch);
        }
        // protocol/transport → servidor provavelmente ausente; tenta de novo.
      } catch (_) {
        // socket remoto sem listener; segue pro retry/bootstrap.
      }
    }
    return null;
  }

  /// Bootstrap "Install server": garante binário no host e sobe o servidor.
  ///
  /// `--exit-on-idle 120` + `--idle-keeps-sessions`: o servidor encerra sozinho
  /// ~2min depois que ninguém mais o usa (sem órfão no host), MAS nunca enquanto
  /// houver sessão viva. Sem a segunda flag, dois minutos de desconexão matavam
  /// o que estivesse rodando lá — um agente aberto, um build, um vim — que é o
  /// oposto da promessa de retomar de onde parou.
  static const _remoteIdleSeconds = 120;

  /// `true` quando o binário do host **existe mas é diferente** do que este
  /// cliente instalaria: o processo velho precisa morrer para o novo valer.
  bool _staleServer = false;

  /// A comparação de versão do servidor roda uma vez por host por sessão —
  /// reconectar (o que acontece a cada oscilação de rede) não paga o SSH extra
  /// de novo.
  bool _serverFreshnessChecked = false;

  /// Compara o `cockpit-server` do host com o que este cliente enviaria.
  ///
  /// Só vale quando o cliente é a FONTE da instalação: num host Windows quem
  /// instala é o próprio host, a partir do bundle do app de lá (D2), então o
  /// binário local desta máquina não é referência de nada — comparar acusaria
  /// "desatualizado" em todo boot e derrubaria o servidor remoto sem motivo.
  Future<bool> _remoteServerIsStale(HostShell shell) async {
    if (shell.installsFromHostBundle) return false;
    // Host de OUTRA plataforma: este cliente não tem binário para enviar (o
    // `.deb` traz só o ELF do Linux, o `.app` só o Mach-O), então não é fonte
    // da instalação e não tem autoridade para julgá-la.
    //
    // Sem esta linha o resolver caía no nome sem sufixo e devolvia o binário
    // da PRÓPRIA plataforma: o hash nunca batia com o do host, todo boot
    // acusava "desatualizado", e o cliente DERRUBAVA uma conexão que estava
    // funcionando para tentar um bootstrap que o guard de OS logo abaixo
    // recusa. Cliente Linux + host macOS ficava sem conexão nenhuma.
    if (shell.probe.os != _localOsName) return false;
    final local = localServerBinaryResolver(arch: shell.probe.arch);
    if (local == null) return false;
    final remoteHash = await shell.serverSha256();
    if (remoteHash == null) return false;
    try {
      final localHash = sha256.convert(await File(local).readAsBytes());
      return localHash.toString() != remoteHash;
    } on FileSystemException {
      return false;
    }
  }

  static String get _localOsName => Platform.isMacOS
      ? 'darwin'
      : Platform.isLinux
      ? 'linux'
      : 'windows';

  Future<void> _installAndStartServer(HostShell shell) async {
    var installed = await shell.serverInstalled();
    if (installed && _staleServer) installed = false;

    if (!installed) {
      if (shell.installsFromHostBundle) {
        // Windows (D2): instalação é cópia LOCAL do bundle do Cockpit
        // instalado no host — nenhum byte de binário viaja pelo SSH, e é o que
        // permite um cliente macOS instalar num host Windows.
        if (!await shell.installFromHost()) {
          _setPhase(RemoteHostPhase.failed);
          throw const RemoteHostException(
            RemoteHostErrorKind.hostBundleMissing,
          );
        }
      } else {
        // POSIX: o bundle vem DESTE cliente, então precisa ser da plataforma
        // do host. Antes o Mach-O do macOS era empurrado pra qualquer host e o
        // servidor morria no `nohup` sem deixar rastro.
        if (shell.probe.os != _localOsName) {
          _setPhase(RemoteHostPhase.failed);
          throw RemoteHostException(
            RemoteHostErrorKind.serverInstallFailed,
            'host runs ${shell.probe.os}; '
            'this build only ships a $_localOsName cockpit-server',
          );
        }
        final binary = localServerBinaryResolver(arch: shell.probe.arch);
        if (binary == null) {
          _setPhase(RemoteHostPhase.failed);
          throw RemoteHostException(
            RemoteHostErrorKind.serverInstallFailed,
            'local cockpit-server binary not found for '
            '${shell.probe.os}/${shell.probe.arch}',
          );
        }
        // Servidor desatualizado: o processo VELHO ainda está no ar (sobrevive
        // à desconexão por causa do `--idle-keeps-sessions`) e continuaria
        // atendendo mesmo depois de trocarmos o arquivo. Derruba antes de
        // sobrescrever — custa as sessões de PTY abertas naquele host, e é por
        // isso que só acontece quando o binário realmente mudou.
        if (_staleServer) {
          await shell.killServer();
          _staleServer = false;
        }
        try {
          await shell.installFromClient(
            ClientBundle(
              root: File(binary).parent.parent.path,
              serverBinary: binary,
            ),
          );
        } on HostShellException catch (e) {
          _setPhase(RemoteHostPhase.failed);
          throw RemoteHostException(
            RemoteHostErrorKind.serverInstallFailed,
            e.detail,
          );
        }
      }
    }
    if (_staleServer) {
      await shell.killServer();
      _staleServer = false;
    }

    try {
      await shell.startServer(idleSeconds: _remoteIdleSeconds);
    } on HostShellException catch (e) {
      _setPhase(RemoteHostPhase.failed);
      throw RemoteHostException(
        RemoteHostErrorKind.serverInstallFailed,
        e.detail,
      );
    }
  }

  // --- Reconexão automática -------------------------------------------------
  //
  // Backoff crescente que NUNCA desiste (decisão do usuário): 1s, 2s, 4s, 8s,
  // 15s e daí 30s fixo. O teto no intervalo (e não no número de tentativas) é
  // o que mantém "insiste pra sempre" sem martelar a rede — num iPad, um socket
  // a cada 30s é desprezível perto de tentar a cada segundo.
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  Timer? _retryTimer;
  int _retryStep = 0;
  bool _disposed = false;

  /// Emite quando a conexão é REFEITA — os gateways de terminal usam pra
  /// re-anexar suas sessões (o serviço é outro objeto após reabrir).
  final _reconnected = StreamController<RemoteTerminalService>.broadcast();
  Stream<RemoteTerminalService> get reconnected => _reconnected.stream;

  void _onTunnelClosed() {
    if (_disposed || _aborting) return;
    if (phase == RemoteHostPhase.connected) {
      _setPhase(RemoteHostPhase.reconnecting);
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    final delay = _backoff[_retryStep.clamp(0, _backoff.length - 1)];
    if (_retryStep < _backoff.length - 1) _retryStep++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _attemptReconnect();
    });
  }

  Future<void> _attemptReconnect() async {
    if (_disposed) return;
    final connection = _connection;
    if (connection != null && connection.isOpen) return;
    try {
      // `ensure()` dedup pelo `_inflight`, então tentativa concorrente com uma
      // ação do usuário não abre dois túneis. Quem anuncia o serviço novo (e
      // zera o backoff) é o próprio `ensure`, para valer em qualquer caminho.
      await ensure();
    } on Object {
      // Falhou de novo: reagenda. A fase já foi pra failed dentro de _open().
      if (!_disposed) {
        _setPhase(RemoteHostPhase.reconnecting);
        _scheduleRetry();
      }
    }
  }

  /// Reconecta AGORA (botão da UI): descarta o backoff acumulado, **aborta a
  /// tentativa em curso** e abre uma nova. Sem efeito se a conexão está viva.
  ///
  /// O abort é o que faz o botão ter efeito de verdade. Sem ele, `ensure()`
  /// devolvia o `_inflight` — e com o host fora do ar há quase sempre uma
  /// abertura em voo (o retry automático dispara a cada 1-30s e cada tentativa
  /// leva até 15s pra estourar), então o clique só pegava carona numa tentativa
  /// já pendurada: da UI, parecia que o botão não fazia nada.
  Future<void> reconnectNow() async {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryStep = 0;
    // Feedback imediato: o abort abaixo pode levar um instante (fechar socket,
    // esperar a tentativa pendurada morrer) e o clique não pode parecer inerte.
    _setPhase(RemoteHostPhase.openingTunnel);
    await _abortCurrentAttempt();
    if (_disposed) return;
    await _attemptReconnect();
  }

  /// Derruba conexão/transporte/tentativa atuais para que a próxima abertura
  /// comece do zero. Fechar o transporte faz a tentativa pendurada estourar na
  /// hora, em vez de esperar o timeout.
  Future<void> _abortCurrentAttempt() async {
    final inflight = _inflight;
    final connection = _connection;
    final tunnel = _tunnel;
    final dartConn = _dartConn;
    _connection = null;
    _service = null;
    _tunnel = null;
    _dartConn = null;
    // O fechamento é NOSSO, deliberado: o `closed`/`done` do transporte vai
    // disparar [_onTunnelClosed], que agendaria um retry concorrente com o que
    // este método está prestes a fazer.
    _aborting = true;
    try {
      await connection?.close();
    } on Object {
      // já morto.
    }
    try {
      await tunnel?.close();
    } on Object {
      // já morto.
    }
    try {
      await dartConn?.close();
    } on Object {
      // já morto.
    }
    if (inflight != null) {
      try {
        await inflight;
      } on Object {
        // a tentativa abortada falha — é o esperado.
      }
    }
    _aborting = false;
  }

  /// Fechamento provocado por nós ([_abortCurrentAttempt]) não deve agendar
  /// retry: quem abortou já vai reabrir.
  bool _aborting = false;

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _reconnected.close();
    await _turnSub?.cancel();
    await _turnStatus.close();
    await _cliSub?.cancel();
    await _cliCommands.close();
    await _connection?.close();
    await _tunnel?.close();
    await _dartConn?.close();
    _connection = null;
    _service = null;
    await _phases.close();
  }
}
