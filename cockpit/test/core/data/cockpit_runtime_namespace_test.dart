import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;

void main() {
  test(
    'normal mode has no isolated namespace and does not consume an auth home override',
    () {
      expect(
        cockpitIsolatedRoot(
          environment: {'HOME': '/real', 'CODEX_HOME': '/auth'},
        ),
        isNull,
      );
    },
  );
  test('isolated roots normalize with the destination platform path rules', () {
    expect(
      cockpitIsolatedRoot(
        environment: {'COCKPIT_ISOLATED_ROOT': r'C:\scratch\one\..\simulation'},
        context: paths.windows,
      ),
      r'C:\scratch\simulation',
    );
    expect(
      cockpitIsolatedRoot(
        environment: {'COCKPIT_ISOLATED_ROOT': ' /tmp/one/../simulation '},
        context: paths.posix,
      ),
      '/tmp/simulation',
    );
  });
  test(
    'invalid explicit roots cannot silently use the current live profile',
    () {
      for (final root in ['relative', './scratch', '../scratch']) {
        expect(
          () => cockpitIsolatedRoot(
            environment: {'COCKPIT_ISOLATED_ROOT': root},
            context: paths.posix,
          ),
          throwsArgumentError,
        );
      }
    },
  );
}
