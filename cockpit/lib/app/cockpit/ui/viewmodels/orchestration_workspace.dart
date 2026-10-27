part of 'cockpit_viewmodel.dart';

extension OrchestrationWorkspace on CockpitViewModel {
  OrchestrationSession? orchestrationFor(String projectId) =>
      _orchestrations[projectId];

  String _orchestrationBoxCwd(String projectId, String boxId) {
    final directory =
        _orchestrations[projectId]?.controller.document?.boxes
            .where((b) => b.box.id == boxId)
            .firstOrNull
            ?.directory ??
        '.';
    final ctx = path.Context(
      style: _isRemoteWorkspace(projectId) ? path.Style.posix : path.style,
    );
    return ctx.normalize(ctx.join(projectRootOf(projectId) ?? '', directory));
  }

  List<OrchestrationTerminal> _orchestrationTerminals(String projectId) {
    final root = projectRootOf(projectId) ?? '';
    final ctx = path.Context(
      style: _isRemoteWorkspace(projectId) ? path.Style.posix : path.style,
    );
    return [
      for (final t in _sessions.values.whereType<TerminalSession>())
        if (t is! NeovimSession && t.projectId == projectId)
          OrchestrationTerminal(
            t.id,
            t.displayTitle,
            ctx.isWithin(root, t.workingDirectory)
                ? ctx
                      .relative(t.workingDirectory, from: root)
                      .replaceAll('\\', '/')
                : '.',
          ),
    ];
  }

  bool get hasLegacyOrchestration {
    if (_orchestrations.containsKey(_selectedProjectId)) return false;
    final saved = _savedLayouts[_selectedProjectId];
    return saved != null &&
        !saved.containsKey('orchestrationActive') &&
        (saved['graph'] is Map) &&
        ((saved['graph'] as Map)['boxes'] is List) &&
        ((saved['graph'] as Map)['boxes'] as List).isNotEmpty;
  }

  OrchestrationDocument _orchestrationSeed(
    String projectId, {
    bool importLegacy = true,
  }) {
    final live = {for (final t in _orchestrationTerminals(projectId)) t.id: t};
    final old = importLegacy
        ? (_graphBoxes[projectId] ?? const <GraphBox>[])
        : const <GraphBox>[];
    final rank = {
      for (final (i, id) in presentationFor(projectId).boxOrder.indexed) id: i,
    };
    final boxes = [
      for (final b in old)
        OrchestrationBox(box: b, directory: live[b.tabId]?.directory ?? '.'),
    ];
    boxes.sort(
      (a, b) => (rank[a.box.id] ?? rank.length).compareTo(
        rank[b.box.id] ?? rank.length,
      ),
    );
    final bound = old.map((b) => b.tabId).toSet();
    for (final t in live.values) {
      if (bound.contains(t.id)) continue;
      boxes.add(
        OrchestrationBox(
          box: GraphBox(
            id: newUid(),
            title: t.title,
            role: '',
            harness: '',
            model: '',
            tabId: t.id,
            position: OrchestrationController.autoPosition(boxes.length),
          ),
          directory: t.directory,
        ),
      );
    }
    return OrchestrationDocument(
      boxes: boxes,
      links: importLegacy ? (_graphLinks[projectId] ?? const []) : const [],
    );
  }

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

