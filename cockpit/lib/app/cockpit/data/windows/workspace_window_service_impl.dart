import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_window_service.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:path/path.dart' as p;

/// Starts the detached window process and returns its pid, or `null` when the
/// OS does not report it (macOS via LaunchServices): the window then records
/// its own pid on boot (see [WorkspaceWindowServiceImpl.start]).
typedef WorkspaceWindowLauncher =
    Future<int?> Function(String isolatedRoot, String workspaceId);

/// Brings to the front the window whose isolated root is [home] (process
/// [pid], when known).
typedef WorkspaceWindowFocuser = Future<bool> Function(String home, int? pid);

/// [WorkspaceWindowService] backed by OS processes.
///
/// On-disk layout per detached window (the isolated root is short on purpose:
/// the window's Unix socket lives inside it, and macOS caps socket paths at
/// ~104 bytes, so `Application Support/...` would overflow):
///
/// ```
/// ~/.cockpit/windows[-debug]/<hash>/   ← the window's COCKPIT_ISOLATED_ROOT
///   window.json                        ← {workspaceId, pid, at}
///   cockpit[-debug]/state/*.json       ← state seeded from the main window
///   terminal_scrollback/<workspace>/   ← seeded scrollback
///   .cockpit/                          ← the window's sockets/CLI/sidecar
/// ```
class WorkspaceWindowServiceImpl implements WorkspaceWindowService {
  WorkspaceWindowServiceImpl({
    required this._layoutStore,
    required this._focuser,
    String? hostedWorkspaceId,
    String? windowsDir,
    Future<String> Function()? stateDir,
    Future<String> Function()? scrollbackDir,
    WorkspaceWindowLauncher? launcher,
    Future<bool> Function(int pid)? isAlive,
    Future<void> Function()? flushState,
    bool? supported,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 2),
    this.launchGrace = const Duration(seconds: 90),
  }) : _now = clock ?? DateTime.now,
       hostedWorkspaceId = hostedWorkspaceId ?? cockpitWorkspaceWindowId(),
       _windowsDirOverride = windowsDir,
       _stateDir = stateDir ?? StorageLocation.stateDir,
       _scrollbackDir = scrollbackDir ?? StorageLocation.scrollbackDir,
       _launch = launcher ?? _launchProcess,
       _isAlive = isAlive ?? isCockpitProcessAlive,
       _flushState = flushState ?? JsonStateStore.flushAll,
       isSupported =
           supported ??
           (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  final WorkspaceLayoutStore _layoutStore;
  final WorkspaceWindowFocuser _focuser;
  final String? _windowsDirOverride;
  final Future<String> Function() _stateDir;
  final Future<String> Function() _scrollbackDir;
  final WorkspaceWindowLauncher _launch;
  final Future<bool> Function(int pid) _isAlive;
  final Future<void> Function() _flushState;
  final DateTime Function() _now;
  final Duration pollInterval;

  /// How long a freshly launched window may take to record its own pid before
  /// the launch is considered failed (cold app boot + sidecar).
  final Duration launchGrace;

  @override
  final String? hostedWorkspaceId;

  @override
  final bool isSupported;

  /// Control file at the root of each window.
  static const String controlFile = 'window.json';

  /// workspaceId → isolated root of the window hosting it.
  final Map<String, String> _open = {};
  final StreamController<String> _closed = StreamController.broadcast();
  Timer? _poll;
  bool _polling = false;
  bool _disposed = false;

  @override
  Set<String> get openWorkspaceIds => Set.unmodifiable(_open.keys);

  @override
  Stream<String> get closed => _closed.stream;

  String? get _windowsDir {
    final override = _windowsDirOverride;
    if (override != null) return override;
    final home = cockpitRuntimeHome();
    if (home == null) return null;
    return p.join(home, '.cockpit', 'windows${kDebugMode ? '-debug' : ''}');
  }

  /// Isolated root key for [workspaceId]: a short, stable hash (an id may be
  /// `rootId::path`, which is not a valid folder name).
  static String rootKey(String workspaceId) =>
      sha1.convert(utf8.encode(workspaceId)).toString().substring(0, 12);

  @override
  Future<void> start() async {
    if (!isSupported) return;
    final hosted = hostedWorkspaceId;
    if (hosted != null) {
      // Detached window: record OUR pid. The pid the main window noted at
      // spawn time may belong to an intermediate launcher.
      final root = cockpitIsolatedRoot();
      if (root != null) await _writeControl(root, hosted, pid, _now());
      return;
    }
    final base = _windowsDir;
    if (base == null) return;
    final dir = Directory(base);
    if (await dir.exists()) {
      await for (final entry in dir.list()) {
        if (entry is! Directory) continue;
        final control = await _readControl(entry.path);
        if (control == null) {
          await _deleteQuietly(entry.path);
          continue;
        }
        final workspaceId = control.workspaceId;
        if (await _windowAlive(control)) {
          _open[workspaceId] = entry.path;
        } else {
          await _reclaim(workspaceId, entry.path);
        }
      }
    }
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_polling || _disposed || _open.isEmpty) return;
    _polling = true;
    try {
      for (final entry in Map.of(_open).entries) {
        final control = await _readControl(entry.value);
        // Unreadable right now (on Windows, a rename in flight): retry on the
        // next tick instead of deleting the root of a window that may be alive.
        if (control == null || await _windowAlive(control)) continue;
        await _reclaim(entry.key, entry.value);
        _open.remove(entry.key);
        if (!_disposed) _closed.add(entry.key);
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<Result<void, WorkspaceWindowError>> open(
    String workspaceId, {
    WindowBounds? near,
  }) async {
    if (!isSupported || hostedWorkspaceId != null) {
      return const Failure(
        WorkspaceWindowError(WorkspaceWindowErrorKind.unsupported),
      );
    }
    if (_open.containsKey(workspaceId)) {
      await focus(workspaceId);
      return const Success(null);
    }
    final base = _windowsDir;
    if (base == null) {
      return const Failure(
        WorkspaceWindowError(WorkspaceWindowErrorKind.seedFailed),
      );
    }
    final root = p.join(base, rootKey(workspaceId));
    try {
      // The main window just saved the workspace layout; the seed reads the
      // files from disk, so nothing may be left in the debounce window.
      await _flushState();
      await _deleteQuietly(root);
      await seedWorkspaceWindowState(
        mainStateDir: await _stateDir(),
        windowStateDir: windowStateDir(root),
        workspaceId: workspaceId,
        near: near,
      );
      await copyWorkspaceScrollback(
        from: await _scrollbackDir(),
        to: p.join(root, 'terminal_scrollback'),
        workspaceId: workspaceId,
      );
      await _writeControl(root, workspaceId, null, _now());
    } on FileSystemException catch (e) {
      await _deleteQuietly(root);
      return Failure(
        WorkspaceWindowError(
          WorkspaceWindowErrorKind.seedFailed,
          detail: e.osError?.message ?? e.message,
        ),
      );
    }
    try {
      final windowPid = await _launch(root, workspaceId);
      // Without a pid (LaunchServices) the file keeps `pid: null` until the
      // window records its own; the grace period in [_windowAlive] covers it.
      if (windowPid != null) {
        final current = await _readControl(root);
        // The window may already be up and have recorded its own pid.
        if (current?.pid == null) {
          await _writeControl(root, workspaceId, windowPid, _now());
        }
      }
    } on ProcessException catch (e) {
      await _deleteQuietly(root);
      return Failure(
        WorkspaceWindowError(
          WorkspaceWindowErrorKind.launchFailed,
          detail: e.message,
        ),
      );
    }
    _open[workspaceId] = root;
    return const Success(null);
  }

  @override
  Future<bool> focus(String workspaceId) async {
    final root = _open[workspaceId];
    if (root == null) return false;
    final control = await _readControl(root);
    return _focuser(root, control?.pid);
  }

  /// Alive = known pid that is still running; or, with no pid yet, launched
  /// recently.
  Future<bool> _windowAlive(_Control control) async {
    final windowPid = control.pid;
    if (windowPid != null) return _isAlive(windowPid);
    final at = control.updatedAt;
    return at != null && _now().difference(at) < launchGrace;
  }

  /// Hands what the detached window saved back to the main window: layouts of
  /// the workspace and its worktrees, plus scrollback. Then deletes the root.
  Future<void> _reclaim(String workspaceId, String root) async {
    try {
      final layouts = await readJsonStateData(
        File(p.join(windowStateDir(root), 'layouts.json')),
      );
      for (final MapEntry(:key, :value) in layouts.entries) {
        if (!belongsToWorkspace(key, workspaceId) || value is! String) {
          continue;
        }
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          await _layoutStore.save(key, decoded.cast<String, dynamic>());
        }
      }
      await copyWorkspaceScrollback(
        from: p.join(root, 'terminal_scrollback'),
        to: await _scrollbackDir(),
        workspaceId: workspaceId,
      );
    } on Object catch (e) {
      // Best effort: whatever fails keeps the version the main window already
      // had. It must never break the boot or the poll.
      debugPrint('[workspace-window] reclaim $workspaceId failed: $e');
    }
    await _deleteQuietly(root);
  }

  Future<_Control?> _readControl(String root) async {
    try {
      final raw = await File(p.join(root, controlFile)).readAsString();
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final id = json['workspaceId'];
      if (id is! String || id.isEmpty) return null;
      final windowPid = json['pid'];
      final at = json['at'];
      return _Control(
        id,
        windowPid is int ? windowPid : null,
        at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      );
    } on Object {
      return null;
    }
  }

  static Future<void> _writeControl(
    String root,
    String workspaceId,
    int? windowPid,
    DateTime at,
  ) async {
    await JsonStateStore.writeAtomic(
      File(p.join(root, controlFile)),
      jsonEncode({
        'workspaceId': workspaceId,
        'pid': windowPid,
        'at': at.millisecondsSinceEpoch,
      }),
    );
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Locked file (antivirus, Windows): left for the next cleanup.
    }
  }

  static Future<int?> _launchProcess(String root, String workspaceId) async {
    final env = {
      'COCKPIT_ISOLATED_ROOT': root,
      cockpitWorkspaceWindowEnv: workspaceId,
    };
    // macOS: go through LaunchServices (`open -n`), like opening a new app
    // instance. Exec'ing the bundle binary directly also works, but outside
    // LaunchServices the new window may appear BEHIND the main one (macOS 14+
    // cooperative activation). If `open` refuses (no `--env` support), fall
    // back to a direct exec.
    if (Platform.isMacOS) {
      final bundle = macAppBundleOf(Platform.resolvedExecutable);
      if (bundle != null) {
        final r = await Process.run('/usr/bin/open', [
          '-n',
          '-a',
          bundle,
          for (final MapEntry(:key, :value) in env.entries) ...[
            '--env',
            '$key=$value',
          ],
        ]);
        if (r.exitCode == 0) return null;
      }
    }
    final process = await Process.start(
      Platform.resolvedExecutable,
      const [],
      environment: env,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _poll?.cancel();
    await _closed.close();
  }
}

class _Control {
  const _Control(this.workspaceId, this.pid, this.updatedAt);
  final String workspaceId;
  final int? pid;
  final DateTime? updatedAt;
}

/// `/Applications/Cockpit.app` from `.../Cockpit.app/Contents/MacOS/x`; `null`
/// outside an app bundle.
String? macAppBundleOf(String executable) {
  final macos = p.dirname(executable);
  final contents = p.dirname(macos);
  final bundle = p.dirname(contents);
  if (p.basename(macos) != 'MacOS' ||
      p.basename(contents) != 'Contents' ||
      !bundle.endsWith('.app')) {
    return null;
  }
  return bundle;
}

/// JSON state folder inside a window's isolated root — the same path that
/// process's `StorageLocation.stateDir()` resolves to.
String windowStateDir(String isolatedRoot) =>
    p.join(isolatedRoot, storageSubdir, 'state');

/// Whether a layout/project key belongs to the workspace: the root itself or
/// one of its worktrees (`<rootId>::<path>`).
bool belongsToWorkspace(String key, String workspaceId) =>
    key == workspaceId || key.startsWith('$workspaceId::');

/// The `data` of a `JsonStateStore` file; empty when missing or unreadable.
Future<Map<String, dynamic>> readJsonStateData(File file) async {
  if (!await file.exists()) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map && decoded['data'] is Map) {
      return (decoded['data'] as Map).cast<String, dynamic>();
    }
  } on FormatException {
    // corrupted → empty
  }
  return <String, dynamic>{};
}

