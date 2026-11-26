import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';
import 'package:cockpit/app/cockpit/ui/services/graph_process_metrics_service.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingProvider implements ProcessMetricsProvider {
  final List<int> requested = [];

  @override
  Future<ProcessMetricsSnapshot> read(int pid) async {
    requested.add(pid);
    return ProcessMetricsSnapshot(
      pid: pid,
      cpuPercent: 4,
      rssBytes: 1024,
      collectedAt: DateTime.now(),
      source: 'test provider',
    );
  }
}

void main() {
  const wsl = TerminalProfile(
    id: 'wsl:Ubuntu',
    label: 'Ubuntu (WSL)',
    executable: 'wsl.exe',
  );
  const native = TerminalProfile(
    id: 'powershell',
    label: 'PowerShell',
    executable: 'powershell.exe',
  );

  test('WSL never treats the Windows launcher PID as a Linux PID', () async {
    final host = _RecordingProvider();
    final guest = _RecordingProvider();
    final service = GraphProcessMetricsService(
      hostProvider: host,
      wslProviderForDistro: (distro) {
        expect(distro, 'Ubuntu');
        return guest;
      },
    );

    final sample = await service.read(
      profile: wsl,
      hostPid: 4312,
      wslPid: null,
    );

    expect(sample.hasMeasurements, isFalse);
    expect(sample.unavailableReason, contains('Linux PID'));
    expect(host.requested, isEmpty);
    expect(guest.requested, isEmpty);
  });

  test(
    'WSL collector receives only an explicitly identified Linux PID',
    () async {
      final host = _RecordingProvider();
      final guest = _RecordingProvider();
      final service = GraphProcessMetricsService(
        hostProvider: host,
        wslProviderForDistro: (_) => guest,
      );

      final sample = await service.read(
        profile: wsl,
        hostPid: 4312,
        wslPid: 27,
      );

      expect(sample.pid, 27);
      expect(guest.requested, [27]);
      expect(host.requested, isEmpty);
    },
  );

  test('native terminal uses the host PID only', () async {
    final host = _RecordingProvider();
    final service = GraphProcessMetricsService(hostProvider: host);

    final sample = await service.read(
      profile: native,
      hostPid: 4312,
      wslPid: null,
    );

    expect(sample.pid, 4312);
    expect(host.requested, [4312]);
  });
}
