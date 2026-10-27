import 'dart:io';

import 'package:cockpit/app/cockpit/data/process/process_metrics_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux reads RSS from proc and CPU from ps', () async {
    final proc = await Directory.systemTemp.createTemp('cockpit-metrics-');
    try {
      final process = await Directory('${proc.path}/42').create();
      await File(
        '${process.path}/status',
      ).writeAsString('Name:\tclaude\nVmRSS:\t2048 kB\n');
      final collector = LinuxProcessMetricsProvider(
        procDir: proc,
        runner: (exe, args) async {
          expect(exe, 'ps');
          expect(args, ['-p', '42', '-o', '%cpu=']);
          return ProcessResult(1, 0, '12.5\n', '');
        },
      );
      final sample = await collector.read(42);
      expect(sample.cpuPercent, 12.5);
      expect(sample.rssBytes, 2097152);
      expect(sample.source, contains('/proc/42/status'));
      expect(sample.unavailableReason, isNull);
    } finally {
      await proc.delete(recursive: true);
    }
  });

  test('macOS parses per-process ps output', () async {
    final collector = MacosProcessMetricsProvider(
      runner: (exe, args) async {
        expect(exe, 'ps');
        expect(args, ['-p', '7', '-o', '%cpu=', '-o', 'rss=']);
        return ProcessResult(1, 0, '  3.2  1024\n', '');
      },
    );
    final sample = await collector.read(7);
    expect(sample.cpuPercent, 3.2);
    expect(sample.rssBytes, 1048576);
  });

  test(
    'WSL invokes selected distro and keeps unavailable values null',
    () async {
      final collector = WslProcessMetricsProvider(
        'Ubuntu',
        runner: (exe, args) async {
          expect(exe, 'wsl.exe');
          expect(args, [
            '-d',
            'Ubuntu',
            '--',
            'ps',
            '-p',
            '12',
            '-o',
            '%cpu=',
            '-o',
            'rss=',
          ]);
          return ProcessResult(1, 1, '', 'not found');
        },
      );
      final sample = await collector.read(12);
      expect(sample.cpuPercent, isNull);
      expect(sample.rssBytes, isNull);
      expect(sample.unavailableReason, isNotNull);
    },
  );

  test(
    'Windows uses Get-Process and calculates CPU only after two samples',
    () async {
      var calls = 0;
      final collector = WindowsProcessMetricsProvider(
        runner: (exe, args) async {
          expect(exe, 'powershell.exe');
        expect(args.last, contains('-Id 23'));
          calls++;
          return ProcessResult(1, 0, '${calls.toDouble()}|4096\n', '');
        },
      );
      final first = await collector.read(23);
      expect(first.cpuPercent, isNull);
      expect(first.rssBytes, 4096);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = await collector.read(23);
      expect(second.cpuPercent, isNotNull);
      expect(second.cpuPercent, greaterThan(0));
      expect(second.rssBytes, 4096);
    },
  );

  test('invalid PIDs never trigger system probes', () async {
    final collector = MacosProcessMetricsProvider(
      runner: (_, _) => throw StateError('must not probe'),
    );
    final sample = await collector.read(-1);
    expect(sample.hasMeasurements, isFalse);
    expect(sample.unavailableReason, 'invalid PID');
  });
}