/// Initial state of the detached window, derived from the main window's state.
///
/// Copies every store (settings, connections, remote hosts…) so the window has
/// the same preferences, but trims the three that define what it shows: only
/// the hosted workspace (and its realm) and only its layouts and its
/// worktrees'. The main window's position/size is not copied verbatim (the new
/// window would open exactly on top of it): with [near], it cascades from the
/// source window.
Future<void> seedWorkspaceWindowState({
  required String mainStateDir,
  required String windowStateDir,
  required String workspaceId,
  WindowBounds? near,
}) async {
  final target = Directory(windowStateDir);
  await target.create(recursive: true);
  final source = Directory(mainStateDir);
  if (await source.exists()) {
    await for (final entry in source.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final name = p.basename(entry.path);
      if (name == 'window_state.json') continue;
      await entry.copy(p.join(windowStateDir, name));
    }
  }

  Future<Map<String, dynamic>> read(String name) =>
      readJsonStateData(File(p.join(mainStateDir, '$name.json')));
  Future<void> write(String name, Map<String, dynamic> data) =>
      JsonStateStore.writeAtomic(
        File(p.join(windowStateDir, '$name.json')),
        jsonEncode({'version': 1, 'data': data}),
      );

  final seed = filterWorkspaceWindowState(
    projects: await read('projects'),
    realms: await read('realms'),
    layouts: await read('layouts'),
    workspaceId: workspaceId,
  );
  await write('projects', seed.projects);
  await write('realms', seed.realms);
  await write('layouts', seed.layouts);
  if (near != null) await write('window_state', cascadeFrom(near));
}

