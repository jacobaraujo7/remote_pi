import 'dart:async';

import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/data/lsp/project_root_finder.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:flutter/foundation.dart';

/// Pool **global do app** de language servers, chaveado por `(linguagem, raiz)`.
/// Vários workspaces vivos compartilham este pool: dois arquivos da mesma raiz
/// reusam o servidor; raízes/linguagens distintas têm servidores distintos.
///
/// Gerencia o ciclo de vida por **contagem de referência** dos documentos
/// abertos: o último `closeDocument` agenda o desligamento (com carência, caso
/// o usuário reabra logo). Degrada graciosamente — linguagem sem servidor
/// instalado é um no-op silencioso, o editor nunca quebra.
class LspServerPool {
  LspServerPool(this._factory);

  final LspClientFactory _factory;
  // Não injetado: o parser do auto_injector não pula parâmetro opcional com
  // default, então fica como campo inline (fora do grafo de DI).
  final ProjectRootFinder _rootFinder = const ProjectRootFinder();

  final Map<String, _ServerEntry> _servers = <String, _ServerEntry>{};
  final Map<String, _DocEntry> _docs = <String, _DocEntry>{};

  final StreamController<LspDiagnosticsBatch> _diagnostics =
      StreamController<LspDiagnosticsBatch>.broadcast();

  /// Emite a cada mudança de estado de servidor (subiu / caiu / reiniciou). A
  /// barra de status do LSP escuta isto pra atualizar o indicador ao vivo.
  final StreamController<void> _statusChanges =
      StreamController<void>.broadcast();

  /// Diagnostics de **todos** os servidores, mesclados. A UI roteia por `uri`.
  Stream<LspDiagnosticsBatch> get diagnostics => _diagnostics.stream;

  /// Pulsos de mudança de estado de servidores (sem payload — a UI re-consulta
  /// [statusForPath]).
  Stream<void> get statusChanges => _statusChanges.stream;

  /// Override de comando por linguagem (Wave 2: vem da tela "Language").
  /// `languageId` → linha de comando (`exec arg1 arg2`). Vazio = usa o default.
  Map<String, String> commandOverrides = const <String, String>{};

  /// Carência antes de desligar um servidor sem documentos abertos.
  static const Duration _shutdownGrace = Duration(seconds: 30);

  /// Abre um documento: resolve linguagem/raiz, **registra o doc** (mesmo se o
  /// servidor não subir — pra que o restart saiba o que reabrir), sobe/reusa o
  /// servidor e manda `didOpen`. [fallbackRoot] (a raiz do workspace) é usado
  /// quando o walk-up não acha marcador. No-op se a linguagem não é suportada.
  Future<void> openDocument({
    required String path,
    required String text,
    String? fallbackRoot,
  }) async {
    final def = languageForPath(path);
    if (def == null) return;
    final root = _rootFinder.findRoot(path, def.markers) ?? fallbackRoot;
    if (root == null) return;

    final key = _key(def.id, root);
    // Registra o doc antes de tentar subir — garante que statusForPath/restart
    // conheçam o documento (texto + raiz) mesmo se o start falhar.
    _docs[path] = _DocEntry(key, root, text);
    final entry = await _ensureServer(key, def, root);
    if (entry != null && entry.client.isRunning) {
      await entry.client.didOpen(path: path, text: text);
    }
  }

  /// Garante um servidor vivo para [key]. Reusa se já existe; senão resolve a
  /// spec e sobe. Retorna o entry vivo, ou `null` se não deu pra subir
  /// (degradação graciosa — os docs ficam registrados, status = stopped).
  Future<_ServerEntry?> _ensureServer(
    String key,
    LanguageDef def,
    String root,
  ) async {
    final existing = _servers[key];
    if (existing != null) {
      existing.cancelPendingShutdown();
      return existing.client.isRunning ? existing : null;
    }
    final spec = await _resolveSpec(def);
    if (spec == null) {
      _statusChanges.add(null);
      return null;
    }
    final client = _factory.create(spec: spec, rootPath: root);
    final entry = _ServerEntry(client);
    _servers[key] = entry;
    entry.sub = client.diagnostics.listen(_onDiagnostics);
    final result = await client.start();
    if (result.isFailure) {
      debugPrint('[lsp-pool] start falhou ($key)');
      await entry.sub?.cancel();
      _servers.remove(key);
      client.dispose();
      _statusChanges.add(null);
      return null;
    }
    _statusChanges.add(null);
    return entry;
  }

