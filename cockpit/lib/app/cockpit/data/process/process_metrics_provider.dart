import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';

typedef MetricsProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Native collectors intentionally inspect only the requested PID. A terminal
/// can be a shell whose child agent has different metrics; callers must pass
/// the actual agent PID when they need agent-specific numbers.
ProcessMetricsProvider createProcessMetricsProvider({String? wslDistro}) {
  if (wslDistro != null && wslDistro.isNotEmpty && Platform.isWindows) {
    return WslProcessMetricsProvider(wslDistro);
  }
  if (Platform.isMacOS) return MacosProcessMetricsProvider();
  if (Platform.isWindows) return WindowsProcessMetricsProvider();
  return LinuxProcessMetricsProvider();
}

class LinuxProcessMetricsProvider implements ProcessMetricsProvider {
  LinuxProcessMetricsProvider({
    Directory? procDir,
    MetricsProcessRunner? runner,
  }) : _procDir = procDir ?? Directory('/proc'),
       _runner = runner ?? Process.run;

  final Directory _procDir;
  final MetricsProcessRunner _runner;

  @override
  Future<ProcessMetricsSnapshot> read(int pid) async {
    final now = DateTime.now();
    if (pid <= 0) return _unavailable(pid, now, '/proc + ps', 'invalid PID');
    int? rssBytes;
    double? cpuPercent;
    try {
      final status = await File('${_procDir.path}/$pid/status').readAsString();
      rssBytes = parseVmRssBytes(status);
    } catch (_) {
      // The process may have exited or /proc may be inaccessible.
    }
    try {
      final result = await _runner('ps', ['-p', '$pid', '-o', '%cpu=']);
      if (result.exitCode == 0) {
        cpuPercent = parseCpuPercent(result.stdout.toString());
      }
    } catch (_) {}
    return ProcessMetricsSnapshot(
      pid: pid,
      cpuPercent: cpuPercent,
      rssBytes: rssBytes,
      collectedAt: now,
      source: '/proc/$pid/status + ps %cpu (lifetime average)',
      unavailableReason: cpuPercent == null && rssBytes == null
          ? 'process exited or metrics unavailable'
          : null,
    );
  }

  static int? parseVmRssBytes(String status) {
    final match = RegExp(
      r'^VmRSS:\s*(\d+)\s+kB\s*$',
      multiLine: true,
    ).firstMatch(status);
    final kib = int.tryParse(match?.group(1) ?? '');
    return kib == null ? null : kib * 1024;
  }
}

class MacosProcessMetricsProvider implements ProcessMetricsProvider {
  MacosProcessMetricsProvider({MetricsProcessRunner? runner})
    : _runner = runner ?? Process.run;

  final MetricsProcessRunner _runner;

  @override
  Future<ProcessMetricsSnapshot> read(int pid) => _readPs(
    pid: pid,
    executable: 'ps',
    arguments: ['-p', '$pid', '-o', '%cpu=', '-o', 'rss='],
    source: 'ps %cpu (recent average), rss',
    runner: _runner,
  );
}

class WslProcessMetricsProvider implements ProcessMetricsProvider {
  WslProcessMetricsProvider(this.distro, {MetricsProcessRunner? runner})
    : _runner = runner ?? Process.run;

  final String distro;
  final MetricsProcessRunner _runner;

  @override
  Future<ProcessMetricsSnapshot> read(int pid) => _readPs(
    pid: pid,
    executable: 'wsl.exe',
    arguments: [
      '-d',
      distro,
      '--',
      'ps',
      '-p',
      '$pid',
      '-o',
      '%cpu=',
      '-o',
      'rss=',
    ],
    source: 'WSL $distro: ps %cpu (lifetime average), rss',
    runner: _runner,
  );
}

class WindowsProcessMetricsProvider implements ProcessMetricsProvider {
  WindowsProcessMetricsProvider({MetricsProcessRunner? runner})
    : _runner = runner ?? Process.run;

  final MetricsProcessRunner _runner;
  final Map<int, (DateTime, double)> _previousCpu = {};

  @override
  Future<ProcessMetricsSnapshot> read(int pid) async {
    final now = DateTime.now();
    if (pid <= 0) return _unavailable(pid, now, 'Get-Process', 'invalid PID');
    // Get-Process avoids the much heavier Win32_Process CIM scan. The PID is
    // validated numeric data, so interpolation cannot inject PowerShell code.
    try {
      final result = await _runner('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$p = Get-Process -Id $pid -ErrorAction Stop; '
            '"\$(\$p.CPU)|\$(\$p.WorkingSet64)"',
      ]);
      if (result.exitCode != 0) {
        return _unavailable(
          pid,
          now,
          'Get-Process',
          'process exited or inaccessible',
        );
      }
      final parts = result.stdout.toString().trim().split('|');
      if (parts.length != 2) {
        return _unavailable(
          pid,
          now,
          'Get-Process',
          'unexpected process metrics',
        );
      }
      final cpuSeconds = double.tryParse(parts[0].replaceAll(',', '.'));
      final rssBytes = int.tryParse(parts[1]);
      double? cpuPercent;
      final previous = _previousCpu[pid];
      if (cpuSeconds != null) {
        _previousCpu[pid] = (now, cpuSeconds);
        if (previous != null && cpuSeconds >= previous.$2) {
          final elapsed = now.difference(previous.$1).inMicroseconds / 1000000;
          if (elapsed > 0) {
            cpuPercent = 100 * (cpuSeconds - previous.$2) / elapsed;
          }
        }
      }
      return ProcessMetricsSnapshot(
        pid: pid,
        cpuPercent: cpuPercent,
        rssBytes: rssBytes,
        collectedAt: now,
        source: 'Get-Process CPU delta, WorkingSet64',
        unavailableReason: cpuPercent == null && rssBytes == null
            ? 'process metrics unavailable'
            : null,
      );
    } catch (_) {
      return _unavailable(
        pid,
        now,
        'Get-Process',
        'process metrics unavailable',
      );
    }
  }
}

Future<ProcessMetricsSnapshot> _readPs({
  required int pid,
  required String executable,
  required List<String> arguments,
  required String source,
  required MetricsProcessRunner runner,
}) async {
  final now = DateTime.now();
  if (pid <= 0) return _unavailable(pid, now, source, 'invalid PID');
  try {
    final result = await runner(executable, arguments);
    if (result.exitCode == 0) {
      final values = result.stdout.toString().trim().split(RegExp(r'\s+'));
      if (values.length >= 2) {
        final cpuPercent = parseCpuPercent(values[0]);
        final rssKib = int.tryParse(values[1]);
        return ProcessMetricsSnapshot(
          pid: pid,
          cpuPercent: cpuPercent,
          rssBytes: rssKib == null ? null : rssKib * 1024,
          collectedAt: now,
          source: source,
          unavailableReason: cpuPercent == null && rssKib == null
              ? 'unexpected process metrics'
              : null,
        );
      }
    }
  } catch (_) {}
  return _unavailable(
    pid,
    now,
    source,
    'process exited or metrics unavailable',
  );
}

double? parseCpuPercent(String value) {
  final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
}

ProcessMetricsSnapshot _unavailable(
  int pid,
  DateTime at,
  String source,
  String reason,
) => ProcessMetricsSnapshot(
  pid: pid,
  cpuPercent: null,
  rssBytes: null,
  collectedAt: at,
  source: source,
  unavailableReason: reason,
);
