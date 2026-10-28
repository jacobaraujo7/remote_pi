part of 'cockpit_viewmodel.dart';

extension OrchestrationWorkspace on CockpitViewModel {
  OrchestrationSession? get activeOrchestration {
    final item = focusedTab()?.$3;
    return item is OrchestrationSession ? item : null;
  }

  /// Contextual menu action; outer dock buttons keep their existing factory.
  void newTerminalForFocusedTab() {
    final owner = activeOrchestration;
    if (owner == null) {
      newTabIn('');
      return;
    }
    _newOwnedTerminalFromMenu(owner);
  }

  bool splitFocusedOrchestration(SplitDir direction) {
    final owner = activeOrchestration;
    if (owner == null) return false;
    _newOwnedTerminalFromMenu(owner, split: direction);
    return true;
  }

  void _newOwnedTerminalFromMenu(
    OrchestrationSession owner, {
    SplitDir? split,
  }) {
    if (owner.disposed || owner.closing) return;
    unawaited(
      owner.context.newTerminal(split: split).then((result) {
        if (result case Failure(:final error) when !owner.disposed) {
          owner.controller.reportError(error);
        }
      }),
    );
  }

  OrchestrationSession? orchestrationById(String id) => _orchestrations[id];

  String _orchestrationBoxCwd(String projectId, String boxId) =>
      projectRootOf(projectId) ?? '';

  // Gallery activation starts clean; legacy files and outside sessions are
  // intentionally not enumerated or imported into an owned document.
  bool get hasLegacyOrchestration => false;

  OrchestrationDocument _orchestrationSeed(
    String projectId, {
    bool importLegacy = false,
  }) => OrchestrationDocument.defaultTerminals(newId: newUid);

  Future<String> _readOrchestrationFile(String projectId, String file) async {
    final hostId = _projectById(projectId)?.remoteHostId;
    if (hostId != null) {
      final host = _remoteHosts.hosts.where((h) => h.id == hostId).first;
      final service = await _remoteHosts.fileServiceFor(host);
      final bytes = await service.read(file);
      return utf8.decode(bytes);
    }
    return File(file).readAsString();
  }

  Future<void> _writeOrchestrationFile(
    String projectId,
    String file,
    String text,
  ) async {
    final hostId = _projectById(projectId)?.remoteHostId;
    if (hostId != null) {
      final host = _remoteHosts.hosts.where((h) => h.id == hostId).first;
      final service = await _remoteHosts.fileServiceFor(host);
      await service.write(file, utf8.encode(text));
    } else {
      // Atomic replacement prevents a watcher observing a partial JSON write.
      final pending = File('$file.cockpit-tmp');
      await pending.writeAsString(text, flush: true);
      await pending.rename(file);
    }
  }

  Future<Result<OrchestrationFilePresentation, String>> _openOwnedFile(
    OrchestrationSession owner,
    TerminalSession terminal,
    String raw, {
    int? line,
  }) async {
    final project = _projectById(owner.projectId);
    if (project == null) return const Failure('Worktree unavailable');
    final root = project.effectiveRoot;
    final hostId = project.remoteHostId;
    final sourceHost = hostId == null
        ? null
        : _remoteHosts.hosts.where((h) => h.id == hostId).firstOrNull;
    final cwd = terminal.currentDirectory ?? terminal.workingDirectory;
    bool available() =>
        !owner.disposed &&
        !owner.closing &&
        identical(_orchestrations[owner.id], owner) &&
        _projectById(owner.projectId)?.effectiveRoot == root &&
        _projectById(owner.projectId)?.remoteHostId == hostId &&
        (hostId == null ||
            (sourceHost != null && !_remoteHosts.isDisconnected(hostId)));
    if (!available()) {
      return const Failure('Originating document or host is unavailable');
    }
    final files = hostId == null
        ? const LocalDocumentFiles()
        : CapturedDocumentFiles(() async {
            if (!available()) {
              throw StateError('Originating host is unavailable');
            }
            return _remoteHosts.fileServiceFor(sourceHost!);
          });
    final changes = hostId == null
        ? _fileChanges
        : ServiceDocumentWatcher(
            files,
            active: () =>
                available() && owner.fileVisible && owner.presentationVisible,
          );
    final host = WorktreeDocumentHost(
      workspaceRoot: root,
      changes: changes,
      files: files,
      remote: hostId != null,
      available: available,
    );
    final resolved = await host.resolve(raw, cwd: cwd);
    if (!available()) {
      return const Failure('Originating document or host is unavailable');
    }
    return Success(
      OrchestrationFilePresentation(
        id: 'of-${newUid()}',
        path: resolved,
        terminalId: terminal.id,
        host: host,
        line: line,
        onPanelCall: (command, directory) async {
          if (!available() ||
              terminal.hasExited ||
              !identical(owner.terminals.session(terminal.id), terminal)) {
            return const {
              'ok': false,
              'error': 'Originating terminal is unavailable',
            };
          }
          return runPanelCommand(
            command,
            sessionId: terminal.id,
            cwd: directory,
          );
        },
      ),
    );
  }

