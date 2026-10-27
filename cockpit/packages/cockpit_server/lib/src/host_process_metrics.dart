import 'dart:io';

final Map<int, (DateTime, double)> _windowsCpuSamples = {};

/// Reads only the PID belonging to a PTY session resolved by the server.
/// A shell's child agent may have different CPU/RAM usage.
Future<Map<String, Object?>> readHostProcessMetrics(int pid) async {
  final at = DateTime.now().toUtc();
  double? cpu;
  int? rss;
  var source = 'ps %cpu,rss';
  if (pid > 0 && Platform.isWindows) {
    source = 'Get-Process CPU seconds, WorkingSet64';
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$p = Get-Process -Id ' +
            '$pid' +
            r' -ErrorAction Stop; "$($p.CPU)|$($p.WorkingSet64)"',
      ]);
      if (result.exitCode == 0) {
        final values = result.stdout.toString().trim().split('|');
        if (values.length == 2) {
          // Get-Process returns accumulated CPU seconds. Derive a rate only
          // after two observations of this same host PID.
          final seconds = double.tryParse(values[0].replaceAll(',', '.'));
          if (seconds != null) {
            final previous = _windowsCpuSamples[pid];
            _windowsCpuSamples[pid] = (at, seconds);
            if (previous != null && seconds >= previous.$2) {
              final elapsed = at.difference(previous.$1).inMicroseconds / 1e6;
              if (elapsed > 0) cpu = 100 * (seconds - previous.$2) / elapsed;
            }
          }
          rss = int.tryParse(values[1]);
        }
      }
    } catch (_) {}
  } else if (pid > 0) {
    try {
      final result = await Process.run('ps', [
        '-p',
        '$pid',
        '-o',
        '%cpu=',
        '-o',
        'rss=',
      ]);
      if (result.exitCode == 0) {
        final values = result.stdout.toString().trim().split(RegExp(r'\s+'));
        if (values.length >= 2) {
          cpu = double.tryParse(values[0].replaceAll(',', '.'));
          final kib = int.tryParse(values[1]);
          rss = kib == null ? null : kib * 1024;
        }
      }
    } catch (_) {}
  }
  return {
    'pid': pid,
    if (cpu != null) 'cpu': cpu,
    if (rss != null) 'rss': rss,
    'at': at.toIso8601String(),
    'source': source,
    if (cpu == null && rss == null) 'reason': 'process unavailable',
  };
}
