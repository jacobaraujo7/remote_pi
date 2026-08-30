import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';


class _RpcUnknown implements Exception {
  const _RpcUnknown(this.method);
  final String method;
}

/// Servidor do protocolo Cockpit Remote sobre socket local (UDS).
///
/// Sessões pertencem ao [TerminalService], não às conexões: um cliente que
/// desconecta faz detach implícito e a sessão continua viva (reattach later).
class RemoteServer {
  /// Caminho da CLI `cockpit` **neste host**, resolvido no bootstrap. A pasta
  /// dela entra no PATH de cada PTY, para que `cockpit …` funcione num
  /// terminal remoto (os comandos são atendidos pelo cliente, do outro lado do
  /// SSH). `null` = CLI não encontrada; o shell segue sem ela.
  static String? cliPath;

  RemoteServer(
    this._terminals,
    this._files,
    this._git,
    this._db, {
    this.serverVersion = '0.1.0',
    DbSecretStore? dbSecrets,
    SshTunnel? dbTunnel,
  }) : _dbSecrets = dbSecrets ?? DbSecretStore(),
       _dbTunnel = dbTunnel ?? SshTunnelImpl(FileSshHostKeyStore());

  final TerminalService _terminals;
  final FileService _files;
  final GitService _git;
  final DbService _db;

  /// Cofre de senhas de banco DESTE host (plano 62). O cliente grava e apaga
  /// por ele, nunca lê de volta.
  final DbSecretStore _dbSecrets;

  /// Túneis SSH das conexões de banco (plano 62, onda 2). Um por servidor, e
  /// não por conexão de cliente: o motor cacheia por (config, alvo), e abrir um
  /// handshake SSH por query custaria ~1s em cada uma.
  final SshTunnel _dbTunnel;
  final String serverVersion;
  static const _codec = RemoteMessageCodec();

  ServerSocket? _listener;
  final Set<_Connection> _connections = {};

  /// Receptor do status de turno (socket local do host onde o hook do agente
  /// escreve). `null` até o [bind]. Cada linha vira um [TurnStatus] broadcast
  /// pras conexões (plano 60, Wave G).
  TurnStatusReceiver? _statusReceiver;

  /// Endpoint local aberto no [bind] (guarda o token, no Windows).
  LocalListener? _endpoint;

  /// Env que o hook do agente precisa pra alcançar o receptor de status: o
  /// path do socket no POSIX, porta + token no Windows. Injetado em cada PTY.
  Map<String, String> _statusEnv = const <String, String>{};

  /// Modo sidecar: quando > Duration.zero, o servidor se encerra sozinho se
  /// ficar esse tempo sem NENHUM cliente conectado (evita órfão quando a GUI
  /// morre sem conseguir matar o filho). Zero = nunca (modo serviço).
  Duration exitOnIdle = Duration.zero;

  /// Sessão viva SEGURA o servidor de pé, mesmo sem cliente conectado.
  ///
  /// É a diferença entre os dois usos do [exitOnIdle]:
  ///
  /// - **sidecar local** (`false`): a GUI morreu, ninguém vai reanexar àqueles
  ///   PTYs e o app sempre abre sessões novas. Encerrar é o certo, senão sobra
  ///   processo órfão na máquina do usuário.
  /// - **servidor remoto** (`true`): desconectar é rotina (rede caiu, laptop
  ///   dormiu) e a promessa é justamente retomar de onde parou. Encerrar aqui
  ///   mata o trabalho em andamento — é o equivalente a derrubar o servidor
  ///   tmux dois minutos depois de você desanexar.
  ///
  /// Sem cliente E sem sessão viva o servidor encerra igual, então o seguro
  /// contra órfão continua valendo para o caso que ele foi criado para cobrir.
  bool idleKeepsSessions = false;

  Timer? _idleTimer;
  void Function()? onIdleExit;

  /// Vigia a posse do caminho anunciado. Um Cockpit novo bindando por cima
  /// deixa este servidor órfão: ninguém mais o acha, mas ele segue vivo. Sem
  /// cliente algum, sair é o certo — com cliente conectado, não: quem já está
  /// falando conosco continua sendo atendido, e a checagem se repete.
  void _armOwnershipWatch() {
    _ownershipTimer?.cancel();
    _ownershipTimer = Timer.periodic(_ownershipCheckInterval, (_) {
      final endpoint = _endpoint;
      if (endpoint == null || endpoint.stillOwned()) return;
      if (_connections.isNotEmpty) return;
      _ownershipTimer?.cancel();
      onIdleExit?.call();
    });
  }

