import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemException;

import 'package:cockpit/app/cockpit/data/browser/browser_bridge.dart';
import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/browser_element.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/entities/dbq_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/sql_statements.dart';
import 'package:cockpit/app/cockpit/domain/services/db_access_gate.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:cockpit/app/cockpit/domain/entities/browser_capability.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/browser_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/mongo_browser_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/redis_browser_session.dart';
import 'package:cockpit/app/cockpit/ui/session/task_output_session.dart';
import 'package:cockpit/app/cockpit/ui/session/task_terminal_store.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_read_window.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart' show SplitDir;
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Atende os comandos da CLI interna `cockpit` (mesmo socket do
/// `TerminalStatusServer`), extraído do `CockpitViewModel` (refactor
/// 2026-07-19). Roda **fora** da árvore de widgets — não toca `BuildContext`,
/// só lê/muta o estado do shell via a API pública do VM. Retorna rápido (o
/// `insertText` só enfileira o write no PTY).
class CockpitCliHandler {
  CockpitCliHandler(
    this._vm,
    this._db,
    this._http,
    this._tasks,
    this._taskRuns,
    this._taskTerms,
  );

  final CockpitViewModel _vm;
  final DbQueryService _db;
  final HttpRequestRunner _http;
  final TaskDiscovery _tasks;
  final TaskRunnerGateway _taskRuns;
  final TaskTerminalStore _taskTerms;

  /// Atende um comando da CLI interna `cockpit` (via o mesmo socket do
  /// [TerminalStatusServer]). Roda **fora** da árvore de widgets — não toca
  /// `BuildContext`, só lê/muta o estado da VM. Retorna rápido (o `insertText`
  /// só enfileira o write no PTY).
  Future<CockpitCommandResult> handle(CockpitCommand rawCommand) async {
    // `--focused` chega como o sentinela `@focused` no `tabId`: quem sabe qual
    // aba está em foco é a VM, não a CLI. Resolver aqui (e não em cada case)
    // vale pra todo comando que mira aba. Ferramenta externa (ditado por voz,
    // por exemplo) não tem como saber o id, e copiá-lo a cada uso é inviável.
    final c = _resolveFocusSentinel(rawCommand);
    if (c == null) {
      return const CockpitCommandResult.fail(
        'no focused tab (is a workspace open?)',
      );
    }
    switch (c.cmd) {
      // `send` e `send-key` chegam unificados como `write` (a CLI já resolveu o
      // texto/tecla em bytes UTF-8, transmitidos em base64 pra não quebrar o
      // framing de uma-linha-por-conexão).
      case 'write':
        final id = c.tabId;
        if (id == null || id.isEmpty) {
          return const CockpitCommandResult.fail(
            'missing tabId (use --tab-id or run inside a Cockpit terminal)',
          );
        }
        final s = _vm.session(id);
        if (s == null) {
          return CockpitCommandResult.fail('tab "$id" does not exist');
        }
        if (s is! TerminalSession) {
          return CockpitCommandResult.fail('tab "$id" is not a terminal');
        }
        final raw = (c.args['data'] ?? '').toString();
        String text;
        try {
          text = utf8.decode(base64.decode(raw));
        } catch (_) {
          return const CockpitCommandResult.fail(
            'invalid data (base64 expected)',
          );
        }
        s.insertText(text);
        return const CockpitCommandResult.ok();

      case 'list-panes':
        final focusedId = _vm.focusedTabId;
        final panes = _vm.allSessions
            .map(
              (s) => <String, dynamic>{
                'id': s.id,
                'kind': _paneKind(s),
                'title': s.title,
                // Rótulo manual estável (duplo-clique / "Rename"); `null` quando
                // a aba segue o título automático. É por ESTE campo que a
                // orquestração resolve pane por nome — não pelo `title` dinâmico
                // (que o claude/OSC reescrevem) nem pelo cwd (volátil).
                'label': s.manualLabel,
                'workspaceId': s.projectId,
                // Raiz do workspace no disco. `workspaceId` é um UUID opaco
                // desde a migração dos realms — quem precisa do caminho (ex.:
                // scripts que casavam por sufixo) usa este campo.
                'workspacePath': _vm.projectById(s.projectId)?.path,
                // Aba de task output → id da task espelhada (`npm:dev`…), o
                // mesmo aceito por `read-task`. Ausente nas demais tabs.
                if (s is TaskOutputSession) 'taskId': s.taskId,
                'working': s.isWorking,
                // Aba em foco (a que `--focused` mira). Sempre no máximo uma.
                'focused': s.id == focusedId,
              },
            )
            .toList();
        return CockpitCommandResult.ok(panes);

      // `cockpit open <path>` — abre um arquivo no viewer. A CLI já resolveu
      // pro caminho absoluto (o cwd do pane ≠ cwd do app). Abre no workspace do
      // pane que emitiu (trazendo-o pra frente se não for o ativo) e como aba
      // ao lado do próprio terminal (mesma folha).
      case 'open':
        final path = (c.args['path'] ?? '').toString();
        if (path.isEmpty) {
          return const CockpitCommandResult.fail('missing path');
        }
        // Aba remota: o path é do HOST. Checar no disco do cliente daria
        // "file not found" (ou, pior, abriria um homônimo local) — quem valida
        // é o `fs.read` do outro lado, dentro de `openFile`.
        if (!_isRemoteTab(c.tabId) && !await File(path).exists()) {
          return CockpitCommandResult.fail('file not found: "$path"');
        }
        final from = c.tabId;
        String? targetProject;
        String? targetLeaf;
        if (from != null && from.isNotEmpty) {
          final s = _vm.session(from);
          if (s != null) {
            targetProject = s.projectId;
            targetLeaf = _vm.leafOfTab(targetProject, from);
          }
        }
        if (targetProject != null && targetProject != _vm.selectedProjectId) {
          _vm.selectProject(targetProject);
        }
        if (_vm.selectedProjectId == null) {
          return const CockpitCommandResult.fail(
            'no active workspace to open the file in',
          );
        }
        await _vm.openFile(path, inPane: targetLeaf, isPreview: false);
        return const CockpitCommandResult.ok();

      // `cockpit new-tab` — cria uma aba de terminal. A CLI já resolveu o cwd
      // pro absoluto. Ancora no workspace/pane da tab emissora (trazendo o
      // workspace pra frente, mesma regra do `open`); `split` = right|down
      // divide a pane em vez de anexar a aba. Devolve `{tabId}` da tab criada.
      case 'new-tab':
        final cwd = (c.args['cwd'] ?? '').toString();
        if (cwd.isEmpty) {
          return const CockpitCommandResult.fail('missing cwd');
        }
        // Idem `open`: num terminal remoto o cwd é uma pasta do host.
        if (!_isRemoteTab(c.tabId) && !await Directory(cwd).exists()) {
          return CockpitCommandResult.fail('directory not found: "$cwd"');
        }
        final split = (c.args['split'] ?? '').toString();
        // Wire usa a geometria (right|down), não os nomes do SplitDir — o
        // enum é contra-intuitivo (vertical = lado a lado).
        final SplitDir? splitDir;
        switch (split) {
          case '':
            splitDir = null;
          case 'right':
            splitDir = SplitDir.vertical;
          case 'down':
            splitDir = SplitDir.horizontal;
          default:
            return CockpitCommandResult.fail(
              'invalid split "$split" (expected right or down)',
            );
        }
        final title = (c.args['title'] ?? '').toString();
        final sender = c.tabId == null ? null : _vm.session(c.tabId!);
        String? anchorLeaf;
        if (sender != null) {
          if (sender.projectId != _vm.selectedProjectId) {
            _vm.selectProject(sender.projectId);
          }
          anchorLeaf = _vm.leafOfTab(sender.projectId, sender.id);
        }
        final created = _vm.newTerminalTab(
          cwd: cwd,
          title: title.isEmpty ? null : title,
          inPane: anchorLeaf,
          splitDir: splitDir,
        );
        return switch (created) {
          Success(:final value) => CockpitCommandResult.ok({'tabId': value}),
          Failure(:final error) => CockpitCommandResult.fail(error),
        };

      // `cockpit orchestrate <file.ckp>` — aplica um layout de panes no
      // workspace ativo. A CLI já resolveu o path pro absoluto. Merge
      // idempotente (tab de mesmo nome = pulada); devolve {created, skipped}.
      case 'orchestrate':
        final path = (c.args['path'] ?? '').toString();
        if (path.isEmpty) {
          return const CockpitCommandResult.fail('missing path');
        }
        final sender = c.tabId == null ? null : _vm.session(c.tabId!);
        if (sender != null && sender.projectId != _vm.selectedProjectId) {
          _vm.selectProject(sender.projectId);
        }
        final applied = await _vm.applyLayoutFile(path);
        return switch (applied) {
          Success(:final value) => CockpitCommandResult.ok({
            'created': value.created,
            'skipped': value.skipped,
          }),
          Failure(:final error) => CockpitCommandResult.fail(error),
        };

      case 'list-workspaces':
        final ws = _vm.projects
            .map(
              (p) => <String, dynamic>{
                'id': p.id,
                'name': p.name,
                // Raiz no disco (mesma razão do `workspacePath` do list-panes:
                // o `id` virou UUID opaco; antes o path ERA o id).
                'path': p.path,
                // Nº de tabs (sessões) abertas nesse workspace. Campo era 'panes'
                // (enganoso — sempre foi contagem de tabs, não de folhas-pane).
                'tabs': _vm.allSessions
                    .where((s) => s.projectId == p.id)
                    .length,
              },
            )
            .toList();
        return CockpitCommandResult.ok(ws);

      // `cockpit read-pane [<label|tab-id>]` — devolve uma janela de linhas do
      // buffer renderizado do pane (texto plano, sem ANSI — é o que o xterm já
      // pintou). Args: `lines` (default 100), `offset` (pula N a partir da
      // âncora), `fromStart` (âncora no começo; default = fim/tail). A ordem
      // das linhas é sempre cronológica — as flags só escolhem a janela.
      case 'read-pane':
        final target = (c.args['target'] ?? '').toString();
        final PaneItem? s;
        if (target.isNotEmpty) {
          final resolved = _resolvePaneTarget(target);
          if (resolved case Failure(:final error)) {
            return CockpitCommandResult.fail(error);
          }
          s = (resolved as Success<PaneItem, String>).value;
        } else {
          final id = c.tabId;
          if (id == null || id.isEmpty) {
            return const CockpitCommandResult.fail(
              'missing target (pass <label|tab-id> or run inside a Cockpit '
              'terminal)',
            );
          }
          s = _vm.session(id);
          if (s == null) {
            return CockpitCommandResult.fail('tab "$id" does not exist');
          }
        }
        final term = switch (s) {
          TerminalSession t => t.terminal,
          TaskOutputSession t => t.terminal,
          _ => null,
        };
        if (term == null) {
          return CockpitCommandResult.fail(
            'tab "${s.id}" (${_paneKind(s)}) has no readable output',
          );
        }
        return CockpitCommandResult.ok(readTerminalWindow(term, c.args));

      // `cockpit list-tasks` — tasks do workspace do pane emissor (tabId,
      // default da CLI = a própria tab; fallback: workspace selecionado).
      // Mesmos binds do painel Tasks → mesma lista que a UI. `id` é o aceito
      // por `read-task`; `hasOutput` diz se o read vai responder.
      case 'list-tasks':
        final sender = c.tabId == null ? null : _vm.session(c.tabId!);
        final project = sender != null
            ? _vm.projectById(sender.projectId)
            : _vm.selectedProject;
        if (project == null ||
            project.isSystemTerminal ||
            project.path.isEmpty) {
          return const CockpitCommandResult.fail(
            'no workspace to list tasks for',
          );
        }
        final defs = await _tasks.discover(project.path);
        final tasks = defs
            .map(
              (d) => <String, dynamic>{
                'id': d.id,
                'label': d.label,
                'kind': d.kind.name,
                'source': d.source.name,
                'running': _taskRuns.runOf(d.id).isActive,
                'hasOutput': _taskTerms.existingTerminal(d.id) != null,
              },
            )
            .toList();
        return CockpitCommandResult.ok(tasks);

      // `cockpit read-task <task-id>` — mesma leitura, mas do terminal da task
      // no `TaskTerminalStore` (funciona mesmo sem aba `task_output` aberta).
      case 'read-task':
        final taskId = (c.args['target'] ?? '').toString();
        if (taskId.isEmpty) {
          return const CockpitCommandResult.fail('missing task id');
        }
        final term = _taskTerms.existingTerminal(taskId);
        if (term == null) {
          return CockpitCommandResult.fail(
            'no output recorded for task "$taskId" (never ran this boot?)',
          );
        }
        return CockpitCommandResult.ok(readTerminalWindow(term, c.args));

      // ── `cockpit db …` (plano 51) — acesso a banco pros agentes. A CLI é
      // cliente magro: quem executa é o app (mesmo motor da tab `.dbq`), e a
      // credencial nunca sai daqui. Workspace do pane emissor; `--workspace
      // <id|path>` pra uso fora de pane. Erros de banco voltam como
      // `<kind>: <message>` (a CLI reconstrói o JSON `{"error":{…}}`).
      case 'db-list':
        return _dbCommand(c, (project) async {
          final conns = await _db.connections(project.path);
          return CockpitCommandResult.ok([
            // `agents: false` = invisível pros agentes (a GUI segue vendo).
            for (final conn in conns)
              if (conn.agents)
                {
                  'name': conn.name,
                  'engine': conn.engine.label,
                  'target': conn.displayTarget,
                  'origin': conn.origin.name,
                  'access': conn.access.name,
                },
          ]);
        });

      case 'db-schema':
        return _dbCommand(c, (project) async {
          final (conn, connErr) = await _agentConn(
            project,
            (c.args['db'] ?? '').toString(),
          );
          if (connErr != null) return CockpitCommandResult.fail(connErr);
          final table = (c.args['table'] ?? '').toString();
          final result = await _db.schema(
            workspaceRoot: project.path,
            workspaceId: project.id,
            connName: conn!.name,
            table: table.isEmpty ? null : table,
          );
          return CockpitCommandResult.ok(result.toJson());
        });

      case 'db-query':
      case 'db-execute':
        return _dbCommand(c, (project) async {
          final (conn, connErr) = await _agentConn(
            project,
            (c.args['db'] ?? '').toString(),
          );
          if (connErr != null) return CockpitCommandResult.fail(connErr);
          final sql = (c.args['sql'] ?? '').toString();
          // Guardrail (conexão `read`): execute é recusado de cara; query
          // passa pelo gate de statement (SELECT-like apenas).
          if (conn!.access == DbAccess.read) {
            if (c.cmd == 'db-execute') {
              return const CockpitCommandResult.fail(
                'read_only_connection: this connection is read-only for '
                'agents — enable Read & write on it in the Database panel',
              );
            }
            final violation = sqlReadViolation(sql);
            if (violation != null) return CockpitCommandResult.fail(violation);
          }
          final result = await _db.query(
            workspaceRoot: project.path,
            workspaceId: project.id,
            connName: conn.name,
            sql: sql,
            limit: int.tryParse('${c.args['limit'] ?? ''}'),
            dml: c.cmd == 'db-execute',
          );
          return CockpitCommandResult.ok(result.toJson());
        });

      // `cockpit db run <file.dbq>` — executa o arquivo (frontmatter decide
      // conexão e limite). O path chega absoluto (a CLI resolve contra o cwd).
      case 'db-run':
        return _dbCommand(c, (project) async {
          final path = (c.args['path'] ?? '').toString();
          if (path.isEmpty) {
            return const CockpitCommandResult.fail('missing .dbq path');
          }
          final String content;
          try {
            content = await File(path).readAsString();
          } on FileSystemException catch (e) {
            return CockpitCommandResult.fail(
              'cannot read "$path": ${e.message}',
            );
          }
          final doc = DbqDocument.parse(content);
          if (doc.db == null) {
            return CockpitCommandResult.fail(
              'unknown_connection: "$path" has no "-- db:" frontmatter — '
              'pick a database in the Cockpit tab or add the line manually',
            );
          }
          final (conn, connErr) = await _agentConn(project, doc.db!);
          if (connErr != null) return CockpitCommandResult.fail(connErr);
          final statements = [
            for (final st in splitSqlStatements(doc.sql)) st.text,
          ];
          // Conexão `read`: cada statement do script passa pelo gate.
          if (conn!.access == DbAccess.read) {
            for (final st in statements) {
              final violation = sqlReadViolation(st);
              if (violation != null) {
                return CockpitCommandResult.fail(violation);
              }
            }
          }
          // Mesma semântica de script da tab: statements em sequência,
          // resultado do último.
          final result = await _db.runStatements(
            workspaceRoot: project.path,
            workspaceId: project.id,
            connName: conn.name,
            statements: statements,
            limit: doc.limit,
          );
          return CockpitCommandResult.ok(result.toJson());
        });

      // ── `cockpit http …` — dispara requests de um arquivo `.http` pros
      // agentes. Mesmo motor da tab (`HttpRequestRunner`), mesma saída JSON de
      // uma linha do `cockpit db`. Texto em inglês por decisão: a CLI fala com
      // agentes e scripts, não com a UI.
      case 'http-list':
        return _projectCommand(c, (project) async {
          final (doc, err) = await _httpDoc(c);
          if (err != null) return CockpitCommandResult.fail(err);
          return CockpitCommandResult.ok([
            for (var i = 0; i < doc!.requests.length; i++)
              {
                'index': i,
                'name': doc.requests[i].name,
                'method': doc.requests[i].method,
                'url': doc.requests[i].url,
              },
          ]);
        });

      // `cockpit http run <file.http> [--request <nome|índice>]` — sem
      // `--request`, roda o primeiro request do arquivo.
      case 'http-run':
        return _projectCommand(c, (project) async {
          final (doc, err) = await _httpDoc(c);
          if (err != null) return CockpitCommandResult.fail(err);
          if (doc!.requests.isEmpty) {
            return const CockpitCommandResult.fail(
              'no_request: the file has no request',
            );
          }
          final wanted = (c.args['request'] ?? '').toString();
          var index = 0;
          if (wanted.isNotEmpty) {
            final asIndex = int.tryParse(wanted);
            if (asIndex != null) {
              if (asIndex < 0 || asIndex >= doc.requests.length) {
                return CockpitCommandResult.fail(
                  'no_request: no request at index $asIndex '
                  '(the file has ${doc.requests.length})',
                );
              }
              index = asIndex;
            } else {
              index = doc.requests.indexWhere(
                (r) => r.name.toLowerCase() == wanted.toLowerCase(),
              );
              if (index < 0) {
                return CockpitCommandResult.fail(
                  'no_request: no request named "$wanted" '
                  '(see `cockpit http list`)',
                );
              }
            }
          }
          final path = (c.args['path'] ?? '').toString();
          final timeout = int.tryParse('${c.args['timeout'] ?? ''}');
          final result = await _http.send(
            doc.resolveRequest(doc.requests[index]),
            baseDir: Directory(path).parent.path,
            timeout: Duration(seconds: timeout ?? 30),
          );
          return result.fold(
            (value) => CockpitCommandResult.ok(value.toJson()),
            (error) => CockpitCommandResult.fail(_httpErrorText(error)),
          );
        });

      // `cockpit redis` — comando de cache CLI-only (plano 51). `args.parts`
      // é a lista do comando (`['GET','foo']`). Reply cru em JSON.
      case 'redis-cmd':
        return _dbCommand(c, (project) async {
          final (conn, connErr) = await _agentConn(
            project,
            (c.args['db'] ?? '').toString(),
          );
          if (connErr != null) return CockpitCommandResult.fail(connErr);
          final parts = [
            for (final p in (c.args['parts'] as List? ?? const [])) '$p',
          ];
          if (conn!.access == DbAccess.read) {
            final violation = redisReadViolation(parts);
            if (violation != null) return CockpitCommandResult.fail(violation);
          }
          final reply = await _db.redisCommand(
            workspaceRoot: project.path,
            workspaceId: project.id,
            connName: conn.name,
            parts: parts,
          );
          return CockpitCommandResult.ok(reply);
        });

      // `cockpit mongo` — CLI-only: `args.command` é o JSON do runCommand.
      case 'mongo-cmd':
        return _dbCommand(c, (project) async {
          final raw = (c.args['command'] ?? '{}').toString();
          final Map<String, dynamic> command;
          try {
            command = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } catch (_) {
            return const CockpitCommandResult.fail(
              'query_failed: invalid JSON command',
            );
          }
          final (conn, connErr) = await _agentConn(
            project,
            (c.args['db'] ?? '').toString(),
          );
          if (connErr != null) return CockpitCommandResult.fail(connErr);
          if (conn!.access == DbAccess.read) {
            final violation = mongoReadViolation(command);
            if (violation != null) return CockpitCommandResult.fail(violation);
          }
          var database = (c.args['database'] ?? '').toString().trim();
          // Comando que só roda no `admin` (listDatabases) é roteado pra lá —
          // é o comando de descoberta do agente e falharia com `Unauthorized`
          // contra qualquer outra base. Mesma regra do seletor do painel.
          if (database.isEmpty) {
            database = mongoForcedDatabase(command) ?? '';
          }
          final dbErr = await _mongoDatabaseError(project, conn, database);
          if (dbErr != null) return CockpitCommandResult.fail(dbErr);
          final reply = await _db.mongoCommand(
            workspaceRoot: project.path,
            workspaceId: project.id,
            connName: conn.name,
            command: command,
            database: database.isEmpty ? null : database,
          );
          return CockpitCommandResult.ok(reply);
        });

      // `cockpit redis browse` / `cockpit mongo browse` (plano 53, decisão D):
      // o agente abre a view filtrada pro humano. Abrir view ≠ executar — não
      // devolve dados; valida filtro/conexão ANTES de abrir.
      case 'browse':
        return _dbCommand(c, (project) async {
          final raw = (c.args['url'] ?? '').toString();
          if (raw.isEmpty) {
            return const CockpitCommandResult.fail('missing url');
          }
          final url = normalizeBrowserUrl(raw);
          // Sem webview inline (Linux): browser do SO, e o JSON diz isso.
          if (!BrowserCapability.resolve().isInline) {
            final ok = await _vm.openUrlExternally(url);
            if (!ok) {
              return CockpitCommandResult.fail('could not open "$url"');
            }
            return CockpitCommandResult.ok({'mode': 'system', 'url': url});
          }
          final session = _vm.openWebBrowser(
            url,
            projectId: project.id,
            reuse: true,
          );
          if (session == null) {
            return const CockpitCommandResult.fail(
              'workspace has no open pane to attach the browser to',
            );
          }
          return CockpitCommandResult.ok({'mode': 'inline', 'url': url});
        });

      case 'redis-browse':
        return _dbCommand(c, (project) async {
          final connName = (c.args['db'] ?? '').toString();
          final err = await _checkBrowseConn(project, connName, DbEngine.redis);
          if (err != null) return CockpitCommandResult.fail(err);
          final ok = _vm.openRedisBrowser(
            connName,
            projectId: project.id,
            pattern: (c.args['pattern'] ?? '').toString(),
          );
          if (!ok) {
            return const CockpitCommandResult.fail(
              'workspace has no open pane to attach the browser to',
            );
          }
          return CockpitCommandResult.ok({'opened': 'redis', 'db': connName});
        });

      case 'mongo-browse':
        return _dbCommand(c, (project) async {
          final connName = (c.args['db'] ?? '').toString();
          final collection = (c.args['collection'] ?? '').toString();
          if (collection.isEmpty) {
            return const CockpitCommandResult.fail('missing <collection>');
          }
          final err = await _checkBrowseConn(project, connName, DbEngine.mongo);
          if (err != null) return CockpitCommandResult.fail(err);
          final filter = (c.args['filter'] ?? '').toString();
          // Valida o JSON aqui — nunca abrir a tab com filtro quebrado.
          MongoBrowseService.parseFilter(filter);
          // Diferente do `mongo-cmd`: aqui o `--database` **fixa** a base da
          // conexão. A tab é o que o humano passa a ver, e ela resolve o alvo
          // pela conexão — abrir uma view apontando pra outra base seria mentira.
          final (conn, _) = await _agentConn(project, connName);
          final database = (c.args['database'] ?? '').toString().trim();
          if (conn != null) {
            final dbErr = await _mongoDatabaseError(project, conn, database);
            if (dbErr != null) return CockpitCommandResult.fail(dbErr);
            if (database.isNotEmpty) {
              await _db.selectMongoDatabase(project.id, conn.name, database);
            }
          }
          final ok = _vm.openMongoBrowser(
            connName,
            collection,
            projectId: project.id,
            filter: filter,
          );
          if (!ok) {
            return const CockpitCommandResult.fail(
              'workspace has no open pane to attach the browser to',
            );
          }
          return CockpitCommandResult.ok({
            'opened': 'mongo',
            'db': connName,
            'collection': collection,
          });
        });

      // `cockpit browser read|click|type|screenshot|eval` (plano 61): controle
      // do navegador embutido via injeção de JS (`evaluateJavascript`) — sem
      // CDP disponível pra WKWebView. Ver `browser_bridge.dart`.
      case 'browser-read':
        return _browserCommand(c, (session, web) async {
          final full = c.args['full'] == true;
          await web.evaluateJavascript(source: browserBridgeJs);
          final raw = await web.evaluateJavascript(
            source: 'window.__cockpitBrowser.read($full);',
          );
          if (raw is! String) {
            throw const BrowserAutomationException(
              'eval_failed',
              'browser bridge returned no data (page may not have finished '
                  'loading)',
            );
          }
          final decoded = jsonDecode(raw) as List<dynamic>;
          return CockpitCommandResult.ok([
            for (final e in decoded)
              BrowserElement.fromJson(e as Map<String, dynamic>).toJson(),
          ]);
        });

      case 'browser-click':
        return _browserCommand(c, (session, web) async {
          final id = (c.args['id'] ?? '').toString();
          if (id.isEmpty) {
            return const CockpitCommandResult.fail(
              'missing <id> (see `cockpit browser read`)',
            );
          }
          final raw = await web.evaluateJavascript(
            source: _safeBridgeCall(
              'window.__cockpitBrowser.click(${jsonEncode(id)})',
            ),
          );
          return _handleBridgeAck(raw);
        });

      case 'browser-type':
        return _browserCommand(c, (session, web) async {
          final id = (c.args['id'] ?? '').toString();
          if (id.isEmpty) {
            return const CockpitCommandResult.fail(
              'missing <id> (see `cockpit browser read`)',
            );
          }
          final text = (c.args['text'] ?? '').toString();
          final raw = await web.evaluateJavascript(
            source: _safeBridgeCall(
              'window.__cockpitBrowser.type(${jsonEncode(id)}, '
              '${jsonEncode(text)})',
            ),
          );
          return _handleBridgeAck(raw);
        });

      case 'browser-screenshot':
        return _browserCommand(c, (session, web) async {
          final bytes = await web.takeScreenshot();
          if (bytes == null) {
            throw const BrowserAutomationException(
              'eval_failed',
              'screenshot failed (webview may not be ready)',
            );
          }
          final out = (c.args['out'] ?? '').toString();
          if (out.isEmpty) {
            return CockpitCommandResult.ok({'base64': base64Encode(bytes)});
          }
          try {
            await File(out).writeAsBytes(bytes);
          } on FileSystemException catch (e) {
            throw BrowserAutomationException(
              'eval_failed',
              'could not write "$out": ${e.message}',
            );
          }
          return CockpitCommandResult.ok({'path': out});
        });

      case 'browser-eval':
        return _browserCommand(c, (session, web) async {
          final js = (c.args['js'] ?? '').toString();
          if (js.isEmpty) {
            return const CockpitCommandResult.fail(
              'missing <js> (see `cockpit browser eval --help`)',
            );
          }
          final raw = await web.evaluateJavascript(source: _evalWrapper(js));
          if (raw is! String) {
            throw const BrowserAutomationException(
              'eval_failed',
              'evaluateJavascript returned no data',
            );
          }
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic> &&
              decoded.containsKey('__cockpitError')) {
            throw BrowserAutomationException(
              'eval_failed',
              decoded['__cockpitError'].toString(),
            );
          }
          return CockpitCommandResult.ok(decoded);
        });

      default:
        return CockpitCommandResult.fail('unknown command: "${c.cmd}"');
    }
  }

  /// Recusa comandos Mongo que não têm database resolvível, listando o que
  /// existe. `null` = pode seguir.
  ///
  /// Sem isto o runner caía em `admin` e o agente recebia `ok:1` com as
  /// `system.*` do deployment — resposta que *parece* sucesso e não é. Erro
  /// explícito é a única saída honesta: URL de Atlas não traz database no path,
  /// e a seleção do painel pode nunca ter acontecido neste workspace.
  Future<String?> _mongoDatabaseError(
    Project project,
    DbConnection conn,
    String database,
  ) async {
    if (database.isNotEmpty) return null;
    if (_db.mongoDatabase(project.id, conn) != null) return null;
    final available = await _mongoDatabaseNames(project, conn);
    return 'query_failed: connection "${conn.name}" has no database — its URL '
        'has none in the path and none was picked in the app. Pass '
        '--database <name>${available.isEmpty ? '' : ' (available: '
                  '${available.join(', ')})'}.';
  }

  /// Databases do deployment, pro texto do erro acima. Falha vira lista vazia:
  /// a mensagem principal continua valendo sem eles.
  Future<List<String>> _mongoDatabaseNames(
    Project project,
    DbConnection conn,
  ) async {
    try {
      final svc = MongoBrowseService(_db)
        ..target(
          workspaceRoot: project.path,
          workspaceId: project.id,
          connName: conn.name,
        );
      return await svc.listDatabases();
    } on Object {
      return const [];
    }
  }

  /// Resolve a conexão [connName] pro caminho **dos agentes**: conexões com
  /// `agents: false` são tratadas como inexistentes (nem o nome vaza — a
  /// lista de disponíveis também as omite). Devolve (conexão, null) ou
  /// (null, mensagem de erro).
  Future<(DbConnection?, String?)> _agentConn(
    Project project,
    String connName,
  ) async {
    if (connName.isEmpty) return (null, 'missing --db <name>');
    final conns = [
      for (final c in await _db.connections(project.path))
        if (c.agents) c,
    ];
    for (final conn in conns) {
      if (conn.name == connName) return (conn, null);
    }
    final available = conns.map((c) => c.name).join(', ');
    return (
      null,
      'no connection named "$connName" '
          '(available: ${available.isEmpty ? 'none' : available})',
    );
  }

  /// Valida a conexão alvo de um `browse`: visível pra agentes e do [engine]
  /// esperado. `null` = ok; senão a mensagem de erro.
  Future<String?> _checkBrowseConn(
    Project project,
    String connName,
    DbEngine engine,
  ) async {
    final (conn, err) = await _agentConn(project, connName);
    if (err != null) return err;
    return conn!.engine == engine
        ? null
        : '"$connName" is a ${conn.engine.label} connection, '
              'not ${engine.label}';
  }

  /// Molde dos comandos `db-*`: resolve o workspace (decisão K do plano 51 —
  /// `--workspace <id|path>` > pane emissor > erro, **nunca** cwd nem chute) e
  /// converte [DbQueryException] em `fail("<kind>: <mensagem>")`.
  /// `true` se a aba emissora pertence a um workspace de host remoto — aí os
  /// caminhos que chegam pela CLI são do host, não deste computador.
  bool _isRemoteTab(String? tabId) {
    if (tabId == null || tabId.isEmpty) return false;
    final session = _vm.session(tabId);
    if (session == null) return false;
    return _vm.projectById(session.projectId)?.isRemoteTerminal ?? false;
  }

  /// Lê e parseia o `.http` de `args['path']` (absoluto — a CLI resolve
  /// contra o cwd). Devolve `(doc, null)` ou `(null, erro em inglês)`.
  Future<(HttpDocument?, String?)> _httpDoc(CockpitCommand c) async {
    final path = (c.args['path'] ?? '').toString();
    if (path.isEmpty) return (null, 'missing .http path');
    try {
      return (HttpDocument.parse(await File(path).readAsString()), null);
    } on FileSystemException catch (e) {
      return (null, 'cannot read "$path": ${e.message}');
    }
  }

  /// Erro de request no formato `<kind>: <mensagem>` que a CLI reconstrói em
  /// `{"error":{kind,message}}`. Em inglês por decisão (saída de CLI não é
  /// traduzida); a UI usa `httpRequestErrorMessage`, que traduz.
  static String _httpErrorText(HttpRequestError e) {
    final detail = e.detail?.trim() ?? '';
    return switch (e.kind) {
      HttpRequestErrorKind.noRequest => 'no_request: no request found',
      HttpRequestErrorKind.invalidUrl =>
        'invalid_url: "$detail" is not a '
            'valid absolute URL',
      HttpRequestErrorKind.unresolvedVariable =>
        'unresolved_variable: {{${e.variable}}} has no value — declare it '
            'with @${e.variable} = … in the file',
      HttpRequestErrorKind.bodyFileUnreadable =>
        'body_file_unreadable: cannot read "${e.path}"'
            '${detail.isEmpty ? '' : ': $detail'}',
      HttpRequestErrorKind.connectionFailed =>
        'connection_failed: ${detail.isEmpty ? 'could not reach the server' : detail}',
      HttpRequestErrorKind.timeout =>
        'timeout: no response after ${e.timeoutSeconds}s',
      HttpRequestErrorKind.responseTooLarge =>
        'response_too_large: over the ${e.limitBytes} byte limit',
    };
  }

  /// Resolve o workspace do comando (`--workspace <id|path>`, ou o do pane
  /// emissor) e roda [action] nele. Compartilhado por `db`/`redis`/`mongo` e
  /// `http` — todos precisam de uma pasta de workspace real.
  Future<CockpitCommandResult> _projectCommand(
    CockpitCommand c,
    Future<CockpitCommandResult> Function(Project project) action,
  ) async {
    Project? project;
    final ws = (c.args['workspace'] ?? '').toString();
    if (ws.isNotEmpty) {
      for (final p in _vm.projects) {
        if (p.id == ws || p.path == ws) {
          project = p;
          break;
        }
      }
      if (project == null) {
        return CockpitCommandResult.fail('no workspace matches "$ws"');
      }
    } else {
      final sender = c.tabId == null ? null : _vm.session(c.tabId!);
      project = sender == null ? null : _vm.projectById(sender.projectId);
      if (project == null) {
        return const CockpitCommandResult.fail(
          'not inside a Cockpit pane — pass --workspace <id|path> '
          '(see `cockpit list-workspaces`)',
        );
      }
    }
    if (project.isSystemTerminal || project.path.isEmpty) {
      return const CockpitCommandResult.fail(
        'this pane has no workspace folder',
      );
    }
    return action(project);
  }

  /// [_projectCommand] + tradução do erro de banco para o formato
  /// `<kind>: <message>` que a CLI reconstrói em `{"error":{…}}`.
  Future<CockpitCommandResult> _dbCommand(
    CockpitCommand c,
    Future<CockpitCommandResult> Function(Project project) action,
  ) => _projectCommand(c, (project) async {
    try {
      return await action(project);
    } on DbQueryException catch (e) {
      return CockpitCommandResult.fail('${e.kind}: ${e.message}');
    }
  });

  /// Resolve a aba de navegador alvo de um `browser *` (plano 61). Duas
  /// formas de endereçar, na mesma flag `--tab-id`:
  /// - aponta direto pra uma `BrowserSession` (id tirado de `list-tabs`) → é
  ///   essa a aba, sem olhar workspace;
  /// - resolve pra outra coisa (o normal: a tab do terminal que emitiu o
  ///   comando) → vira só sinal de **workspace** (mesma regra do
  ///   `_dbCommand`), e a aba de navegador é a única existente naquele
  ///   workspace. Zero ou mais de uma = erro tipado, nunca chute.
  Future<Result<BrowserSession, String>> _resolveBrowserSession(
    CockpitCommand c,
  ) async {
    final explicitId = c.tabId;
    if (explicitId != null && explicitId.isNotEmpty) {
      final direct = _vm.session(explicitId);
      if (direct is BrowserSession) return Success(direct);
    }
    Project? project;
    final ws = (c.args['workspace'] ?? '').toString();
    if (ws.isNotEmpty) {
      for (final p in _vm.projects) {
        if (p.id == ws || p.path == ws) {
          project = p;
          break;
        }
      }
      if (project == null) {
        return Failure('no workspace matches "$ws"');
      }
    } else {
      final sender = explicitId == null || explicitId.isEmpty
          ? null
          : _vm.session(explicitId);
      project = sender == null ? null : _vm.projectById(sender.projectId);
      if (project == null) {
        return const Failure(
          'not inside a Cockpit pane — pass --workspace <id|path> or '
          '--tab-id <browser-tab-id> (see `cockpit list-tabs`)',
        );
      }
    }
    if (project.isSystemTerminal || project.path.isEmpty) {
      return const Failure('this pane has no workspace folder');
    }
    final tabs = _vm.allSessions
        .whereType<BrowserSession>()
        .where((s) => s.projectId == project!.id)
        .toList();
    if (tabs.isEmpty) {
      return const Failure(
        'no_browser_tab: no browser tab open in this workspace (open one '
        'first with `cockpit browse <url>`)',
      );
    }
    if (tabs.length > 1) {
      return Failure(
        'ambiguous_browser_tab: multiple browser tabs open '
        '(${tabs.map((s) => s.id).join(', ')}) — pass --tab-id <id>',
      );
    }
    return Success(tabs.single);
  }

  /// Molde dos comandos `browser *`: resolve a aba (acima), garante que o
  /// webview está vivo, e converte [BrowserAutomationException] em
  /// `fail("<kind>: <mensagem>")` (mesmo contrato do `_dbCommand`).
  Future<CockpitCommandResult> _browserCommand(
    CockpitCommand c,
    Future<CockpitCommandResult> Function(
      BrowserSession session,
      InAppWebViewController web,
    )
    action,
  ) async {
    final resolved = await _resolveBrowserSession(c);
    if (resolved case Failure(:final error)) {
      return CockpitCommandResult.fail(error);
    }
    final session = (resolved as Success<BrowserSession, String>).value;
    final web = session.controller;
    if (web == null) {
      return const CockpitCommandResult.fail(
        'tab_closed: browser tab has no active webview (it may have just '
        'been opened, or the tab was closed)',
      );
    }
    try {
      return await action(session, web);
    } on BrowserAutomationException catch (e) {
      return CockpitCommandResult.fail('${e.kind}: ${e.message}');
    }
  }

  /// Envolve uma chamada ao bridge (`click`/`type`) com um guard pra bridge
  /// ausente — acontece se a página navegou depois do `read` sem `read` de
  /// novo: o `window.__cockpitBrowser` da página anterior sumiu junto. Vira
  /// `stale_element_id` (mesma família de erro de um id velho), não exceção
  /// solta do lado Dart.
  String _safeBridgeCall(String call) =>
      '(function(){ if (!window.__cockpitBrowser) '
      'return JSON.stringify({error:"stale_element_id"}); '
      'return $call; })();';

  /// Decodifica o retorno `{ok:true}` / `{error:"..."}` de `click`/`type`.
  CockpitCommandResult _handleBridgeAck(Object? raw) {
    if (raw is! String) {
      throw const BrowserAutomationException(
        'eval_failed',
        'browser bridge returned no data (page may not have finished '
            'loading)',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final error = decoded['error'] as String?;
    if (error == 'stale_element_id') {
      throw const BrowserAutomationException(
        'stale_element_id',
        'element id is from an old `read` (or the page navigated) — read '
            'again',
      );
    }
    if (error != null) {
      throw BrowserAutomationException('eval_failed', error);
    }
    return const CockpitCommandResult.ok({'ok': true});
  }

  /// Envolve a expressão do `browser eval` pra devolver sempre uma linha
  /// JSON: resultado serializável vira `json`, função/símbolo ou exceção JS
  /// viram `{__cockpitError}` (decodificado no case como `eval_failed`).
  String _evalWrapper(String js) =>
      '(function(){ try { var r = ($js); '
      'if (typeof r === "function" || typeof r === "symbol") { '
      'throw new Error("result not serializable (" + typeof r + ")"); } '
      'var json = JSON.stringify(r === undefined ? null : r); '
      'if (json === undefined) { throw new Error("result not serializable"); } '
      'return json; } catch (e) { '
      'return JSON.stringify({__cockpitError: String((e && e.message) || e)}); '
      '} })();';

  /// Resolve o alvo de um `read-pane`: primeiro por id exato (`t3`), depois
  /// por `manualLabel` (case-insensitive). Label ambíguo = erro — nunca chuta
  /// pane (mesma regra do dispatch de orquestração).
  Result<PaneItem, String> _resolvePaneTarget(String target) {
    final byId = _vm.session(target);
    if (byId != null) return Success(byId);
    final lower = target.toLowerCase();
    final byLabel = _vm.allSessions
        .where((s) => s.manualLabel?.toLowerCase() == lower)
        .toList();
    if (byLabel.length == 1) return Success(byLabel.first);
    if (byLabel.length > 1) {
      return Failure(
        'label "$target" is ambiguous (${byLabel.length} tabs) — '
        'use a tab-id from `cockpit list-tabs`',
      );
    }
    return Failure(
      'no tab with id or label "$target" (see `cockpit list-tabs`)',
    );
  }

  String _paneKind(PaneItem s) {
    if (s is TerminalSession) return 'terminal';
    if (s is AgentSession) return 'agent';
    if (s is FileViewerSession) return 'file';
    if (s is TaskOutputSession) return 'task';
    if (s is RedisBrowserSession) return 'redis';
    if (s is MongoBrowserSession) return 'mongo';
    if (s is BrowserSession) return 'browser';
    return 'other';
  }

  /// Sentinela do `--focused` da CLI. Devolve o comando com o `tabId` real, ou
  /// `null` quando não há aba em foco pra resolver (aí o chamador falha com
  /// mensagem clara em vez de escrever numa aba arbitrária).
  static const String _focusSentinel = '@focused';

  CockpitCommand? _resolveFocusSentinel(CockpitCommand c) {
    if (c.tabId != _focusSentinel) return c;
    final id = _vm.focusedTabId;
    if (id == null || id.isEmpty) return null;
    return CockpitCommand(cmd: c.cmd, tabId: id, args: c.args);
  }
}
