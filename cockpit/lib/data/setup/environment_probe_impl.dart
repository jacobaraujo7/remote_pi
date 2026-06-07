import 'dart:convert';
import 'dart:io';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/domain/contracts/environment_probe.dart';

/// Detecta o que está instalado lendo o disco e (no máximo) rodando `pi
/// --version`. Tudo é best-effort: qualquer falha de IO vira "não instalado".
class EnvironmentProbeImpl implements EnvironmentProbe {
  EnvironmentProbeImpl(this._config);

  final PiSpawnConfig _config;

  String? get _home => Platform.environment['HOME'];

  @override
  Future<bool> piInstalled() async {
    final exe = _config.executable;
    // Caminho absoluto resolvido no boot → basta existir.
    if (exe.contains('/')) {
      if (await File(exe).exists()) return true;
    }
    // 'pi' solto (PATH): tenta rodar. App macOS não herda o PATH do shell, então
    // isto pode falhar mesmo instalado — mas aí os caminhos-candidato do boot já
    // teriam achado. Best-effort.
    try {
      final result = await Process.run(exe, const ['--version']);
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
