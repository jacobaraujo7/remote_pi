/// Preferência manual de device de uma task. A escolha automática não é gravada.
class DevicePreference {
  const DevicePreference({required this.deviceId});

  final String deviceId;
}

/// Persistência da escolha manual, por pasta da task + id da task.
/// Device ids são da máquina local — não vão para o `tasks.json` do projeto.
abstract class DeviceSelectionStore {
  DevicePreference? read(String cwd, String taskId);

  Future<void> write(String cwd, String taskId, String deviceId);
}