  OrchestrationSession _makeOrchestration(
    String projectId,
    String file, {
    String? id,
  }) {
    final docs = _orchestrationBindings.putIfAbsent(projectId, () => {});
    final bindings = docs.putIfAbsent(file, () => {});
    late OrchestrationSession session;
    final controller = OrchestrationController(
      read: () => _readOrchestrationFile(projectId, session.path),
      write: (text) => _writeOrchestrationFile(projectId, session.path, text),
      terminals: () => _orchestrationTerminals(projectId),
      newBoxId: newUid,
      bindings: bindings,
      createShell: (box) async {
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
        final created = newTerminalTab(
          cwd: cwd,
          title: box.box.title,
          graphBoxId: box.box.id,
          workspaceId: projectId,
          takeFocus: false,
        );
        if (created case Success(:final value)) return value;
        throw StateError((created as Failure<String, String>).error);
      },
      closeTerminal: (tabId) async =>
          _closeOrchestrationTerminal(projectId, tabId),
    );
    session = OrchestrationSession(
      id: id ?? _nid('orch'),
      projectId: projectId,
      path: file,
      controller: controller,
    );
    _orchestrations[projectId] = session;
    _sessions[session.id] = session;
    controller.addListener(() {
      if (_orchestrations[projectId] != session) return;
      final doc = controller.document;
      if (doc == null) {
        notifyListeners();
        return;
      }
      _publishingOrchestration.add(projectId);
      try {
        _graphBoxes[projectId] = controller.graphBoxes;
        _graphLinks[projectId] = [...doc.links];
        docs[session.path] = controller.bindings;
        for (final box in controller.graphBoxes) {
          final tab = _sessions[box.tabId];
          if (tab != null && tab.displayTitle != box.title) {
            tab.setManualLabel(box.title);
          }
        }
        final state = presentationFor(projectId);
        _presentations[projectId] = state.copyWith(
          boxOrder: doc.boxes.map((b) => b.box.id).toList(),
        );
        _scheduleSave(projectId);
        // Queue discrete session bindings before the window's flushAll.
        final layout = _serializeLayout(projectId);
        if (layout.isNotEmpty) unawaited(_layoutStore.save(projectId, layout));
        notifyListeners();
        if (_orchestrationTerminals(
          projectId,
        ).any((t) => !controller.bindings.containsValue(t.id))) {
          unawaited(controller.discover());
        }
      } finally {
        _publishingOrchestration.remove(projectId);
      }
    });
    _watchOrchestration(session);
    return session;
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
    final existing = _orchestrations[projectId];
    if (existing != null) {
      if (!filePaths.equals(existing.path, file)) {
        // Finish pending writes before changing the destination document.
        await existing.controller.settle();
        if (existing.controller.dirty) return;
        try {
          OrchestrationDocument.parse(
            await _readOrchestrationFile(projectId, file),
          );
        } catch (e) {
          existing.controller.reportError(e);
          return;
        }
        final oldBindings = existing.controller.bindings;
        _orchestrationBindings[projectId]![existing.path] = {...oldBindings};
        existing.path = file;
        existing.controller.switchDocument(
          _orchestrationBindings[projectId]![file] ?? {},
        );
        _watchOrchestration(existing);
      }
      var pane = leafOfTab(projectId, existing.id);
      if (pane == null) {
        _initTree(projectId);
        pane = _focused[projectId] ?? leaves(_trees[projectId]!).first.id;
        _sessions[existing.id] = existing;
        _addLeafTab(projectId, pane, existing.id);
      }
      _trees[projectId] = updateLeaf(
        _trees[projectId]!,
        pane,
        (p) => p.copyWith(active: existing.id),
      );
      _focused[projectId] = pane;
      await existing.controller.load();
      notifyListeners();
      return;
    }
    _initTree(projectId);
    final session = _makeOrchestration(projectId, file);
    final leaf = _focused[projectId] ?? leaves(_trees[projectId]!).first.id;
    _addLeafTab(projectId, leaf, session.id);
    _presentations[projectId] = presentationFor(
      projectId,
    ).copyWith(mode: OrchestrationViewMode.boxes);
    // Preserve bindings from #269 for a newly seeded document.
    final binding = session.controller.bindings;
    binding.addAll(initialBindings);
    for (final box in _graphBoxes[projectId] ?? const <GraphBox>[]) {
      if (_sessions[box.tabId]?.projectId == projectId) {
        binding[box.id] = box.tabId!;
      }
    }
    await session.controller.load();
    _scheduleSave(projectId);
    notifyListeners();
  }

  void _watchOrchestration(OrchestrationSession session) {
    _fileWatchers.remove(session.id)?.cancel();
    if (_isRemoteWorkspace(session.projectId)) return;
    _fileWatchers[session.id] = _fileChanges.watchFile(session.path).listen((
      _,
    ) {
      if (_orchestrations[session.projectId] == session) {
        unawaited(session.controller.load());
      }
    });
  }

