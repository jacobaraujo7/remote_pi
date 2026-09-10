import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/core/utils/child_process_lifetime.dart';
import 'package:cockpit/app/core/utils/user_home.dart';
import 'package:cockpit_remote/cockpit_remote.dart';
import 'package:flutter/foundation.dart';

/// Garante um `cockpit-server` sidecar de pé e devolve o serviço de terminais
/// remoto conectado a ele via loopback (plano 58, Wave 1).
///
/// Ciclo de vida (decisões F/I do plano):
/// - **Descoberta antes de spawn**: se o socket responde, adota o servidor
///   existente — nunca dois servidores no mesmo estado.
/// - Se ninguém responde, spawna o binário como filho com `--exit-on-idle`,
///   que é o seguro contra órfão (GUI morreu sem matar o filho → o servidor
///   se encerra sozinho ao ficar sem clientes).
/// - `null` = sidecar indisponível (binário não empacotado/ambiente mínimo);
///   o chamador faz fallback pro PTY in-process e o app segue como antes.
/// - **Veredito negativo é definitivo pela sessão do app** ([unavailableReason]):
///   sem isso, cada aba nova repetia o backoff inteiro do passo 3 — foi o que
///   deixou toda aba de terminal ~5.8s mais lenta na 1.28.0, com o bundle
///   universal quebrado pelo `lipo`.
class SidecarTerminalConnector implements TurnStatusSource {
  RemoteConnection? _connection;
  RemoteTerminalService? _service;
  Future<RemoteTerminalService?>? _inflight;
  Process? _child;

  /// Por que o sidecar não está disponível, ou `null` enquanto ele serve.
  /// Uma vez preenchido, [ensure] devolve `null` na hora (fallback in-process)
  /// em vez de tentar spawnar de novo a cada terminal. Sobrevive à sessão do
  /// app; um sidecar quebrado não conserta sozinho, e insistir só custa tempo
  /// na abertura de cada aba.
  String? unavailableReason;

  RemoteTerminalService? _giveUp(String reason) {
    unavailableReason = reason;
    debugPrint('sidecar: $reason; using local PTY');
    return null;
  }

  /// Status de turno (spinner/chime/notificação) dos agentes rodando nas PTYs
  /// do sidecar. Mesmo mecanismo do [RemoteHostConnector], e pela mesma razão:
  /// o PTY não nasce mais dentro do app, e o SERVIDOR injeta o socket de
  /// status DELE no env (ver `remote_server.dart`, caso `PtyOpen`),
  /// sobrescrevendo o do cliente. Logo o hook do agente reporta ao sidecar, e
  /// o único caminho de volta é este broadcast do protocolo — sem assiná-lo, o
  /// turn-status local simplesmente sumia.
  final _turnStatus = StreamController<ClaudeStatusUpdate>.broadcast();
  StreamSubscription<RemoteTurnStatus>? _turnSub;

  @override
  Stream<ClaudeStatusUpdate> get turnStatus => _turnStatus.stream;

  void _bindTurnStatus() {
    _turnSub?.cancel();
    _turnSub = _service?.turnStatus.listen(
      (s) => _turnStatus.add(
        ClaudeStatusUpdate(
          paneId: s.paneId,
          status: s.status,
          event: s.event,
          sessionId: s.sid,
          transcriptPath: s.transcriptPath,
          harness: s.harness,
        ),
      ),
    );
  }

  /// Serviço conectado, reusando a conexão viva; reconecta (ou respawna) se
  /// o sidecar caiu. Nunca lança: falha vira `null` (fallback local).
  Future<RemoteTerminalService?> ensure() {
    if (unavailableReason != null) return Future.value(null);
    final connection = _connection;
    if (connection != null && connection.isOpen) {
      return Future.value(_service);
    }
    return _inflight ??= _connect().whenComplete(() => _inflight = null);
  }