  OrchestrationSession _makeOrchestration(
    String projectId,
    String file, {
    String? id,
    bool startWatching = true,
    OrchestrationPresentation presentation = const OrchestrationPresentation(),
  }) {
    final sourceProject = _projectById(projectId);
    if (sourceProject == null) throw StateError('Worktree unavailable');
    final sourceHostId = sourceProject.remoteHostId;
    late OrchestrationSession session;
    Future<void> saveLocal() {
      final layout = _serializeLayout(projectId);
      return layout.isEmpty
          ? Future<void>.value()
          : _layoutStore.save(projectId, layout);
    }

    final controller = OrchestrationController(
      read: () => _readOrchestrationFile(projectId, session.path),
      write: (text) => _writeOrchestrationFile(projectId, session.path, text),
      terminals: () => [
        for (final t in session.terminals.sessions.values)
          OrchestrationTerminal(t.id, t.displayTitle, '.'),
      ],
      newBoxId: newUid,
      flushLocalState: saveLocal,
      createShell: (box) async {
        if (session.disposed ||
            session.closing ||
            !identical(_orchestrations[session.id], session)) {
          throw StateError('Orchestration is closing');
        }
        final hostId = _projectById(projectId)?.remoteHostId;
        if (hostId != null && _remoteHosts.isDisconnected(hostId)) {
          throw StateError(
            'Host disconnected; reconnect and reload this document',
          );
        }
        final ctx = path.Context(
          style: _isRemoteWorkspace(projectId) ? path.Style.posix : path.style,
        );
        final cwd = ctx.normalize(
          ctx.join(projectRootOf(projectId)!, box.directory),
        );
        final previousId = session.controller.bindings[box.box.id];
        final previous = previousId == null
            ? null
            : session.terminals.session(previousId);
        final pane = previousId == null
            ? null
            : session.terminals.paneOf(previousId);
        final index = pane?.tabs.indexOf(previousId!);
        final created = _buildTerminal(
          'ot-${newUid()}',
          projectId,
          cwd,
          title: box.box.title,
          manualLabel: box.box.title,
          ownedBy: session,
          ownedPane: pane?.id,
          replay: previous?.hasExited == true
              ? '\x1bc${previous!.scrollbackSnapshot}\x1b[<9u\r\n'
              : null,
        );
        if (pane != null && index != null) {
          session.terminals.move(created.id, pane.id, index: index);
        }
        return created.id;
      },
      closeTerminal: (tabId) async {
        final result = await _closeOwnedTerminal(
          session,
          tabId,
          forgetDefinition: false,
        );
        if (result case Failure(:final error)) throw StateError(error);
      },
    );
    session = OrchestrationSession(
      id: id ?? _nid('orch'),
      projectId: projectId,
      path: file,
      remoteFileSystem: _isRemoteWorkspace(projectId),
      controller: controller,
      presentation: presentation,
      remoteDisconnected: () {
        final hostId = _projectById(projectId)?.remoteHostId;
        return hostId != null && _remoteHosts.isDisconnected(hostId);
      },
      onPersist: () => _scheduleSave(projectId),
      readAliases: (terminal) async {
        final file = terminal.transcriptPath;
        if (file == null ||
            session.disposed ||
            session.closing ||
            (Platform.isWindows && terminal.profile.wslDistro != null)) {
          return {};
        }
        if (sourceHostId != null) {
          final host = _remoteHosts.hosts
              .where((h) => h.id == sourceHostId)
              .first;
          final files = await _remoteHosts.fileServiceFor(host);
          return _graphIdentityResolver.readAliasesBytes(
            await files.read(file, maxBytes: 32 * 1024 * 1024),
          );
        }
        return _graphIdentityResolver.readAliases(file);
      },
      onBeforeDispose: saveLocal,
      windowActive: () => notifications.windowActive,
      windowActivityChanges: notifications.windowActivityChanges,
      onFocus: () {
        final pane = leafOfTab(projectId, session.id);
        if (pane != null && selectedProjectId == projectId) focus(pane);
      },
      onCloseTerminal: (tabId) => _closeOwnedTerminal(session, tabId),
      onOpenFile: (terminal, file, {line}) =>
          _openOwnedFile(session, terminal, file, line: line),
      onOpenShell: (boxId) => _openOwnedShell(session, boxId),
      onStartCli: (boxId) => _startOwnedCli(session, boxId),
      onHandoff: (boxId) => _handoffOwned(session, boxId),
      onSuggestRole: (boxId) => suggestOrchestrationRole(session.id, boxId),
    );
    _orchestrations[session.id] = session;
    _sessions[session.id] = session;
    if (startWatching) {
      _watchOrchestration(session);
      controller.startPolling();
    }
    return session;
  }