  void _syncOrchestrationDocument(String projectId) {
    final session = _orchestrations[projectId];
    if (session == null ||
        session.controller.busy ||
        _publishingOrchestration.contains(projectId)) {
      return;
    }
    final controller = session.controller;
    final doc = controller.document;
    if (doc == null || controller.error != null) return;
    final old = {for (final b in doc.boxes) b.box.id: b};
    final live = {for (final t in _orchestrationTerminals(projectId)) t.id: t};
    final state = presentationFor(projectId);
    final rank = {for (final (i, id) in state.boxOrder.indexed) id: i};
    final boxes = [
      for (final b in _graphBoxes[projectId] ?? const <GraphBox>[])
        if (!controller.pendingRemovals.containsKey(b.id))
          OrchestrationBox(
            box: b,
            directory: old[b.id]?.directory ?? live[b.tabId]?.directory ?? '.',
          ),
    ];
    boxes.sort(
      (a, b) => (rank[a.box.id] ?? rank.length).compareTo(
        rank[b.box.id] ?? rank.length,
      ),
    );
    final ids = boxes.map((b) => b.box.id).toSet();
    final links = (_graphLinks[projectId] ?? const <GraphLink>[])
        .where((l) => ids.contains(l.from) && ids.contains(l.to))
        .toList();
    for (final b in boxes) {
      if (live.containsKey(b.box.tabId)) {
        controller.bindings[b.box.id] = b.box.tabId!;
      }
    }
    final next = OrchestrationDocument(
      boxes: boxes,
      links: links,
      extra: doc.extra,
    );
    if (next.encode() != doc.encode()) {
      unawaited(controller.update(boxes, links));
    }
  }

  void _closeOrchestrationTerminal(String projectId, String tabId) {
    final pane = leafOfTab(projectId, tabId);
    if (pane != null) {
      _closeTabIn(projectId, pane, tabId, disposeAfterFrame: true);
    }
  }

  Future<Result<String, String>> configureOrchestrationBox(
    String projectId,
    String boxId, {
    required String title,
    required String role,
    required String harness,
    required String model,
    required String directory,
  }) async {
    final controller = _orchestrations[projectId]?.controller;
    final doc = controller?.document;
    if (controller == null || doc == null) {
      return const Failure('Document unavailable');
    }
    if (title.trim().isEmpty) return const Failure('Title is required');
    if (harness.isNotEmpty &&
        !const {'claude', 'codex', 'pi'}.contains(harness)) {
      return const Failure('Unsupported tool');
    }
    if (model.isNotEmpty && !RegExp(r'^[a-zA-Z0-9._:/-]+$').hasMatch(model)) {
      return const Failure('Invalid model');
    }
    final next = OrchestrationDocument(
      boxes: [
        for (final b in doc.boxes)
          b.box.id == boxId
              ? OrchestrationBox(
                  box: b.box.copyWith(
                    title: title.trim(),
                    role: role.trim(),
                    harness: harness,
                    model: model.trim(),
                  ),
                  directory: directory.trim(),
                )
              : b,
      ],
      links: doc.links,
      extra: doc.extra,
    );
    try {
      OrchestrationDocument.parse(next.encode());
    } on FormatException catch (e) {
      return Failure(e.message);
    }
    await controller.update(next.boxes, next.links);
    return controller.error == null
        ? Success(boxId)
        : Failure(controller.error!);
  }
}

final _agentRoleSuggestions = AgentRoleSuggestionService();

extension OrchestrationRoleSuggestions on CockpitViewModel {
  Future<Result<String, String>> suggestOrchestrationRole(
    String projectId,
    String boxId,
  ) async {
    final tr = slang.t.orchestration;
    final doc = _orchestrations[projectId];
    final terminal = _sessions[doc?.controller.bindings[boxId]];
    if (doc == null ||
        terminal is! TerminalSession ||
        terminal.hasExited ||
        terminal.activeHarness == null) {
      return Failure(tr.roleNoAgent);
    }
    if (terminal.status != TerminalStatus.idle) return Failure(tr.roleBusy);
    final documentPath = doc.path;
    final cli = terminal.activeHarness;
    final conversation = terminal.claudeSessionId;
    bool current() =>
        _orchestrations[projectId] == doc &&
        doc.path == documentPath &&
        doc.controller.bindings[boxId] == terminal.id &&
        _sessions[terminal.id] == terminal &&
        !terminal.hasExited &&
        terminal.activeHarness == cli &&
        (conversation == null || terminal.claudeSessionId == conversation);
    try {
      final role = await _agentRoleSuggestions.request(
        key: '${identityHashCode(this)}|$projectId|$documentPath|$boxId',
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
