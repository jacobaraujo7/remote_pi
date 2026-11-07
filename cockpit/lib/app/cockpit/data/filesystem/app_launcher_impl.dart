import 'dart:io';

import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';

class _Candidate {
  const _Candidate(this.id, this.name, this.bundle);
  final String id;
  final String name;
  final String bundle;
}

/// Candidatos macOS por ordem de preferência (primeiro encontrado = padrão).
const _kCandidates = [
  _Candidate('cursor', 'Cursor', 'Cursor.app'),
  _Candidate('windsurf', 'Windsurf', 'Windsurf.app'),
  _Candidate('antigravity', 'Antigravity', 'Antigravity.app'),
  _Candidate('vscode', 'Visual Studio Code', 'Visual Studio Code.app'),
];

class _WinCandidate {
  const _WinCandidate(this.id, this.name, this.exeCandidates);
  final String id;
  final String name;

  /// Pares `(envVar, subpath)` — o caminho final é `%envVar%\<subpath>`. O
  /// primeiro que existir no disco resolve o app.
  final List<(String, String)> exeCandidates;
}

/// Candidatos Windows por ordem de preferência. Os IDEs instalam o `.exe` sob
/// `%LOCALAPPDATA%\Programs\…` (install por usuário) ou `%ProgramFiles%\…`.
const _kWinCandidates = [
  _WinCandidate('cursor', 'Cursor', [
    ('LOCALAPPDATA', r'Programs\cursor\Cursor.exe'),
  ]),
  _WinCandidate('windsurf', 'Windsurf', [
    ('LOCALAPPDATA', r'Programs\Windsurf\Windsurf.exe'),
  ]),
  _WinCandidate('vscode', 'Visual Studio Code', [
    ('LOCALAPPDATA', r'Programs\Microsoft VS Code\Code.exe'),
    ('ProgramFiles', r'Microsoft VS Code\Code.exe'),
  ]),
];

class _LinuxCandidate {
  const _LinuxCandidate(this.id, this.name, this.command);
  final String id;
  final String name;

  /// Comando CLI resolvido via PATH (`cursor`, `windsurf`, `code`).
  final String command;
}

/// Candidatos Linux por ordem de preferência. Os IDEs expõem um comando no PATH
/// (deb/snap/flatpak-wrapper) que abre a pasta como workspace.
const _kLinuxCandidates = [
  _LinuxCandidate('cursor', 'Cursor', 'cursor'),
  _LinuxCandidate('windsurf', 'Windsurf', 'windsurf'),
  _LinuxCandidate('vscode', 'Visual Studio Code', 'code'),
];

/// Lança apps externos pra abrir uma pasta. **macOS**: sonda `/Applications` e
/// extrai ícones via `sips`. **Windows**: resolve os `.exe` conhecidos sob
/// `%LOCALAPPDATA%`/`%ProgramFiles%` e usa o Explorer como equivalente do Finder.
/// **Linux**: resolve os comandos de IDE no PATH e usa `xdg-open` como
/// equivalente do Finder (gerenciador de arquivos padrão). Sem ícone fora do
/// macOS — a UI cai no fallback Material.
class AppLauncherImpl implements AppLauncherGateway {
  const AppLauncherImpl();

  @override
  Future<List<LaunchableApp>> probe() async {
    if (Platform.isMacOS) return _probeMacOS();
    if (Platform.isWindows) return _probeWindows();
    if (Platform.isLinux) return _probeLinux();
    return const <LaunchableApp>[];
  }

  @override
  Future<void> launch(LaunchableApp app, String path) async {
    if (Platform.isWindows) return _launchWindows(app, path);
    if (Platform.isMacOS) return _launchMacOS(app, path);
    if (Platform.isLinux) return _launchLinux(app, path);
  }

  @override
  Future<void> openWithDefaultApp(String path) async {
    if (Platform.isMacOS) {
      // `open <path>` abre com o app padrão do tipo (arquivo) ou Finder (pasta).
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      final xdg = await unixWhich('xdg-open') ?? 'xdg-open';
      await Process.run(xdg, [path]);
    } else if (Platform.isWindows) {
      // `start` (builtin do cmd) abre com o app padrão via ShellExecute. O `""`
      // é o título da janela — obrigatório quando o alvo pode vir entre aspas.
      await Process.run('cmd', ['/c', 'start', '', path]);
    }
  }