  /// `textDocument/didChange` (full sync). Guarda o texto mesmo sem servidor
  /// vivo (pro restart reabrir com o conteúdo atual).
  Future<void> changeDocument({
    required String path,
    required String text,
  }) async {
    final doc = _docs[path];
    if (doc == null) return;
    doc.version++;
    doc.lastText = text;
    final entry = _servers[doc.serverKey];
    if (entry == null || !entry.client.isRunning) return;
    await entry.client.didChange(path: path, text: text, version: doc.version);
  }

  /// Estado do LSP para o documento [path]: a linguagem e se o servidor está
  /// rodando. `null` se a linguagem não é suportada (a UI mostra vazio).
  LspDocStatus? statusForPath(String path) {
    final def = languageForPath(path);
    if (def == null) return null;
    final doc = _docs[path];
    final entry = doc == null ? null : _servers[doc.serverKey];
    return LspDocStatus(
      languageId: def.id,
      label: def.label,
      running: entry?.client.isRunning ?? false,
    );
  }

  /// Reinicia o servidor que atende [path]. Funciona mesmo se o servidor estava
  /// parado/falho (re-tenta subir e reabre os docs com o texto atual).
  Future<void> restartForPath(String path) async {
    final doc = _docs[path];
    if (doc == null) return;
    await _restartKey(doc.serverKey);
  }

  /// Reinicia todos os servidores de uma linguagem (ex.: após o usuário salvar
  /// um novo comando na tela "Language"). Cobre tanto servidores vivos quanto
  /// chaves com docs registrados mas sem servidor (start falhou antes).
  Future<void> restartLanguage(String languageId) async {
    final prefix = '$languageId$_sep';
    final keys = <String>{
      ..._servers.keys.where((k) => k.startsWith(prefix)),
      ..._docs.values
          .map((d) => d.serverKey)
          .where((k) => k.startsWith(prefix)),
    };
    for (final key in keys) {
      await _restartKey(key);
    }
  }

  /// Mata (se vivo) e re-sobe o servidor de [key], reabrindo todos os docs
  /// registrados nele com o último texto conhecido.
  Future<void> _restartKey(String key) async {
    final entry = _servers.remove(key);
    if (entry != null) {
      entry.cancelPendingShutdown();
      await entry.sub?.cancel();
      await entry.client.kill();
      entry.client.dispose();
    }
    _statusChanges.add(null);

    final docs = <String, _DocEntry>{
      for (final e in _docs.entries)
        if (e.value.serverKey == key) e.key: e.value,
    };
    if (docs.isEmpty) return;
    final def = languageForPath(docs.keys.first);
    if (def == null) return;
    final fresh = await _ensureServer(key, def, docs.values.first.root);
    if (fresh == null || !fresh.client.isRunning) return;
    for (final e in docs.entries) {
      await fresh.client.didOpen(path: e.key, text: e.value.lastText);
    }
  }

  /// Fecha o documento; agenda o desligamento do servidor quando não sobra
  /// nenhum doc registrado naquela chave.
  Future<void> closeDocument(String path) async {
    final doc = _docs.remove(path);
    if (doc == null) return;
    final entry = _servers[doc.serverKey];
    if (entry == null) return;
    if (entry.client.isRunning) await entry.client.didClose(path: path);
    final remaining = _docs.values.any((d) => d.serverKey == doc.serverKey);
    if (!remaining) _scheduleShutdown(doc.serverKey, entry);
  }

