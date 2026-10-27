import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/terminal/pty_terminal_gateway.dart';
import 'package:cockpit/app/cockpit/data/terminal/sidecar/sidecar_terminal_connector.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_remote/cockpit_remote.dart';

/// [TerminalGateway] servido pelo `cockpit-server` sidecar via loopback
/// (plano 58, Wave 1). A UI não sabe a diferença: mesmo contrato, mesmos
/// bytes; o PTY nasce no servidor e o emulador continua no cliente.
///
/// `start()` é síncrono no contrato, mas conectar/abrir é assíncrono — as
/// operações chegadas antes do backend ficar pronto entram numa fila e são
/// aplicadas na ordem. Se o sidecar não estiver disponível, o gateway cai
/// para um [PtyTerminalGateway] in-process (mesmo comportamento de sempre).
class SidecarTerminalGateway implements TerminalGateway {
  SidecarTerminalGateway(this._connector);

  final SidecarTerminalConnector _connector;

  // Backend remoto (quando o sidecar respondeu).
  RemoteTerminalService? _service;
  String? _sessionId;
  int? _rootPid;
  StreamSubscription<PtyEvent>? _attachment;

  /// Créditos de flow control por CONTADOR acumulado, não por fila de
  /// chunks: cada [acknowledgeOutput] devolve TUDO que foi entregue e ainda
  /// não confirmado. Imune ao caso em que o Utf8Decoder segura uma sequência
  /// parcial e o coalescer suprime o add vazio (ack daquele chunk nunca
  /// viria; com fila, a janela do servidor vazaria até stall).
  int _bytesDelivered = 0;
  int _bytesAcked = 0;

  // Backend local (fallback).
  PtyTerminalGateway? _local;

  final StreamController<List<int>> _output = StreamController<List<int>>();
  final List<void Function()> _queued = [];
  bool _ready = false;
  bool _killed = false;
  SpawnDirectory? _spawnDirectory;

  @override
  SpawnDirectory? get spawnDirectory =>
      _local?.spawnDirectory ?? _spawnDirectory;

  // pid do processo raiz do PTY. Sidecar é local (loopback), então o pid vale
  // pro monitor de harness (turn status via árvore de processos). No fallback
  // in-process, delega ao gateway local.
  @override
  int? get rootProcessId => _local?.rootProcessId ?? _rootPid;

  @override
  int? get wslProcessId => null;

  @override
  Stream<List<int>> get output => _output.stream;

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {
    // Mesma resolução do gateway local: pasta sumida não é erro, é fallback
    // pro ancestral (a ui/ avisa lendo spawnDirectory).
    final dir = resolveSpawnDirectory(workingDirectory);
    _spawnDirectory = dir;
    unawaited(_init(dir, profile, rows, columns, extraEnv));
  }

  Future<void> _init(
    SpawnDirectory dir,
    TerminalProfile profile,
    int rows,
    int columns,
    Map<String, String> extraEnv,
  ) async {
    final service = await _connector.ensure();
    if (_killed) return;

    if (service == null) {
      // Fallback in-process: replica exatamente o caminho de hoje.
      final local = _local = PtyTerminalGateway();
      local.start(
        workingDirectory: dir.requested,
        profile: profile,
        rows: rows,
        columns: columns,
        extraEnv: extraEnv,
      );
      unawaited(_output.addStream(local.output));
      _flushQueue();
      return;
    }

    try {
      final info = await service.open(
        PtySpawnSpec(
          executable: profile.executable,
          arguments: profile.args,
          workingDirectory: dir.path.isEmpty ? null : dir.path,
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
      _rootPid = info.pid;
      _attachment = service
          .attach(info.id)
          .listen(
            (event) {
              switch (event) {
                case PtyOutputEvent(:final chunk):
                  _bytesDelivered += chunk.bytes.length;
                  _output.add(chunk.bytes);
                case PtyExitEvent():
                  _closeOutput();
              }
            },
            onError: (Object _) => _closeOutput(),
            onDone: _closeOutput,
          );
      _flushQueue();
    } on TerminalException {
      // Spawn remoto falhou (ex.: executável inexistente). Mesma semântica
      // do gateway local: o stream fecha e a sessão mostra o encerramento.
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

  void _run(void Function() op) {
    if (_killed) return;
    if (_ready) {
      op();
    } else {
      _queued.add(op);
    }
  }

  void _closeOutput() {
    if (!_output.isClosed) _output.close();
  }

  @override
  void write(List<int> data) => _run(() {
    final local = _local;
    if (local != null) return local.write(data);
    final id = _sessionId;
    if (id == null) return;
    unawaited(
      _service?.write(id, data is Uint8List ? data : Uint8List.fromList(data)),
    );
  });

  @override
  void resize(int rows, int columns) => _run(() {
    final local = _local;
    if (local != null) return local.resize(rows, columns);
    final id = _sessionId;
    if (id == null) return;
    unawaited(_service?.resize(id, rows, columns));
  });

  @override
  void acknowledgeOutput() {
    final local = _local;
    if (local != null) return local.acknowledgeOutput();
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
    await _local?.kill();
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

  /// Mesmo ambiente que o [PtyTerminalGateway] anuncia (TERM/COLORTERM, ver
  /// racional lá) — o servidor funde por cima do ambiente dele próprio.
  Map<String, String> _terminalEnv(Map<String, String> extraEnv) => {
    ...Platform.environment,
    if (!Platform.isWindows) 'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
    ...extraEnv,
  };
}