  @override
  Future<void> revealInFileManager(String path) async {
    if (Platform.isMacOS) {
      final isDir = await Directory(path).exists();
      if (isDir) {
        await Process.run('open', [path]);
      } else {
        await Process.run('open', ['-R', path]);
      }
    } else if (Platform.isWindows) {
      final isDir = await Directory(path).exists();
      final isFile = !isDir && await File(path).exists();
      final winPath = path.replaceAll('/', '\\');
      if (isDir) {
        await Process.run('explorer', [winPath]);
      } else if (isFile) {
        await Process.run('explorer', ['/select,$winPath']);
      } else {
        final parent = File(path).parent.path;
        if (await Directory(parent).exists()) {
          await Process.run('explorer', [parent.replaceAll('/', '\\')]);
        }
      }
    } else if (Platform.isLinux) {
      final isDir = await Directory(path).exists();
      final target = isDir ? path : File(path).parent.path;
      final xdg = await unixWhich('xdg-open') ?? 'xdg-open';
      await Process.run(xdg, [target]);
    }
  }

  // ---- macOS ----------------------------------------------------------------

  Future<List<LaunchableApp>> _probeMacOS() async {
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
    found.add(
      LaunchableApp(id: 'finder', name: 'Finder', iconPath: finderIcon),
    );
    return found;
  }

  Future<void> _launchMacOS(LaunchableApp app, String path) async {
    if (app.id == 'finder') {
      await Process.run('open', [path]);
      return;
    }
    final c = _kCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    await Process.run('open', ['-a', c.name, path]);
  }

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
      final plist = await Process.run('defaults', [
        'read',
        '$bundlePath/Contents/Info',
        'CFBundleIconFile',
      ]);
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
        '-s',
        'format',
        'png',
        '-z',
        '32',
        '32',
        icnsPath,
        '--out',
        outPath,
      ]);
      return sips.exitCode == 0 ? outPath : null;
    } catch (_) {
      return null;
    }
  }

  // ---- Windows --------------------------------------------------------------

  Future<List<LaunchableApp>> _probeWindows() async {
    final found = <LaunchableApp>[];
    for (final c in _kWinCandidates) {
      if (await _findWindowsExe(c) != null) {
        found.add(LaunchableApp(id: c.id, name: c.name));
      }
    }
    // Explorer — equivalente do Finder, sempre disponível no Windows.
    found.add(const LaunchableApp(id: 'explorer', name: 'Explorer'));
    return found;
  }

  Future<void> _launchWindows(LaunchableApp app, String path) async {
    if (app.id == 'explorer') {
      // explorer.exe abre a pasta; ignora o exit code (retorna 1 mesmo no ok).
      await Process.run('explorer', [path]);
      return;
    }
    final c = _kWinCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    final exe = await _findWindowsExe(c);
    if (exe == null) return;
    // IDE abre a pasta como workspace; detached pra não prender o app.
    await Process.start(exe, [path], mode: ProcessStartMode.detached);
  }

  /// Primeiro `.exe` candidato que existir no disco, ou `null`.
  Future<String?> _findWindowsExe(_WinCandidate c) async {
    for (final (envVar, sub) in c.exeCandidates) {
      final base = Platform.environment[envVar];
      if (base == null || base.isEmpty) continue;
      final exe = '$base\\$sub';
      if (await File(exe).exists()) return exe;
    }
    return null;
  }

  // ---- Linux ----------------------------------------------------------------

  Future<List<LaunchableApp>> _probeLinux() async {
    final found = <LaunchableApp>[];
    for (final c in _kLinuxCandidates) {
      if (await unixWhich(c.command) != null) {
        found.add(LaunchableApp(id: c.id, name: c.name));
      }
    }
    // Gerenciador de arquivos via `xdg-open` — equivalente do Finder/Explorer,
    // presente em praticamente todo desktop Linux (xdg-utils).
    if (await unixWhich('xdg-open') != null) {
      found.add(const LaunchableApp(id: 'files', name: 'Arquivos'));
    }
    return found;
  }

  Future<void> _launchLinux(LaunchableApp app, String path) async {
    if (app.id == 'files') {
      // Abre a pasta no gerenciador de arquivos padrão.
      final xdg = await unixWhich('xdg-open') ?? 'xdg-open';
      await Process.run(xdg, [path]);
      return;
    }
    final c = _kLinuxCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    final exe = await unixWhich(c.command) ?? c.command;
    // IDE abre a pasta como workspace; detached pra não prender o app.
    await Process.start(exe, [path], mode: ProcessStartMode.detached);
  }
}
