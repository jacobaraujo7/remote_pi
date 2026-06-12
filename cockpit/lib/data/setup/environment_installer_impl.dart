import 'dart:io';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/domain/entities/install_result.dart';

/// Instala extensão e supervisor rodando processos (`pi` / `node`). Best-effort:
/// qualquer falha de IO vira [InstallResult.failure] com mensagem legível.
class EnvironmentInstallerImpl implements EnvironmentInstaller {
  EnvironmentInstallerImpl(this._config);

  final PiSpawnConfig _config;

  @override
  Future<InstallResult> installExtension() async {
    try {
      final result = await Process.run(
        _config.executable,
        const ['install', 'npm:remote-pi'],
        runInShell: Platform.isWindows,
        environment: await envWithNodeOnPath(),
      );
      if (result.exitCode == 0) return const InstallResult.success();
      return InstallResult.failure(_output(result));
    } catch (e) {
      return InstallResult.failure('Failed to run "pi install": $e');
    }
  }

  @override
  Future<InstallResult> installSupervisor() async {
    final indexJs = await resolveRemotePiIndexJs();
    if (indexJs == null) {
      return const InstallResult.failure(
        'Could not find the remote-pi extension\'s index.js. '
        'Install the extension before installing the supervisor.',
      );
    }
    final node = await resolveNode();
    try {
      final result = await Process.run(
        node,
        [indexJs, 'install'],
        runInShell: Platform.isWindows,
        environment: await envWithNodeOnPath(),
      );
      if (result.exitCode == 0) return const InstallResult.success();
      return InstallResult.failure(_output(result));
    } catch (e) {
      return InstallResult.failure('Failed to run the installer: $e');
    }
  }

  /// Junta stderr + stdout (truncado) pra uma mensagem de erro útil no dialog.
  String _output(ProcessResult r) {
    final err = (r.stderr ?? '').toString().trim();
    final out = (r.stdout ?? '').toString().trim();
    final text = err.isNotEmpty ? err : out;
    if (text.isEmpty) return 'Exited with code ${r.exitCode}.';
    return text.length > 600 ? text.substring(text.length - 600) : text;
  }
}
