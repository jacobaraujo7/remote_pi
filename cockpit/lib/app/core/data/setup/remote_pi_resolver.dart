import 'dart:io';

import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// Helpers de ambiente do usuário: HOME, diretórios app-managed em `~/.cockpit`
/// e o `node` no PATH dos subprocessos. (O nome do arquivo vem da época em que
/// também resolvia o `remote-pi`; isso saiu com o agente nativo na 2.0.)

/// `~/` do usuário: Windows não seta `HOME`, o equivalente é `USERPROFILE`.
String? remotePiHome() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

/// Onde a **CLI interna** (`cockpit`) é materializada, e o único diretório que o
/// app prefixa no PATH das suas abas.
///
/// Namespaceado por debug/release pela mesma razão do `status.sock`: `~/.cockpit`
/// é o HOME real (não é isolado por bundle id como o Hive), então uma build de
/// dev e a instalada disputariam o mesmo arquivo — quem bootasse por último
/// sobrescreveria a CLI da outra. Como o PATH é injetado por app, cada um aponta
/// pro seu diretório e o comando continua se chamando `cockpit` nos dois.
///
/// O `cockpit-hook` **não** segue este namespace: o caminho dele vai gravado no
/// `~/.claude/settings.json` (global, um só), e apontar pra uma pasta de build de
/// dev quebraria o hook no dia em que essa build sumisse.
String? cockpitCliDir() {
  final home = remotePiHome();
  if (home == null) return null;
  return '$home/.cockpit/bin${kDebugMode ? '-debug' : ''}';
}

/// Diretório estável do helper de hooks, compartilhado entre builds.
String? cockpitHookDir() {
  final home = remotePiHome();
  if (home == null) return null;
  return '$home/.cockpit/bin';
}

/// Resolve o `node` em caminhos conhecidos (mesma estratégia do `pi`).
/// Cacheado por processo: a resolução via `which` num shell de login pode
/// levar segundos (carrega o `.zshrc`) e o resultado é estável.
Future<String> resolveNode() => _cachedNode ??= resolveExecutable(
  'node',
  unixCandidates: const ['/opt/homebrew/bin/node', '/usr/local/bin/node'],
  unixHomeRelative: const ['.local/bin/node'],
  windowsExtraDirs: const [r'C:\Program Files\nodejs'],
);

Future<String>? _cachedNode;

/// Diretório onde o `node` resolvido mora (geralmente o mesmo bin do `pi`/`npm`/
/// `remote-pi`). `null` se o node não foi resolvido pra um caminho.
Future<String?> resolveNodeBinDir() async {
  final node = await resolveNode();
  final idx = node.lastIndexOf(RegExp(r'[/\\]'));
  return idx > 0 ? node.substring(0, idx) : null;
}

/// Environment do processo com o bin do `node` **prefixado** na PATH. Necessário
/// pra rodar shims `pi`/`remote-pi`, cujo shebang `#!/usr/bin/env node` precisa
/// achar o `node` — que em setups nvm/Homebrew não está na PATH herdada pelo app
/// GUI (erro `/usr/bin/env: 'node': No such file or directory`).
Future<Map<String, String>> envWithNodeOnPath() async {
  final env = Map<String, String>.of(Platform.environment);
  final dir = await resolveNodeBinDir();
  if (dir != null) {
    final sep = Platform.isWindows ? ';' : ':';
    // Windows usa 'Path'; POSIX usa 'PATH'.
    final key = env.containsKey('Path') && !env.containsKey('PATH')
        ? 'Path'
        : 'PATH';
    final cur = env[key] ?? '';
    if (!cur.split(sep).contains(dir)) {
      env[key] = cur.isEmpty ? dir : '$dir$sep$cur';
    }
  }
  return env;
}