  static const _ownershipCheckInterval = Duration(seconds: 30);
  Timer? _ownershipTimer;

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (exitOnIdle == Duration.zero || _connections.isNotEmpty) return;
    _idleTimer = Timer(exitOnIdle, () async {
      if (_connections.isNotEmpty) return;
      if (idleKeepsSessions && await _hasLiveSession()) {
        // Ainda há trabalho rodando: reagenda a checagem em vez de encerrar.
        _armIdleTimer();
        return;
      }
      onIdleExit?.call();
    });
  }

  /// Arma o timer de ociosidade como faria a saída do último cliente. Os
  /// testes não abrem socket real; é o gatilho da regra que interessa.
  @visibleForTesting
  Future<void> armIdleTimerForTest() async => _armIdleTimer();

  /// Alguma sessão com processo ainda vivo? Sessões já finalizadas (que só
  /// retêm scrollback) não seguram o servidor.
  Future<bool> _hasLiveSession() async {
    try {
      final sessions = await _terminals.sessions();
      return sessions.any((s) => s.isAlive);
    } on Object {
      // Falha ao consultar não deve virar um servidor imortal.
      return false;
    }
  }

  Future<void> bind(String socketPath) async {
    // Transporte por plataforma (UDS no POSIX, TCP loopback + token no
    // Windows, onde o dart:io não tem socket UNIX). Ver [LocalEndpoint].
    final endpoint = await LocalEndpoint.bind(socketPath);
    _endpoint = endpoint;
    _listener = endpoint.listener;
    _listener!.listen(_accept);
    // Socket de status ao lado do socket principal. Falha ao bindar (ex.: path
    // longo demais) é não-fatal: o servidor segue sem turn-status.
    _statusReceiver = TurnStatusReceiver(
      _broadcastTurnStatus,
      onCommand: _forwardCommandToClient,
    );
    try {
      await _statusReceiver!.bind('$socketPath.status');
    } catch (_) {
      _statusReceiver = null;
    }
    _statusEnv = _statusReceiver?.hookEnv ?? const <String, String>{};
    _armOwnershipWatch();
    _armIdleTimer();
  }

  /// Correlaciona os comandos de CLI em voo (rid → quem espera a resposta).
  final Map<int, Completer<Map<String, Object?>>> _cliCalls = {};
  int _nextCliRid = 0;

  /// Teto de espera de um comando de CLI. O agente no host está bloqueado
  /// nisto, então o timeout é curto o bastante para não pendurar um turno e
  /// longo o bastante para uma query de banco atravessar o SSH.
  static const Duration _cliTimeout = Duration(seconds: 30);

  /// Encaminha um comando da CLI do host ao **cliente** e devolve a resposta.
  ///
  /// O host não executa nada: quem tem abas, workspaces e conexões de banco é
  /// o Cockpit do outro lado. Vai pelo RPC do protocolo, na direção inversa da
  /// habitual (normalmente é o cliente que pergunta).
  Future<Map<String, Object?>> _forwardCommandToClient(
    Map<String, Object?> request,
  ) async {
    // Sem cliente não há a quem perguntar — e o agente recebe um erro em vez
    // de esperar o timeout inteiro.
    if (_connections.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'error': 'no Cockpit client attached to this host',
      };
    }
    // O comando vai para o cliente DONO da aba. Dois clientes no mesmo host
    // (desktop e iPad) compartilham este servidor, e responder pelo último que
    // conectou fazia o comando de um agente cair no outro dispositivo.
    final tabId = (request['tabId'] ?? '').toString();
    _Connection? connection;
    if (tabId.isNotEmpty) {
      for (final c in _connections) {
        if (c.ownsTab(tabId)) {
          connection = c;
          break;
        }
      }
    }
    // Ninguém reivindica a aba (ela nasceu antes deste servidor, ou o comando
    // veio de fora de uma aba). Com um cliente só, ele é a resposta óbvia;
    // com vários, chutar erraria de dispositivo — melhor dizer o que houve.
    if (connection == null) {
      if (_connections.length > 1) {
        return <String, Object?>{
          'ok': false,
          'error': tabId.isEmpty
              ? 'more than one Cockpit is attached to this host: run the '
                    'command from a terminal tab, so it knows which one to ask'
              : 'no attached Cockpit owns tab "$tabId" (it may predate the '
                    'current server — open a new terminal tab)',
        };
      }
      connection = _connections.last;
    }
    final rid = _nextCliRid++;
    final completer = Completer<Map<String, Object?>>();
    _cliCalls[rid] = completer;
    connection._onRpcResponse = _completeCliCall;
    connection._send(RpcRequest(rid: rid, method: 'cli.cmd', params: request));
    try {
      return await completer.future.timeout(_cliTimeout);
    } on TimeoutException {
      return <String, Object?>{
        'ok': false,
        'error':
            'the Cockpit client did not answer in '
            '${_cliTimeout.inSeconds}s',
      };
    } finally {
      _cliCalls.remove(rid);
    }
  }

  void _completeCliCall(RpcResponse response) {
    final completer = _cliCalls.remove(response.rid);
    if (completer == null || completer.isCompleted) return;
    if (response.ok) {
      final data = response.data;
      completer.complete(<String, Object?>{
        'ok': true,
        if (data != null) 'data': data,
      });
    } else {
      completer.complete(<String, Object?>{
        'ok': false,
        'error': response.detail ?? response.code ?? 'command failed',
      });
    }
  }

  /// Endereço do socket que recebe status do hook **e** comandos da CLI deste
  /// host (`<socket>.status`). `null` se o bind falhou.
  String? get statusSocketPath => _statusReceiver?.socketPath;

  /// Token exigido nesse socket quando o transporte é TCP (Windows). `null` no
  /// UDS, onde a permissão do arquivo já protege.
  String? get statusToken => _statusReceiver?.token;

  /// Reenvia um status de turno (vindo do hook no host) pra todos os clientes
  /// conectados. O cliente roteia por `paneId` — típico 1 cliente por host.
  void _broadcastTurnStatus(TurnStatus status) {
    for (final connection in _connections) {
      connection._send(status);
    }
  }

  Future<void> close() async {
    _ownershipTimer?.cancel();
    _idleTimer?.cancel();
    for (final connection in _connections.toList()) {
      await connection.close();
    }
    await _statusReceiver?.close();
    // Fecha PELO endpoint: ele também apaga o inode/arquivo anunciado, que no
    // Windows apontaria pra uma porta morta e enganaria a próxima descoberta.
    if (_endpoint != null) {
      await _endpoint!.close();
      _endpoint = null;
      _listener = null;
    }
    await _listener?.close();
    await _terminals.dispose();
  }

  void _accept(Socket socket) {
    final connection = _Connection(
      socket,
      _terminals,
      _files,
      _git,
      _db,
      _dbSecrets,
      _dbTunnel,
      serverVersion,
      _statusEnv,
      _endpoint?.token,
    );
    _connections.add(connection);
    _idleTimer?.cancel();
    connection.done.whenComplete(() {
      _connections.remove(connection);
      _armIdleTimer();
    });
  }
}

