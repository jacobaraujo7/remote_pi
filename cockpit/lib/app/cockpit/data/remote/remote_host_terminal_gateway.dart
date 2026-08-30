import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart'
    show SpawnDirectory;
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_remote/cockpit_remote.dart';

/// [TerminalGateway] de um workspace REMOTO: o PTY roda no `cockpit-server`
/// do host (via túnel SSH) e o emulador continua no cliente (plano 58,
/// Wave 2). Mesma forma do [SidecarTerminalGateway], com duas diferenças:
///
/// - a fonte do serviço é um [RemoteHostConnector] (SSH), não o sidecar local;
/// - **sem fallback in-process**: um workspace remoto sem host alcançável é um
///   erro (o stream fecha e a aba mostra o encerramento), nunca um shell
///   local silencioso na máquina errada.
class RemoteHostTerminalGateway implements TerminalGateway {
  RemoteHostTerminalGateway(this._connector);

  final RemoteHostConnector _connector;

  RemoteTerminalService? _service;
  String? _sessionId;
  StreamSubscription<PtyEvent>? _attachment;

  // Flow control por contador acumulado (mesma razão do gateway do sidecar).
  int _bytesDelivered = 0;
  int _bytesAcked = 0;

  final StreamController<List<int>> _output = StreamController<List<int>>();
  final List<void Function()> _queued = [];
  bool _ready = false;
  bool _killed = false;

  /// Conexão caiu com a sessão VIVA no host: a aba congela (mantém buffer e
  /// [_bytesDelivered]) e espera o connector reconectar para re-anexar. É o que
  /// diferencia queda de transporte do fim real do processo — só o segundo
  /// fecha a aba.
  bool _detached = false;

  /// Último tamanho pedido pela view. Reenviado no re-attach: a aba pode ter
  /// sido redimensionada enquanto esteve desanexada, e o PTY remoto não soube.
  int _rows = 25;
  int _columns = 80;

  StreamSubscription<RemoteTerminalService>? _reconnectSub;

  /// A sessão terminou de fato (processo saiu)? Congelar aqui seria errado.
  bool _exited = false;

  /// A sessão não existia mais no host ao reconectar (servidor reiniciado): não
  /// há o que retomar, então a aba encerra em vez de ficar muda.
  bool _sessionLost = false;

  /// A aba encerrou porque a sessão remota se perdeu na reconexão? A UI usa
  /// para diferenciar de um processo que terminou normalmente.
  bool get sessionLost => _sessionLost;

  @override
  Stream<List<int>> get output => _output.stream;

  // pid do processo raiz do PTY REMOTO — usado pelo monitor de harness (turn
  // status via árvore de processos), que é LOCAL. No remoto não vale (a árvore
  // vive no host), então não expomos pid.
  @override
  int? get rootProcessId => null;

  // Sem fallback de pasta: o path é do filesystem remoto, resolvido lá.
  @override
  SpawnDirectory? get spawnDirectory => null;

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {
    _rows = rows;
    _columns = columns;
    // Re-anexa quando o connector refaz a conexão (o serviço é outro objeto:
    // guardar o `_service` antigo falaria com a conexão morta).
    _reconnectSub = _connector.reconnected.listen(_onReconnected);
    unawaited(_init(workingDirectory, profile, rows, columns, extraEnv));
  }

