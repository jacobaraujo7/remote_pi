import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/terminal/file_terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/data/windows/workspace_window_service_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_window_service.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MemoryLayouts implements WorkspaceLayoutStore {
  final Map<String, Map<String, dynamic>> docs = {};

  @override
  Future<Map<String, dynamic>?> load(String projectId) async => docs[projectId];

  @override
  Future<Map<String, Map<String, dynamic>>> loadAll() async => Map.of(docs);

  @override
  Future<void> remove(String projectId) async => docs.remove(projectId);

  @override
  Future<void> save(String projectId, Map<String, dynamic> document) async =>
      docs[projectId] = document;
}

const _ws = 'ws-1';
const _other = 'ws-2';
const _fork = 'ws-1::/repo/feature';

Future<void> _writeStore(String dir, String name, Map<String, dynamic> data) =>
    File(p.join(dir, '$name.json'))
        .create(recursive: true)
        .then((f) => f.writeAsString(jsonEncode({'version': 1, 'data': data})));

Future<Map<String, dynamic>> _readStore(String dir, String name) =>
    readJsonStateData(File(p.join(dir, '$name.json')));

void main() {
  late Directory tmp;
  late String mainState;
  late String mainScrollback;
  late String windowsDir;
  late _MemoryLayouts layouts;
  late List<(String, String)> launched;
  late Map<int, bool> alive;
  late DateTime now;
  late List<(String, int?)> focused;

  WorkspaceWindowServiceImpl service({
    String? hosted,
  }) => WorkspaceWindowServiceImpl(
    layoutStore: layouts,
    focuser: (home, pid) async {
      focused.add((home, pid));
      return true;
    },
    hostedWorkspaceId: hosted,
    windowsDir: windowsDir,
    stateDir: () async => mainState,
    scrollbackDir: () async => mainScrollback,
    launcher: (root, id) async {
      launched.add((root, id));
      return 4242;
    },
    isAlive: (pid) async => alive[pid] ?? false,
    flushState: () async {},
    supported: true,
    clock: () => now,
    // Tests drive reconciliation through start(); keep the timer out of the way.
    pollInterval: const Duration(hours: 1),
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('workspace-window-test');
    mainState = p.join(tmp.path, 'main', 'state');
    mainScrollback = p.join(tmp.path, 'main', 'scrollback');
    windowsDir = p.join(tmp.path, 'windows');
    layouts = _MemoryLayouts();
    launched = [];
    alive = {};
    now = DateTime(2026, 11, 26, 12);
    focused = [];

    await _writeStore(mainState, 'projects', {
      _ws: {'id': _ws, 'name': 'one', 'path': '/repo', 'realm': 'r1'},
      _other: {'id': _other, 'name': 'two', 'path': '/two', 'realm': 'r2'},
      '__last_selected__::r2': _other,
    });
    await _writeStore(mainState, 'realms', {
      'r1': {'id': 'r1', 'name': 'Work'},
      'r2': {'id': 'r2', 'name': 'Home'},
      '__active__': 'r2',
    });
    await _writeStore(mainState, 'layouts', {
      _ws: jsonEncode({'v': 'root'}),
      _fork: jsonEncode({'v': 'fork'}),
      _other: jsonEncode({'v': 'other'}),
    });
    await _writeStore(mainState, 'settings', {'theme': 'dark'});
    await _writeStore(mainState, 'window_state', {'x': 10});
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('filterWorkspaceWindowState', () {
    test('keeps only the hosted workspace, its realm and its layouts', () {
      final seed = filterWorkspaceWindowState(
        projects: {
          _ws: {'id': _ws, 'realm': 'r1'},
          _other: {'id': _other, 'realm': 'r2'},
          '__last_selected__::r2': _other,
        },
        realms: {
          'r1': {'id': 'r1'},
          'r2': {'id': 'r2'},
          '__active__': 'r2',
        },
        layouts: {_ws: 'a', _fork: 'b', _other: 'c', 'ws-10': 'd'},
        workspaceId: _ws,
      );
      expect(
        seed.projects.keys,
        unorderedEquals([_ws, '__last_selected__::r1']),
      );
      expect(seed.projects['__last_selected__::r1'], _ws);
      expect(seed.realms, {
        'r1': {'id': 'r1'},
        '__active__': 'r1',
      });
      // `ws-10` shares the textual prefix but is not a worktree of `ws-1`.
      expect(seed.layouts, {_ws: 'a', _fork: 'b'});
    });
  });

  test('scrollback folder names match the scrollback store escaping', () async {
    final store = FileTerminalScrollbackStore(root: Directory(mainScrollback));
    await store.save(projectId: _fork, sessionId: 't1', contents: 'fork');
    await store.save(projectId: _ws, sessionId: 't2', contents: 'root');
    await store.save(projectId: _other, sessionId: 't3', contents: 'other');
    final copy = p.join(tmp.path, 'copy');

    await copyWorkspaceScrollback(
      from: mainScrollback,
      to: copy,
      workspaceId: _ws,
    );

    final copied = FileTerminalScrollbackStore(root: Directory(copy));
    expect(await copied.load(projectId: _ws, sessionId: 't2'), 'root');
    expect(await copied.load(projectId: _fork, sessionId: 't1'), 'fork');
    expect(await copied.load(projectId: _other, sessionId: 't3'), isNull);
  });

  test('open seeds an isolated state and launches the window', () async {
    final svc = service();
    await FileTerminalScrollbackStore(
      root: Directory(mainScrollback),
    ).save(projectId: _ws, sessionId: 't1', contents: 'history');

    final result = await svc.open(_ws);

    expect(result, isA<Success<void, WorkspaceWindowError>>());
    expect(svc.openWorkspaceIds, {_ws});
    final root = p.join(windowsDir, WorkspaceWindowServiceImpl.rootKey(_ws));
    expect(launched, [(root, _ws)]);
    final state = windowStateDir(root);
    expect((await _readStore(state, 'projects')).keys, contains(_ws));
    expect((await _readStore(state, 'projects')).keys, isNot(contains(_other)));
    expect(
      (await _readStore(state, 'layouts')).keys,
      unorderedEquals([_ws, _fork]),
    );
    expect(await _readStore(state, 'settings'), {'theme': 'dark'});
    expect(File(p.join(state, 'window_state.json')).existsSync(), isFalse);
    expect(
      await FileTerminalScrollbackStore(
        root: Directory(p.join(root, 'terminal_scrollback')),
      ).load(projectId: _ws, sessionId: 't1'),
      'history',
    );
    final control = jsonDecode(
      File(
        p.join(root, WorkspaceWindowServiceImpl.controlFile),
      ).readAsStringSync(),
    );
    expect(control['workspaceId'], _ws);
    expect(control['pid'], 4242);
    await svc.dispose();
  });

  test('the new window cascades from the source window', () async {
    final svc = service();
    await svc.open(_ws, near: (x: 100, y: 50, width: 1200, height: 800));
    final root = p.join(windowsDir, WorkspaceWindowServiceImpl.rootKey(_ws));
    expect(await _readStore(windowStateDir(root), 'window_state'), {
      'x': 132,
      'y': 82,
      'width': 1200,
      'height': 800,
      'maximized': false,
    });
    await svc.dispose();
  });

  test('a window that already exists is focused, not launched again', () async {
    final svc = service();
    alive[4242] = true;
    await svc.open(_ws);
    await svc.open(_ws);
    expect(launched, hasLength(1));
    expect(focused.single.$2, 4242);
    await svc.dispose();
  });

  test('hosted window refuses to open other windows', () async {
    final svc = service(hosted: _ws);
    final result = await svc.open(_other);
    expect(
      result,
      isA<Failure<void, WorkspaceWindowError>>().having(
        (f) => f.error.kind,
        'kind',
        WorkspaceWindowErrorKind.unsupported,
      ),
    );
    expect(launched, isEmpty);
  });

  test('launch failure leaves nothing behind', () async {
    final svc = WorkspaceWindowServiceImpl(
      layoutStore: layouts,
      focuser: (_, _) async => true,
      hostedWorkspaceId: null,
      windowsDir: windowsDir,
      stateDir: () async => mainState,
      scrollbackDir: () async => mainScrollback,
      launcher: (_, _) async => throw const ProcessException('cockpit', []),
      isAlive: (_) async => false,
      flushState: () async {},
      supported: true,
    );
    final result = await svc.open(_ws);
    expect(
      result,
      isA<Failure<void, WorkspaceWindowError>>().having(
        (f) => f.error.kind,
        'kind',
        WorkspaceWindowErrorKind.launchFailed,
      ),
    );
    expect(svc.openWorkspaceIds, isEmpty);
    expect(Directory(windowsDir).listSync(), isEmpty);
  });

  group('boot reconciliation', () {
    late String root;

    Future<void> openThenRestart() async {
      final first = service();
      await first.open(_ws);
      await first.dispose();
      root = p.join(windowsDir, WorkspaceWindowServiceImpl.rootKey(_ws));
      // What the detached window saved while it was alive.
      await _writeStore(windowStateDir(root), 'layouts', {
        _ws: jsonEncode({'v': 'root-from-window'}),
        _fork: jsonEncode({'v': 'fork-from-window'}),
        'stranger': jsonEncode({'v': 'not ours'}),
      });
      await FileTerminalScrollbackStore(
        root: Directory(p.join(root, 'terminal_scrollback')),
      ).save(projectId: _ws, sessionId: 'new', contents: 'from window');
    }

    test('a live window keeps its workspace', () async {
      await openThenRestart();
      alive[4242] = true;
      final svc = service();
      await svc.start();
      expect(svc.openWorkspaceIds, {_ws});
      expect(layouts.docs, isEmpty);
      expect(Directory(root).existsSync(), isTrue);
      await svc.dispose();
    });

    test('a closed window gives its layouts and history back', () async {
      await openThenRestart();
      final svc = service();
      await svc.start();
      expect(svc.openWorkspaceIds, isEmpty);
      expect(layouts.docs, {
        _ws: {'v': 'root-from-window'},
        _fork: {'v': 'fork-from-window'},
      });
      expect(
        await FileTerminalScrollbackStore(
          root: Directory(mainScrollback),
        ).load(projectId: _ws, sessionId: 'new'),
        'from window',
      );
      expect(Directory(root).existsSync(), isFalse);
      await svc.dispose();
    });

    test('a window without a pid yet survives the launch grace', () async {
      final first = WorkspaceWindowServiceImpl(
        layoutStore: layouts,
        focuser: (_, _) async => true,
        hostedWorkspaceId: null,
        windowsDir: windowsDir,
        stateDir: () async => mainState,
        scrollbackDir: () async => mainScrollback,
        // LaunchServices (macOS): no pid.
        launcher: (_, _) async => null,
        isAlive: (_) async => false,
        flushState: () async {},
        supported: true,
        clock: () => now,
      );
      await first.open(_ws);
      await first.dispose();

      now = now.add(const Duration(seconds: 30));
      final early = service();
      await early.start();
      expect(early.openWorkspaceIds, {_ws});
      await early.dispose();

      now = now.add(const Duration(minutes: 5));
      final late = service();
      await late.start();
      expect(late.openWorkspaceIds, isEmpty);
      await late.dispose();
    });
  });

  test('closing a live window emits closed after the layout is back', () async {
    final svc = WorkspaceWindowServiceImpl(
      layoutStore: layouts,
      focuser: (_, _) async => true,
      hostedWorkspaceId: null,
      windowsDir: windowsDir,
      stateDir: () async => mainState,
      scrollbackDir: () async => mainScrollback,
      launcher: (_, _) async => 4242,
      isAlive: (pid) async => alive[pid] ?? false,
      flushState: () async {},
      supported: true,
      pollInterval: const Duration(milliseconds: 20),
    );
    alive[4242] = true;
    await svc.start();
    await svc.open(_ws);
    final root = p.join(windowsDir, WorkspaceWindowServiceImpl.rootKey(_ws));
    await _writeStore(windowStateDir(root), 'layouts', {
      _ws: jsonEncode({'v': 'edited'}),
    });

    final closed = svc.closed.first;
    alive[4242] = false; // the user closed the detached window
    expect(await closed.timeout(const Duration(seconds: 5)), _ws);
    expect(layouts.docs[_ws], {'v': 'edited'});
    expect(svc.openWorkspaceIds, isEmpty);
    expect(Directory(root).existsSync(), isFalse);
    await svc.dispose();
  });

  group('cockpitWorkspaceWindowId', () {
    test('needs an isolated root to be honoured', () {
      expect(
        cockpitWorkspaceWindowId(environment: {cockpitWorkspaceWindowEnv: _ws}),
        isNull,
      );
      expect(
        cockpitWorkspaceWindowId(
          environment: {
            cockpitWorkspaceWindowEnv: _ws,
            'COCKPIT_ISOLATED_ROOT': p.join(tmp.path, 'iso'),
          },
        ),
        _ws,
      );
    });
  });

  test('macAppBundleOf finds the .app around the executable', () {
    expect(
      macAppBundleOf('/Applications/Cockpit.app/Contents/MacOS/Cockpit'),
      '/Applications/Cockpit.app',
    );
    expect(macAppBundleOf('/opt/cockpit/cockpit'), isNull);
  });
}
