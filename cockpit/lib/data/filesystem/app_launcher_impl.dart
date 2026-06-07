import 'dart:io';

import 'package:cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/domain/entities/launchable_app.dart';

class _Candidate {
  const _Candidate(this.id, this.name, this.bundle);
  final String id;
  final String name;
  final String bundle;
}

/// Candidatos por ordem de preferência (primeiro encontrado = padrão no botão).
const _kCandidates = [
  _Candidate('cursor', 'Cursor', 'Cursor.app'),
  _Candidate('windsurf', 'Windsurf', 'Windsurf.app'),
  _Candidate('antigravity', 'Antigravity', 'Antigravity.app'),
  _Candidate('vscode', 'Visual Studio Code', 'Visual Studio Code.app'),
];

/// Implementação macOS: sonda `/Applications` e `~/Applications` e extrai ícones
/// via `sips` (converte `.icns` → PNG, cacheado em `Directory.systemTemp`).
class AppLauncherImpl implements AppLauncherGateway {
  const AppLauncherImpl();

  @override
  Future<List<LaunchableApp>> probe() async {
    final found = <LaunchableApp>[];
    for (final c in _kCandidates) {
      final bundlePath = await _findBundle(c.bundle);
      if (bundlePath != null) {
        final icon = await _extractIcon(bundlePath);
        found.add(LaunchableApp(id: c.id, name: c.name, iconPath: icon));
      }
    }
    // Finder — sempre disponível no macOS.
    final finderIcon = await _extractIcon(
      '/System/Library/CoreServices/Finder.app',
    );
    found.add(LaunchableApp(id: 'finder', name: 'Finder', iconPath: finderIcon));
    return found;
  }

  @override
  Future<void> launch(LaunchableApp app, String path) async {
    if (app.id == 'finder') {
      await Process.run('open', [path]);
      return;
    }
    final c = _kCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    await Process.run('open', ['-a', c.name, path]);
  }

  // ---- helpers ---------------------------------------------------------------

  Future<String?> _findBundle(String bundle) async {
    final home = Platform.environment['HOME'] ?? '';
    for (final base in ['/Applications', '$home/Applications']) {
      final path = '$base/$bundle';
      if (await Directory(path).exists()) return path;
    }
    return null;
  }

  /// Lê `CFBundleIconFile` do Info.plist do bundle, converte o `.icns` para
  /// PNG 32×32 com `sips` e retorna o caminho do PNG cacheado.
  Future<String?> _extractIcon(String bundlePath) async {
    try {
      // Lê o nome do arquivo de ícone do plist.
      final plist = await Process.run(
        'defaults',
        ['read', '$bundlePath/Contents/Info', 'CFBundleIconFile'],
      );
      if (plist.exitCode != 0) return null;
      var iconName = (plist.stdout as String).trim();
      if (iconName.isEmpty) return null;
      if (!iconName.endsWith('.icns')) iconName = '$iconName.icns';

      final icnsPath = '$bundlePath/Contents/Resources/$iconName';
      if (!File(icnsPath).existsSync()) return null;

      // Cache: <temp>/ck_icon_<hash>.png — reutiliza entre boots do app.
      final cacheKey = icnsPath.hashCode.abs();
      final outPath = '${Directory.systemTemp.path}/ck_icon_$cacheKey.png';
      if (File(outPath).existsSync()) return outPath;

      final sips = await Process.run('sips', [
        '-s', 'format', 'png',
        '-z', '32', '32',
        icnsPath,
        '--out', outPath,
      ]);
      return sips.exitCode == 0 ? outPath : null;
    } catch (_) {
      return null;
    }
  }
}
