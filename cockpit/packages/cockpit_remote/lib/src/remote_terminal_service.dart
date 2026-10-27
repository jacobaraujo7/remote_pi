import 'dart:async';
import 'dart:typed_data';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'remote_connection.dart';

/// Status de turno de um agente numa PTY do host (plano 60, Wave G), tipo
/// neutro pro cliente — não expõe a mensagem do protocolo. [paneId] é o
/// `COCKPIT_PANE_ID` da aba (roteamento); [status] é `working`/`idle`/`waiting`.
class RemoteTurnStatus {
  const RemoteTurnStatus({
    required this.paneId,
    required this.status,
    this.event,
    this.sid,
    this.transcriptPath,
    this.harness,
    this.subagentId,
    this.subagentType,
    this.eventAt,
  });

  final String paneId;
  final String status;
  final String? event;
  final String? sid;
  final String? transcriptPath;
  final String? harness;
  final String? subagentId;
  final String? subagentType;
  final DateTime? eventAt;
}

/// Um comando da CLI do host à espera de resposta deste cliente.
class RemoteCliCommand {
  const RemoteCliCommand({
    required this.request,
    required this.respond,
    required this.fail,
  });

  /// Envelope cru da CLI (`{cmd, args, tabId}`) — o mesmo que o socket local
  /// entrega, para que o handler não precise saber de onde veio.
  final Map<String, Object?> request;

  final void Function(Object? data) respond;
  final void Function(String message) fail;
}

/// Proxy do [TerminalService] falando o protocolo com um cockpit-server.
///
/// A UI consome este e o nativo pelo MESMO contrato; a diferença é só a
/// composição (plano 58, "Arquitetura de pacotes").
class RemoteTerminalService implements TerminalService {
  RemoteTerminalService(this._connection);

  final RemoteConnection _connection;

  /// Metrics are collected by the host that owns the PTY PID. The client
  /// never interprets a remote PID in its local process namespace.
  Future<Map<String, Object?>> processMetrics(String sessionId) async {
    final data = await _connection.call('process.metrics', {
      'session': sessionId,
    });
    return (data as Map).cast<String, Object?>();
  }

  /// Comandos da CLI `cockpit` rodando **no host**, encaminhados pelo servidor
  /// (direção inversa do RPC). O host não executa nada: quem tem abas,
  /// workspaces e conexões de banco é este cliente.
  ///
  /// Cada item traz o pedido e o `respond` que devolve a resposta pela mesma
  /// `rid`. Fora do contrato [TerminalService], como o [turnStatus].
  Stream<RemoteCliCommand> get cliCommands => _connection.messages
      .where((m) => m is RpcRequest && m.method == 'cli.cmd')
      .cast<RpcRequest>()
      .map(
        (m) => RemoteCliCommand(
          request: m.params,
          respond: (data) =>
              _connection.send(RpcResponse(rid: m.rid, ok: true, data: data)),
          fail: (message) => _connection.send(
            RpcResponse(rid: m.rid, ok: false, code: 'cli', detail: message),
          ),
        ),
      );

  /// Eventos de status de turno vindos do host (broadcast do protocolo). Fora
  /// do contrato [TerminalService]; consumido pelo connector/gateway remoto.
  Stream<RemoteTurnStatus> get turnStatus => _connection.messages
      .where((m) => m is TurnStatus)
      .cast<TurnStatus>()
      .map(
        (m) => RemoteTurnStatus(
          paneId: m.paneId,
          status: m.status,
          event: m.event,
          sid: m.sid,
          transcriptPath: m.transcriptPath,
          harness: m.harness,
          subagentId: m.subagentId,
          subagentType: m.subagentType,
          eventAt: m.eventEpochMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(m.eventEpochMs!),
        ),
      );

