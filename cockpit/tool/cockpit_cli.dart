// `cockpit` — CLI **interna** do Cockpit. Fica visível apenas dentro dos
// terminais que o app spawna (o app prependa `~/.cockpit/bin` no PATH só dessas
// abas) e fala com o app pelo **mesmo socket** do `cockpit-hook`
// (`COCKPIT_STATUS_SOCK` no POSIX; `COCKPIT_STATUS_PORT`+`COCKPIT_STATUS_TOKEN`
// no Windows), discriminando `type:"cmd"` no wire (request/response).
//
// Verbos:
//   cockpit send      [--tab-id <id>] <texto>     digita texto literal (sem \r)
//   cockpit send-key  [--tab-id <id>] <Key>...    pressiona tecla(s) nomeada(s)
//   cockpit list-panes      [--json]              panes ativos
//   cockpit list-workspaces [--json]              workspaces (projetos) abertos
//   cockpit install-skill   [--force]             instala a skill do Claude Code
//   cockpit --help | --version
//
// `--tab-id` default = $COCKPIT_PANE_ID (o pane que emitiu). Pane ids (t0, t1…)
// são sequenciais e **resetam a cada boot do app** → descubra-os com list-panes
// antes de mirar cross-pane.
//
// Compilar: dart compile exe tool/cockpit_cli.dart -o <dest>/cockpit-cli

import 'dart:convert';
import 'dart:io';

const String _version = '0.1.0';

Future<void> main(List<String> argv) async {
  final args = List<String>.from(argv);
  if (args.isEmpty) {
    _printHelp(stderr);
    exit(2);
  }
  final first = args.first;
  if (first == '--help' || first == '-h' || first == 'help') {
    _printHelp(stdout);
    exit(0);
  }
  if (first == '--version' || first == '-v') {
    stdout.writeln('cockpit $_version');
    exit(0);
  }

  final cmd = args.removeAt(0);
  switch (cmd) {
    case 'send':
      await _cmdSend(args);
    case 'send-key':
    case 'send-keys':
      await _cmdSendKey(args);
    case 'list-panes':
      await _cmdList('list-panes', args);
    case 'list-workspaces':
      await _cmdList('list-workspaces', args);
    case 'install-skill':
      await _cmdInstallSkill(args);
    default:
      stderr.writeln('cockpit: comando desconhecido "$cmd" (veja --help)');
      exit(2);
  }
}

// ---- comandos ---------------------------------------------------------------

Future<void> _cmdSend(List<String> args) async {
  final parsed = _Flags.parse(args);
  final text = parsed.positionals.join(' ');
  if (text.isEmpty) {
    stderr.writeln('cockpit send: falta o texto a enviar');
    exit(2);
  }
  await _writeToPane(parsed.tabId, text);
}

Future<void> _cmdSendKey(List<String> args) async {
  final parsed = _Flags.parse(args);
  if (parsed.positionals.isEmpty) {
    stderr.writeln('cockpit send-key: falta a tecla (ex.: Enter, C-c, Escape)');
    exit(2);
  }
  final buf = StringBuffer();
  for (final name in parsed.positionals) {
    final resolved = _resolveKey(name);
    if (resolved == null) {
      stderr.writeln('cockpit send-key: tecla desconhecida "$name"');
      exit(2);
    }
    buf.write(resolved);
  }
  await _writeToPane(parsed.tabId, buf.toString());
}

Future<void> _cmdList(String cmd, List<String> args) async {
  final parsed = _Flags.parse(args);
  final resp = await _request(<String, dynamic>{'cmd': cmd});
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'falhou'}');
    exit(1);
  }
  final data = (resp['data'] as List?) ?? const [];
  if (parsed.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
    exit(0);
  }
  if (data.isEmpty) {
    stdout.writeln('(nenhum)');
    exit(0);
  }
  if (cmd == 'list-panes') {
    for (final e in data.cast<Map>()) {
      final flag = e['working'] == true ? '●' : ' ';
      stdout.writeln(
        '$flag ${_pad(e['id']?.toString(), 6)} '
        '${_pad(e['kind']?.toString(), 9)} '
        '${_pad(e['workspaceId']?.toString(), 8)} ${e['title'] ?? ''}',
      );
    }
  } else {
    for (final e in data.cast<Map>()) {
      stdout.writeln(
        '${_pad(e['id']?.toString(), 10)} '
        '${_pad('${e['panes'] ?? 0} panes', 10)} ${e['name'] ?? ''}',
      );
    }
  }
  exit(0);
}