/// Cascade offset between the source window and the new one.
const double windowCascadeOffset = 32;

/// `window_state` of the new window: offset from [near] and never maximized
/// (the boot refits it into the work area if the offset pushes it off-screen).
Map<String, dynamic> cascadeFrom(WindowBounds near) => {
  'x': near.x + windowCascadeOffset,
  'y': near.y + windowCascadeOffset,
  'width': near.width,
  'height': near.height,
  'maximized': false,
};

/// Pure state trim for [workspaceId]'s window (see
/// [seedWorkspaceWindowState]).
({
  Map<String, dynamic> projects,
  Map<String, dynamic> realms,
  Map<String, dynamic> layouts,
})
filterWorkspaceWindowState({
  required Map<String, dynamic> projects,
  required Map<String, dynamic> realms,
  required Map<String, dynamic> layouts,
  required String workspaceId,
}) {
  final project = projects[workspaceId];
  final outProjects = <String, dynamic>{};
  final outRealms = <String, dynamic>{};
  if (project is Map) {
    outProjects[workspaceId] = project;
    final realmId = project['realm'];
    if (realmId is String) {
      final realm = realms[realmId];
      if (realm is Map) outRealms[realmId] = realm;
      outRealms['__active__'] = realmId;
      // Same key as JsonProjectRepository: the window opens straight on it.
      outProjects['__last_selected__::$realmId'] = workspaceId;
    }
  }
  return (
    projects: outProjects,
    realms: outRealms,
    layouts: {
      for (final MapEntry(:key, :value) in layouts.entries)
        if (belongsToWorkspace(key, workspaceId)) key: value,
    },
  );
}