  /// Restore only local descriptors saved under this exact outer app tab.
  /// The gate is retained on failure so Reload cannot bypass ownership checks
  /// or replace recoverable sessions with a fresh portable-file reconciliation.
  void _prepareOrchestrationRestore(
    OrchestrationSession owner,
    Project project,
    Set<String> reservedIds,
  ) {
    OrchestrationRestoreState? state;
    var migrateLegacy = owner.pendingRestoration?['ownershipVersion'] == null;
    owner.controller.beforeReconcile = () async {
      if (owner.disposed || owner.closing) {
        throw StateError('Orchestration is closing');
      }
      final hostId = project.remoteHostId;
      if (hostId != null && _remoteHosts.isDisconnected(hostId)) {
        throw StateError(
          'Host disconnected; reconnect and reload this document',
        );
      }
      if (state == null) {
        if (migrateLegacy) {
          await _migrateOrchestrationOwnership(owner, project);
          migrateLegacy = false;
        }
        final raw = Map<String, dynamic>.from(owner.pendingRestoration!);
        final migration = raw['ownershipMigration'];
        owner.ownershipMigration = migration is Map
            ? Map<String, dynamic>.from(migration)
            : null;
        var parsed = OrchestrationRestoreState.parse(
          raw,
          instanceId: owner.id,
          projectId: project.id,
        );
        final remap = <String, String>{
          for (final id in parsed.sessions.keys)
            if (reservedIds.contains(id) || session(id) != null)
              id: 'ot-${newUid()}',
        };
        if (remap.isNotEmpty) {
          final mux = {...parsed.multiplexer};
          final tree = mux['tree'];
          if (tree is Map) {
            mux['tree'] = paneNodeToJson(
              _remapTabs(paneNodeFromJson(tree.cast<String, dynamic>()), remap),
            );
          }
          mux['keyboardTabId'] =
              remap[mux['keyboardTabId']] ?? mux['keyboardTabId'];
          raw['bindings'] = {
            for (final e in parsed.bindings.entries)
              e.key: remap[e.value] ?? e.value,
          };
          raw['sessions'] = {
            for (final e in parsed.sessions.entries)
              remap[e.key] ?? e.key: e.value,
          };
          raw['multiplexer'] = mux;
          // Copy before committing the remap, retaining the original history if
          // a host or local store fails. Portable files never reach this path.
          for (final entry in remap.entries) {
            final history = await _scrollback.load(
              projectId: project.id,
              sessionId: entry.key,
            );
            if (history != null) {
              await _scrollback.save(
                projectId: project.id,
                sessionId: entry.value,
                contents: history,
              );
            }
          }
          parsed = OrchestrationRestoreState.parse(
            raw,
            instanceId: owner.id,
            projectId: project.id,
          );
        }
        owner.controller.restoreSnapshot(
          savedDocument: parsed.document,
          savedBindings: parsed.bindings,
          savedPendingRemovals: parsed.pendingRemovals,
          wasDirty: parsed.dirty,
        );
        owner.pendingRestoration = raw;
        state = parsed;
      }
      for (final entry in state!.sessions.entries) {
        if (owner.terminals.session(entry.key) != null) continue;
        await _restoreSession(entry.key, entry.value, project, ownedBy: owner);
      }
      owner.terminals.restoreLayout(state!.multiplexer);
      owner.context.restorePresentation(state!.presentation);
      owner.pendingRestoration = null;
      owner.controller.beforeReconcile = null;
      _watchOrchestration(owner);
      owner.controller.startPolling();
      unawaited(owner.context.reconcileIdentities());
    };
  }

