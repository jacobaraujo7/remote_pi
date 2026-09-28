import 'package:cockpit/app/core/data/diagnostics/performance_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores only fixed metric names and numeric values', () {
    final diagnostics = PerformanceDiagnostics(
      enabled: true,
      maxEntries: 4,
      minSampleInterval: Duration.zero,
      sink: (_, _) {},
    );
    diagnostics.record(PerfMetric.pty, {
      PerfField.pending: 42,
      PerfField.sources: 3,
    });
    final row = diagnostics.entries.single;
    expect(row['metric'], 'pty');
    expect(row['pending'], 42);
    expect(row['sources'], 3);
    expect(
      row.keys,
      everyElement(isIn(['at', 'metric', 'pending', 'sources'])),
    );
  });

  test('ring buffer discards oldest samples at its fixed limit', () {
    final diagnostics = PerformanceDiagnostics(
      enabled: true,
      maxEntries: 2,
      minSampleInterval: Duration.zero,
      sink: (_, _) {},
    );
    for (var i = 1; i <= 3; i++) {
      diagnostics.record(PerfMetric.memory, {
        PerfField.rssBytes: i,
      }, force: true);
    }
    expect(diagnostics.entries.map((e) => e['rssBytes']), [2, 3]);
  });

  test('flush hands every sample to the sink and clears', () {
    final seen = <String>[];
    final diagnostics = PerformanceDiagnostics(
      enabled: true,
      minSampleInterval: Duration.zero,
      sink: (metric, fields) => seen.add('$metric:${fields.keys.join(',')}'),
    );
    diagnostics.record(PerfMetric.spawn, {PerfField.durationUs: 10});
    diagnostics.record(PerfMetric.boot, {PerfField.durationUs: 900});
    diagnostics.flush();
    expect(seen, ['spawn:durationUs', 'boot:durationUs']);
    expect(diagnostics.entries, isEmpty);
  });

  test('disabled instance records nothing', () {
    final diagnostics = PerformanceDiagnostics(enabled: false, sink: (_, _) {});
    diagnostics.record(PerfMetric.pty, {PerfField.pending: 1}, force: true);
    diagnostics.markBootReady();
    expect(diagnostics.entries, isEmpty);
  });
}