  /// Request genérico ao servidor que atende [path] (ex.: formatting na Wave 3).
  /// Falha se não há servidor para o documento.
  Future<Result<Object?, LspError>> requestForPath(
    String path,
    String method,
    Map<String, dynamic> params,
  ) async {
    final doc = _docs[path];
    final entry = doc == null ? null : _servers[doc.serverKey];
    if (entry == null) {
      return const Failure(LspError('No language server for this document.'));
    }
    return entry.client.request(method, params);
  }

  /// `textDocument/formatting` — pede a formatação do documento ao servidor e
  /// devolve os edits a aplicar no buffer. Lista vazia se não há servidor vivo,
  /// se o servidor não suporta formatting, ou em erro.
  Future<List<LspTextEdit>> formatDocument(
    String path, {
    int tabSize = 2,
    bool insertSpaces = true,
  }) async {
    final result = await requestForPath(path, 'textDocument/formatting', {
      'textDocument': {'uri': Uri.file(path).toString()},
      'options': {'tabSize': tabSize, 'insertSpaces': insertSpaces},
    });
    return result.fold(parseTextEdits, (_) => const <LspTextEdit>[]);
  }

  /// Desliga tudo (shutdown do app).
  void dispose() {
    for (final entry in _servers.values) {
      entry.cancelPendingShutdown();
      entry.sub?.cancel();
      entry.client.dispose();
    }
    _servers.clear();
    _docs.clear();
    if (!_diagnostics.isClosed) _diagnostics.close();
    if (!_statusChanges.isClosed) _statusChanges.close();
  }

  void _onDiagnostics(LspDiagnosticsBatch batch) {
    if (!_diagnostics.isClosed) _diagnostics.add(batch);
  }

  void _scheduleShutdown(String key, _ServerEntry entry) {
    entry.shutdownTimer = Timer(_shutdownGrace, () async {
      // Pode ter sido reusado durante a carência (algum doc voltou pra chave).
      if (_docs.values.any((d) => d.serverKey == key)) return;
      _servers.remove(key);
      await entry.sub?.cancel();
      await entry.client.kill();
      entry.client.dispose();
      _statusChanges.add(null);
      debugPrint('[lsp-pool] desligou $key');
    });
  }

  /// Resolve a spec: aplica override do usuário (Wave 2) ou o default, e
  /// localiza o binário no PATH (apps GUI não herdam PATH do shell).
  Future<LspServerSpec?> _resolveSpec(LanguageDef def) async {
    String executable = def.defaultExecutable;
    List<String> args = def.defaultArgs;

    final override = commandOverrides[def.id]?.trim();
    if (override != null && override.isNotEmpty) {
      final parts = splitLspCommand(override);
      if (parts.isNotEmpty) {
        executable = parts.first;
        args = parts.sublist(1);
      }
    }

    final resolved = await resolveExecutable(executable);
    return def.toSpec(executable: resolved, args: args);
  }

  /// Separador da chave `(linguagem, raiz)`. NUL nunca aparece num caminho nem
  /// num languageId, então é um delimitador seguro (raízes podem ter espaços).
  static const String _sep = '\u0000';

  String _key(String languageId, String root) => '$languageId$_sep$root';
}

class _ServerEntry {
  _ServerEntry(this.client);

  final LspClient client;
  StreamSubscription<LspDiagnosticsBatch>? sub;
  Timer? shutdownTimer;

  void cancelPendingShutdown() {
    shutdownTimer?.cancel();
    shutdownTimer = null;
  }
}

class _DocEntry {
  _DocEntry(this.serverKey, this.root, this.lastText);

  final String serverKey;

  /// Raiz usada ao abrir — reusada no restart pra recriar o mesmo servidor.
  final String root;

  /// Último texto conhecido (open/change) — reaberto no restart.
  String lastText;

  int version = 1;
}

/// Estado do LSP de um documento, pra barra de status do pane de Files.
class LspDocStatus {
  const LspDocStatus({
    required this.languageId,
    required this.label,
    required this.running,
  });

  final String languageId;
  final String label;
  final bool running;
}
