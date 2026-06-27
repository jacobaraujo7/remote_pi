import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';

/// Detecta o que está instalado lendo o disco e (no máximo) rodando `pi
/// --version`. Tudo é best-effort: qualquer falha de IO vira "não instalado".
class EnvironmentProbeImpl implements EnvironmentProbe {
  EnvironmentProbeImpl(this._config);

  final PiSpawnConfig _config;

  // Windows não seta HOME; o equivalente é USERPROFILE.
  String? get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  @override
  Future<bool> piInstalled() async {
    final exe = _config.executable;
    // Caminho (não um nome solto no PATH) resolvido no boot → basta existir.
    // Detecta separador Unix (`/`) e Windows (`\`).
    if (exe.contains('/') || exe.contains(r'\')) {
      if (await File(exe).exists()) return true;
    }
    // 'pi' solto (PATH): tenta rodar. App macOS não herda o PATH do shell, então
    // isto pode falhar mesmo instalado — mas aí os caminhos-candidato do boot já
    // teriam achado. `runInShell` deixa o Windows resolver shims `.cmd`/`.bat`
    // do npm via PATHEXT. Best-effort.
    try {
      final result = await Process.run(exe, const [
        '--version',
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> extensionInstalled() async {
    final home = _home;
    if (home == null) return false;
    try {
      final file = File('$home/.pi/agent/settings.json');
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return false;
      final packages = json['packages'];
      if (packages is! List) return false;
      // Casa tanto o spec de produção (`npm:remote-pi` / `remote-pi`) quanto o
      // dev (caminho local terminando em `pi-extension`).
      return packages.whereType<String>().any((p) {
        final low = p.toLowerCase();
        return low.contains('remote-pi') || low.endsWith('pi-extension');
      });
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> supervisorInstalled() async {
    final home = _home;
    if (home == null) return false;
    try {
      // Sinal primário: o serviço foi instalado por `remote-pi install`.
      if (Platform.isMacOS) {
        final plist = File(
          '$home/Library/LaunchAgents/dev.remotepi.supervisord.plist',
        );
        if (await plist.exists()) return true;
      } else if (Platform.isLinux) {
        final unit = File(
          '$home/.config/systemd/user/remote-pi-supervisord.service',
        );
        if (await unit.exists()) return true;
      } else if (Platform.isWindows) {
        // Windows: o supervisor roda como uma Scheduled Task
        // (`RemotePiSupervisor`) criada por `remote-pi install`. A task é a
        // fonte de verdade — sobrevive a reboot e ao uninstall do .vbs.
        // Query não precisa de elevação; só o /Create precisava.
        try {
          final task = await Process.run('schtasks', const [
            '/Query',
            '/TN',
            'RemotePiSupervisor',
          ], runInShell: true);
          if (task.exitCode == 0) return true;
        } catch (_) {
          // schtasks indisponível → cai pro check de arquivo abaixo.
        }
        // Secundário: o launcher VBS escrito no install (em ~/.pi/remote/).
        final vbs = File('$home/.pi/remote/RemotePiSupervisorLauncher.vbs');
        return vbs.exists();
      }
      // Fallback: o binário existe em algum prefixo de usuário conhecido.
      const candidates = <String>[
        '/opt/homebrew/bin/pi-supervisord',
        '/usr/local/bin/pi-supervisord',
      ];
      for (final candidate in candidates) {
        if (await File(candidate).exists()) return true;
      }
      final local = '$home/.local/bin/pi-supervisord';
      return File(local).exists();
    } catch (_) {
      return false;
    }
  }
}
