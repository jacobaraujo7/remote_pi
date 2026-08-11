import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/lsp/lsp_codec.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/entities/lsp_semantic_tokens.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Tipos/modificadores padrão da spec LSP (3.16+) — anunciados no handshake pra
/// satisfazer servers que exigem `tokenTypes`/`tokenModifiers` não-vazios
/// (ex: Dart analysis server). O servidor usa a *legend* própria dele na
/// resposta (índices na `semanticTokensProvider.legend`), então esta lista só
/// precisa declarar que o client entende o vocabulário padrão.
const List<String> _kSemanticTokenTypes = <String>[
  'namespace',
  'type',
  'class',
  'enum',
  'interface',
  'struct',
  'typeParameter',
  'parameter',
  'variable',
  'property',
  'enumMember',
  'event',
  'function',
  'method',
  'macro',
  'keyword',
  'modifier',
  'comment',
  'string',
  'number',
  'regexp',
  'operator',
  'decorator',
];
const List<String> _kSemanticTokenModifiers = <String>[
  'declaration',
  'definition',
  'readonly',
  'static',
  'deprecated',
  'abstract',
  'async',
  'modification',
  'documentation',
  'defaultLibrary',
];

/// Implementação de [LspClient] sobre `dart:io` `Process`. Dona do ciclo de vida
/// de **um** language server: spawn, escrita no stdin (framing
/// [encodeLspMessage]), parse do stdout ([LspMessageDecoder]), handshake LSP,
/// publish de diagnostics e kill limpo.
///
/// Espelha o padrão do `PiRpcProcess` (write-chain serializada, Completer por id,
/// close-stdin→SIGTERM→SIGKILL). Difere no framing (Content-Length, não JSONL) e
/// no id JSON-RPC (inteiro, não `req-N`).
class LspClientImpl implements LspClient {
  LspClientImpl({required this.spec, required this.rootPath});

  final LspServerSpec spec;

  @override
  final String rootPath;

  final StreamController<LspDiagnosticsBatch> _diagnostics =
      StreamController<LspDiagnosticsBatch>.broadcast();

  /// Requests pendentes aguardando a `response` com o `id` correspondente.
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _seq = 0;

  /// Serializa escritas no stdin (ver `PiRpcProcess._writeChain`).
  Future<void> _writeChain = Future<void>.value();

  Process? _process;
  StreamSubscription<Map<String, dynamic>>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _initialized = false;
  SemanticTokensLegend? _semanticLegend;

  @override
  Stream<LspDiagnosticsBatch> get diagnostics => _diagnostics.stream;

  @override
  bool get isRunning => _process != null;

  @override
  SemanticTokensLegend? get semanticTokensLegend => _semanticLegend;

