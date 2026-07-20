import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemException;

import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/entities/dbq_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/sql_statements.dart';
import 'package:cockpit/app/cockpit/domain/services/db_access_gate.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/services/mongo_browse_service.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
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

/// Atende os comandos da CLI interna `cockpit` (mesmo socket do
/// `TerminalStatusServer`), extraído do `CockpitViewModel` (refactor
/// 2026-07-19). Roda **fora** da árvore de widgets — não toca `BuildContext`,
/// só lê/muta o estado do shell via a API pública do VM. Retorna rápido (o
/// `insertText` só enfileira o write no PTY).
class CockpitCliHandler {
  CockpitCliHandler(
    this._vm,
    this._db,
    this._tasks,
    this._taskRuns,
    this._taskTerms,
  );

  final CockpitViewModel _vm;
  final DbQueryService _db;
  final TaskDiscovery _tasks;
  final TaskRunnerGateway _taskRuns;
  final TaskTerminalStore _taskTerms;

  /// Atende um comando da CLI interna `cockpit` (via o mesmo socket do
  /// [TerminalStatusServer]). Roda **fora** da árvore de widgets — não toca
  /// `BuildContext`, só lê/muta o estado da VM. Retorna rápido (o `insertText`
  /// só enfileira o write no PTY).
  Future<CockpitCommandResult> handle(CockpitCommand c) async {
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
        if (!await File(path).exists()) {
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
        if (!await Directory(cwd).exists()) {
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
          final reply = await _db.mongoCommand(
            workspaceRoot: project.path,
            workspaceId: project.id,
            connName: conn.name,
            command: command,
          );
          return CockpitCommandResult.ok(reply);
        });

      // `cockpit redis browse` / `cockpit mongo browse` (plano 53, decisão D):
      // o agente abre a view filtrada pro humano. Abrir view ≠ executar — não
      // devolve dados; valida filtro/conexão ANTES de abrir.
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

      default:
        return CockpitCommandResult.fail('unknown command: "${c.cmd}"');
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
  Future<CockpitCommandResult> _dbCommand(
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
    try {
      return await action(project);
    } on DbQueryException catch (e) {
      return CockpitCommandResult.fail('${e.kind}: ${e.message}');
    }
  }

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
    return 'other';
  }
}