Future<void> _writeToPane(String? tabIdFlag, String text) async {
  final tabId = tabIdFlag ?? Platform.environment['COCKPIT_PANE_ID'];
  if (tabId == null || tabId.isEmpty) {
    stderr.writeln(
      'cockpit: sem alvo — passe --tab-id <id> ou rode dentro de um terminal '
      'do Cockpit (COCKPIT_PANE_ID ausente). Use `cockpit list-panes`.',
    );
    exit(2);
  }
  final resp = await _request(<String, dynamic>{
    'cmd': 'write',
    'tabId': tabId,
    'args': <String, dynamic>{'data': base64.encode(utf8.encode(text))},
  });
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'falhou'}');
    exit(1);
  }
  exit(0);
}

// ---- transporte (socket) ----------------------------------------------------

Future<Map<String, dynamic>> _request(Map<String, dynamic> req) async {
  final env = Platform.environment;
  final sock = env['COCKPIT_STATUS_SOCK'];
  final port = int.tryParse(env['COCKPIT_STATUS_PORT'] ?? '');
  if ((sock == null || sock.isEmpty) && port == null) {
    stderr.writeln(
      'cockpit: fora de um terminal do Cockpit (COCKPIT_STATUS_SOCK ausente)',
    );
    exit(3);
  }
  req['type'] = 'cmd';
  final tok = env['COCKPIT_STATUS_TOKEN'];
  if (tok != null) req['tok'] = tok;

  Socket socket;
  try {
    socket = (sock != null && sock.isNotEmpty)
        ? await Socket.connect(
            InternetAddress(sock, type: InternetAddressType.unix),
            0,
          )
        : await Socket.connect(InternetAddress.loopbackIPv4, port!);
  } catch (e) {
    stderr.writeln('cockpit: não conectou ao app: $e');
    exit(3);
  }

  socket.add(utf8.encode('${jsonEncode(req)}\n'));
  await socket.flush();
  // O servidor escreve uma linha JSON e fecha → basta juntar até o EOF.
  final raw = await socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .join()
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          socket.destroy();
          return '';
        },
      );
  socket.destroy();
  final line = raw.trim();
  if (line.isEmpty) {
    return <String, dynamic>{'ok': false, 'error': 'sem resposta do app'};
  }
  try {
    final decoded = jsonDecode(line);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'ok': false, 'error': 'resposta malformada'};
  } catch (_) {
    return <String, dynamic>{'ok': false, 'error': 'resposta malformada'};
  }
}

// ---- teclas nomeadas --------------------------------------------------------

/// Resolve um nome de tecla na sua sequência de bytes (como String de code
/// points < 128 → UTF-8 idêntico). `null` se o nome é desconhecido.
String? _resolveKey(String name) {
  switch (name.toLowerCase()) {
    case 'enter':
    case 'return':
    case 'cr':
      return '\r';
    case 'tab':
      return '\t';
    case 'escape':
    case 'esc':
      return '\x1b';
    case 'space':
      return ' ';
    case 'bspace':
    case 'backspace':
      return '\x7f';
    case 'up':
      return '\x1b[A';
    case 'down':
      return '\x1b[B';
    case 'right':
      return '\x1b[C';
    case 'left':
      return '\x1b[D';
    case 'home':
      return '\x1b[H';
    case 'end':
      return '\x1b[F';
    case 'pageup':
    case 'ppage':
      return '\x1b[5~';
    case 'pagedown':
    case 'npage':
      return '\x1b[6~';
    case 'delete':
    case 'del':
      return '\x1b[3~';
  }
  // Ctrl: C-<letra> → byte de controle (a=0x01 … z=0x1a).
  final ctrl = RegExp(r'^c-(.)$', caseSensitive: false).firstMatch(name);
  if (ctrl != null) {
    final ch = ctrl.group(1)!.toLowerCase().codeUnitAt(0);
    if (ch >= 0x61 && ch <= 0x7a) return String.fromCharCode(ch - 0x60);
  }
  // Nome de 1 caractere → literal (ex.: `cockpit send-key a`).
  if (name.length == 1) return name;
  return null;
}

// ---- flags ------------------------------------------------------------------

class _Flags {
  _Flags(this.positionals, this.tabId, this.json, this.force);
  final List<String> positionals;
  final String? tabId;
  final bool json;
  final bool force;

  static _Flags parse(List<String> args) {
    final positionals = <String>[];
    String? tabId;
    var json = false;
    var force = false;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--tab-id' || a == '-t') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --tab-id precisa de um valor');
          exit(2);
        }
        tabId = args[++i];
      } else if (a.startsWith('--tab-id=')) {
        tabId = a.substring('--tab-id='.length);
      } else if (a == '--json') {
        json = true;
      } else if (a == '--force' || a == '-f') {
        force = true;
      } else if (a == '--') {
        positionals.addAll(args.sublist(i + 1));
        break;
      } else {
        positionals.add(a);
      }
    }
    return _Flags(positionals, tabId, json, force);
  }
}

// ---- install-skill ----------------------------------------------------------