  @override
  Future<Result<void, LspError>> start() async {
    if (_process != null) {
      return const Failure(LspError('Language server already running.'));
    }
    try {
      // Mesmo cuidado do pi: servers como typescript-language-server/intelephense
      // são shims que precisam do `node` na PATH (GUI macOS não herda do shell).
      final env = await envWithNodeOnPath();
      final process = await Process.start(
        spec.executable,
        spec.args,
        workingDirectory: rootPath,
        environment: env,
        runInShell: Platform.isWindows,
      );
      _process = process;
      unawaited(LspProcessRegistry.register(process.pid));

      _stdoutSub = process.stdout
          .transform(const LspMessageDecoder())
          .listen(_onMessage, onError: _onStreamError);

      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine, onError: _onStreamError);

      unawaited(process.exitCode.then(_onExit));

      await _handshake();
      return const Success(null);
    } catch (error, stackTrace) {
      final failed = _process;
      _process = null;
      _initialized = false;
      if (failed != null) {
        failed.kill(ProcessSignal.sigterm);
        unawaited(LspProcessRegistry.unregister(failed.pid));
      }
      return Failure(
        LspError(
          'Failed to start "${spec.executable}": $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// `initialize` → `initialized`. Anuncia as capabilities mínimas que usamos
  /// (publishDiagnostics, semanticTokens, formatting). `positionEncoding` fica no
  /// default (utf-16) — alinhado com as code units da `String` Dart.
  Future<void> _handshake() async {
    final rootUri = Uri.directory(rootPath).toString();
    final result = await _request('initialize', <String, dynamic>{
      'processId': pid,
      'rootUri': rootUri,
      'workspaceFolders': <Map<String, dynamic>>[
        {'uri': rootUri, 'name': rootPath.split(Platform.pathSeparator).last},
      ],
      'capabilities': <String, dynamic>{
        'textDocument': <String, dynamic>{
          'publishDiagnostics': <String, dynamic>{'relatedInformation': false},
          'synchronization': <String, dynamic>{
            'didSave': true,
            'dynamicRegistration': false,
          },
          'formatting': <String, dynamic>{'dynamicRegistration': false},
          // Spec exige `requests`/`tokenTypes`/`tokenModifiers`/`formats` —
          // sem eles o Dart analysis server rejeita o `initialize` inteiro
          // (params.capabilities.textDocument.semanticTokens.formats must
          // not be undefined) e o servidor nunca sobe.
          'semanticTokens': <String, dynamic>{
            'dynamicRegistration': false,
            'requests': <String, dynamic>{'full': true},
            'tokenTypes': _kSemanticTokenTypes,
            'tokenModifiers': _kSemanticTokenModifiers,
            'formats': <String>['relative'],
          },
        },
      },
    });
    // Captura a legenda de semantic tokens da resposta. `legend` vem
    // ANINHADA dentro de `semanticTokensProvider` (não nos campos direto) —
    // ex: `semanticTokensProvider: {legend: {tokenTypes, tokenModifiers},
    // full: ..., range: ...}`.
    if (result is Map<String, dynamic>) {
      final serverCaps = result['capabilities'] as Map<String, dynamic>?;
      final semTokens = serverCaps?['semanticTokensProvider'];
      if (semTokens is Map<String, dynamic>) {
        final legend = semTokens['legend'];
        if (legend is Map<String, dynamic>) {
          _semanticLegend = SemanticTokensLegend.fromJson(legend);
        }
      }
    }
    _notify('initialized', <String, dynamic>{});
    _initialized = true;
  }

  @override
  Future<void> didOpen({required String path, required String text}) async {
    if (!_initialized) return;
    _notify('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': _uri(path),
        'languageId': spec.languageId,
        'version': 1,
        'text': text,
      },
    });
  }

  @override
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  }) async {
    if (!_initialized) return;
    _notify('textDocument/didChange', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': _uri(path), 'version': version},
      // Full sync: mandamos o documento inteiro a cada edição (simples e
      // suficiente pro tamanho de arquivo que o editor abre).
      'contentChanges': <Map<String, dynamic>>[
        {'text': text},
      ],
    });
  }

  @override
  Future<void> didClose({required String path}) async {
    if (!_initialized) return;
    _notify('textDocument/didClose', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': _uri(path)},
    });
  }

  @override
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    try {
      return Success(await _request(method, params));
    } on LspError catch (error) {
      return Failure(error);
    } catch (error, stackTrace) {
      return Failure(LspError('$error', cause: error, stackTrace: stackTrace));
    }
  }

  @override
  Future<Result<Object?, LspError>> semanticTokensFull(String path) async {
    try {
      final result = await _request('textDocument/semanticTokens/full', {
        'textDocument': {'uri': _uri(path)},
      });
      return Success(result);
    } on LspError catch (error) {
      return Failure(error);
    } catch (error, stackTrace) {
      return Failure(LspError('$error', cause: error, stackTrace: stackTrace));
    }
  }

  @override
  Future<Result<Object?, LspError>> definition(
    String path, {
    required int line,
    required int character,
  }) async {
    try {
      final result = await _request('textDocument/definition', {
        'textDocument': {'uri': _uri(path)},
        'position': {'line': line, 'character': character},
      });
      return Success(result);
    } on LspError catch (error) {
      return Failure(error);
    } catch (error, stackTrace) {
      return Failure(LspError('$error', cause: error, stackTrace: stackTrace));
    }
  }

  @override
  Future<void> kill() async {
    final process = _process;
    if (process == null) return;
    // Caminho gracioso do LSP: shutdown (request) → exit (notify) → close stdin.
    try {
      await _request(
        'shutdown',
        const <String, dynamic>{},
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      _notify('exit', const <String, dynamic>{});
    } catch (_) {}
    try {
      await process.stdin.close();
    } catch (_) {}

    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  @override
  void dispose() {
    final process = _process;
    if (process != null) {
      try {
        process.stdin.close();
      } catch (_) {}
      process.kill(ProcessSignal.sigterm);
    }
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    if (!_diagnostics.isClosed) _diagnostics.close();
  }

  // --- wire ---

  String _uri(String path) => Uri.file(path).toString();

  void _onMessage(Map<String, dynamic> message) {
    // Resposta a um request nosso: tem `id` e (`result` ou `error`), sem `method`.
    final id = message['id'];
    final method = message['method'];
    if (method == null && id is int) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        final error = message['error'];
        if (error != null) {
          completer.completeError(
            LspError('LSP error: ${error is Map ? error['message'] : error}'),
          );
        } else {
          completer.complete(message['result']);
        }
      }
      return;
    }

    // Request servidor→cliente (tem `id` E `method`): precisa de resposta pra
    // não travar o servidor. Respondemos o mínimo viável.
    if (method is String && id != null) {
      _handleServerRequest(id, method);
      return;
    }

    // Notificação servidor→cliente (tem `method`, sem `id`).
    if (method is String) _handleNotification(method, message['params']);
  }

  void _handleServerRequest(Object id, String method) {
    final Object? result = switch (method) {
      // Configuração: devolve um item nulo por scope pedido (usa defaults).
      'workspace/configuration' => <Object?>[null],
      // Registro dinâmico de capability: aceitamos (no-op do nosso lado).
      'client/registerCapability' ||
      'client/unregisterCapability' ||
      'window/workDoneProgress/create' => null,
      _ => null,
    };
    _send(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void _handleNotification(String method, Object? params) {
    if (method == 'textDocument/publishDiagnostics' &&
        params is Map<String, dynamic>) {
      final uri = params['uri'] as String? ?? '';
      final raw = params['diagnostics'];
      final list = <LspDiagnostic>[
        if (raw is List)
          for (final d in raw)
            if (d is Map<String, dynamic>) LspDiagnostic.fromJson(d),
      ];
      if (!_diagnostics.isClosed) {
        _diagnostics.add(LspDiagnosticsBatch(uri: uri, diagnostics: list));
      }
    }
    // Demais notificações (logMessage, progress, …) são ignoradas por ora.
  }

  Future<Object?> _request(String method, Map<String, dynamic> params) async {
    if (_process == null) throw const LspError('Language server not running.');
    final id = ++_seq;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw LspError('Timed out waiting for "$method".');
      },
    );
  }

  void _notify(String method, Map<String, dynamic> params) {
    if (_process == null) return;
    _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  /// Escreve uma mensagem no stdin, serializada com as demais (ver write-chain
  /// do `PiRpcProcess`).
  void _send(Map<String, dynamic> message) {
    final bytes = encodeLspMessage(message);
    final result = _writeChain.then((_) async {
      final process = _process;
      if (process == null) return;
      process.stdin.add(bytes);
      await process.stdin.flush();
    });
    _writeChain = result.then((_) {}, onError: (_) {});
  }

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    // Alguns language servers escrevem telemetria verbosa no stderr. Em
    // produção isso não pode alimentar a fila throttled do debugPrint junto
    // com terminais, builds e agentes.
    if (kDebugMode) debugPrint('[lsp:${spec.languageId}][err] $line');
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    debugPrint('[lsp:${spec.languageId}] stream error: $error');
  }

  void _onExit(int code) {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final exitedPid = _process?.pid;
    _process = null;
    _initialized = false;
    if (exitedPid != null) unawaited(LspProcessRegistry.unregister(exitedPid));
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          LspError('Language server exited (code=$code).'),
        );
      }
    }
    _pending.clear();
    debugPrint('[lsp:${spec.languageId}] exited code=$code');
  }
}

/// Implementação de [LspClientFactory] — cria um [LspClientImpl] por raiz.
class LspClientFactoryImpl implements LspClientFactory {
  const LspClientFactoryImpl();

  @override
  LspClient create({required LspServerSpec spec, required String rootPath}) =>
      LspClientImpl(spec: spec, rootPath: rootPath);
}
