import 'dart:io';

import 'package:cockpit/app/cockpit/data/telemetry/telemetry_store_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'isolated telemetry never asks for the installed app support directory',
    () async {
      final root = p.join(Directory.systemTemp.path, 'cockpit-private-run');
      final result = await TelemetryStoreRegistry.directory(
        environment: {'COCKPIT_ISOLATED_ROOT': root},
        applicationSupportDirectory: () async =>
            throw StateError('must not access installed application support'),
      );
      expect(result, p.join(root, 'telemetry'));
    },
  );

  test(
    'normal telemetry preserves the application support cache path',
    () async {
      final support = Directory(
        p.join(Directory.systemTemp.path, 'installed-support'),
      );
      var calls = 0;
      final result = await TelemetryStoreRegistry.directory(
        environment: {'CODEX_HOME': '/auth-only'},
        applicationSupportDirectory: () async {
          calls++;
          return support;
        },
      );
      expect(calls, 1);
      expect(result, p.join(support.path, 'telemetry'));
    },
  );

  test(
    'invalid private root fails before touching the installed cache',
    () async {
      await expectLater(
        TelemetryStoreRegistry.directory(
          environment: {'COCKPIT_ISOLATED_ROOT': 'relative-root'},
          applicationSupportDirectory: () async =>
              throw StateError('must not fall back to installed storage'),
        ),
        throwsArgumentError,
      );
    },
  );
}