  Future<RemoteTerminalService?> _connect() async {
    try {
      final socketPath = _socketPath();
      if (socketPath == null) return _giveUp('no home directory');

      // 1. Descoberta: já existe servidor atendendo este socket?
      final binary = _resolveServerBinary();
      final adopted = await _tryConnect(socketPath);
      if (adopted != null) {
        if (_isOurBinary(adopted, binary)) return _adopt(adopted);
        // Servidor de OUTRA instalação (release anterior, pasta temporária).
        // Adotar em silêncio faz o app novo seguir rodando código velho — foi
        // assim que uma correção publicada não chegou a rodar na máquina do
        // usuário. Encerra o intruso e sobe o nosso.
        debugPrint(
          'sidecar: servidor alheio no socket '
          '(${adopted.serverExecutable}); encerrando e subindo o meu',
        );
        await _evict(adopted);
      }

      // 2. Spawn do sidecar.
      if (binary == null) {
        return _giveUp('cockpit-server binary not found');
      }
      // Bundle `bin/` + `lib/`: as dylibs (anaki via rpath, pty via env) ficam
      // em ../lib relativo ao exe (@executable_path/../lib). O nome da lib do
      // PTY muda por plataforma; se ela não estiver em ../lib, o próprio
      // servidor ainda a procura ao lado do seu executável (ver openPtyDylib),
      // que é onde os bundles de Windows/Linux a colocam.
      final libDir = '${File(binary).parent.parent.path}/lib';
      final ptyDylib = File('$libDir/${_ptyLibName()}');
      _child = await Process.start(
        binary,
        [
          '--socket',
          socketPath,
          '--exit-on-idle',
          '15',
          // Amarra a vida do sidecar à do app: quando este processo morre, o
          // kernel fecha a ponta de escrita do stdin do filho e ele sai por
          // EOF. Cobre a morte ABRUPTA (Force Quit, kill -9, crash), que o
          // `dispose()` não cobre porque não chega a rodar. Fora do Windows é
          // a única amarra que existe — lá o Job Object abaixo já garante.
          '--exit-on-parent-close',
        ],
        environment: {
          ...Platform.environment,
          if (ptyDylib.existsSync()) 'COCKPIT_PTY_DYLIB': ptyDylib.path,
        },
      );
      // Windows: o filho morre com o app (Job Object). Órfão vivo no caminho
      // anunciado é o que faz um app novo conversar com build antiga.
      tieChildToThisProcess(_child!.pid);
      // Drena stdout/stderr: pipe cheio bloquearia o servidor (e SIGPIPE já
      // é tratado no AppDelegate, lição do fechamento silencioso). O stderr,
      // além de drenado, é GUARDADO: é a única explicação de um sidecar que
      // morre no arranque (binário inválido, dylib faltando) — antes ia pro
      // lixo e a falha ficava muda.
      unawaited(_child!.stdout.drain<void>());
      final diagnostics = StringBuffer();
      _child!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((
        chunk,
      ) {
        if (diagnostics.length < 2000) diagnostics.write(chunk);
      }, onError: (_) {});

      // Morte do filho é resposta definitiva: para de esperar na hora. Sem
      // isto, um servidor que nem chega a abrir o socket ainda custava os
      // 5,75s do backoff completo — em CADA aba nova.
      var died = false;
      var exitCode = 0;
      unawaited(
        _child!.exitCode.then((code) {
          died = true;
          exitCode = code;
        }),
      );

      // 3. Retry com backoff curto até o listener subir.
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(Duration(milliseconds: 50 + attempt * 25));
        final connection = await _tryConnect(socketPath);
        if (connection != null) return _adopt(connection);
        if (died) {
          final why = diagnostics.toString().trim();
          return _giveUp(
            'server exited with code $exitCode${why.isEmpty ? '' : ': $why'}',
          );
        }
      }
      return _giveUp('server did not come up');
    } catch (e) {
      return _giveUp('unavailable ($e)');
    }
  }

  /// O servidor que atendeu é o MESMO binário que este app subiria?
  ///
  /// A versão do handshake não serve para decidir: ela é a do pacote
  /// `cockpit_server`, que raramente muda entre releases do app. O caminho do
  /// executável distingue. Servidor antigo demais para informar o caminho é
  /// tratado como alheio — ele é, por definição, de outra build.
  bool _isOurBinary(RemoteConnection connection, String? binary) {
    final theirs = connection.serverExecutable;
    if (theirs == null || binary == null) return false;
    return _samePath(theirs, binary);
  }

  /// Comparação de caminho tolerante ao que muda sem mudar o arquivo:
  /// separador e caixa no Windows.
  static bool _samePath(String a, String b) {
    String norm(String p) {
      final unified = p.replaceAll(r'\', '/');
      return Platform.isWindows ? unified.toLowerCase() : unified;
    }

    return norm(a) == norm(b);
  }

  /// Fecha a conexão com o servidor alheio e o encerra, para o nosso poder
  /// bindar o socket. Sem matá-lo, ele continuaria dono do caminho anunciado.
  Future<void> _evict(RemoteConnection intruder) async {
    final pid = intruder.serverPid;
    await intruder.close();
    if (pid == null) return;
    final announced = _socketPath();
    try {
      // SIGTERM: o servidor tem desligamento com teto e limpa o anúncio.
      Process.killPid(pid);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (announced == null || !File(announced).existsSync()) return;
      }
      // Insistente (SIGTERM não existe no Windows): força.
      Process.killPid(pid, ProcessSignal.sigkill);
    } on Object {
      // Sem permissão / já morto: o bind por cima ainda costuma funcionar.
    }
  }

  RemoteTerminalService _adopt(RemoteConnection connection) {
    _connection = connection;
    _service = RemoteTerminalService(connection);
    _bindTurnStatus(); // reassina a cada (re)conexão/respawn do sidecar.
    return _service!;
  }

  Future<RemoteConnection?> _tryConnect(String socketPath) async {
    if (!File(socketPath).existsSync()) return null;
    try {
      return await RemoteConnection.connect(
        socketPath,
        clientName: 'cockpit-gui',
        // Mesma máquina: as PTYs mantêm o COCKPIT_STATUS_SOCK do app, que é
        // por onde a CLI interna (`cockpit send`, `list-tabs`, `db`) fala. Um
        // host remoto sobrescreve, porque lá o socket do app é inalcançável.
        local: true,
      );
    } catch (_) {
      return null; // socket velho/morto; o bind do servidor novo o substitui.
    }
  }

  String? _socketPath() {
    final home = userHome();
    if (home == null) return null;
    final dir = Directory('$home/.cockpit');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // Namespaceado por debug/release, pela mesma razão do `status.sock` e do
    // `bin/` da CLI: `~/.cockpit` é o HOME real (não é isolado por bundle id),
    // então uma build de dev e a instalada disputavam ESTE socket. E aqui a
    // disputa é pior que sobrescrever um arquivo: cada app vê o servidor do
    // outro como alheio (`_isOurBinary` compara o caminho do executável) e o
    // ENCERRA para subir o seu — em cima do app vizinho, que perde o sidecar e
    // os terminais dele. Abrir a build de dev com a instalada aberta derrubava
    // as duas em revezamento.
    //
    // Só o socket LOCAL leva o sufixo: o caminho do socket no host REMOTO
    // (`posix_host_shell`/`windows_host_shell`) é o da máquina do outro lado,
    // que roda release — sufixar lá quebraria conexão remota a partir de um
    // debug.
    final suffix = kDebugMode ? '-debug' : '';
    return '${dir.path}/cockpit-server$suffix.sock';
  }

  /// Resolve o binário NATIVO do servidor no bundle `bin/`+`lib/`.
  /// Bundles de outras plataformas são usados apenas pelo bootstrap SSH.
  String? _resolveServerBinary() => resolveServerBundleBinary();

  /// Nome da lib nativa do PTY por plataforma (o servidor a carrega por FFI).
  static String _ptyLibName() => Platform.isMacOS
      ? 'libcockpit_pty.dylib'
      : Platform.isLinux
      ? 'libcockpit_pty.so'
      : 'cockpit_pty.dll';

  /// Nome do executável do servidor no disco (Windows carrega a extensão).
  static String get serverExeName => serverExeNameFor(hostOs);

  static String serverExeNameFor(String os) =>
      os == 'windows' ? 'cockpit-server.exe' : 'cockpit-server';

  /// Mesmo executável, com sufixo de arquitetura (`cockpit-server-arm64`).
  ///
  /// Um bundle macOS universal **não pode** ter um exe fat: o AOT do Dart
  /// carrega o snapshot anexado ao próprio arquivo e o container fat que o
  /// `lipo` produz o esconde do `dartaotruntime` ("is not an AOT snapshot") —
  /// o binário morre nas duas arquiteturas. Então o bundle traz uma fatia por
  /// arquitetura, cada uma um Mach-O fino e válido, e quem escolhe é o
  /// runtime. Ver `tool/lipo-server-bundle.sh`.
  static String serverExeFor(String arch, {String? os}) =>
      (os ?? hostOs) == 'windows'
      ? 'cockpit-server-$arch.exe'
      : 'cockpit-server-$arch';

  /// Arquitetura deste processo (`arm64` | `x64`), lida do `Platform.version`
  /// (`... on "macos_arm64"`) — a fonte confiável, como no resolver de perfis.
  static String get hostArch =>
      Platform.version.toLowerCase().contains('arm') ? 'arm64' : 'x64';

  /// Escolhe o executável do servidor dentro de um `bin/`, preferindo a fatia
  /// de [arch]. O nome sem sufixo só é elegível para a arquitetura deste
  /// processo, salvo quando [targetSpecificDir] garante a arquitetura no nome
  /// do diretório (`targets/linux-arm64`).
  static String? serverBinaryIn(
    String binDir, {
    String? os,
    String? arch,
    bool targetSpecificDir = false,
  }) {
    final requestedOs = os ?? hostOs;
    final requestedArch = arch ?? hostArch;
    for (final name in <String>[
      serverExeFor(requestedArch, os: requestedOs),
      if (targetSpecificDir || requestedArch == hostArch)
        serverExeNameFor(requestedOs),
    ]) {
      final candidate = '$binDir/$name';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Resolve o binário do servidor num bundle produzido por `dart build cli`.
  ///
  /// O bundle nativo mantém o layout histórico `<root>/{bin,lib}`. Targets de
  /// bootstrap cross-platform ficam isolados em
  /// `<root>/targets/<os>-<arch>/{bin,lib}`, para o sidecar local nunca escolher
  /// por engano um ELF e para o bootstrap inferir as libs do mesmo target a
  /// partir do caminho do executável.
  ///
  /// Ordem das raízes: env (somente target nativo) → bundle do app →
  /// app-managed (`~/.cockpit/server`) → build de dev.
  static String? resolveServerBundleBinary({String? os, String? arch}) =>
      resolveServerBundleBinaryFrom(
        os: os ?? hostOs,
        arch: arch ?? hostArch,
        nativeBinDirs: serverBundleBinDirs(),
        environmentBinary: Platform.environment['COCKPIT_SERVER_BIN'],
      );

  /// Núcleo injetável do resolver: permite provar que nem o env override nem o
  /// nome puro escapam para um host da mesma plataforma em outra arquitetura.
  @visibleForTesting
  static String? resolveServerBundleBinaryFrom({
    required String os,
    required String arch,
    required List<String> nativeBinDirs,
    String? environmentBinary,
  }) {
    if (os == hostOs && arch == hostArch) {
      final fromEnv = environmentBinary;
      if (fromEnv != null && fromEnv.isNotEmpty && File(fromEnv).existsSync()) {
        return fromEnv;
      }
    }
    for (final nativeBinDir in nativeBinDirs) {
      final found = serverBinaryInBundle(
        Directory(nativeBinDir).parent.path,
        os: os,
        arch: arch,
      );
      if (found != null) return found;
    }
    return null;
  }

  /// Resolve dentro de uma raiz de bundle explícita. Separado para tornar o
  /// contrato de layout verificável sem depender da localização do executável.
  @visibleForTesting
  static String? serverBinaryInBundle(
    String root, {
    required String os,
    required String arch,
  }) {
    final binDir = os == hostOs ? '$root/bin' : '$root/targets/$os-$arch/bin';
    return serverBinaryIn(
      binDir,
      os: os,
      arch: arch,
      targetSpecificDir: os != hostOs,
    );
  }

  /// Sistema deste processo no mesmo vocabulário de `uname`/`probeHost`.
  static String get hostOs => Platform.isMacOS
      ? 'darwin'
      : Platform.isLinux
      ? 'linux'
      : 'windows';

  /// Pastas `bin/` onde o bundle do servidor pode estar, em ordem de prioridade.
  static List<String> serverBundleBinDirs() {
    final home = userHome();
    return <String>[
      if (Platform.isMacOS)
        // .app/Contents/MacOS/<exe> → ../Resources/cockpit-server-bundle/bin
        '${File(Platform.resolvedExecutable).parent.parent.path}'
            '/Resources/cockpit-server-bundle/bin'
      else
        // Windows/Linux: o bundle é instalado ao lado do executável, mesmo
        // lugar do cockpit-hook e da cockpit-cli (ver os CMakeLists).
        '${File(Platform.resolvedExecutable).parent.path}'
            '/cockpit-server-bundle/bin',
      if (home != null) '$home/.cockpit/server/bin',
      '${Directory.current.path}/build/server-bundle/bin',
    ];
  }

  Future<void> dispose() async {
    await _turnSub?.cancel();
    await _turnStatus.close();
    await _connection?.close();
    _connection = null;
    _service = null;
    // Cortesia: pede pro filho sair já; o --exit-on-idle é o fallback.
    _child?.kill(ProcessSignal.sigterm);
    _child = null;
  }
}
