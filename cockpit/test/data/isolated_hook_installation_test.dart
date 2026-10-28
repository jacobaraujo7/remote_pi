import 'package:cockpit/app/cockpit/data/hooks/hook_installer_base.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

class _Installer extends HookInstallerBase {
  _Installer({this.privateRuntime = true, this.cliAvailable = true});
  final bool privateRuntime, cliAvailable;
  int cliCopies = 0, hookResolutions = 0, configWrites = 0;
  @override
  bool get isolatedRuntime => privateRuntime;
  @override
  String get harnessName => 'test';
  @override
  Future<String?> ensureCli() async {
    cliCopies++;
    return cliAvailable ? '/synthetic/private/cockpit' : null;
  }

  @override
  Future<String?> resolveHookCommand(String? path) async {
    hookResolutions++;
    return 'synthetic hook';
  }

  @override
  Future<void> writeConfig({
    required String home,
    required String command,
  }) async {
    configWrites++;
  }
}

void main() {
  test(
    'isolated startup materializes its CLI without resolving or rewriting global hooks',
    () async {
      final installer = _Installer();
      expect(await installer.ensureInstalled(), isA<Success<void, String>>());
      expect(installer.cliCopies, 1);
      expect(installer.hookResolutions, 0);
      expect(installer.configWrites, 0);
    },
  );
  test(
    'missing isolated CLI reports failure without falling through to global installation',
    () async {
      final installer = _Installer(cliAvailable: false);
      expect(await installer.ensureInstalled(), isA<Failure<void, String>>());
      expect(installer.configWrites, 0);
      expect(installer.hookResolutions, 0);
    },
  );
  test('normal startup retains existing hook installation behavior', () async {
    final installer = _Installer(privateRuntime: false);
    expect(await installer.ensureInstalled(), isA<Success<void, String>>());
    expect(installer.cliCopies, 1);
    expect(installer.hookResolutions, 1);
    expect(installer.configWrites, 1);
  });
}
