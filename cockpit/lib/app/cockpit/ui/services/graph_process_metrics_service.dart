import 'package:cockpit/app/cockpit/data/process/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';

/// Resolves a terminal's process namespace before collecting graph metrics.
/// A Windows `wsl.exe` PID cannot identify a process inside a Linux distro.
class GraphProcessMetricsService {
  GraphProcessMetricsService({
    required this.hostProvider,
    ProcessMetricsProvider Function(String distro)? wslProviderForDistro,
  }) : _wslProviderForDistro =
           wslProviderForDistro ??
           ((distro) => WslProcessMetricsProvider(distro));

  final ProcessMetricsProvider hostProvider;
  final ProcessMetricsProvider Function(String distro) _wslProviderForDistro;
  final Map<String, ProcessMetricsProvider> _wslProviders = {};

  Future<ProcessMetricsSnapshot> read({
    required TerminalProfile profile,
    required int? hostPid,
    required int? wslPid,
  }) {
    final distro = profile.wslDistro;
    if (distro != null) {
      if (wslPid == null || wslPid <= 0) {
        return Future.value(
          ProcessMetricsSnapshot(
            pid: 0,
            cpuPercent: null,
            rssBytes: null,
            collectedAt: DateTime.now(),
            source: 'WSL $distro',
            unavailableReason: 'Linux PID unavailable for this terminal',
          ),
        );
      }
      final provider = _wslProviders.putIfAbsent(
        distro,
        () => _wslProviderForDistro(distro),
      );
      return provider.read(wslPid);
    }
    if (hostPid == null || hostPid <= 0) {
      return Future.value(
        ProcessMetricsSnapshot(
          pid: 0,
          cpuPercent: null,
          rssBytes: null,
          collectedAt: DateTime.now(),
          source: 'Host process',
          unavailableReason: 'process PID unavailable',
        ),
      );
    }
    return hostProvider.read(hostPid);
  }
}