/// Variáveis pelas quais o hook do agente descobre o receptor de status (as
/// duas formas: path do socket, ou porta + token).
const _statusEnvKeys = <String>{
  'COCKPIT_STATUS_SOCK',
  'COCKPIT_STATUS_PORT',
  'COCKPIT_STATUS_TOKEN',
};

class _Connection {
  _Connection(
    this._socket,
    this._terminals,
    this._files,
    this._git,
    this._db,
    this._dbSecrets,
    this._dbTunnel,
    this._serverVersion,
    this._statusEnv,
    this._expectedToken,
  ) {
    // Erro no socket chega TAMBÉM por aqui (assíncrono, fora de qualquer
    // try/catch de escrita); sem o catch, vira exceção não tratada e mata o
    // processo.
    unawaited(
      _socket.done.then((_) => close()).catchError((Object _) => close()),
    );
    RemoteServer._codec
        .decodeStream(_socket)
        .listen(
          // Dispatch SERIALIZADO por conexão: o listen não espera handlers
          // async, então sem a corrente um pty.list ultrapassa um pty.kill
          // em andamento e a resposta observa estado antigo.
          (message) => _pending = _pending.then((_) => _dispatch(message)),
          onError: (Object _) => close(),
          onDone: close,
        );
  }

  Future<void> _pending = Future.value();

  /// Entregue pelo [RemoteServer]: recebe as [RpcResponse] deste cliente para
  /// os comandos de CLI que o host encaminhou.
  void Function(RpcResponse response)? _onRpcResponse;

  /// `COCKPIT_TAB_ID` de cada PTY que ESTE cliente abriu. É o que diz de quem
  /// é a aba quando um comando de CLI chega do host: com dois clientes no
  /// mesmo servidor (o desktop e o iPad, por exemplo), mandar para o último
  /// que conectou responderia com as abas do dispositivo errado.
  final Set<String> _tabIds = <String>{};

  bool ownsTab(String tabId) => _tabIds.contains(tabId);

