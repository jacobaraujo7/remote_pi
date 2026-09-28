import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_change_watcher.dart';

/// [FileChangeWatcher] do disco local (`dart:io`). Três camadas, cada uma
/// cobrindo o buraco da anterior:
///
/// 1. **Watch da PASTA**, nunca do arquivo. `File.watch` fica preso ao inode:
///    no rename atômico que o Claude Code usa (`x.tmp.<pid>` → `x`) ele emite
///    um delete e ENCERRA o stream, e a aba nunca mais recarregava. A pasta
///    sobrevive; o evento chega com o nome do arquivo (ou como destino do
///    move) e é filtrado aqui.
/// 2. **Re-arm com backoff** quando o stream do SO termina ou falha (pasta
///    apagada e recriada, volume desmontado, limite de watchers), seguido de
///    uma conferência pra pegar o que mudou no intervalo.
/// 3. **Poll de `stat`** a cada [pollInterval]: rede de segurança pra evento
///    coalescido/perdido pelo FSEvents e pra janela oculta.
///
/// Evento e poll só avisam se a assinatura (mtime + tamanho; na pasta, a de
/// cada entrada) mudou desde o último aviso. Isso descarta o evento atrasado
/// que o FSEvents entrega sobre uma escrita anterior ao `listen`, e o evento
/// de metadado sem mudança de conteúdo.
class DiskFileChangeWatcher implements FileChangeWatcher {
  const DiskFileChangeWatcher({
    this.debounce = const Duration(milliseconds: 120),
    this.pollInterval = const Duration(seconds: 2),
    this.retryMin = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 30),
  });

  /// Junta a rajada de eventos de um save num aviso só.
  final Duration debounce;
  final Duration pollInterval;
  final Duration retryMin;
  final Duration retryMax;

  @override
  Stream<void> watchFile(String path) {
    final parent = File(path).parent.path;
    return _DiskWatch(
      dir: parent,
      matches: _fileMatcher(path, parent),
      signature: () => _fileSignature(path),
      config: this,
    ).stream;
  }

  @override
  Stream<void> watchFolder(String path) => _DiskWatch(
    dir: path,
    matches: (_) => true,
    signature: () => _folderSignature(path),
    config: this,
  ).stream;

  /// Casa o evento com o arquivo pelo caminho pedido OU pelo caminho real da
  /// pasta: o FSEvents reporta o caminho resolvido (`/tmp` → `/private/tmp`,
  /// pasta por symlink), e aí a comparação literal falharia.
  static bool Function(String) _fileMatcher(String path, String parent) {
    final name = path.substring(parent.length);
    String? resolved;
    try {
      resolved = '${Directory(parent).resolveSymbolicLinksSync()}$name';
    } on FileSystemException {
      resolved = null; // pasta ainda não existe: fica só o literal
    }
    return (p) => p == path || p == resolved;
  }

  static String _fileSignature(String path) {
    final st = FileStat.statSync(path);
    if (st.type == FileSystemEntityType.notFound) return '-';
    return '${st.modified.microsecondsSinceEpoch}:${st.size}';
  }

  static String _folderSignature(String path) {
    try {
      final parts = <String>[
        for (final e in Directory(path).listSync(followLinks: false))
          '${e.path}|${_fileSignature(e.path)}',
      ]..sort();
      return Object.hashAll(parts).toString();
    } on FileSystemException {
      return '-';
    }
  }
}

/// Uma assinatura de [DiskFileChangeWatcher]: vive entre o `listen` e o
/// `cancel` do consumidor.
class _DiskWatch {
  _DiskWatch({
    required this.dir,
    required this.matches,
    required this.signature,
    required this.config,
  }) : _backoff = config.retryMin {
    _controller = StreamController<void>(onListen: _start, onCancel: _stop);
  }

  final String dir;
  final bool Function(String path) matches;
  final String Function() signature;
  final DiskFileChangeWatcher config;

  late final StreamController<void> _controller;
  Stream<void> get stream => _controller.stream;

  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _debounce;
  Timer? _poll;
  Timer? _retry;
  Duration _backoff;
  String? _sig;
  bool _closed = false;

  void _start() {
    _sig = signature();
    _arm();
    _poll = Timer.periodic(config.pollInterval, (_) => _check());
  }

  void _arm() {
    if (_closed) return;
    try {
      _sub = Directory(dir).watch().listen(
        _onEvent,
        onError: (Object _) => _rearmLater(),
        onDone: _rearmLater,
        cancelOnError: true,
      );
    } on FileSystemException {
      _rearmLater();
    }
  }

  /// O stream do SO morreu: tenta de novo com backoff exponencial e, ao
  /// voltar, confere se algo mudou enquanto estava cego.
  void _rearmLater() {
    if (_closed) return;
    unawaited(_sub?.cancel());
    _sub = null;
    _retry?.cancel();
    _retry = Timer(_backoff, () {
      final next = _backoff * 2;
      _backoff = next > config.retryMax ? config.retryMax : next;
      _arm();
      _check();
    });
  }

  void _onEvent(FileSystemEvent e) {
    final hit =
        matches(e.path) ||
        (e is FileSystemMoveEvent &&
            e.destination != null &&
            matches(e.destination!));
    if (!hit) return;
    _backoff = config.retryMin; // stream saudável
    _debounce?.cancel();
    _debounce = Timer(config.debounce, _emitIfChanged);
  }

  /// Poll e re-arm. Evento pendente no debounce já vai conferir; não duplica.
  void _check() {
    if (_closed || (_debounce?.isActive ?? false)) return;
    _emitIfChanged();
  }

  void _emitIfChanged() {
    if (_closed) return;
    final sig = signature();
    if (sig == _sig) return;
    _sig = sig;
    _controller.add(null);
  }

  Future<void> _stop() async {
    _closed = true;
    _debounce?.cancel();
    _poll?.cancel();
    _retry?.cancel();
    await _sub?.cancel();
    _sub = null;
  }
}
