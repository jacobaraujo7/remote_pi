/// Estado de um daemon observado pelo supervisor.
enum DaemonState { running, stopped, starting, crashed, unknown }

DaemonState daemonStateFromWire(String? raw) => switch (raw) {
  'running' => DaemonState.running,
  'stopped' => DaemonState.stopped,
  'starting' => DaemonState.starting,
  'crashed' => DaemonState.crashed,
  _ => DaemonState.unknown,
};

/// Um "Daemon Agent" — um `pi --mode rpc` que roda 24/7 sob o `pi-supervisord`.
///
/// Espelha o `DaemonInfo` do control protocol do remote-pi
/// (`pi-extension/src/daemon/control_protocol.ts`). O `id` é derivado do cwd
/// (sha256[0..8]); `name`/cwd vêm do registry + config local.
class DaemonInfo {
  const DaemonInfo({
    required this.id,
    required this.cwd,
    required this.name,
    required this.state,
    this.pid,
    this.uptimeSeconds,
    this.restartCount,
  });

  final String id;
  final String cwd;
  final String name;
  final DaemonState state;
  final int? pid;
  final int? uptimeSeconds;
  final int? restartCount;

  @override
  bool operator ==(Object other) =>
      other is DaemonInfo &&
      other.id == id &&
      other.cwd == cwd &&
      other.name == name &&
      other.state == state &&
      other.pid == pid &&
      other.uptimeSeconds == uptimeSeconds &&
      other.restartCount == restartCount;

  @override
  int get hashCode =>
      Object.hash(id, cwd, name, state, pid, uptimeSeconds, restartCount);
}