  Future<void> _migrateOrchestrationOwnership(
    OrchestrationSession owner,
    Project project,
  ) async {
    final layouts = _layoutStore;
    if (layouts is! WorkspaceLayoutCheckpointStore) {
      throw StateError('This layout store cannot verify migration checkpoints');
    }
    final root = projectRootOf(project.id);
    if (root == null || root.isEmpty) throw StateError('Worktree unavailable');
    final paths = path.Context(
      style: project.isRemoteTerminal ? path.Style.posix : path.style,
    );
    // Capture the original host: no operation may follow the selected project.
    final hostId = project.remoteHostId;
    final host = hostId == null
        ? null
        : _remoteHosts.hosts.where((h) => h.id == hostId).first;
    final remoteFiles = host == null
        ? null
        : await _remoteHosts.fileServiceFor(host);
    void ensureCurrent() {
      if (owner.disposed ||
          owner.closing ||
          !identical(_orchestrations[owner.id], owner)) {
        throw StateError('Orchestration closed during migration');
      }
    }

    final migration = OrchestrationOwnershipMigration(
      seed: () => _orchestrationSeed(project.id),
      newPath: () =>
          paths.join(root, 'agents-isolated-${newUid().substring(0, 8)}.orc'),
      validDestination: (file) =>
          paths.equals(paths.dirname(file), paths.normalize(root)) &&
          OrchestrationDocument.isFilePath(file),
      checkpoint: (next) async {
        ensureCurrent();
        owner.pendingRestoration = next;
        owner.retarget(next['path'] as String);
        final layout = _serializeLayout(project.id);
        if (layout.isEmpty) throw StateError('Workspace layout unavailable');
        await (layouts as WorkspaceLayoutCheckpointStore).checkpoint(
          project.id,
          layout,
        );
      },
      read: (file) async {
        ensureCurrent();
        if (remoteFiles != null) {
          try {
            return utf8.decode(await remoteFiles.read(file));
          } on FileException catch (e) {
            if (e.kind == FileErrorKind.notFound) return null;
            rethrow;
          }
        }
        try {
          return await File(file).readAsString();
        } on PathNotFoundException {
          return null;
        }
      },
      createNew: (file, text) async {
        ensureCurrent();
        if (remoteFiles != null) {
          return remoteFiles.createNew(file, utf8.encode(text));
        }
        final target = File(file);
        try {
          await target.create(exclusive: true);
        } on PathExistsException {
          return false;
        } on FileSystemException {
          if (await FileSystemEntity.type(file, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return false;
          }
          rethrow;
        }
        await target.writeAsString(text, flush: true);
        return true;
      },
    );
    owner.pendingRestoration = await migration.migrate(
      owner.pendingRestoration!,
    );
    _bumpFileTree();
  }

  Future<Result<String, String>> _closeOwnedTerminal(
    OrchestrationSession owner,
    String tabId, {
    bool forgetDefinition = true,
  }) async {
    if (owner.disposed) return const Failure('Document closed');
    final terminal = owner.terminals.session(tabId);
    if (terminal == null) {
      return const Failure('Terminal is not owned by this document');
    }
    if (!owner.closingTerminals.add(tabId)) {
      return const Failure('Terminal is already closing');
    }
    try {
      await terminal.stopProcess();
      if (forgetDefinition) await owner.controller.forgetTerminal(tabId);
      _clearGraphRole(tabId);
      owner.terminals.detach(tabId);
      await _endOfFrame();
      await terminal.dispose();
      return Success(tabId);
    } catch (e) {
      owner.controller.reportError(e);
      return Failure(e.toString());
    } finally {
      owner.closingTerminals.remove(tabId);
    }
  }

  Future<Result<String, String>> _openOwnedShell(
    OrchestrationSession owner,
    String boxId,
  ) async {
    if (owner.disposed || owner.closing) {
      return const Failure('Document closed');
    }
    final box = owner.context.graphBoxes
        .where((b) => b.id == boxId)
        .firstOrNull;
    if (box == null) return const Failure('Box not found');
    final current = owner.terminals.session(box.tabId ?? '');
    if (current != null && !current.hasExited) return Success(current.id);
    if (current != null) {
      await owner.controller.restartShell(boxId, expectedTabId: current.id);
      final replacement = owner.controller.bindings[boxId];
      if (owner.controller.error != null) {
        return Failure(owner.controller.error!);
      }
      return replacement != null && owner.terminals.contains(replacement)
          ? Success(replacement)
          : const Failure('Could not restart shell');
    }
    await owner.controller.load();
    final tabId = owner.controller.bindings[boxId];
    return tabId != null && owner.terminals.contains(tabId)
        ? Success(tabId)
        : Failure(owner.controller.error ?? 'Could not create shell');
  }

  Future<Result<String, String>> _startOwnedCli(
    OrchestrationSession owner,
    String boxId,
  ) async {
    final opened = await _openOwnedShell(owner, boxId);
    if (opened case Failure()) return opened;
    final box = owner.context.graphBoxes
        .where((b) => b.id == boxId)
        .firstOrNull;
    if (box == null) return const Failure('Box not found');
    final command = _graphCliCommand(box);
    if (command == null) {
      return const Failure('Configure Claude, Codex or Pi before starting');
    }
    final terminal = owner.terminals.session(
      (opened as Success<String, String>).value,
    )!;
    if (terminal.activeHarness != null) {
      return _graphHarnessMatches(terminal, box.harness)
          ? Success(terminal.id)
          : const Failure('Another agent is already running in this tab');
    }
    _typeWhenReady(terminal.id, command);
    _queueGraphRole(terminal.id, box.role, box.harness);
    return Success(terminal.id);
  }

  Future<Result<String, String>> _handoffOwned(
    OrchestrationSession owner,
    String boxId,
  ) async {
    final box = owner.context.graphBoxes
        .where((b) => b.id == boxId)
        .firstOrNull;
    if (box == null || _graphCliCommand(box) == null) {
      return const Failure('Configure a tool before handoff');
    }
    final previous = owner.terminals.session(box.tabId ?? '');
    if (previous == null || previous.hasExited) {
      return const Failure('Open the session before handoff');
    }
    await owner.controller.handoff(
      boxId,
      historyTitle: '${box.title} (${owner.context.graphBoxes.length + 1})',
    );
    if (owner.controller.error != null || owner.controller.dirty) {
      return Failure(owner.controller.error ?? 'Document has unsaved changes');
    }
    return _startOwnedCli(owner, boxId);
  }

  /// A native OS open has no terminal/selected-workspace origin. Resolve its
  /// actual local worktree, or create an empty workspace beside the file.
  Future<void> openNativeOrchestration(String raw) async {
    if (_nativeDocumentsDisposed || !OrchestrationDocument.isFilePath(raw)) {
      return;
    }
    final file = path.normalize(path.absolute(raw));
    if (!await File(file).exists() || _nativeDocumentsDisposed) return;
    // Observe discovery already in progress, at boot or after adding a root.
    // Never request another reconciliation just to locate the file's worktree.
    await _worktreeReconciler.settle();
    if (_nativeDocumentsDisposed) return;
    var project = nativeOrchestrationProject(
      file,
      _projectList,
      realmId: realmCtrl.activeId,
      selectedProjectId: _selectedProjectId,
    );
    if (project == null) {
      final directory = path.dirname(file);
      project = await addProject(
        Platform.isWindows ? directory.replaceAll(r'\', '/') : directory,
        name: path.basename(directory),
      );
    }
    final projectId = project.id;
    if (_nativeDocumentsDisposed || _projectById(projectId) == null) return;
    await _activateProject(projectId);
    if (_nativeDocumentsDisposed || _projectById(projectId) == null) return;
    selectProject(projectId);
    await openOrchestration(file, projectId: projectId);
    if (!_nativeDocumentsDisposed && !isMobilePlatform) {
      await windowManager.show();
      if (!_nativeDocumentsDisposed) await windowManager.focus();
    }
  }

  Future<void> openOrchestration(
    String file, {
    required String projectId,
    Map<String, String> initialBindings = const {},
  }) {
    final previous = _orchestrationOpens[projectId] ?? Future<void>.value();
    final operation = previous.then(
      (_) => _openOrchestration(
        file,
        projectId: projectId,
        initialBindings: initialBindings,
      ),
    );
    _orchestrationOpens[projectId] = operation.then(
      (_) {},
      onError: (Object e, StackTrace st) {
        DiagnosticsLog.instance.logError('orchestration-open', e, st);
      },
    );
    return operation;
  }

  Future<void> _openOrchestration(
    String file, {
    required String projectId,
    Map<String, String> initialBindings = const {},
  }) async {
    final filePaths = path.Context(
      style: _isRemoteWorkspace(projectId) ? path.Style.posix : path.style,
    );
    file = filePaths.normalize(file);
    if (!filePaths.isAbsolute(file)) {
      file = filePaths.normalize(
        filePaths.join(projectRootOf(projectId)!, file),
      );
    }
    final existing = _orchestrations.values
        .where(
          (owner) =>
              owner.projectId == projectId &&
              filePaths.equals(owner.path, file),
        )
        .firstOrNull;
    if (existing != null) {
      final pane = leafOfTab(projectId, existing.id);
      if (pane != null) {
        _trees[projectId] = updateLeaf(
          _trees[projectId]!,
          pane,
          (p) => p.copyWith(active: existing.id),
        );
        _focused[projectId] = pane;
      }
      await existing.controller.load();
      notifyListeners();
      return;
    }
    _initTree(projectId);
    final session = _makeOrchestration(projectId, file);
    final leaf = _focused[projectId] ?? leaves(_trees[projectId]!).first.id;
    _addLeafTab(projectId, leaf, session.id);
    await session.controller.load();
    final first = session.context.graphBoxes.firstOrNull;
    if (first != null) session.context.openBoxInTerminals(first.id);
    _scheduleSave(projectId);
    notifyListeners();
  }

  void _watchOrchestration(OrchestrationSession session) {
    _fileWatchers.remove(session.id)?.cancel();
    if (_isRemoteWorkspace(session.projectId)) return;
    _fileWatchers[session.id] = _fileChanges.watchFile(session.path).listen((
      _,
    ) {
      if (_orchestrations[session.id] == session) {
        unawaited(session.controller.load());
      }
    });
  }
}

final _agentRoleSuggestions = AgentRoleSuggestionService();

extension OrchestrationRoleSuggestions on CockpitViewModel {
  Future<Result<String, String>> suggestOrchestrationRole(
    String instanceId,
    String boxId,
  ) async {
    final tr = slang.t.orchestration;
    final doc = _orchestrations[instanceId];
    final terminal = doc?.terminals.session(
      doc.controller.bindings[boxId] ?? '',
    );
    if (doc == null ||
        terminal is! TerminalSession ||
        terminal.hasExited ||
        terminal.activeHarness == null) {
      return Failure(tr.roleNoAgent);
    }
    final projectId = doc.projectId;
    if (terminal.status != TerminalStatus.idle) return Failure(tr.roleBusy);
    final documentPath = doc.path;
    final cli = terminal.activeHarness;
    final conversation = terminal.claudeSessionId;
    bool current() =>
        _orchestrations[instanceId] == doc &&
        !doc.disposed &&
        !doc.closing &&
        doc.path == documentPath &&
        doc.controller.bindings[boxId] == terminal.id &&
        identical(doc.terminals.session(terminal.id), terminal) &&
        !terminal.hasExited &&
        terminal.activeHarness == cli &&
        (conversation == null || terminal.claudeSessionId == conversation);
    try {
      final role = await _agentRoleSuggestions.request(
        key:
            '${identityHashCode(this)}|$instanceId|$projectId|$documentPath|$boxId',
        requestId: newUid(),
        language: slang.LocaleSettings.currentLocale.languageCode,
        isCurrent: current,
        prepare: () async {
          final hostId = _projectById(projectId)?.remoteHostId;
          final host = hostId == null
              ? null
              : _remoteHosts.hosts.where((h) => h.id == hostId).first;
          final remote = host == null
              ? null
              : await _remoteHosts.fileServiceFor(host);
          final id = newUid().replaceAll(RegExp('[^a-zA-Z0-9-]'), '');
          final responsePath = remote == null
              ? path.join(Directory.systemTemp.path, 'cockpit-role-$id.json')
              : '/tmp/cockpit-role-$id.json';
          if (remote == null) {
            await File(responsePath).writeAsString('{}', flush: true);
          } else {
            await remote.write(responsePath, utf8.encode('{}'));
          }
          var agentPath = responsePath;
          try {
            if (remote == null) {
              if (terminal.profile.wslDistro case final distro?) {
                agentPath = await const LocalTerminalPathConverter().forWsl(
                  responsePath,
                  distro,
                );
              }
            }
          } catch (_) {
            if (remote == null) await File(responsePath).delete();
            rethrow;
          }
          return AgentRoleSuggestionChannel(
            path: agentPath,
            send: (prompt) async {
              if (!current()) throw AgentRoleSuggestionFailure.changed;
              if (terminal.status != TerminalStatus.idle) {
                throw StateError(tr.roleBusy);
              }
              terminal.insertText('$prompt\r');
            },
            read: () async {
              if (remote != null) {
                return utf8.decode(
                  await remote.read(responsePath, maxBytes: 4096),
                );
              }
              final file = await File(responsePath).open();
              try {
                final bytes = await file.read(4097);
                if (bytes.length > 4096) {
                  throw AgentRoleSuggestionFailure.invalid;
                }
                return utf8.decode(bytes, allowMalformed: true);
              } finally {
                await file.close();
              }
            },
            dispose: () async {
              if (remote == null) {
                await File(responsePath).delete();
              } else {
                await remote.write(responsePath, utf8.encode(''));
              }
            },
          );
        },
      );
      return current() ? Success(role) : Failure(tr.roleChanged);
    } on AgentRoleSuggestionFailure catch (e) {
      return Failure(switch (e) {
        AgentRoleSuggestionFailure.changed => tr.roleChanged,
        AgentRoleSuggestionFailure.timeout => tr.roleTimeout,
        AgentRoleSuggestionFailure.invalid => tr.roleInvalid,
      });
    } catch (e) {
      return Failure(e.toString());
    }
  }
}
