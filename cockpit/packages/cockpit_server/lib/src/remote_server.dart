import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

class _RpcUnknown implements Exception {
  const _RpcUnknown(this.method);
  final String method;
}

/// Converts a wire-level PTY open request into the host-side spawn spec.
/// Keeping the mapping in one function prevents flow-control options from
/// being lost when the request crosses the server boundary.
PtySpawnSpec ptySpawnSpecFromOpen(PtyOpen message, {String? statusSocketPath}) {
  final environment = statusSocketPath == null
      ? message.environment
      : {...message.environment, 'COCKPIT_STATUS_SOCK': statusSocketPath};
  return PtySpawnSpec(
    executable: message.executable,
    arguments: message.arguments,
    workingDirectory: message.workingDirectory,
    environment: environment,
    rows: message.rows,
    columns: message.columns,
    flowControlled: message.flowControlled,
  );
}

/// Servidor do protocolo Cockpit Remote sobre socket local (UDS).
///
/// Sessões pertencem ao [TerminalService], não às conexões: um cliente que
/// desconecta faz detach implícito e a sessão continua viva (reattach later).
class RemoteServer {
  RemoteServer(
    this._terminals,
    this._files,
    this._git,
    this._db, {
    this.serverVersion = '0.1.0',
  });

  final TerminalService _terminals;
  final FileService _files;
  final GitService _git;
  final DbService _db;
  final String serverVersion;
  static const _codec = RemoteMessageCodec();

  ServerSocket? _listener;
  final Set<_Connection> _connections = {};

  /// Receptor do status de turno (socket local do host onde o hook do agente
  /// escreve). `null` até o [bind]. Cada linha vira um [TurnStatus] broadcast
  /// pras conexões (plano 60, Wave G).
  TurnStatusReceiver? _statusReceiver;
  String? get _statusSocketPath => _statusReceiver?.socketPath;

  /// Modo sidecar: quando > Duration.zero, o servidor se encerra sozinho se
  /// ficar esse tempo sem NENHUM cliente conectado (evita órfão quando a GUI
  /// morre sem conseguir matar o filho). Zero = nunca (modo serviço).
  Duration exitOnIdle = Duration.zero;
  Timer? _idleTimer;
  void Function()? onIdleExit;

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (exitOnIdle == Duration.zero || _connections.isNotEmpty) return;
    _idleTimer = Timer(exitOnIdle, () {
      if (_connections.isEmpty) onIdleExit?.call();
    });
  }

  Future<void> bind(String socketPath) async {
    final file = File(socketPath);
    if (file.existsSync()) file.deleteSync();
    _listener = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    _listener!.listen(_accept);
    // Socket de status ao lado do socket principal. Falha ao bindar (ex.: path
    // longo demais) é não-fatal: o servidor segue sem turn-status.
    _statusReceiver = TurnStatusReceiver(_broadcastTurnStatus);
    try {
      await _statusReceiver!.bind('$socketPath.status');
    } catch (_) {
      _statusReceiver = null;
    }
    _armIdleTimer();
  }

  /// Reenvia um status de turno (vindo do hook no host) pra todos os clientes
  /// conectados. O cliente roteia por `paneId` — típico 1 cliente por host.
  void _broadcastTurnStatus(TurnStatus status) {
    for (final connection in _connections) {
      connection._send(status);
    }
  }

  Future<void> close() async {
    for (final connection in _connections.toList()) {
      await connection.close();
    }
    await _statusReceiver?.close();
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
      serverVersion,
      _statusSocketPath,
    );
    _connections.add(connection);
    _idleTimer?.cancel();
    connection.done.whenComplete(() {
      _connections.remove(connection);
      _armIdleTimer();
    });
  }
}

class _Connection {
  _Connection(
    this._socket,
    this._terminals,
    this._files,
    this._git,
    this._db,
    this._serverVersion,
    this._statusSocketPath,
  ) {
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

  final Socket _socket;
  final TerminalService _terminals;
  final FileService _files;
  final GitService _git;
  final DbService _db;
  final String _serverVersion;

  /// Socket local (no host) onde o hook do agente escreve o status de turno. É
  /// injetado como `COCKPIT_STATUS_SOCK` no env de cada PTY, pra o hook alcançar
  /// (plano 60, Wave G). `null` = turn-status desligado.
  final String? _statusSocketPath;

  final Map<String, StreamSubscription<PtyEvent>> _attachments = {};
  final Completer<void> _done = Completer();
  bool _handshaken = false;
  bool _closed = false;

  Future<void> get done => _done.future;

  void _send(RemoteMessage message) {
    if (_closed) return;
    _socket.add(utf8.encode(RemoteServer._codec.encode(message)));
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
        _handshaken = true;
        _send(HelloAck(version: protocolVersion, server: _serverVersion));
        return;
      }

      switch (message) {
        case PtyOpen():
          // Injeta o socket de status do HOST no env da PTY (o cliente já
          // manda COCKPIT_PANE_ID); assim o hook do agente no host alcança o
          // servidor, que reenvia o turno pelo protocolo (Wave G). O env do
          // cliente NÃO sobrescreve isto (o socket do cliente é inalcançável do
          // host).
          final info = await _terminals.open(
            ptySpawnSpecFromOpen(message, statusSocketPath: _statusSocketPath),
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
            RpcResponse() ||
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
          RemoteDbConnDescriptor.fromJson(
            (p['conn'] as Map).cast<String, Object?>(),
          ),
          p['sql'] as String,
          limit: (p['limit'] as num?)?.toInt() ?? 200,
          dml: p['dml'] as bool? ?? false,
        ),
        'db.redis' => _db.redis(
          RemoteDbConnDescriptor.fromJson(
            (p['conn'] as Map).cast<String, Object?>(),
          ),
          (p['parts'] as List).cast<String>(),
        ),
        'db.redisMany' => _db.redisMany(
          RemoteDbConnDescriptor.fromJson(
            (p['conn'] as Map).cast<String, Object?>(),
          ),
          [
            for (final c in (p['commands'] as List).cast<List>())
              c.cast<String>(),
          ],
        ),
        'db.mongo' => _db.mongo(
          RemoteDbConnDescriptor.fromJson(
            (p['conn'] as Map).cast<String, Object?>(),
          ),
          (p['command'] as Map).cast<String, Object?>(),
          database: p['database'] as String?,
        ),
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
/// Só POSIX: no host remoto (macOS/Linux) o transporte é UDS. O envelope do
/// hook é `{paneId, st, ev, sid, tx, hn, tid?, tok?}` (ver cli/src/hook.rs).
class TurnStatusReceiver {
  TurnStatusReceiver(this.onStatus);

  final void Function(TurnStatus status) onStatus;

  ServerSocket? _listener;
  String? socketPath;

  Future<void> bind(String path) async {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    _listener = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    socketPath = path;
    _listener!.listen(_accept);
  }

  void _accept(Socket socket) {
    // Uma linha JSON por conexão; o hook fecha logo após escrever.
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (Object _) => socket.destroy(),
          onDone: socket.destroy,
        );
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final json = decoded.cast<String, Object?>();
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

  Future<void> close() async {
    await _listener?.close();
    final path = socketPath;
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}
