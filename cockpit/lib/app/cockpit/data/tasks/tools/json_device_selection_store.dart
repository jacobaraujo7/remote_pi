import 'package:cockpit/app/cockpit/domain/contracts/device_selection_store.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';

/// Escolha manual de device em `state/task_devices.json`.
/// A chave é a pasta da task mais o id — labels iguais em projetos diferentes
/// não compartilham device.
class JsonDeviceSelectionStore implements DeviceSelectionStore {
  JsonDeviceSelectionStore(this._store);

  static const storeName = 'task_devices';

  final JsonStateStore _store;

  static String key(String cwd, String taskId) => '$cwd\u0000$taskId';

  @override
  DevicePreference? read(String cwd, String taskId) {
    final raw = _store.get(key(cwd, taskId));
    if (raw is! Map) return null;
    if (raw['manual'] != true) return null;
    final id = raw['deviceId'];
    if (id is! String || id.isEmpty) return null;
    return DevicePreference(deviceId: id);
  }

  @override
  Future<void> write(String cwd, String taskId, String deviceId) {
    return _store.put(key(cwd, taskId), {'manual': true, 'deviceId': deviceId});
  }
}