  /// Reassina o stream da sessão do ponto exato onde parou.
  ///
  /// O protocolo endereça a saída por offset absoluto desde o spawn, então
  /// [_bytesDelivered] é o que já entregamos à view: o host manda só o que
  /// passou durante a queda, sem buraco nem repetição.
  Future<void> _onReconnected(RemoteTerminalService service) async {
    // NÃO exige `_detached`: nem toda queda é percebida por aqui (um transporte
    // pode morrer sem o stream do attach emitir done/error). Nesse caso o
    // gateway seguia "pronto", mas escrevendo num serviço morto — o teclado
    // ficava mudo. Reconectou, re-anexa e troca o serviço, tendo percebido ou
    // não a queda.
    if (_killed || _exited) return;
    final id = _sessionId;
    if (id == null) return;
    _service = service;
    try {
      // A sessão ainda existe no host? Pergunta ANTES de anexar.
      //
      // `attach()` devolve um Stream: quando a sessão sumiu, o erro chega pelo
      // stream (assíncrono), fora deste try, e caía no `onError` -> congela de
      // novo. A aba ficava viva porém MUDA para sempre, sem nada explicando.
      // E o caso é comum: se o host ficou fora do ar, o cockpit-server de lá
      // morreu junto e voltou sem nenhuma das sessões antigas.
      final alive = await service.sessions();
      if (!alive.any((s) => s.id == id)) {
        _sessionLost = true;
        _closeOutput();
        return;
      }
      _listen(service.attach(id, fromOffset: _bytesDelivered));
      // Destrava ANTES do resize: se o resize falhasse, a aba ficava aceitando
      // o attach novo mas com a digitação bloqueada para sempre. O tamanho é
      // ajuste fino; o teclado é o que o usuário sente.
      _detached = false;
      _flushQueue();
      // O PTY remoto não soube dos resizes ocorridos enquanto estivemos fora.
      await service.resize(id, _rows, _columns);
    } on TerminalException catch (e) {
      // Servidor reiniciou e não conhece mais a sessão: não há o que retomar.
      if (e.kind == TerminalErrorKind.sessionNotFound) {
        _closeOutput();
      }
      // Outros erros: segue congelado, o connector tenta de novo.
    }
  }

  /// Assina o stream de eventos da sessão (usado na abertura e no re-attach).
  void _listen(Stream<PtyEvent> events) {
    _attachment?.cancel();
    _attachment = events.listen(
      (event) {
        switch (event) {
          case PtyOutputEvent(:final chunk):
            _bytesDelivered += chunk.bytes.length;
            _output.add(chunk.bytes);
          case PtyExitEvent():
            // Processo terminou de verdade: a aba encerra (não é queda).
            _exited = true;
            _closeOutput();
        }
      },
      // Fim de stream sem PtyExitEvent = transporte caiu com a sessão viva no
      // host. Congela e espera o reconnect em vez de matar a aba.
      onError: (Object _) => _freezeOrClose(),
      onDone: _freezeOrClose,
    );
  }

  void _freezeOrClose() {
    if (_killed || _exited) {
      _closeOutput();
      return;
    }
    _detached = true;
    _ready = false;
  }

  Future<void> _init(
    String workingDirectory,
    TerminalProfile profile,
    int rows,
    int columns,
    Map<String, String> extraEnv,
  ) async {
    final RemoteTerminalService service;
    try {
      service = await _connector.ensure();
    } catch (_) {
      // Erro de conexão (SSH/bootstrap) — a UI já observa RemoteHostConnector
      // .phases pra mostrar loading/erro; aqui só encerra a aba.
      _closeOutput();
      return;
    }
    if (_killed) return;

    // Login shell: o **host** resolve seu próprio shell (o cliente não sabe qual
    // é o shell do host — pior no iPad, onde o fallback é `/bin/sh` e o
    // oh-my-zsh/.zshrc não carrega). Executable vazio = "use o $SHELL do host,
    // login". Perfis explícitos (pwsh, wsl…) seguem literais.
    final loginShell = profile.id == TerminalProfile.loginShellId;
    try {
      final info = await service.open(
        PtySpawnSpec(
          executable: loginShell ? '' : profile.executable,
          arguments: loginShell ? const <String>[] : profile.args,
          // Caminho é do filesystem REMOTO (vazio = HOME remota do servidor).
          workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
          environment: _terminalEnv(extraEnv),
          rows: rows,
          columns: columns,
          flowControlled: true,
        ),
      );
      if (_killed) {
        await service.kill(info.id);
        return;
      }
      _service = service;
      _sessionId = info.id;
      _listen(service.attach(info.id));
      _flushQueue();
    } on TerminalException catch (e) {
      // Abertura falhou: sem isto a aba some do log e o usuário vê apenas
      // uma aba muda — foi assim que o `/bin/sh` num host Windows passou
      // despercebido até alguém rodar o E2E.
      DiagnosticsLog.instance.log(
        'remote-term',
        'abertura do PTY remoto falhou: ${e.kind.name} ${e.detail ?? ''}',
      );
      _closeOutput();
    }
  }

  void _flushQueue() {
    _ready = true;
    for (final op in _queued) {
      op();
    }
    _queued.clear();
  }

