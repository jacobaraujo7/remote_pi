import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Test the server collector through the workspace's Flutter test runner.
// ignore: avoid_relative_lib_imports
import '../../packages/cockpit_server/lib/src/host_process_metrics.dart';

void main() {
  test('host collector reports source and timestamp for its own PID', () async {
    final result = await readHostProcessMetrics(pid);
    expect(result['pid'], pid);
    expect(DateTime.tryParse(result['at'] as String), isNotNull);
    expect(result['source'], isA<String>());
    expect(result.containsKey('rss') || result.containsKey('reason'), isTrue);
  });

  test('invalid PID never fabricates a measurement', () async {
    final result = await readHostProcessMetrics(0);
    expect(result.containsKey('cpu'), isFalse);
    expect(result.containsKey('rss'), isFalse);
    expect(result['reason'], isNotNull);
  });
}