  /// Descritor de conexão do payload, **com o segredo do host preenchido**
  /// (plano 62).
  ///
  /// Este é o ponto em que a senha entra no fluxo, e ele fica do lado do host
  /// de propósito: antes, o cliente resolvia a senha no cofre DELE e a mandava
  /// pelo fio a cada query — o que fazia a conexão só funcionar a partir da
  /// máquina que a cadastrou, e punha a senha em trânsito o tempo todo.
  Future<RemoteDbConnDescriptor> _conn(Map<String, Object?> p) async {
    var conn = RemoteDbConnDescriptor.fromJson(
      (p['conn'] as Map).cast<String, Object?>(),
    );
    // Senha veio no fio (conexão sem segredo guardado): respeita o que o
    // cliente mandou, não há o que resolver.
    if (conn.storedSecret) {
      final secret = _dbSecrets.read(conn.workspaceRoot, conn.connName);
      if (secret == null || secret.isEmpty) {
        // Conectar sem senha aqui produziria um erro do banco ("authentication
        // failed") que não diz a coisa importante: a senha existe, só está no
        // cofre do cliente que cadastrou a conexão, e precisa ser regravada
        // aqui.
        throw const DbServiceException(
          DbErrorKind.passwordRequired,
          'no stored password on this host for this connection',
        );
      }
      conn = conn.withPassword(secret);
    }
    return _tunneled(conn);
  }

  /// Abre (ou reusa) o túnel SSH da conexão e devolve o descritor apontando
  /// para a ponta local — **deste host**.
  ///
  /// É o passo que faltava para conexão com bastion funcionar a partir de um
  /// cliente remoto: antes o bloco `ssh` nem viajava, o host recebia
  /// `host:porta` cru e discava direto, sem o salto.
  ///
  /// A chave privada e a passphrase são as **daqui**, não as do cliente — quem
  /// alcança o bastion é esta máquina, e é nela que a credencial tem de estar.
  Future<RemoteDbConnDescriptor> _tunneled(RemoteDbConnDescriptor conn) async {
    final ssh = conn.ssh;
    if (ssh == null) return conn;
    final passphrase = _dbSecrets.readKey(
      DbSecretStore.sshKeyFor(conn.workspaceRoot, conn.connName),
    );
    try {
      // Mongo vai por SOCKS, os demais por port-forward: num replica set o
      // driver descobre os membros e passa a discar os hostnames reais, o que
      // fura qualquer porta fixa. Mesma regra do caminho local.
      if (conn.engine == 'mongo') {
        final proxy = await _dbTunnel.ensureSocks(ssh, passphrase: passphrase);
        return conn.withSocksProxy(proxy.host, proxy.port);
      }
      final endpoint = await _dbTunnel.ensure(
        ssh,
        targetHost: conn.host,
        targetPort: conn.port ?? _defaultPort(conn.engine),
        passphrase: passphrase,
      );
      return conn.withEndpoint(endpoint.host, endpoint.port);
    } on SshTunnelException catch (e) {
      // Detail estruturado (JSON) em vez de prosa: é com o `kind` que a UI
      // decide se pode oferecer "confiar nesta host key", e com `endpoint` +
      // `fingerprint` que ela monta o diálogo. Extrair isso de uma frase seria
      // frágil justamente no caminho que precisa ser confiável.
      throw DbServiceException(
        DbErrorKind.sshTunnelFailed,
        jsonEncode({
          'kind': e.kind,
          'message': e.message,
          if (e.endpoint != null) 'endpoint': e.endpoint,
          if (e.fingerprint != null) 'fingerprint': e.fingerprint,
        }),
      );
    }
  }

  static int _defaultPort(String engine) => switch (engine) {
    'postgres' => 5432,
    'mysql' => 3306,
    'mssql' => 1433,
    'redis' => 6379,
    'mongo' => 27017,
    _ => 0,
  };

  final Socket _socket;
  final TerminalService _terminals;
  final FileService _files;
  final GitService _git;
  final DbService _db;
  final DbSecretStore _dbSecrets;
  final SshTunnel _dbTunnel;
  final String _serverVersion;

  /// Env que leva o hook do agente até o receptor de status do HOST
  /// (`COCKPIT_STATUS_SOCK` no POSIX; `COCKPIT_STATUS_PORT` + `_TOKEN` no
  /// Windows). Injetado no env de cada PTY (plano 60, Wave G). Vazio =
  /// turn-status desligado.
  final Map<String, String> _statusEnv;

  /// Token exigido no `Hello` quando o transporte é TCP de loopback (Windows).
  /// `null` sobre socket UNIX/túnel SSH, onde o canal já é a credencial.
  final String? _expectedToken;

  final Map<String, StreamSubscription<PtyEvent>> _attachments = {};
  final Completer<void> _done = Completer();
  bool _handshaken = false;

  /// Cliente na mesma máquina (sidecar): as PTYs dele ficam com o env de
  /// status que ele mandou. Ver [Hello.local].
  bool _localClient = false;
  bool _closed = false;