Future<void> _cmdInstallSkill(List<String> args) async {
  final parsed = _Flags.parse(args);
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    stderr.writeln('cockpit: HOME não resolvido');
    exit(1);
  }
  final dir = Directory('$home/.claude/skills/cockpit-cli');
  final file = File('${dir.path}/SKILL.md');
  if (await file.exists() && !parsed.force) {
    final current = await file.readAsString();
    if (current == _skillMarkdown) {
      stdout.writeln('cockpit: skill já instalada (${file.path})');
      exit(0);
    }
  }
  await dir.create(recursive: true);
  await file.writeAsString(_skillMarkdown);
  stdout.writeln('cockpit: skill instalada em ${file.path}');
  exit(0);
}

// ---- help -------------------------------------------------------------------

void _printHelp(IOSink out) {
  out.writeln(
    r'''cockpit — CLI interna do Cockpit (visível só nos terminais do app)

USO:
  cockpit send      [--tab-id <id>] <texto>    digita texto literal (sem Enter)
  cockpit send-key  [--tab-id <id>] <Key>...   pressiona tecla(s) nomeada(s)
  cockpit list-panes      [--json]             lista panes ativos
  cockpit list-workspaces [--json]             lista workspaces (projetos)
  cockpit install-skill   [--force]            instala a skill do Claude Code
  cockpit --help | --version

ALVO:
  --tab-id <id>   pane alvo. Default = $COCKPIT_PANE_ID (o pane atual).
                  Ids (t0, t1…) resetam a cada boot do app → descubra com
                  `cockpit list-panes` antes de mirar outro pane (cross-pane).

TECLAS (send-key):
  Enter Tab Escape Space BSpace Up Down Left Right Home End
  PageUp PageDown Delete   |   C-<letra> (ex.: C-c = Ctrl+C)

EXEMPLOS:
  cockpit send "echo oi" && cockpit send-key Enter
  cockpit send-key C-c
  cockpit send --tab-id t3 "ls" ; cockpit send-key --tab-id t3 Enter''',
  );
}

String _pad(String? s, int n) {
  final v = s ?? '';
  return v.length >= n ? v : v + ' ' * (n - v.length);
}

// ---- conteúdo da skill (versiona junto com o binário) -----------------------

const String _skillMarkdown = r'''---
name: cockpit-cli
description: Drive Cockpit's multiplexed terminals from inside a pane. Use when you (an agent running in a Cockpit terminal) need to type text or press keys into your own or another pane, or to list the open panes/workspaces. Triggers on tmux-like control needs: send-keys, run a command in another tab, discover pane ids.
---

# cockpit — CLI interna do Cockpit

Você está rodando dentro de um terminal do **Cockpit** (uma IDE que multiplexa
terminais). O comando `cockpit` fala com o app e deixa você **injetar texto/teclas**
em qualquer pane e **listar** panes/workspaces. Ele só existe dentro das abas do
Cockpit (não está no PATH global).

## Verbos

- `cockpit send [--tab-id <id>] <texto>` — digita texto literal (sem Enter).
- `cockpit send-key [--tab-id <id>] <Key>...` — pressiona tecla(s): `Enter`, `Tab`,
  `Escape`, `Space`, `BSpace`, `Up`/`Down`/`Left`/`Right`, `Home`/`End`,
  `PageUp`/`PageDown`, `Delete`, e `C-<letra>` (ex.: `C-c` = Ctrl+C).
- `cockpit list-panes [--json]` — panes ativos: `id`, `kind`, `title`,
  `workspaceId`, `working`.
- `cockpit list-workspaces [--json]` — projetos abertos: `id`, `name`, `panes`.

## Alvo (--tab-id)

Sem `--tab-id`, o comando age no **seu próprio pane** (via `$COCKPIT_PANE_ID`).
Para dirigir **outro** pane, passe `--tab-id <id>`.

> Os ids (`t0`, `t1`…) são sequenciais e **mudam a cada boot do app**. Nunca
> chute um id: rode `cockpit list-panes` primeiro e use o `id` de lá.

## Padrão de uso

Para rodar um comando num pane, **envie o texto e depois o Enter** (o `send` não
adiciona quebra de linha):

```sh
cockpit send "npm test"
cockpit send-key Enter
```

Cross-pane (dirigir outra aba):

```sh
cockpit list-panes                       # descubra o id alvo, ex.: t4
cockpit send --tab-id t4 "git status"
cockpit send-key --tab-id t4 Enter
```

Interromper um processo travado noutro pane:

```sh
cockpit send-key --tab-id t4 C-c
```

## Erros comuns

- "COCKPIT_STATUS_SOCK ausente" → você não está num terminal do Cockpit.
- "pane ... não existe" → id velho (reboot do app). Rode `list-panes` de novo.
- "pane ... não é um terminal" → o alvo é uma aba de agente/arquivo, não um shell.
''';
