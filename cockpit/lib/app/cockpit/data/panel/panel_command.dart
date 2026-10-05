import 'dart:convert';

import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/shell_command.dart';

/// Executa `cockpit <line>` num shell e devolve o mapa que a página de um
/// `.panel` recebe da ponte (`{ok, code, stdout, stderr, timedOut, json,
/// error}`). É o **mesmo** caminho na aba do shell e na janela de documento:
/// só muda o [environment] (PATH com a CLI interna, socket do app), que quem
/// chama monta. Spawnar o próprio binário, em vez de reimplementar o parser da
/// CLI, garante paridade — o que funciona no terminal funciona no botão.
///
/// `json` é o stdout parseado quando é JSON (`--json`, `db query`...), senão
/// `null`. Nunca lança: falha de spawn vira `ok: false` com o stderr.
///
/// [profile] é o perfil de terminal padrão das configurações: a linha roda no
/// mesmo shell que o `+` abre (no Windows, PowerShell em vez de `cmd` quando é
/// esse o padrão), então a citação que vale no terminal vale no botão.
Future<Map<String, Object?>> runPanelCommandLine(
  String line, {
  required String cwd,
  required Map<String, String> environment,
  TerminalProfile? profile,
}) async {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return const <String, Object?>{
      'ok': false,
      'code': 2,
      'stdout': '',
      'stderr': 'cockpit: empty command',
      'error': 'cockpit: empty command',
      'json': null,
    };
  }
  final result = await runShellCommand(
    'cockpit $trimmed',
    cwd: cwd,
    environment: environment,
    profile: profile,
  );
  Object? parsed;
  final out = result.stdout.trim();
  if (out.startsWith('{') || out.startsWith('[')) {
    try {
      parsed = jsonDecode(out);
    } on FormatException {
      parsed = null;
    }
  }
  final ok = result.code == 0;
  return <String, Object?>{
    'ok': ok,
    'code': result.code,
    'stdout': result.stdout,
    'stderr': result.stderr,
    'timedOut': result.timedOut,
    'json': parsed,
    'error': ok
        ? null
        : (result.stderr.trim().isNotEmpty
              ? result.stderr.trim()
              : 'exit code ${result.code}'),
  };
}