  Future<void> get done => _done.future;

  /// Escreve no cliente, tolerando que ele tenha sumido.
  ///
  /// Sem este try/catch, um cliente que morre enquanto o servidor despeja
  /// saída de PTY derruba o PROCESSO INTEIRO com `SocketException: Broken
  /// pipe` — e com ele os terminais de todos os workspaces daquele sidecar.
  /// Escrita em socket morto é evento esperado num servidor de longa vida,
  /// não erro fatal: a conexão se encerra e o resto segue.
  void _send(RemoteMessage message) {
    if (_closed) return;
    try {
      _socket.add(utf8.encode(RemoteServer._codec.encode(message)));
    } on Object {
      unawaited(close());
    }
  }

  Future<void> _dispatch(RemoteMessage message) async {
    try {
      if (!_handshaken) {
        if (message is! Hello) {
          _send(const RemoteError(code: 'handshake_required'));
          return close();
        }
        if (message.version != protocolVersion) {
          _send(
            RemoteError(
              code: 'version_mismatch',
              detail: 'server=$protocolVersion client=${message.version}',
            ),
          );
          return close();
        }
        // Porta de loopback aceita conexão de qualquer processo da máquina;
        // o token é o que restringe ao dono do arquivo de rendezvous.
        if (_expectedToken != null && message.token != _expectedToken) {
          _send(const RemoteError(code: 'invalid_token'));
          return close();
        }
        _handshaken = true;
        _localClient = message.local;
        // Identidade do processo: é por ela que um cliente local decide se
        // adota este servidor ou sobe o dele (ver SidecarTerminalConnector).
        _send(
          HelloAck(
            version: protocolVersion,
            server: _serverVersion,
            executable: Platform.resolvedExecutable,
            pid: pid,
          ),
        );
        return;
      }

      switch (message) {
        case PtyOpen():
          // Injeta o endereço do receptor de status do HOST no env da PTY (o
          // cliente já manda COCKPIT_PANE_ID); assim o hook do agente no host
          // alcança o servidor, que reenvia o turno pelo protocolo (Wave G). O
          // env do cliente NÃO sobrescreve isto (o socket do cliente é
          // inalcançável do host). No Windows são porta + token, não um path:
          // o hook já lê as duas formas (ver cli/src/hook.rs).
          // `TERM` é conceito Unix (terminfo) e, no PowerShell nativo, sua
          // simples presença quebra o auto-load do PSReadLine. O cliente não
          // tem como saber a plataforma daqui, então manda sempre e QUEM
          // DESCARTA é o servidor (mesma regra do PTY local do app).
          final fromClient = Platform.isWindows
              ? {
                  for (final e in message.environment.entries)
                    if (e.key != 'TERM') e.key: e.value,
                }
              : message.environment;
          final env = _statusEnv.isEmpty || _localClient
              ? fromClient
              : {
                  // As chaves do OUTRO transporte saem juntas: o hook lê
                  // COCKPIT_STATUS_SOCK ANTES de porta/token (cli/src/
                  // transport.rs), então um path herdado do cliente venceria o
                  // endereço TCP do servidor e o status sumiria no Windows.
                  for (final e in fromClient.entries)
                    if (!_statusEnvKeys.contains(e.key)) e.key: e.value,
                  ..._statusEnv,
                  // Marca a sessão como remota. A CLI e o agente leem isto pra
                  // saber que os comandos são atendidos pelo Cockpit do OUTRO
                  // lado do SSH — e que nem todos atravessam.
                  'COCKPIT_REMOTE': '1',
                  // Deixa o binário `cockpit` do host alcançável no shell. O
                  // PATH aqui é do HOST (ao contrário do cliente, que não pode
                  // mandar o dele: destruiria o PATH desta máquina).
                  ..._cliPathEnv(fromClient['PATH']),
                };
          final tabId = env['COCKPIT_TAB_ID'];
          if (tabId != null && tabId.isNotEmpty) _tabIds.add(tabId);
          final info = await _terminals.open(
            PtySpawnSpec(
              executable: message.executable,
              arguments: message.arguments,
              workingDirectory: message.workingDirectory,
              environment: env,
              rows: message.rows,
              columns: message.columns,
            ),
          );
          // Ecoa o `rid`: é ele que diz ao cliente QUAL `pty.open` esta
          // resposta atende. Sem isso, dois opens simultâneos casavam com a
          // mesma resposta e os dois terminais adotavam o mesmo sessionId.
          _send(PtyOpened(sessionId: info.id, pid: info.pid, rid: message.rid));

        case PtyList():
          final sessions = await _terminals.sessions();
          _send(
            PtySessions(
              sessions: [
                for (final s in sessions)
                  {
                    'id': s.id,
                    'pid': s.pid,
                    'cmd': s.executable,
                    'rows': s.rows,
                    'cols': s.columns,
                    'len': s.scrollbackLength,
                    if (s.exitCode != null) 'exit': s.exitCode,
                  },
              ],
              rid: message.rid,
            ),
          );

        case PtyAttach():
          await _attachments.remove(message.sessionId)?.cancel();
          _attachments[message.sessionId] = _terminals
              .attach(message.sessionId, fromOffset: message.fromOffset)
              .listen(
                (event) => switch (event) {
                  PtyOutputEvent(:final chunk) => _send(
                    PtyOutput(
                      sessionId: message.sessionId,
                      offset: chunk.offset,
                      bytes: chunk.bytes,
                    ),
                  ),
                  PtyExitEvent(:final exitCode) => _send(
                    PtyExited(sessionId: message.sessionId, exitCode: exitCode),
                  ),
                },
              );

        case PtyDetach():
          await _attachments.remove(message.sessionId)?.cancel();

        case PtyInput():
          await _terminals.write(message.sessionId, message.bytes);

        case PtyAck():
          await _terminals.ack(message.sessionId, message.bytes);

        case PtyResize():
          await _terminals.resize(
            message.sessionId,
            message.rows,
            message.columns,
          );

        case PtyKill():
          await _attachments.remove(message.sessionId)?.cancel();
          await _terminals.kill(message.sessionId);

        case RpcRequest():
          await _handleRpc(message);

        // Resposta do CLIENTE a um comando da CLI que encaminhamos (direção
        // inversa do RPC: normalmente é o cliente que pergunta).
        case RpcResponse():
          _onRpcResponse?.call(message);

        // Tipo desconhecido (cliente mais novo): ignora — forward-compat.
        case UnknownMessage():
          break;

        case Hello() ||
            HelloAck() ||
            PtyOpened() ||
            PtySessions() ||
            PtyOutput() ||
            PtyExited() ||
            TurnStatus() ||
            RemoteError():
          _send(const RemoteError(code: 'bad_message'));
      }
    } on TerminalException catch (e) {
      _send(
        RemoteError(code: e.kind.name, detail: e.detail, rid: _ridOf(message)),
      );
    } catch (e) {
      _send(RemoteError(code: 'internal', detail: '$e', rid: _ridOf(message)));
    }
  }

