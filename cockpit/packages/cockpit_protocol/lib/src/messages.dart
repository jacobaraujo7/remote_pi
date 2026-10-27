import 'dart:convert';
import 'dart:typed_data';

/// Versão do protocolo. Incrementa em mudança incompatível; o handshake
/// rejeita versões diferentes (cliente decide se faz bootstrap/update).
///
/// 2: `rid` de correlação nas requisições `pty.open`/`pty.list` (ver
/// [PtyOpen.rid]). Incompatível na prática: um cliente 2 falando com um
/// servidor 1 nunca receberia o `rid` de volta e ficaria esperando a resposta
/// para sempre. Melhor falhar no handshake, que já tem tratamento e oferece
/// atualizar o servidor, do que abrir terminal que não responde.
const int protocolVersion = 2;

/// Mensagem do protocolo. Envelope JSON: `{"t": "<tipo>", ...campos}`.
sealed class RemoteMessage {
  const RemoteMessage();

  String get type;

  Map<String, Object?> toJson();

  static RemoteMessage fromJson(Map<String, Object?> json) {
    final t = json['t'];
    return switch (t) {
      Hello.kType => Hello.fromJson(json),
      HelloAck.kType => HelloAck.fromJson(json),
      PtyOpen.kType => PtyOpen.fromJson(json),
      PtyOpened.kType => PtyOpened.fromJson(json),
      PtyList.kType => PtyList.fromJson(json),
      PtySessions.kType => PtySessions.fromJson(json),
      PtyAttach.kType => PtyAttach.fromJson(json),
      PtyDetach.kType => PtyDetach.fromJson(json),
      PtyInput.kType => PtyInput.fromJson(json),
      PtyAck.kType => PtyAck.fromJson(json),
      PtyOutput.kType => PtyOutput.fromJson(json),
      PtyResize.kType => PtyResize.fromJson(json),
      PtyKill.kType => PtyKill.fromJson(json),
      PtyExited.kType => PtyExited.fromJson(json),
      TurnStatus.kType => TurnStatus.fromJson(json),
      RpcRequest.kType => RpcRequest.fromJson(json),
      RpcResponse.kType => RpcResponse.fromJson(json),
      RemoteError.kType => RemoteError.fromJson(json),
      // Tolerante a tipos desconhecidos (forward-compat): um cliente/servidor
      // mais antigo simplesmente ignora um `t` que não conhece, em vez de
      // derrubar o stream. Assim dá pra adicionar eventos (ex.: turn.status)
      // sem bump de versão nem quebrar conexões existentes.
      _ => UnknownMessage(t),
    };
  }
}

/// Mensagem de tipo desconhecido (versão do outro lado é mais nova). Ignorada
/// pelos dispatchers; existe só pra não quebrar o stream.
class UnknownMessage extends RemoteMessage {
  const UnknownMessage(this.rawType);
  final Object? rawType;
  @override
  String get type => 'unknown';
  @override
  Map<String, Object?> toJson() => {'t': rawType};
}

// ---------------------------------------------------------------------------
// Handshake
// ---------------------------------------------------------------------------

class Hello extends RemoteMessage {
  const Hello({
    required this.version,
    required this.client,
    this.token,
    this.local = false,
  });
  static const kType = 'hello';

  final int version;
  final String client;

  /// Cliente na MESMA máquina que o servidor (sidecar), e não do outro lado de
  /// um túnel SSH. Muda uma coisa só, mas decisiva: as PTYs de um cliente local
  /// mantêm o `COCKPIT_STATUS_SOCK` que ELE injetou, porque aquele socket é a
  /// via da CLI interna (`cockpit send`, `list-tabs`, `db`...) além do status
  /// de turno. Sobrescrevê-lo pelo receptor do servidor — correto para um host
  /// remoto, cujo socket o agente não alcança — deixaria a CLI muda em toda aba.
  final bool local;

  /// Token do endpoint local, exigido onde o transporte é TCP de loopback
  /// (Windows — ver `LocalEndpoint`). `null` sobre socket UNIX ou túnel SSH,
  /// onde o próprio canal já é a credencial. Campo opcional: cliente e
  /// servidor de versões diferentes seguem se entendendo no POSIX.
  final String? token;

  factory Hello.fromJson(Map<String, Object?> j) => Hello(
    version: j['v'] as int,
    client: j['client'] as String,
    token: j['tok'] as String?,
    local: j['loc'] as bool? ?? false,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'v': version,
    'client': client,
    if (token != null) 'tok': token,
    if (local) 'loc': true,
  };
}