  /// Motivos já registrados, para não encher o log a cada tecla.
  final Set<String> _loggedBlocks = <String>{};

  /// Registra, UMA vez por motivo, que uma operação da aba não saiu.
  ///
  /// A digitação sumir em silêncio é o pior sintoma desta classe: a aba
  /// parece viva (a saída pode até continuar chegando) e o teclado não faz
  /// nada, sem erro nenhum. Sem este rastro, diagnosticar exige o aparelho
  /// em mãos — que é justamente o que não se tem quando o cliente é um iPad.
  void _logBlocked(String reason) {
    if (!_loggedBlocks.add(reason)) return;
    DiagnosticsLog.instance.log(
      'remote-term',
      'operação não enviada ($reason): sessão=$_sessionId, '
          'ready=$_ready, detached=$_detached, killed=$_killed',
    );
  }

  void _run(void Function() op) {
    if (_killed) {
      _logBlocked('killed');
      return;
    }
    // Congelado: DESCARTA em vez de enfileirar. A fila existe pra abertura
    // (ops que chegam antes do PTY existir); reusá-la aqui despejaria no shell,
    // de uma vez e às cegas, tudo que foi digitado durante a queda — num shell
    // que pode ter mudado de estado nesse meio tempo.
    if (_detached) {
      _logBlocked('detached');
      return;
    }
    if (_ready) {
      op();
    } else {
      _logBlocked('not-ready');
      _queued.add(op);
    }
  }

  void _closeOutput() {
    if (!_output.isClosed) _output.close();
  }

  /// Quantos writes já saíram — só para o primeiro deixar rastro.
  int _writes = 0;

  @override
  void write(List<int> data) {
    // A PRIMEIRA tecla é registrada: separa "o teclado não chega no
    // gateway" de "chega e é bloqueado". Sem esta linha, os dois casos
    // produzem exatamente o mesmo silêncio no log.
    if (_writes++ == 0) {
      DiagnosticsLog.instance.log(
        'remote-term',
        'primeiro write da aba: ${data.length}B, sessão=$_sessionId, '
            'ready=$_ready, detached=$_detached',
      );
    }
    _run(() {
      final id = _sessionId;
      if (id == null) return;
      unawaited(
        _service?.write(
          id,
          data is Uint8List ? data : Uint8List.fromList(data),
        ),
      );
    });
  }

  @override
  void resize(int rows, int columns) {
    // Guardado FORA do _run: enquanto congelado o `op` é descartado, mas o
    // tamanho novo precisa sobreviver pra ser reenviado no re-attach.
    _rows = rows;
    _columns = columns;
    _run(() {
      final id = _sessionId;
      if (id == null) return;
      unawaited(_service?.resize(id, rows, columns));
    });
  }

  @override
  void acknowledgeOutput() {
    final id = _sessionId;
    final credit = _bytesDelivered - _bytesAcked;
    if (id == null || credit <= 0) return;
    _bytesAcked = _bytesDelivered;
    unawaited(_service?.ack(id, credit));
  }

  @override
  Future<void> kill() async {
    _killed = true;
    _queued.clear();
    await _reconnectSub?.cancel();
    await _attachment?.cancel();
    final id = _sessionId;
    if (id != null) {
      try {
        await _service?.kill(id);
      } on TerminalException {
        // sessão já encerrada.
      }
    }
    _closeOutput();
  }

  /// TERM/COLORTERM como nos outros gateways; o servidor remoto funde por cima
  /// do ambiente dele. Não herda `Platform.environment` local (é outra
  /// máquina) — o env do host vem do próprio servidor.
  /// Capacidades do EMULADOR (que é daqui) anunciadas pra PTY do host.
  ///
  /// `TERM` vai sempre: a condição de plataforma que existia aqui olhava para
  /// o CLIENTE, e o PTY nasce no HOST — de um Windows falando com um Mac, o
  /// shell de lá subia sem `TERM` e as TUIs ncurses degradavam. Quem sabe se o
  /// `TERM` faz sentido é o servidor, e é ele quem o descarta quando roda em
  /// Windows (ver `remote_server.dart`, caso `PtyOpen`).
  Map<String, String> _terminalEnv(Map<String, String> extraEnv) => {
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
    ...extraEnv,
  };
}