  /// Prefixa a pasta da CLI `cockpit` deste host no PATH da PTY, para que
  /// `cockpit …` resolva num terminal remoto como resolve num local. Sem a CLI
  /// instalada, devolve vazio (e o comando segue "not found", como hoje).
  Map<String, String> _cliPathEnv(String? inherited) {
    final cli = RemoteServer.cliPath;
    if (cli == null || cli.isEmpty) return const <String, String>{};
    final dir = File(cli).parent.path;
    final sep = Platform.isWindows ? ';' : ':';
    final base = (inherited == null || inherited.isEmpty)
        ? (Platform.environment['PATH'] ?? '')
        : inherited;
    return <String, String>{'PATH': base.isEmpty ? dir : '$dir$sep$base'};
  }

  /// `rid` da requisição em tratamento, pra que o erro volte ao chamador certo
  /// (ver [PtyOpen.rid]): sem isso, um open que falha resolveria o future de
  /// OUTRO open em voo.
  static int? _ridOf(RemoteMessage message) => switch (message) {
    PtyOpen(:final rid) => rid,
    PtyList(:final rid) => rid,
    _ => null,
  };

  /// Domínios request/response (fs.*, git.*). Erros viram RpcResponse{ok:false}
  /// com code/detail tipados — a frase nasce na UI do cliente.
  Future<void> _handleRpc(RpcRequest req) async {
    try {
      final p = req.params;
      final data = switch (req.method) {
        'fs.list' => {
          'entries': [
            for (final e in await _files.list(p['path'] as String)) e.toJson(),
          ],
        },
        'fs.read' => {
          'b64': base64Encode(
            await _files.read(
              p['path'] as String,
              maxBytes: (p['max'] as num?)?.toInt() ?? 8 * 1024 * 1024,
            ),
          ),
        },
        'fs.write' => () async {
          await _files.write(
            p['path'] as String,
            base64Decode(p['b64'] as String),
          );
          return null;
        }(),
        'fs.home' => {'home': await _files.home()},
        'git.status' => (await _git.status(p['repo'] as String)).toJson(),
        'git.diff' => {
          'diff': await _git.diff(
            p['repo'] as String,
            p['file'] as String,
            staged: p['staged'] as bool? ?? false,
          ),
        },
        'git.stage' => () async {
          await _git.stage(
            p['repo'] as String,
            (p['files'] as List).cast<String>(),
          );
          return null;
        }(),
        'git.unstage' => () async {
          await _git.unstage(
            p['repo'] as String,
            (p['files'] as List).cast<String>(),
          );
          return null;
        }(),
        'git.commit' => () async {
          await _git.commit(p['repo'] as String, p['message'] as String);
          return null;
        }(),
        'git.run' => (await _git.run(
          p['repo'] as String,
          (p['args'] as List).cast<String>(),
        )).toJson(),
        'db.query' => _db.query(
          await _conn(p),
          p['sql'] as String,
          limit: (p['limit'] as num?)?.toInt() ?? 200,
          dml: p['dml'] as bool? ?? false,
        ),
        'db.redis' => _db.redis(await _conn(p), (p['parts'] as List).cast<String>()),
        'db.redisMany' => _db.redisMany(await _conn(p), [
          for (final c in (p['commands'] as List).cast<List>()) c.cast<String>(),
        ]),
        'db.mongo' => _db.mongo(
          await _conn(p),
          (p['command'] as Map).cast<String, Object?>(),
          database: p['database'] as String?,
        ),
        // Segredo de banco: escrita e remoção apenas. Não existe `db.secretGet`
        // de propósito (plano 62, decisão B) — o cliente é mensageiro, e
        // mensageiro não relê o que entregou.
        // `kind` escolhe QUAL segredo da conexão: a senha do banco (default) ou
        // a passphrase da chave SSH do túnel. São segredos distintos e a
        // conexão pode ter um sem o outro.
        'db.secretSet' => () {
          final root = p['root'] as String;
          final conn = p['conn'] as String;
          final key = p['kind'] == 'sshPassphrase'
              ? DbSecretStore.sshKeyFor(root, conn)
              : DbSecretStore.keyFor(root, conn);
          _dbSecrets.writeKey(key, p['value'] as String);
          return null;
        }(),
        // Confiança numa host key de bastion: a decisão é do humano, no
        // cliente (que tem o diálogo), e o estado fica aqui — mesmo idioma do
        // cofre de senhas. O servidor não pergunta nada a ninguém; ele falha
        // com `ssh_host_key_unknown` carregando o fingerprint e espera este
        // comando.
        'db.hostKeyTrust' => () async {
          await FileSshHostKeyStore().trust(
            p['endpoint'] as String,
            p['fingerprint'] as String,
          );
          return null;
        }(),
        'db.secretDelete' => () {
          final root = p['root'] as String;
          final conn = p['conn'] as String;
          _dbSecrets.deleteKey(
            p['kind'] == 'sshPassphrase'
                ? DbSecretStore.sshKeyFor(root, conn)
                : DbSecretStore.keyFor(root, conn),
          );
          return null;
        }(),
        // Renome acontece AQUI, e não como delete+set no cliente, porque o
        // cliente não pode ler o valor para regravá-lo — o segredo nunca sai
        // do host, nem para dar a volta.
        'db.secretRename' => () {
          _dbSecrets.rename(
            p['root'] as String,
            p['from'] as String,
            p['to'] as String,
          );
          return null;
        }(),
        _ => throw _RpcUnknown(req.method),
      };
      _send(RpcResponse(rid: req.rid, ok: true, data: await _awaited(data)));
    } on FileException catch (e) {
      _send(
        RpcResponse(
          rid: req.rid,
          ok: false,
          code: e.kind.name,
          detail: e.detail,
        ),
      );
    } on GitException catch (e) {
      _send(
        RpcResponse(
          rid: req.rid,
          ok: false,
          code: e.kind.name,
          detail: e.detail,
        ),
      );
    } on DbServiceException catch (e) {
      _send(
        RpcResponse(
          rid: req.rid,
          ok: false,
          code: e.kind.name,
          detail: e.detail,
        ),
      );
    } on _RpcUnknown catch (e) {
      _send(
        RpcResponse(
          rid: req.rid,
          ok: false,
          code: 'unknown_method',
          detail: e.method,
        ),
      );
    } catch (e) {
      _send(
        RpcResponse(rid: req.rid, ok: false, code: 'internal', detail: '$e'),
      );
    }
  }

