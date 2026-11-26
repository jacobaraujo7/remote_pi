import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as paths;
import '../../../core/domain/result.dart';
import '../../domain/contracts/terminal_status_server.dart';
import '../session/orchestration_session.dart';
import '../session/pane_item.dart';
import '../session/terminal_read_window.dart';
import '../session/terminal_session.dart';
import '../states/pane_node.dart';

/// Resolves the sender before looking up destinations. No selected-workspace
/// fallback is permitted for a sender that has disappeared.
class OrchestrationCliRouter {
  OrchestrationCliRouter({
    required this.findSession,
    required this.findOwner,
    required this.focusedTabId,
    required this.workspace,
    required this.projectCommand,
  });

  final PaneItem? Function(String) findSession;
  final OrchestrationSession? Function(String) findOwner;
  final String? Function() focusedTabId;
  final ({String root, String name, bool remote})? Function(String) workspace;
  final Future<CockpitCommandResult> Function(CockpitCommand) projectCommand;

  Future<CockpitCommandResult?> handle(CockpitCommand c) async {
    final callerId = c.callerTabId;
    final caller = callerId == null ? null : findSession(callerId);
    if (callerId != null &&
        (caller == null || (caller is TerminalSession && caller.hasExited))) {
      return const CockpitCommandResult.fail(
        'Originating terminal is no longer available',
      );
    }
    if (caller is OrchestrationSession) {
      return _handle(caller, c);
    }
    final ownerId = caller?.owner.instanceId;
    if (ownerId != null) {
      final owner = findOwner(ownerId);
      if (owner == null ||
          !identical(owner.terminals.session(callerId!), caller)) {
        return const CockpitCommandResult.fail(
          'Originating orchestration is no longer available',
        );
      }
      return _handle(owner, c);
    }

    // External --focused automation may address the selected internal shell.
    // A normal workspace terminal cannot cross into another app's registry.
    final id = c.tabId == '@focused' ? focusedTabId() : c.tabId;
    final rawTarget = c.args['target'];
    final target = findSession(
      rawTarget is String && rawTarget.isNotEmpty ? rawTarget : id ?? '',
    );
    if (c.tabId != null &&
        c.tabId != '@focused' &&
        (rawTarget == null || rawTarget == '') &&
        target == null) {
      return const CockpitCommandResult.fail(
        'Target pane is no longer available',
      );
    }
    final targetOwner = target is OrchestrationSession
        ? target
        : target?.owner.instanceId == null
        ? null
        : findOwner(target!.owner.instanceId!);
    if (targetOwner == null) return null;
    if (callerId != null) {
      return const CockpitCommandResult.fail(
        'Target belongs to an orchestration app',
      );
    }
    if (target is OrchestrationSession && c.tabId != '@focused') {
      return const CockpitCommandResult.fail(
        'Close or configure the orchestration app through its own controls',
      );
    }
    return _handle(targetOwner, c);
  }

  Future<CockpitCommandResult> _handle(
    OrchestrationSession owner,
    CockpitCommand c,
  ) {
    final info = workspace(owner.projectId);
    if (info == null) {
      return Future.value(
        const CockpitCommandResult.fail(
          'Orchestration worktree is no longer available',
        ),
      );
    }
    return OrchestrationCliHandler(
      owner: owner,
      root: info.root,
      workspaceName: info.name,
      remote: info.remote,
      projectCommand: projectCommand,
    ).handle(c);
  }
}

/// Uses only the app's private registry; never enumerates workspace panes.
class OrchestrationCliHandler {
  OrchestrationCliHandler({
    required this.owner,
    required this.root,
    required this.workspaceName,
    required this.remote,
    required this.projectCommand,
  });

  final OrchestrationSession owner;
  final String root;
  final String workspaceName;
  final bool remote;
  final Future<CockpitCommandResult> Function(CockpitCommand) projectCommand;
  bool get _available => !owner.disposed && !owner.closing;