class HelloAck extends RemoteMessage {
  const HelloAck({
    required this.version,
    required this.server,
    this.executable,
    this.pid,
  });
  static const kType = 'hello.ack';

  final int version;
  final String server;

  /// Caminho do executável do servidor. Serve para o cliente LOCAL decidir se
  /// adota um servidor que já estava de pé: `server` é a versão do pacote
  /// `cockpit_server`, que quase nunca muda entre releases do app e portanto
  /// não distingue um sidecar velho de um novo — o caminho distingue.
  ///
  /// Sem isso, um app recém-atualizado adotava em silêncio o servidor de uma
  /// instalação anterior (ou de uma pasta temporária) e seguia rodando o
  /// binário antigo. Foi assim que uma correção publicada não chegou a rodar.
  final String? executable;

  /// Pid do servidor, para o cliente encerrar um adotado que não serve.
  final int? pid;

  factory HelloAck.fromJson(Map<String, Object?> j) => HelloAck(
    version: j['v'] as int,
    server: j['server'] as String,
    executable: j['exe'] as String?,
    pid: j['pid'] as int?,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'v': version,
    'server': server,
    if (executable != null) 'exe': executable,
    if (pid != null) 'pid': pid,
  };
}

// ---------------------------------------------------------------------------
// Terminais
// ---------------------------------------------------------------------------

class PtyOpen extends RemoteMessage {
  const PtyOpen({
    required this.executable,
    this.rid,
    this.arguments = const [],
    this.workingDirectory,
    this.environment = const {},
    this.rows = 24,
    this.columns = 80,
    this.flowControlled = false,
  });
  static const kType = 'pty.open';

  /// Correlação request/response, como no par `rpc`/`rpc.res`. Sem ela, dois
  /// `pty.open` em voo ao mesmo tempo (restaurar um workspace com dois panes)
  /// disputavam a MESMA `pty.opened`: os dois terminais adotavam o mesmo
  /// `sessionId`, liam o mesmo PTY (espelho) e o segundo PTY ficava órfão.
  /// O servidor ecoa este valor na resposta.
  final int? rid;

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final int rows;
  final int columns;

  /// Backpressure fim-a-fim: o servidor abre o PTY com `ackRead` e gate por
  /// janela de créditos; o cliente devolve `pty.ack` por chunk consumido.
  final bool flowControlled;

  factory PtyOpen.fromJson(Map<String, Object?> j) => PtyOpen(
    rid: j['rid'] as int?,
    executable: j['cmd'] as String,
    arguments: (j['args'] as List? ?? const []).cast<String>(),
    workingDirectory: j['cwd'] as String?,
    environment: (j['env'] as Map? ?? const {}).cast<String, String>(),
    rows: j['rows'] as int? ?? 24,
    columns: j['cols'] as int? ?? 80,
    flowControlled: j['flow'] as bool? ?? false,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    if (rid != null) 'rid': rid,
    'cmd': executable,
    'args': arguments,
    if (workingDirectory != null) 'cwd': workingDirectory,
    if (environment.isNotEmpty) 'env': environment,
    'rows': rows,
    'cols': columns,
    if (flowControlled) 'flow': true,
  };
}

/// Crédito de flow control: o cliente consumiu [bytes] de `pty.output` da
/// sessão. O servidor abate da janela pendente e libera a leitura nativa.
class PtyAck extends RemoteMessage {
  const PtyAck({required this.sessionId, required this.bytes});
  static const kType = 'pty.ack';

  final String sessionId;
  final int bytes;

  factory PtyAck.fromJson(Map<String, Object?> j) =>
      PtyAck(sessionId: j['id'] as String, bytes: j['n'] as int);

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {'t': kType, 'id': sessionId, 'n': bytes};
}

class PtyOpened extends RemoteMessage {
  const PtyOpened({required this.sessionId, required this.pid, this.rid});
  static const kType = 'pty.opened';

  final String sessionId;
  final int pid;

  /// Eco do [PtyOpen.rid] que originou esta resposta (ver lá o porquê).
  final int? rid;

  factory PtyOpened.fromJson(Map<String, Object?> j) => PtyOpened(
    sessionId: j['id'] as String,
    pid: j['pid'] as int,
    rid: j['rid'] as int?,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'id': sessionId,
    'pid': pid,
    if (rid != null) 'rid': rid,
  };
}

class PtyList extends RemoteMessage {
  const PtyList({this.rid});
  static const kType = 'pty.list';

  /// Correlação request/response (ver [PtyOpen.rid]).
  final int? rid;

