import 'package:cockpit/app/cockpit/data/tasks/tools/dev_tool_registry.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/cockpit/domain/contracts/device_selection_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_device_snapshot.dart';

/// Catálogo de devices e escolha efetiva por task. Não conhece Flutter: pergunta
/// ao [DevToolRegistry]. A UI e o `run-task` da CLI consomem só esta classe.
class TaskDeviceCoordinator {
  TaskDeviceCoordinator(this._tools, this._store, this._host);

  final DevToolRegistry _tools;
  final DeviceSelectionStore _store;
  final HostOs _host;

  final _catalogs = <String, _Catalog>{};
  final _inflight = <String, Future<bool>>{};

  bool offers(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  }) {
    if (remote) return false;
    return _parsed(def, profileName)?.operation == DevOperation.runOnDevice;
  }

  /// Ação da execução, ou null se a ferramenta não oferece uma, se [sessionUrl]
  /// não serve, ou se o workspace é remoto (a URL seria do loopback do host).
  TaskRunAction? sessionAction(
    TaskDefinition def, {
    required String? profileName,
    required String sessionUrl,
    required bool remote,
  }) {
    if (remote || sessionUrl.isEmpty) return null;
    return _tools.action(
      def.command,
      _resolvedArgs(def, profileName),
      sessionUrl: sessionUrl,
    );
  }

  TaskDeviceSnapshot snapshot(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  }) {
    if (!offers(def, profileName: profileName, remote: remote)) {
      return TaskDeviceSnapshot.hidden;
    }
    final parsed = _parsed(def, profileName)!;
    final tool = _tools.deviceTool(parsed.toolId);
    if (tool == null) return TaskDeviceSnapshot.hidden;
    final key = _catalogKey(def.cwd, parsed.invocation);
    final catalog = _catalogs[key];
    final ready = catalog != null;
    final devices = catalog?.devices ?? const <DevDevice>[];
    final platforms = catalog?.platforms ?? const <DevPlatform>{};
    final selectedId = _selectedId(
      def,
      parsed,
      tool,
      platforms: platforms,
      devices: devices,
      ready: ready,
    );
    final selectedName = _nameOf(selectedId, devices);
    final inList = selectedName != null;
    return TaskDeviceSnapshot(
      offered: true,
      loading: !ready,
      unavailable: ready && selectedId != null && !inList,
      canStart: !ready || inList,
      devices: devices,
      selectedId: selectedId,
      selectedName: selectedName,
    );
  }

  /// Atualiza o catálogo do projeto da task. `false` quando a lista não mudou
  /// (ou a task não executa em device). Falha de listagem preserva a anterior.
  Future<bool> refresh(TaskDefinition def, {required String? profileName}) {
    final parsed = _parsed(def, profileName);
    if (parsed == null || parsed.operation != DevOperation.runOnDevice) {
      return Future<bool>.value(false);
    }
    final tool = _tools.deviceTool(parsed.toolId);
    if (tool == null) return Future<bool>.value(false);
    final key = _catalogKey(def.cwd, parsed.invocation);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _load(tool, def.cwd, parsed, key);
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    });
    return future;
  }

  Future<void> select(TaskDefinition def, String deviceId) {
    return _store.write(def.cwd, def.id, deviceId);
  }

  /// Argv para o tooltip. Inclui `-d` quando já há um id efetivo.
  List<String> previewArgs(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  }) {
    final resolved = _resolvedArgs(def, profileName);
    if (remote) return resolved;
    final snap = snapshot(def, profileName: profileName, remote: false);
    final id = snap.selectedId;
    if (!snap.offered || id == null) return resolved;
    final tool = _tools.deviceTool(_parsed(def, profileName)!.toolId);
    if (tool == null) return resolved;
    return tool.withDevice(resolved, id);
  }

  /// Prepara o start. No remoto, e em tasks que não rodam em device, não mexe
  /// no argv. Sem device compatível, [TaskLaunchPlan.blocked] impede o spawn.
  Future<TaskLaunchPlan> plan(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  }) async {
    if (remote || !offers(def, profileName: profileName, remote: false)) {
      return TaskLaunchPlan.plain;
    }
    await refresh(def, profileName: profileName);
    final snap = snapshot(def, profileName: profileName, remote: false);
    final id = snap.selectedId;
    if (!snap.canStart || id == null || snap.unavailable) {
      return TaskLaunchPlan.blockedRun;
    }
    final tool = _tools.deviceTool(_parsed(def, profileName)!.toolId);
    if (tool == null) return TaskLaunchPlan.blockedRun;
    return TaskLaunchPlan(
      blocked: false,
      argsOverride: tool.withDevice(_resolvedArgs(def, profileName), id),
    );
  }

  Future<bool> _load(
    DeviceRunTool tool,
    String cwd,
    ParsedDevCommand parsed,
    String key,
  ) async {
    try {
      final platforms = await tool.platforms(cwd);
      final devices = await tool.devices(cwd, parsed);
      final next = _Catalog(platforms: platforms, devices: devices);
      final previous = _catalogs[key];
      final changed = previous == null || !_same(previous, next);
      _catalogs[key] = next;
      return changed;
    } on Object {
      if (_catalogs.containsKey(key)) return false;
      _catalogs[key] = const _Catalog(platforms: {}, devices: []);
      return true;
    }
  }

  ParsedDevCommand? _parsed(TaskDefinition def, String? profileName) {
    return _tools.match(def.command, _resolvedArgs(def, profileName));
  }

  String? _selectedId(
    TaskDefinition def,
    ParsedDevCommand parsed,
    DeviceRunTool tool, {
    required Set<DevPlatform> platforms,
    required List<DevDevice> devices,
    required bool ready,
  }) {
    final manual = _store.read(def.cwd, def.id);
    if (manual != null) return manual.deviceId;
    final explicit = parsed.explicitDeviceId;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (!ready) return null;
    return tool.prefer(_host, platforms, devices)?.id;
  }

  static String? _nameOf(String? id, List<DevDevice> devices) {
    if (id == null) return null;
    for (final device in devices) {
      if (device.id == id) return device.name;
    }
    return null;
  }

  static List<String> _resolvedArgs(TaskDefinition def, String? profileName) {
    TaskProfile? profile;
    if (profileName != null) {
      for (final candidate in def.profiles) {
        if (candidate.name == profileName) {
          profile = candidate;
          break;
        }
      }
    }
    return def.resolveArgs(profile);
  }

  static String _catalogKey(String cwd, List<String> invocation) =>
      '$cwd\u001f${invocation.join('\u001f')}';

  static bool _same(_Catalog a, _Catalog b) {
    if (a.platforms.length != b.platforms.length) return false;
    for (final platform in a.platforms) {
      if (!b.platforms.contains(platform)) return false;
    }
    if (a.devices.length != b.devices.length) return false;
    for (var i = 0; i < a.devices.length; i++) {
      final left = a.devices[i];
      final right = b.devices[i];
      if (left.id != right.id ||
          left.name != right.name ||
          left.platform != right.platform) {
        return false;
      }
    }
    return true;
  }
}

class _Catalog {
  const _Catalog({required this.platforms, required this.devices});

  final Set<DevPlatform> platforms;
  final List<DevDevice> devices;
}
