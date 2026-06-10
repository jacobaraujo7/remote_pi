import 'dart:convert';
import 'dart:io';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/config/utils/executable_resolver.dart';
import 'package:cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/domain/entities/install_result.dart';

/// Instala extensão e supervisor rodando processos (`pi` / `node`). Best-effort:
/// qualquer falha de IO vira [InstallResult.failure] com mensagem legível.
class EnvironmentInstallerImpl implements EnvironmentInstaller {
  EnvironmentInstallerImpl(this._config);

  final PiSpawnConfig _config;

  // Windows não seta HOME; o equivalente é USERPROFILE.
  String? get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  @override
  Future<InstallResult> installExtension() async {
    try {
      final result = await Process.run(
        _config.executable,
        const ['install', 'npm:remote-pi'],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) return const InstallResult.success();
      return InstallResult.failure(_output(result));
    } catch (e) {
      return InstallResult.failure('Falha ao executar "pi install": $e');
    }
  }

  @override
  Future<InstallResult> installSupervisor() async {
    final indexJs = await _resolveIndexJs();
    if (indexJs == null) {
      return const InstallResult.failure(
        'Não encontrei o index.js da extensão remote-pi. '
        'Instale a extensão antes de instalar o supervisor.',
      );
    }
    final node = await resolveExecutable(
      'node',
      unixCandidates: const ['/opt/homebrew/bin/node', '/usr/local/bin/node'],
      unixHomeRelative: const ['.local/bin/node'],
      windowsExtraDirs: const [r'C:\Program Files\nodejs'],
    );
    try {
      final result = await Process.run(
        node,
        [indexJs, 'install'],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) return const InstallResult.success();
      return InstallResult.failure(_output(result));
    } catch (e) {
      return InstallResult.failure('Falha ao executar o instalador: $e');
    }
  }

  /// Resolve o caminho absoluto do `dist/index.js` da extensão remote-pi a partir
  /// do `packages[]` em `~/.pi/agent/settings.json`. `null` se não der pra achar.
  Future<String?> _resolveIndexJs() async {
    final home = _home;
    if (home == null) return null;
    try {
      final file = File('$home/.pi/agent/settings.json');
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final packages = json['packages'];
      if (packages is! List) return null;

      final spec = packages.whereType<String>().firstWhere((p) {
        final low = p.toLowerCase();
        return low.contains('remote-pi') || low.endsWith('pi-extension');
      }, orElse: () => '');
      if (spec.isEmpty) return null;

      final String pkgRoot;
      if (!spec.contains('/') && !spec.contains(r'\')) {
        // Spec do npm (`npm:remote-pi` / `remote-pi`) → node_modules do pi.
        pkgRoot = '$home/.pi/agent/npm/node_modules/remote-pi';
      } else {
        // Caminho local (possivelmente relativo a ~/.pi/agent/, com `../`).
        final clean = spec.startsWith('npm:') ? spec.substring(4) : spec;
        pkgRoot = Uri.directory(
          '$home/.pi/agent/',
        ).resolve(clean).toFilePath();
      }

      final indexJs = File('$pkgRoot/dist/index.js');
      if (await indexJs.exists()) return indexJs.path;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Junta stderr + stdout (truncado) pra uma mensagem de erro útil no dialog.
  String _output(ProcessResult r) {
    final err = (r.stderr ?? '').toString().trim();
    final out = (r.stdout ?? '').toString().trim();
    final text = err.isNotEmpty ? err : out;
    if (text.isEmpty) return 'Saída com código ${r.exitCode}.';
    return text.length > 600 ? text.substring(text.length - 600) : text;
  }
}