  factory PtyList.fromJson(Map<String, Object?> j) =>
      PtyList(rid: j['rid'] as int?);

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {'t': kType, if (rid != null) 'rid': rid};
}

class PtySessions extends RemoteMessage {
  const PtySessions({required this.sessions, this.rid});
  static const kType = 'pty.sessions';

  /// Cada item: {id, pid, cmd, rows, cols, len, exit?}
  final List<Map<String, Object?>> sessions;

  /// Eco do [PtyList.rid] que originou esta resposta.
  final int? rid;

  factory PtySessions.fromJson(Map<String, Object?> j) => PtySessions(
    sessions: (j['sessions'] as List)
        .cast<Map>()
        .map((m) => m.cast<String, Object?>())
        .toList(),
    rid: j['rid'] as int?,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'sessions': sessions,
    if (rid != null) 'rid': rid,
  };
}

class PtyAttach extends RemoteMessage {
  const PtyAttach({required this.sessionId, this.fromOffset = 0});
  static const kType = 'pty.attach';

  final String sessionId;
  final int fromOffset;

  factory PtyAttach.fromJson(Map<String, Object?> j) => PtyAttach(
    sessionId: j['id'] as String,
    fromOffset: j['from'] as int? ?? 0,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'id': sessionId,
    'from': fromOffset,
  };
}

class PtyDetach extends RemoteMessage {
  const PtyDetach({required this.sessionId});
  static const kType = 'pty.detach';

  final String sessionId;

  factory PtyDetach.fromJson(Map<String, Object?> j) =>
      PtyDetach(sessionId: j['id'] as String);

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {'t': kType, 'id': sessionId};
}

class PtyInput extends RemoteMessage {
  PtyInput({required this.sessionId, required this.bytes});
  static const kType = 'pty.input';

  final String sessionId;
  final Uint8List bytes;

  factory PtyInput.fromJson(Map<String, Object?> j) => PtyInput(
    sessionId: j['id'] as String,
    bytes: base64Decode(j['d'] as String),
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'id': sessionId,
    'd': base64Encode(bytes),
  };
}

class PtyOutput extends RemoteMessage {
  PtyOutput({
    required this.sessionId,
    required this.offset,
    required this.bytes,
  });
  static const kType = 'pty.output';

  final String sessionId;

  /// Offset absoluto do primeiro byte deste chunk no stream da sessão.
  final int offset;
  final Uint8List bytes;

  factory PtyOutput.fromJson(Map<String, Object?> j) => PtyOutput(
    sessionId: j['id'] as String,
    offset: j['off'] as int,
    bytes: base64Decode(j['d'] as String),
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'id': sessionId,
    'off': offset,
    'd': base64Encode(bytes),
  };
}

class PtyResize extends RemoteMessage {
  const PtyResize({
    required this.sessionId,
    required this.rows,
    required this.columns,
  });
  static const kType = 'pty.resize';

  final String sessionId;
  final int rows;
  final int columns;

  factory PtyResize.fromJson(Map<String, Object?> j) => PtyResize(
    sessionId: j['id'] as String,
    rows: j['rows'] as int,
    columns: j['cols'] as int,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'id': sessionId,
    'rows': rows,
    'cols': columns,
  };
}

class PtyKill extends RemoteMessage {
  const PtyKill({required this.sessionId});
  static const kType = 'pty.kill';

  final String sessionId;

  factory PtyKill.fromJson(Map<String, Object?> j) =>
      PtyKill(sessionId: j['id'] as String);

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {'t': kType, 'id': sessionId};
}

class PtyExited extends RemoteMessage {
  const PtyExited({required this.sessionId, required this.exitCode});
  static const kType = 'pty.exited';

  final String sessionId;
  final int exitCode;

  factory PtyExited.fromJson(Map<String, Object?> j) =>
      PtyExited(sessionId: j['id'] as String, exitCode: j['code'] as int);

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'id': sessionId,
    'code': exitCode,
  };
}

// ---------------------------------------------------------------------------
// Turn status (spinner/chime do agente — plano 60, Wave G)
// ---------------------------------------------------------------------------

/// Evento server→cliente de status de turno de um agente (Claude Code/Codex)
/// rodando numa PTY do host. Nasce do hook do agente (no host), que escreve num
/// socket local; o servidor o converte nesta mensagem e a envia pelo protocolo.
/// O cliente roteia por [paneId] (o `COCKPIT_PANE_ID` da aba) e reusa o mesmo
/// caminho do status local (`applyClaudeStatus`) → spinner + som.
class TurnStatus extends RemoteMessage {
  const TurnStatus({
    required this.paneId,
    required this.status,
    this.event,
    this.sid,
    this.transcriptPath,
    this.harness,
    this.subagentId,
    this.subagentType,
    this.eventEpochMs,
  });
  static const kType = 'turn.status';

