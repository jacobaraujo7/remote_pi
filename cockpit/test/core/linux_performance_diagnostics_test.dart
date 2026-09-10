import 'dart:convert';

import 'package:cockpit/app/core/data/diagnostics/linux_performance_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores only fixed metric names and numeric values', () {
    final diagnostics = LinuxPerformanceDiagnostics(
      enabled: true,
      maxEntries: 4,
      minSampleInterval: Duration.zero,
      sink: (_) {},
    );
    diagnostics.record(LinuxPerfMetric.pty, {
      LinuxPerfField.pending: 42,
      LinuxPerfField.sources: 3,
    });

    final decoded = jsonDecode(diagnostics.snapshotJson()) as List<dynamic>;
    final row = decoded.single as Map<String, dynamic>;
    expect(row['metric'], 'pty');
    expect(row['pending'], 42);
    expect(row['sources'], 3);
    expect(
      row.keys,
      everyElement(isIn(['at', 'metric', 'pending', 'sources'])),
    );
  });

  test('ring buffer discards oldest samples at its fixed limit', () {
    final diagnostics = LinuxPerformanceDiagnostics(
      enabled: true,
      maxEntries: 2,
      minSampleInterval: Duration.zero,
      sink: (_) {},
    );
    for (var i = 1; i <= 3; i++) {
      diagnostics.record(LinuxPerfMetric.memory, {
        LinuxPerfField.rssBytes: i,
      }, force: true);
    }
    expect(diagnostics.entries, hasLength(2));
    expect(diagnostics.entries.first['rssBytes'], 2);
    expect(diagnostics.entries.last['rssBytes'], 3);
  });

  test('flush emits bounded JSON and clears retained samples', () {
    String? output;
    final diagnostics = LinuxPerformanceDiagnostics(
      enabled: true,
      maxEntries: 1,
      minSampleInterval: Duration.zero,
      sink: (value) => output = value,
    );
    diagnostics.record(LinuxPerfMetric.processScan, {
      LinuxPerfField.durationUs: 100,
    });
    diagnostics.flush();
    expect(output, isNotNull);
    expect(output, isNot(contains('/home/')));
    expect(diagnostics.entries, isEmpty);
  });
}