/// Copies the scrollback folders of the workspace (and its worktrees) between
/// two caches. Folders use the escaped id of `FileTerminalScrollbackStore`.
Future<void> copyWorkspaceScrollback({
  required String from,
  required String to,
  required String workspaceId,
}) async {
  final source = Directory(from);
  if (!await source.exists()) return;
  final root = scrollbackDirName(workspaceId);
  final forkPrefix = scrollbackDirName('$workspaceId::');
  await for (final entry in source.list()) {
    if (entry is! Directory) continue;
    final name = p.basename(entry.path);
    if (name != root && !name.startsWith(forkPrefix)) continue;
    await _copyDir(entry, Directory(p.join(to, name)));
  }
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list()) {
    final target = p.join(to.path, p.basename(entry.path));
    if (entry is File) {
      await entry.copy(target);
    } else if (entry is Directory) {
      await _copyDir(entry, Directory(target));
    }
  }
}

/// Same folder-name escaping as `FileTerminalScrollbackStore`: anything
/// outside `[A-Za-z0-9._-]` becomes `%XX`.
String scrollbackDirName(String id) {
  final buf = StringBuffer();
  for (final unit in id.codeUnits) {
    final ok =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5a) ||
        (unit >= 0x61 && unit <= 0x7a) ||
        unit == 0x2e ||
        unit == 0x5f ||
        unit == 0x2d;
    if (ok) {
      buf.writeCharCode(unit);
    } else {
      buf.write('%${unit.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
  }
  return buf.toString();
}

/// Is process [pid] still a running Cockpit? Checks the executable name along
/// with the pid, so a pid recycled by another program does not keep the
/// workspace locked.
Future<bool> isCockpitProcessAlive(int pid) async {
  final exe = p.basenameWithoutExtension(Platform.resolvedExecutable);
  try {
    if (Platform.isLinux) {
      final comm = File('/proc/$pid/comm');
      if (!await comm.exists()) return false;
      // `comm` is truncated to 15 bytes.
      final name = (await comm.readAsString()).trim();
      return exe.startsWith(name) || name.startsWith(exe);
    }
    if (Platform.isWindows) {
      final r = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      return (r.stdout as String).toLowerCase().contains(
        '"${exe.toLowerCase()}.exe"',
      );
    }
    final r = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
    final out = (r.stdout as String).trim();
    return out.isNotEmpty && p.basename(out) == exe;
  } on Object {
    // Cannot tell: treating it as dead would delete the root of a window that
    // may be alive (and its work). Keeping the workspace locked is the lesser
    // evil.
    return true;
  }
}