  // Alguns ramos do switch são Future (write/stage/...); normaliza.
  Future<Object?> _awaited(Object? value) async =>
      value is Future ? await value : value;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final sub in _attachments.values) {
      await sub.cancel();
    }
    _attachments.clear();
    _socket.destroy();
    if (!_done.isCompleted) _done.complete();
  }
}

/// Receptor do status de turno no HOST (plano 60, Wave G). Espelha o
/// `TerminalStatusServerImpl` do cliente, mas do lado do servidor: um socket
/// UNIX local onde o `cockpit hook` (rodando junto do agente na PTY) escreve
/// UMA linha JSON por evento e fecha. Cada linha vira um [TurnStatus] entregue
/// ao [onStatus] (que o [RemoteServer] faz broadcast pros clientes).
///
/// Transporte por plataforma, igual ao do servidor: UDS no POSIX, TCP loopback
/// + token no Windows (ver [LocalEndpoint]). Quem diz ao hook onde escrever é o
/// [hookEnv], injetado no env de cada PTY. O envelope do hook é
/// `{paneId, st, ev, sid, tx, hn, tid?, tok?}` (ver cli/src/hook.rs).
class TurnStatusReceiver {
  TurnStatusReceiver(this.onStatus, {this.onCommand});

  final void Function(TurnStatus status) onStatus;