  @override
  Future<PtySessionInfo> open(PtySpawnSpec spec) async {
    final rid = _nextRid();
    final reply = _firstReply(
      (m) =>
          (m is PtyOpened && m.rid == rid) ||
          (m is RemoteError && m.rid == rid),
    );
    _connection.send(
      PtyOpen(
        rid: rid,
        executable: spec.executable,
        arguments: spec.arguments,
        workingDirectory: spec.workingDirectory,
        environment: spec.environment,
        rows: spec.rows,
        columns: spec.columns,
        flowControlled: spec.flowControlled,
      ),
    );
    final message = await reply;
    if (message is RemoteError) throw _asException(message);
    final opened = message as PtyOpened;
    return PtySessionInfo(
      id: opened.sessionId,
      pid: opened.pid,
      executable: spec.executable,
      rows: spec.rows,
      columns: spec.columns,
      scrollbackLength: 0,
    );
  }

  @override
  Future<List<PtySessionInfo>> sessions() async {
    final rid = _nextRid();
    final reply = _firstReply(
      (m) =>
          (m is PtySessions && m.rid == rid) ||
          (m is RemoteError && m.rid == rid),
    );
    _connection.send(PtyList(rid: rid));
    final message = await reply;
    if (message is RemoteError) throw _asException(message);
    final sessions = (message as PtySessions).sessions;
    return [
      for (final s in sessions)
        PtySessionInfo(
          id: s['id'] as String,
          pid: s['pid'] as int,
          executable: s['cmd'] as String,
          rows: s['rows'] as int,
          columns: s['cols'] as int,
          scrollbackLength: s['len'] as int,
          exitCode: s['exit'] as int?,
        ),
    ];
  }

  @override
  Stream<PtyEvent> attach(String sessionId, {int fromOffset = 0}) {
    late StreamController<PtyEvent> controller;
    StreamSubscription<RemoteMessage>? sub;
    controller = StreamController<PtyEvent>(
      onListen: () {
        sub = _connection.messages.listen((message) {
          if (message is PtyOutput && message.sessionId == sessionId) {
            controller.add(
              PtyOutputEvent(
                PtyOutputChunk(offset: message.offset, bytes: message.bytes),
              ),
            );
          } else if (message is PtyExited && message.sessionId == sessionId) {
            controller.add(PtyExitEvent(message.exitCode));
          } else if (message is RemoteError && message.sessionId == sessionId) {
            controller.addError(_asException(message));
          }
        }, onDone: controller.close);
        _connection.send(
          PtyAttach(sessionId: sessionId, fromOffset: fromOffset),
        );
      },
      onCancel: () {
        _connection.send(PtyDetach(sessionId: sessionId));
        return sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> write(String sessionId, Uint8List data) async =>
      _connection.send(PtyInput(sessionId: sessionId, bytes: data));

  @override
  Future<void> resize(String sessionId, int rows, int columns) async =>
      _connection.send(
        PtyResize(sessionId: sessionId, rows: rows, columns: columns),
      );

  @override
  Future<void> ack(String sessionId, int bytes) async =>
      _connection.send(PtyAck(sessionId: sessionId, bytes: bytes));

  @override
  Future<void> kill(String sessionId) async =>
      _connection.send(PtyKill(sessionId: sessionId));

  @override
  Future<void> dispose() => _connection.close();

  Future<RemoteMessage> _firstReply(bool Function(RemoteMessage) test) =>
      _connection.messages.firstWhere(test);

  /// Id de correlação, crescente por conexão. O casamento request/response é
  /// por ele — NUNCA só pelo tipo da mensagem: `messages` é broadcast, então
  /// duas chamadas em voo ao mesmo tempo eram resolvidas as duas pela primeira
  /// resposta que chegasse (dois panes restaurados juntos adotavam o mesmo
  /// `sessionId` e espelhavam o mesmo PTY).
  int _nextRid() => ++_rid;
  int _rid = 0;

  static TerminalException _asException(RemoteError error) {
    final kind =
        TerminalErrorKind.values.asNameMap()[error.code] ??
        TerminalErrorKind.protocol;
    return TerminalException(kind, error.detail);
  }
}
