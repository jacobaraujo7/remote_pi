import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/exceptions/neovim_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/settings/ui/neovim_settings_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements NeovimGateway {
  String? path;
  int refreshes = 0;

  @override
  Future<String?> executable({bool refresh = false}) async {
    if (refresh) refreshes++;
    return path;
  }

  @override
  Future<Result<bool, NeovimError>> hasModifiedBuffers(
    String executable,
    String address,
  ) async => const Success(false);

  @override
  Future<bool> isAlive(String executable, String address) async => false;

  @override
  Future<Result<void, NeovimError>> openRemote(
    String executable,
    String address,
    String path, {
    int? line,
  }) async => const Success(null);

  @override
  Future<void> prepareServer(String address) async {}

  @override
  String serverAddress(String workspaceId) => '/tmp/$workspaceId';
}

void main() {
  test(
    'reports unavailable, then refreshes after Neovim is installed',
    () async {
      final gateway = _Gateway();
      final vm = NeovimSettingsViewModel(gateway);

      await vm.check();
      expect(vm.available, isFalse);

      gateway.path = '/usr/bin/nvim';
      await vm.check(refresh: true);
      expect(vm.available, isTrue);
      expect(vm.executable, '/usr/bin/nvim');
      expect(gateway.refreshes, 1);
    },
  );
}