  /// Comando da CLI `cockpit` rodando NO HOST (`{"type":"cmd",…}`). O host não
  /// executa nada: encaminha ao cliente, que é quem tem abas, workspaces e
  /// conexões de banco, e devolve a resposta por esta mesma conexão.
  ///
  /// `null` = nenhum cliente conectado; a CLI recebe um erro em vez de pendurar.
  Future<Map<String, Object?>> Function(Map<String, Object?> request)?
  onCommand;

  LocalListener? _endpoint;
  String? socketPath;

  /// Token exigido no envelope quando o transporte é TCP (ver [hookEnv]).
  String? get token => _endpoint?.token;

  /// Env que leva o hook até aqui. No POSIX é o path do socket; no Windows,
  /// porta + token — as duas formas que o `cockpit hook` já sabe ler.
  Map<String, String> get hookEnv {
    final endpoint = _endpoint;
    if (endpoint == null) return const <String, String>{};
    final token = endpoint.token;
    if (token == null) {
      return <String, String>{'COCKPIT_STATUS_SOCK': endpoint.path};
    }
    return <String, String>{
      'COCKPIT_STATUS_PORT': '${endpoint.listener.port}',
      'COCKPIT_STATUS_TOKEN': token,
    };
  }

  Future<void> bind(String path) async {
    final endpoint = await LocalEndpoint.bind(path);
    _endpoint = endpoint;
    socketPath = path;
    endpoint.listener.listen(_accept);
  }

  void _accept(Socket socket) {
    // Uma linha JSON por conexão. O hook (status) escreve e fecha; a CLI
    // (comando) espera UMA linha de resposta antes de fechar — por isso o
    // socket é passado adiante em vez de destruído no fim da linha.
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleLine(line, socket),
          onError: (Object _) => socket.destroy(),
          onDone: socket.destroy,
        );
  }

  void _handleLine(String line, [Socket? socket]) {
    if (line.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final json = decoded.cast<String, Object?>();
    // Loopback TCP (Windows) aceita qualquer processo local: só entra quem
    // traz o token que foi injetado no env da PTY.
    final expected = _endpoint?.token;
    if (expected != null && json['tok'] != expected) return;
    // Envelope da CLI interna (`type:"cmd"`) — mesmo socket do hook,
    // discriminado pelo campo `type`, como no app cliente.
    if (json['type'] == 'cmd') {
      _handleCommand(json, socket);
      return;
    }
    final paneId = json['paneId'];
    final status = json['st'];
    if (paneId is! String || status is! String) return;
    onStatus(
      TurnStatus(
        paneId: paneId,
        status: status,
        event: json['ev'] as String?,
        sid: json['sid'] as String?,
        transcriptPath: json['tx'] as String?,
        harness: json['hn'] as String?,
      ),
    );
  }

  /// Encaminha o comando ao cliente e escreve a resposta de volta no socket.
  /// Erro vira `{ok:false,error:…}` — a CLI já sabe ler essa forma.
  Future<void> _handleCommand(
    Map<String, Object?> request,
    Socket? socket,
  ) async {
    if (socket == null) return;
    Map<String, Object?> reply;
    final handler = onCommand;
    if (handler == null) {
      reply = <String, Object?>{
        'ok': false,
        'error': 'no Cockpit client attached to this host',
      };
    } else {
      try {
        reply = await handler(request);
      } on Object catch (e) {
        reply = <String, Object?>{'ok': false, 'error': '$e'};
      }
    }
    try {
      socket.write('${jsonEncode(reply)}\n');
      await socket.flush();
    } on Object {
      // Cliente da CLI desistiu (Ctrl-C / timeout) — nada a fazer.
    }
    await socket.close();
  }

  Future<void> close() async {
    // O endpoint fecha o listener e apaga o inode/arquivo anunciado.
    await _endpoint?.close();
    _endpoint = null;
  }
}
