import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/app/cockpit/domain/services/content_search_paths.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

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
class DiskFileChangeWatcher
    implements FileChangeWatcher, TreeFileChangeWatcher {
  const DiskFileChangeWatcher({
    this.debounce = const Duration(milliseconds: 120),
    this.pollInterval = const Duration(seconds: 2),
    this.treePollInterval = const Duration(seconds: 10),
    this.treeSafetyPollInterval = const Duration(seconds: 60),
    this.recursiveWatchSupported,
    this.directoryWatch,
    this.treeSnapshot,
    this.retryMin = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 30),
  });

  /// Junta a rajada de eventos de um save num aviso só.
  final Duration debounce;
  final Duration pollInterval;

  /// Fallback for platforms/filesystems without a healthy recursive watch.
  final Duration treePollInterval;

  /// Safety net for missed events while the recursive native watch is healthy.
  final Duration treeSafetyPollInterval;
  final bool? recursiveWatchSupported;

  /// Filesystem adapters, injectable for deterministic watcher lifecycle tests.
  final Stream<FileSystemEvent> Function(String path, bool recursive)?
  directoryWatch;
  final FutureOr<String> Function(String path)? treeSnapshot;
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

  @override
  Stream<void> watchTree(String path) {
    String? lastSignature;
    var subscribedBefore = false;
    return Stream<void>.multi((listener) {
      // A cancelled initial snapshot leaves no trustworthy baseline. On a
      // subsequent attach, invalidate conservatively instead of trusting it.
      final previous = lastSignature ?? (subscribedBefore ? '' : null);
      subscribedBefore = true;
      final watch = _DiskWatch(
        dir: path,
        recursive: true,
        initialSignature: previous,
        onSignature: (signature) => lastSignature = signature,
        safetyPollInterval: treeSafetyPollInterval,
        matches: (eventPath) {
          final relative = p.relative(eventPath, from: path);
          final parts = p.split(relative);
          return parts
                  .take(parts.length - 1)
                  .every(contentSearchIncludesDirectory) &&
              parts.last != '.DS_Store';
        },
        // One baseline per attach; no polling or isolate while unsubscribed.
        signature: () => treeSnapshot?.call(path) ?? _snapshotTree(path),
        config: DiskFileChangeWatcher(
          debounce: debounce,
          pollInterval: treePollInterval,
          retryMin: retryMin,
          retryMax: retryMax,
          recursiveWatchSupported: recursiveWatchSupported,
          directoryWatch: directoryWatch,
        ),
      );
      final subscription = watch.stream.listen(listener.add);
      listener.onCancel = subscription.cancel;
    });
  }

  // Keep the isolate closure outside the listener scope so it captures only
  // the path, never a native subscription/controller or filesystem adapter.
  static Future<String> _snapshotTree(String path) =>
      Isolate.run(() => _treeSignature(path));

  static String _treeSignature(String path) {
    final parts = <String>[];
    final pending = <Directory>[Directory(path)];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          final name = p.basename(entity.path);
          if (entity is Directory && contentSearchIncludesDirectory(name)) {
            pending.add(entity);
          } else if (entity is File && name != '.DS_Store') {
            parts.add('${entity.path}|${_fileSignature(entity.path)}');
          }
        }
      } on FileSystemException {
        parts.add('${dir.path}|unavailable');
      }
    }
    parts.sort();
    return sha256.convert(utf8.encode(parts.join('\n'))).toString();
  }

  /// Casa o evento com o arquivo pelo caminho pedido OU pelo caminho real da
  /// pasta: o FSEvents reporta o caminho resolvido (`/tmp` → `/private/tmp`,
  /// pasta por symlink), e aí a comparação literal falharia.
  static bool Function(String) _fileMatcher(String path, String parent) {
    // Callers may use mixed separators on Windows; OS events use native paths.
    final normalized = p.normalize(path);
    final name = p.basename(normalized);
    String? resolved;
    try {
      resolved = p.join(Directory(parent).resolveSymbolicLinksSync(), name);
    } on FileSystemException {
      resolved = null; // pasta ainda não existe: fica só o literal
    }
    return (eventPath) =>
        p.equals(eventPath, normalized) ||
        (resolved != null && p.equals(eventPath, resolved));
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
    this.recursive = false,
    this.initialSignature,
    this.onSignature,
    this.safetyPollInterval,
  }) : _backoff = config.retryMin {
    _controller = StreamController<void>(onListen: _start, onCancel: _stop);
  }

  final String dir;
  final bool Function(String path) matches;
  final FutureOr<String> Function() signature;
  final bool recursive;
  final String? initialSignature;
  final void Function(String)? onSignature;
  final Duration? safetyPollInterval;
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
  bool _checking = false;

  Future<void> _start() async {
    final sig = await signature();
    if (_closed) return;
    _sig = sig;
    onSignature?.call(sig);
    _arm();
    if (initialSignature != null && sig != initialSignature) {
      _controller.add(null);
    }
  }

  bool _arm() {
    if (_closed) return false;
    try {
      final supportsRecursive =
          config.recursiveWatchSupported ??
          (Platform.isMacOS || Platform.isWindows);
      final events =
          config.directoryWatch?.call(dir, recursive) ??
          Directory(dir).watch(recursive: recursive && supportsRecursive);
      _sub = events.listen(
        _onEvent,
        onError: (Object _) => _rearmLater(),
        onDone: _rearmLater,
        cancelOnError: true,
      );
      _setPollInterval(
        recursive && supportsRecursive
            ? safetyPollInterval ?? config.pollInterval
            : config.pollInterval,
      );
      return true;
    } on FileSystemException {
      _rearmLater();
    } on UnsupportedError {
      _rearmLater();
    }
    return false;
  }

  Duration? _activePollInterval;

  void _setPollInterval(Duration interval) {
    if (_activePollInterval == interval && _poll != null) return;
    _activePollInterval = interval;
    _poll?.cancel();
    _poll = Timer.periodic(interval, (_) => _check());
  }

  /// O stream do SO morreu: tenta de novo com backoff exponencial e, ao
  /// voltar, confere se algo mudou enquanto estava cego.
  void _rearmLater() {
    if (_closed) return;
    _setPollInterval(config.pollInterval);
    unawaited(_sub?.cancel());
    _sub = null;
    _retry?.cancel();
    _retry = Timer(_backoff, () {
      final next = _backoff * 2;
      _backoff = next > config.retryMax ? config.retryMax : next;
      if (_arm()) _check();
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

  Future<void> _emitIfChanged() async {
    if (_closed || _checking) return;
    _checking = true;
    try {
      final sig = await signature();
      if (_closed || sig == _sig) return;
      _sig = sig;
      onSignature?.call(sig);
      _controller.add(null);
    } finally {
      _checking = false;
    }
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