  // Existing data tools keep using the sender's project and host. UI commands
  // that open/replace global tabs or workspaces deliberately aren't delegated.
  static const _projectVerbs = {
    'exec',
    'db-list',
    'db-schema',
    'db-query',
    'db-execute',
    'db-run',
    'http-list',
    'http-run',
    'redis-cmd',
    'mongo-cmd',
    'list-tasks',
    'read-task',
    'run-task',
    'stop-task',
    'restart-task',
    'send-task-key',
    'telemetry-open',
    'telemetry-ingest',
    'telemetry-close',
    'telemetry-errors',
    'telemetry-logs',
    'telemetry-events',
    'telemetry-runs',
    'telemetry-show',
    'telemetry-wait',
    'telemetry-mark',
    'telemetry-triage',
    'telemetry-clear',
    'telemetry-perf',
    'telemetry-probes',
    'telemetry-replay',
  };

  Future<CockpitCommandResult> handle(CockpitCommand c) async {
    if (!_available) {
      return const CockpitCommandResult.fail('Orchestration is closing');
    }
    final caller = c.callerTabId == null
        ? null
        : owner.terminals.session(c.callerTabId!);
    if (c.callerTabId != null && (caller == null || caller.hasExited)) {
      return const CockpitCommandResult.fail(
        'Originating terminal is no longer available',
      );
    }
    final requested = (c.args['workspace'] ?? '').toString();
    if (requested.isNotEmpty &&
        requested != owner.projectId &&
        requested != root) {
      return const CockpitCommandResult.fail(
        'Workspace is outside this orchestration',
      );
    }
    if (_projectVerbs.contains(c.cmd)) {
      if (caller == null || c.args['app'] == true) {
        return const CockpitCommandResult.fail(
          'Project tools require a terminal in this orchestration',
        );
      }
      return projectCommand(
        CockpitCommand(
          cmd: c.cmd,
          callerTabId: caller.id,
          tabId: caller.id,
          args: {
            ...c.args,
            'workspace': owner.projectId,
            if (c.cmd == 'exec' && (c.args['cwd'] ?? '').toString().isEmpty)
              'cwd': caller.workingDirectory,
          },
        ),
      );
    }
    switch (c.cmd) {
      case 'list-panes':
        return CockpitCommandResult.ok([
          for (final s in owner.terminals.sessions.values)
            {
              'id': s.id,
              'kind': 'terminal',
              'title': s.title,
              'label': s.manualLabel,
              'workspaceId': s.projectId,
              'workspacePath': root,
              'working': s.isWorking,
              'focused': owner.terminals.keyboardTabId == s.id,
            },
        ]);
      case 'list-workspaces':
        return CockpitCommandResult.ok([
          {
            'id': owner.projectId,
            'name': workspaceName,
            'path': root,
            'tabs': owner.terminals.sessions.length,
          },
        ]);
      case 'open':
        final target = _target(c);
        if (target == null) {
          return const CockpitCommandResult.fail(
            'Terminal is not in this orchestration',
          );
        }
        final file = c.args['path'];
        if (file is! String || file.isEmpty) {
          return const CockpitCommandResult.fail('Missing document path');
        }
        final result = await owner.openFile(target.id, file);
        return switch (result) {
          Success(:final value) => CockpitCommandResult.ok({'path': value}),
          Failure(:final error) => CockpitCommandResult.fail(error),
        };
      case 'new-tab':
        if (![null, '', 'right', 'down'].contains(c.args['split'])) {
          return const CockpitCommandResult.fail('Invalid split direction');
        }
        final split = switch (c.args['split']) {
          null || '' => null,
          'right' => SplitDir.vertical,
          'down' => SplitDir.horizontal,
          _ => null,
        };
        final target = _target(c);
        if (target == null) {
          return const CockpitCommandResult.fail(
            'Terminal is not in this orchestration',
          );
        }
        final raw = (c.args['cwd'] ?? target.workingDirectory).toString();
        final directory = _relativeDirectory(raw, target);
        if (directory == null) {
          return const CockpitCommandResult.fail(
            'Directory must be inside this worktree',
          );
        }
        final result = await owner.context.newTerminal(
          title: c.args['title']?.toString(),
          directory: directory,
          inPane: owner.terminals.paneOf(target.id)?.id,
          split: split,
        );
        return switch (result) {
          Success(:final value) => CockpitCommandResult.ok({'tabId': value}),
          Failure(:final error) => CockpitCommandResult.fail(error),
        };
      case 'write':
      case 'read-pane':
      case 'close-tab':
        final target = _target(c);
        if (target == null) {
          return const CockpitCommandResult.fail(
            'Terminal is not in this orchestration (or label is ambiguous)',
          );
        }
        if (c.cmd == 'read-pane') {
          final result = readTerminalWindow(target.terminal, c.args);
          if (caller != null && (result['lines'] as int? ?? 0) > 0) {
            owner.context.recordTraffic(target.id, caller.id);
          }
          return CockpitCommandResult.ok(result);
        }
        if (c.cmd == 'write') {
          if (target.hasExited || owner.closingTerminals.contains(target.id)) {
            return const CockpitCommandResult.fail('Terminal has ended');
          }
          final String text;
          try {
            text = utf8.decode(
              base64.decode((c.args['data'] ?? '').toString()),
            );
          } on Object {
            return const CockpitCommandResult.fail(
              'invalid data (base64 expected)',
            );
          }
          target.insertText(text);
          if (caller != null) owner.context.recordTraffic(caller.id, target.id);
          return const CockpitCommandResult.ok();
        }
        final close = owner.onCloseTerminal;
        if (close == null) {
          return const CockpitCommandResult.fail(
            'Terminal close is unavailable',
          );
        }
        // The sender may be the process being closed. Flush the response first.
        return CockpitCommandResult.ok({'closed': target.id}, () {
          if (_available &&
              identical(owner.terminals.session(target.id), target)) {
            unawaited(owner.closeTerminal(target.id));
          }
        });
      default:
        return CockpitCommandResult.fail(
          'Command "${c.cmd}" is not available inside an orchestration app',
        );
    }
  }