  /// Aba dona (o `COCKPIT_PANE_ID` que o cliente injetou e o host reportou).
  final String paneId;

  /// `working` | `idle` | `waiting`.
  final String status;

  /// Evento cru do harness (ex.: `UserPromptSubmit`, `Stop`) — a UI usa pra
  /// saber se é início de turno.
  final String? event;
  final String? sid;
  final String? transcriptPath;
  final String? harness;
  final String? subagentId;
  final String? subagentType;
  final int? eventEpochMs;

  factory TurnStatus.fromJson(Map<String, Object?> j) => TurnStatus(
    paneId: j['pane'] as String,
    status: j['st'] as String,
    event: j['ev'] as String?,
    sid: j['sid'] as String?,
    transcriptPath: j['tx'] as String?,
    harness: j['hn'] as String?,
    subagentId: j['aid'] as String?,
    subagentType: j['at'] as String?,
    eventEpochMs: j['ts'] as int?,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'pane': paneId,
    'st': status,
    if (event != null) 'ev': event,
    if (sid != null) 'sid': sid,
    if (transcriptPath != null) 'tx': transcriptPath,
    if (harness != null) 'hn': harness,
    if (subagentId != null) 'aid': subagentId,
    if (subagentType != null) 'at': subagentType,
    if (eventEpochMs != null) 'ts': eventEpochMs,
  };
}

// ---------------------------------------------------------------------------
// RPC request/response (domínios Arquivos e Git — plano 58, Wave 3)
// ---------------------------------------------------------------------------

/// Chamada request/response correlacionada por [rid]. Envelope genérico para
/// os domínios não-streaming (fs.*, git.*): evita explosão de classes e dá
/// correlação de graça. `method` é `<domínio>.<op>` (ex.: `fs.list`).
class RpcRequest extends RemoteMessage {
  const RpcRequest({
    required this.rid,
    required this.method,
    this.params = const {},
  });
  static const kType = 'rpc';

  final int rid;
  final String method;
  final Map<String, Object?> params;

  factory RpcRequest.fromJson(Map<String, Object?> j) => RpcRequest(
    rid: j['rid'] as int,
    method: j['m'] as String,
    params: (j['p'] as Map? ?? const {}).cast<String, Object?>(),
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'rid': rid,
    'm': method,
    'p': params,
  };
}

/// Resposta de um [RpcRequest]. `ok=false` carrega `code`/`detail` tipados
/// (a frase nasce na UI). `data` é o payload JSON-able quando `ok`.
class RpcResponse extends RemoteMessage {
  const RpcResponse({
    required this.rid,
    required this.ok,
    this.data,
    this.code,
    this.detail,
  });
  static const kType = 'rpc.res';

  final int rid;
  final bool ok;
  final Object? data;
  final String? code;
  final String? detail;

  factory RpcResponse.fromJson(Map<String, Object?> j) => RpcResponse(
    rid: j['rid'] as int,
    ok: j['ok'] as bool,
    data: j['data'],
    code: j['code'] as String?,
    detail: j['detail'] as String?,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'rid': rid,
    'ok': ok,
    if (data != null) 'data': data,
    if (code != null) 'code': code,
    if (detail != null) 'detail': detail,
  };
}

// ---------------------------------------------------------------------------
// Erro
// ---------------------------------------------------------------------------

class RemoteError extends RemoteMessage {
  const RemoteError({
    required this.code,
    this.detail,
    this.sessionId,
    this.rid,
  });
  static const kType = 'err';

  /// Eco do `rid` da requisição que falhou, quando o erro é resposta a uma
  /// (ver [PtyOpen.rid]). `null` em erro não solicitado (ex.: handshake).
  final int? rid;

  /// Código estável (ex.: `session_not_found`, `spawn_failed`,
  /// `version_mismatch`, `bad_message`). A frase nasce na UI.
  final String code;
  final String? detail;
  final String? sessionId;

  factory RemoteError.fromJson(Map<String, Object?> j) => RemoteError(
    code: j['code'] as String,
    detail: j['detail'] as String?,
    sessionId: j['id'] as String?,
    rid: j['rid'] as int?,
  );

  @override
  String get type => kType;
  @override
  Map<String, Object?> toJson() => {
    't': kType,
    'code': code,
    if (detail != null) 'detail': detail,
    if (sessionId != null) 'id': sessionId,
    if (rid != null) 'rid': rid,
  };
}