  TerminalSession? _target(CockpitCommand c) {
    final named = (c.args['target'] ?? '').toString();
    if (named.isNotEmpty) {
      final exact = owner.terminals.session(named);
      if (exact != null) return exact;
      final matches = owner.terminals.sessions.values
          .where((s) => s.manualLabel?.toLowerCase() == named.toLowerCase())
          .toList();
      return matches.length == 1 ? matches.single : null;
    }
    final id = c.tabId == '@focused'
        ? owner.terminals.keyboardTabId
        : c.tabId ?? c.callerTabId;
    return id == null ? null : owner.terminals.session(id);
  }

  String? _relativeDirectory(String value, TerminalSession source) {
    final ctx = paths.Context(style: remote ? paths.Style.posix : paths.style);
    var cwd = value;
    if (!remote &&
        ctx.style == paths.Style.windows &&
        source.profile.wslDistro != null) {
      final mount = RegExp(r'^/mnt/([a-zA-Z])/(.*)$').firstMatch(cwd);
      if (mount != null) cwd = '${mount[1]}:/${mount[2]}';
    }
    final absolute = ctx.normalize(
      ctx.isAbsolute(cwd) ? cwd : ctx.join(root, cwd),
    );
    final base = ctx.normalize(root);
    if (!ctx.equals(base, absolute) && !ctx.isWithin(base, absolute)) {
      return null;
    }
    final relative = ctx.relative(absolute, from: base);
    if (ctx.style != paths.Style.windows && relative.contains('\\')) {
      return null;
    }
    return relative.replaceAll('\\', '/');
  }
}
