// `cockpit` — CLI **interna** do Cockpit. Fica visível apenas dentro dos
// terminais que o app spawna (o app prependa `~/.cockpit/bin` no PATH só dessas
// abas) e fala com o app pelo **mesmo socket** do `cockpit-hook`
// (`COCKPIT_STATUS_SOCK` no POSIX; `COCKPIT_STATUS_PORT`+`COCKPIT_STATUS_TOKEN`
// no Windows), discriminando `type:"cmd"` no wire (request/response).
//
// Nomenclatura: a unidade que a CLI endereça é uma **tab** (uma sessão de
// terminal/agente). Um **pane** é a folha do split que agrupa várias tabs — a
// CLI não o endereça. Por isso o vocabulário é "tab"; `list-panes`/`read-pane`
// e `COCKPIT_PANE_ID` ficam como **aliases legados** dos novos `list-tabs`/
// `read-tab`/`COCKPIT_TAB_ID`.
//
// Verbos:
//   cockpit send      [--tab-id <id>] <texto>     digita texto literal (sem \r)
//   cockpit send-key  [--tab-id <id>] <Key>...    pressiona tecla(s) nomeada(s)
//   cockpit open      [--tab-id <id>] <arquivo>   abre o arquivo no viewer
//   cockpit <arquivo>                             atalho de `open`
//   cockpit read-tab  [<label|tab-id>] [--lines N] [--offset N] [--from-start]
//                                                 lê o output de uma tab
//                                                 (alias: read-pane)
//   cockpit read-task <task-id> [--lines N] [--offset N] [--from-start]
//                                                 lê o output de uma task
//   cockpit list-tabs       [--json]              tabs ativas (alias: list-panes)
//   cockpit list-workspaces [--json]              workspaces (projetos) abertos
//   cockpit list-tasks      [--json]              tasks do workspace da tab
//   cockpit install-skill   [--force]             instala a skill do Claude Code
//   cockpit --help | --version
//
// `--tab-id` default = $COCKPIT_TAB_ID (a tab que emitiu; fallback: o legado
// $COCKPIT_PANE_ID). Tab ids (t0, t1…) são sequenciais e **resetam a cada boot
// do app** → descubra-os com list-tabs antes de mirar cross-tab.
//
// Compilar: dart compile exe tool/cockpit_cli.dart -o <dest>/cockpit-cli

import 'dart:convert';
import 'dart:io';

const String _version = '0.5.0';

/// Id da própria tab: `COCKPIT_TAB_ID` (novo) com fallback pro legado
/// `COCKPIT_PANE_ID`. O app injeta os dois; o fallback cobre binário novo com
/// app antigo (só PANE_ID) e vice-versa.
String? _selfTabId() =>
    Platform.environment['COCKPIT_TAB_ID'] ??
    Platform.environment['COCKPIT_PANE_ID'];

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
    case 'open':
      await _cmdOpen(args);
    case 'list-tabs':
    case 'list-panes': // alias legado
      // Mantém o comando de wire 'list-panes' (protocolo estável); só o nome do
      // verbo mudou na superfície.
      await _cmdList('list-panes', args);
    case 'list-workspaces':
      await _cmdList('list-workspaces', args);
    case 'list-tasks':
      await _cmdList('list-tasks', args);
    case 'read-tab':
    case 'read-pane': // alias legado
      await _cmdRead('read-pane', args);
    case 'read-task':
      await _cmdRead('read-task', args);
    case 'db':
      await _cmdDb(args);
    case 'redis':
      await _cmdRedis(args);
    case 'mongo':
      await _cmdMongo(args);
    case 'new-tab':
      await _cmdNewTab(args);
    case 'install-skill':
      await _cmdInstallSkill(args);
    default:
      // Atalho: `cockpit <arquivo>` (sem verbo) abre o arquivo — o token
      // desconhecido é tratado como caminho. `cockpit open <arquivo>` é a
      // forma explícita.
      await _cmdOpen([cmd, ...args]);
  }
}

// ---- comandos ---------------------------------------------------------------

Future<void> _cmdSend(List<String> args) async {
  final parsed = _Flags.parse(args);
  final text = parsed.positionals.join(' ');
  if (text.isEmpty) {
    stderr.writeln('cockpit send: missing text to send');
    exit(2);
  }
  await _writeToTab(parsed.tabId, text);
}

Future<void> _cmdSendKey(List<String> args) async {
  final parsed = _Flags.parse(args);
  if (parsed.positionals.isEmpty) {
    stderr.writeln('cockpit send-key: missing key (e.g. Enter, C-c, Escape)');
    exit(2);
  }
  final buf = StringBuffer();
  for (final name in parsed.positionals) {
    final resolved = _resolveKey(name);
    if (resolved == null) {
      stderr.writeln('cockpit send-key: unknown key "$name"');
      exit(2);
    }
    buf.write(resolved);
  }
  await _writeToTab(parsed.tabId, buf.toString());
}

Future<void> _cmdOpen(List<String> args) async {
  final parsed = _Flags.parse(args);
  if (parsed.positionals.isEmpty) {
    stderr.writeln('cockpit open: missing file path');
    exit(2);
  }
  // O app tem cwd próprio — resolve pro caminho absoluto no cwd deste pane
  // (onde a CLI está rodando) antes de mandar.
  final abs = _resolvePath(parsed.positionals.first);
  final tabId = parsed.tabId ?? _selfTabId();
  final req = <String, dynamic>{
    'cmd': 'open',
    'args': <String, dynamic>{'path': abs},
  };
  if (tabId != null && tabId.isNotEmpty) req['tabId'] = tabId;
  final resp = await _request(req);
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  exit(0);
}

/// `cockpit new-tab [--cwd <dir>] [--title <name>] [--split h|v]` — cria uma
/// aba de terminal no app. `--cwd` default = o cwd atual; `--title` vira o
/// rótulo estável da aba (endereçável por `read-tab <title>`); sem `--split` a
/// aba nasce na mesma pane; `h`/`right` divide lado a lado, `v`/`down` empilha
/// (semântica tmux). Imprime o id da tab criada (`t12`) no stdout.
Future<void> _cmdNewTab(List<String> args) async {
  String? cwd;
  String? title;
  String? split;
  String? tabId;
  var json = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? take(String flag) {
      if (a == flag) return ++i < args.length ? args[i] : null;
      if (a.startsWith('$flag=')) return a.substring(flag.length + 1);
      return null;
    }

    if (a == '--help' || a == '-h') {
      stdout.writeln(
        'cockpit new-tab [--cwd <dir>] [--title <name>] [--split h|v]\n'
        '  --cwd    working directory (default: current directory)\n'
        '  --title  stable tab label (read-tab/send can target it)\n'
        '  --split  h|right = side by side, v|down = stacked; omit = new tab\n'
        '           in the same pane\n'
        '  Prints the new tab id (e.g. t12).',
      );
      exit(0);
    }
    if (a == '--json') {
      json = true;
      continue;
    }
    cwd = take('--cwd') ?? cwd;
    title = take('--title') ?? title;
    split = take('--split') ?? split;
    tabId = take('--tab-id') ?? tabId;
  }
  final String? wireSplit;
  switch (split?.toLowerCase()) {
    case null:
      wireSplit = null;
    case 'h' || 'horizontal' || 'right':
      wireSplit = 'right';
    case 'v' || 'vertical' || 'down':
      wireSplit = 'down';
    default:
      stderr.writeln(
        'cockpit new-tab: invalid --split "$split" (use h|right or v|down)',
      );
      exit(2);
  }
  final req = <String, dynamic>{
    'cmd': 'new-tab',
    'args': <String, dynamic>{
      'cwd': _resolvePath(cwd ?? Directory.current.path),
      if (title != null && title.isNotEmpty) 'title': title,
      'split': ?wireSplit,
    },
  };
  final tid = tabId ?? _selfTabId();
  if (tid != null && tid.isNotEmpty) req['tabId'] = tid;
  final resp = await _request(req);
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  final data = (resp['data'] as Map?) ?? const {};
  stdout.writeln(json ? jsonEncode(data) : (data['tabId'] ?? '').toString());
  exit(0);
}

/// Expande `~` e resolve caminhos relativos contra o cwd atual → absoluto.
String _resolvePath(String path) {
  var p = path;
  if (p == '~' || p.startsWith('~/')) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      p = p == '~' ? home : '$home/${p.substring(2)}';
    }
  }
  return File(p).absolute.path;
}

Future<void> _cmdList(String cmd, List<String> args) async {
  final parsed = _Flags.parse(args);
  final req = <String, dynamic>{'cmd': cmd};
  // `list-tasks` lista as tasks do workspace da tab emissora (ou da `--tab-id`
  // passada); os outros list-* ignoram o campo — mandar sempre é inofensivo.
  final tabId = parsed.tabId ?? _selfTabId();
  if (tabId != null && tabId.isNotEmpty) req['tabId'] = tabId;
  final resp = await _request(req);
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  final data = (resp['data'] as List?) ?? const [];
  if (parsed.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
    exit(0);
  }
  if (data.isEmpty) {
    stdout.writeln('(none)');
    exit(0);
  }
  if (cmd == 'list-panes') {
    // (comando de wire estável; a superfície é `list-tabs`)
    for (final e in data.cast<Map>()) {
      final flag = e['working'] == true ? '●' : ' ';
      // Rótulo manual (nome estável) vence o título dinâmico; `⚲` sinaliza que
      // está travado. Sem rótulo, mostra o título automático.
      final label = e['label'];
      final name = (label is String && label.isNotEmpty)
          ? '⚲ $label'
          : (e['title'] ?? '').toString();
      // Workspace: basename do path (legível) — o `workspaceId` virou UUID
      // opaco. `workspacePath` ausente = app antigo → mostra o id mesmo.
      final wsPath = e['workspacePath']?.toString();
      final ws = (wsPath != null && wsPath.isNotEmpty)
          ? _basename(wsPath)
          : (e['workspaceId'] ?? '').toString();
      stdout.writeln(
        '$flag ${_pad(e['id']?.toString(), 6)} '
        '${_pad(e['kind']?.toString(), 9)} '
        '${_pad(ws, 14)} $name',
      );
    }
  } else if (cmd == 'list-tasks') {
    for (final e in data.cast<Map>()) {
      final flag = e['running'] == true ? '●' : ' ';
      // `[output]` = já rodou neste boot → `read-task <id>` tem o que ler.
      final out = e['hasOutput'] == true ? '  [output]' : '';
      stdout.writeln(
        '$flag ${_pad(e['id']?.toString(), 16)} '
        '${_pad(e['source']?.toString(), 9)} '
        '${e['label'] ?? ''}$out',
      );
    }
  } else {
    for (final e in data.cast<Map>()) {
      // `tabs` é o campo novo; `panes` fica como fallback (app antigo).
      final n = e['tabs'] ?? e['panes'] ?? 0;
      // Nome + path (o `id` virou UUID opaco e não é endereçável pela CLI —
      // no JSON ele continua íntegro pra quem precisar).
      stdout.writeln(
        '${_pad(e['name']?.toString(), 18)} '
        '${_pad('$n tabs', 9)} ${e['path'] ?? ''}',
      );
    }
  }
  exit(0);
}

Future<void> _writeToTab(String? tabIdFlag, String text) async {
  final tabId = tabIdFlag ?? _selfTabId();
  if (tabId == null || tabId.isEmpty) {
    stderr.writeln(
      'cockpit: no target — pass --tab-id <id> or run inside a Cockpit '
      'terminal (COCKPIT_TAB_ID is unset). Use `cockpit list-tabs`.',
    );
    exit(2);
  }
  final resp = await _request(<String, dynamic>{
    'cmd': 'write',
    'tabId': tabId,
    'args': <String, dynamic>{'data': base64.encode(utf8.encode(text))},
  });
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  exit(0);
}

/// `read-pane [<label|tab-id>]` / `read-task <task-id>` — lê uma janela do
/// output do alvo. `--lines N` (default 100), `--offset N` (pula N a partir da
/// âncora), `--from-start` (âncora no começo; default = tail). A saída é sempre
/// cronológica (de cima pra baixo) — as flags só escolhem a janela. Payload
/// volta base64 numa linha (framing do socket é uma-linha-por-conexão).
Future<void> _cmdRead(String cmd, List<String> args) async {
  final parsed = _Flags.parse(args);
  final target = parsed.positionals.isNotEmpty ? parsed.positionals.first : '';
  if (cmd == 'read-task' && target.isEmpty) {
    stderr.writeln('cockpit read-task: missing task id');
    exit(2);
  }
  final req = <String, dynamic>{
    'cmd': cmd,
    'args': <String, dynamic>{
      if (target.isNotEmpty) 'target': target,
      if (parsed.lines != null) 'lines': parsed.lines,
      if (parsed.offset != null) 'offset': parsed.offset,
      if (parsed.fromStart) 'fromStart': true,
    },
  };
  // Sem alvo posicional, o server cai na própria tab ($COCKPIT_TAB_ID).
  final tabId = parsed.tabId ?? _selfTabId();
  if (tabId != null && tabId.isNotEmpty) req['tabId'] = tabId;
  final resp = await _request(req);
  if (resp['ok'] != true) {
    stderr.writeln('cockpit: ${resp['error'] ?? 'failed'}');
    exit(1);
  }
  final data = (resp['data'] as Map?) ?? const {};
  String text;
  try {
    text = utf8.decode(base64.decode((data['text'] ?? '').toString()));
  } catch (_) {
    stderr.writeln('cockpit: malformed payload');
    exit(1);
  }
  if (text.isNotEmpty) stdout.writeln(text);
  if (data['truncated'] == true) {
    stderr.writeln(
      'cockpit: output truncated (server cap 2000 lines/read — page with '
      '--offset)',
    );
  }
  exit(0);
}

// ---- transporte (socket) ----------------------------------------------------

Future<Map<String, dynamic>> _request(
  Map<String, dynamic> req, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final env = Platform.environment;
  final sock = env['COCKPIT_STATUS_SOCK'];
  final port = int.tryParse(env['COCKPIT_STATUS_PORT'] ?? '');
  if ((sock == null || sock.isEmpty) && port == null) {
    stderr.writeln(
      'cockpit: not inside a Cockpit terminal (COCKPIT_STATUS_SOCK is unset)',
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
    stderr.writeln('cockpit: could not connect to app: $e');
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
        timeout,
        onTimeout: () {
          socket.destroy();
          return '';
        },
      );
  socket.destroy();
  final line = raw.trim();
  if (line.isEmpty) {
    return <String, dynamic>{'ok': false, 'error': 'no response from app'};
  }
  try {
    final decoded = jsonDecode(line);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'ok': false, 'error': 'malformed response'};
  } catch (_) {
    return <String, dynamic>{'ok': false, 'error': 'resposta malformada'};
  }
}

// ---- db (plano 51) ----------------------------------------------------------

/// Kinds estáveis que o app devolve prefixados em `fail("<kind>: <msg>")` —
/// reconstruímos o JSON `{"error":{kind,message}}` do contrato da CLI.
const _dbErrorKinds = {
  'connection_failed',
  'query_failed',
  'timeout',
  'unsupported_engine',
  'unknown_connection',
  'password_required',
};

/// `cockpit db <list|schema|query|run|execute>` — database access for agents.
/// Saída é SEMPRE uma linha JSON: `{"ok": …}` ou `{"error":{kind,message}}`
/// (exit 1). Quem executa é o app (mesmo motor da tab `.dbq`); a credencial
/// nunca passa por aqui. Workspace = pane atual, ou `--workspace <id|path>`.
Future<void> _cmdDb(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _printDbHelp(args.isEmpty ? stderr : stdout);
    exit(args.isEmpty ? 2 : 0);
  }
  final sub = args.removeAt(0);

  String? db;
  String? sql;
  String? limit;
  String? table;
  String? workspace;
  String? tabId;
  final positionals = <String>[];
  String? pending;
  for (final a in args) {
    if (pending != null) {
      switch (pending) {
        case '--db':
          db = a;
        case '--sql':
          sql = a;
        case '--limit':
          limit = a;
        case '--table':
          table = a;
        case '--workspace':
          workspace = a;
        case '--tab-id':
          tabId = a;
      }
      pending = null;
      continue;
    }
    if (const {
      '--db',
      '--sql',
      '--limit',
      '--table',
      '--workspace',
      '--tab-id',
    }.contains(a)) {
      pending = a;
      continue;
    }
    final eq = a.indexOf('=');
    if (a.startsWith('--') && eq > 0) {
      final key = a.substring(0, eq);
      final value = a.substring(eq + 1);
      switch (key) {
        case '--db':
          db = value;
        case '--sql':
          sql = value;
        case '--limit':
          limit = value;
        case '--table':
          table = value;
        case '--workspace':
          workspace = value;
        case '--tab-id':
          tabId = value;
        default:
          _dbFail('error', 'unknown flag "$key" (see `cockpit db --help`)');
      }
      continue;
    }
    positionals.add(a);
  }
  if (pending != null) _dbFail('error', 'missing value for $pending');

  final cmdArgs = <String, dynamic>{'workspace': ?workspace};
  final String wire;
  switch (sub) {
    case 'list':
      wire = 'db-list';
    case 'schema':
      wire = 'db-schema';
      if (db == null) _dbFail('error', 'missing --db <name>');
      cmdArgs['db'] = db;
      final t = table ?? (positionals.isEmpty ? null : positionals.first);
      if (t != null) cmdArgs['table'] = t;
    case 'query':
    case 'execute':
      wire = sub == 'query' ? 'db-query' : 'db-execute';
      if (db == null) _dbFail('error', 'missing --db <name>');
      final statement = sql ?? positionals.join(' ');
      if (statement.trim().isEmpty) {
        _dbFail('error', 'missing --sql "<statement>"');
      }
      cmdArgs['db'] = db;
      cmdArgs['sql'] = statement;
      if (limit != null) cmdArgs['limit'] = limit;
    case 'run':
      wire = 'db-run';
      if (positionals.isEmpty) _dbFail('error', 'missing <file.dbq>');
      cmdArgs['path'] = _resolvePath(positionals.first);
    default:
      _dbFail('error', 'unknown subcommand "$sub" (see `cockpit db --help`)');
  }

  final req = <String, dynamic>{'cmd': wire, 'args': cmdArgs};
  final tid = tabId ?? _selfTabId();
  if (tid != null && tid.isNotEmpty) req['tabId'] = tid;
  // Timeout folgado: o app corta a query em 30s; a folga cobre fila + IO.
  final resp = await _request(req, timeout: const Duration(seconds: 60));
  if (resp['ok'] == true) {
    stdout.writeln(jsonEncode({'ok': resp['data']}));
    exit(0);
  }
  final raw = (resp['error'] ?? 'failed').toString();
  final sep = raw.indexOf(': ');
  final kind = sep > 0 ? raw.substring(0, sep) : '';
  if (_dbErrorKinds.contains(kind)) {
    _dbFail(kind, raw.substring(sep + 2));
  }
  _dbFail('error', raw);
}

/// `cockpit redis --db <conn> <COMMAND> [args...]` — Redis/cache (CLI-only).
/// Saída: 1 linha JSON `{"ok": <reply>}` / `{"error":{kind,message}}`.
/// `cockpit redis browse --db <conn> [--pattern '<glob>']` abre a tabela de
/// chaves no app (view pro humano — não devolve dados).
Future<void> _cmdRedis(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    stdout.writeln(
      'cockpit redis --db <conn> <COMMAND> [args...]\n'
      '  e.g. cockpit redis --db cache GET session:42\n'
      '  Output: one JSON line. Connection registered in the Database panel.\n'
      "cockpit redis browse --db <conn> [--pattern 'user:*']\n"
      '  Opens the key table in the app, pre-filtered. Opens a view — '
      'returns no data.',
    );
    exit(args.isEmpty ? 2 : 0);
  }
  if (args.first == 'browse') {
    await _cmdBrowse('redis-browse', args.sublist(1));
    return;
  }
  String? db;
  String? workspace;
  String? tabId;
  final parts = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--db') {
      db = ++i < args.length ? args[i] : null;
    } else if (a.startsWith('--db=')) {
      db = a.substring(5);
    } else if (a == '--workspace') {
      workspace = ++i < args.length ? args[i] : null;
    } else if (a.startsWith('--workspace=')) {
      workspace = a.substring(12);
    } else if (a == '--tab-id') {
      tabId = ++i < args.length ? args[i] : null;
    } else {
      parts.add(a);
    }
  }
  if (db == null) _dbFail('error', 'missing --db <conn>');
  if (parts.isEmpty) _dbFail('error', 'missing Redis command');
  await _nosqlRequest('redis-cmd', {
    'db': db,
    'parts': parts,
    'workspace': ?workspace,
  }, tabId);
}

/// `cockpit mongo --db <conn> --command '<json>'` — MongoDB (CLI-only). O
/// comando é um documento runCommand (`{"find":"users","filter":{}}`).
/// `cockpit mongo browse --db <conn> <collection> [--filter '<json>']` abre o
/// collection browser no app (view pro humano — não devolve documentos).
Future<void> _cmdMongo(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    stdout.writeln(
      "cockpit mongo --db <conn> --command '<json>'\n"
      "  e.g. cockpit mongo --db app --command '{\"find\":\"users\",\"filter\":{}}'\n"
      '  The command is a MongoDB runCommand document. Output: one JSON line.\n'
      "cockpit mongo browse --db <conn> <collection> [--filter '<json>']\n"
      '  Opens the collection browser in the app, pre-filtered. Opens a '
      'view — returns no documents.',
    );
    exit(args.isEmpty ? 2 : 0);
  }
  if (args.first == 'browse') {
    await _cmdBrowse('mongo-browse', args.sublist(1));
    return;
  }
  String? db;
  String? command;
  String? workspace;
  String? tabId;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? take(String flag) {
      if (a == flag) return ++i < args.length ? args[i] : null;
      if (a.startsWith('$flag=')) return a.substring(flag.length + 1);
      return null;
    }

    db = take('--db') ?? db;
    command = take('--command') ?? command;
    workspace = take('--workspace') ?? workspace;
    tabId = take('--tab-id') ?? tabId;
  }
  if (db == null) _dbFail('error', 'missing --db <conn>');
  if (command == null || command.trim().isEmpty) {
    _dbFail('error', "missing --command '<json>'");
  }
  await _nosqlRequest('mongo-cmd', {
    'db': db,
    'command': command,
    'workspace': ?workspace,
  }, tabId);
}

/// `… browse` (plano 53): abre a view de browse no app. [wire] =
/// `redis-browse` (`--pattern`) ou `mongo-browse` (positional `<collection>` +
/// `--filter`).
Future<void> _cmdBrowse(String wire, List<String> args) async {
  String? db;
  String? workspace;
  String? tabId;
  String? pattern;
  String? filter;
  final positionals = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? take(String flag) {
      if (a == flag) return ++i < args.length ? args[i] : null;
      if (a.startsWith('$flag=')) return a.substring(flag.length + 1);
      return null;
    }

    if (a == '--help' || a == '-h') {
      stdout.writeln(
        wire == 'redis-browse'
            ? "cockpit redis browse --db <conn> [--pattern 'user:*']"
            : "cockpit mongo browse --db <conn> <collection> "
                  "[--filter '<json>']",
      );
      exit(0);
    }
    db = take('--db') ?? db;
    workspace = take('--workspace') ?? workspace;
    tabId = take('--tab-id') ?? tabId;
    pattern = take('--pattern') ?? pattern;
    filter = take('--filter') ?? filter;
    if (!a.startsWith('--')) positionals.add(a);
  }
  if (db == null) _dbFail('error', 'missing --db <conn>');
  final cmdArgs = <String, dynamic>{'db': db, 'workspace': ?workspace};
  if (wire == 'mongo-browse') {
    if (positionals.isEmpty) _dbFail('error', 'missing <collection>');
    cmdArgs['collection'] = positionals.first;
    if (filter != null) cmdArgs['filter'] = filter;
  } else if (pattern != null) {
    cmdArgs['pattern'] = pattern;
  }
  await _nosqlRequest(wire, cmdArgs, tabId);
}

/// Envia um comando NoSQL e imprime `{"ok": ...}` / `{"error": ...}`.
Future<void> _nosqlRequest(
  String wire,
  Map<String, dynamic> cmdArgs,
  String? tabId,
) async {
  final req = <String, dynamic>{'cmd': wire, 'args': cmdArgs};
  final tid = tabId ?? _selfTabId();
  if (tid != null && tid.isNotEmpty) req['tabId'] = tid;
  final resp = await _request(req, timeout: const Duration(seconds: 60));
  if (resp['ok'] == true) {
    stdout.writeln(jsonEncode({'ok': resp['data']}));
    exit(0);
  }
  final raw = (resp['error'] ?? 'failed').toString();
  final sep = raw.indexOf(': ');
  final kind = sep > 0 ? raw.substring(0, sep) : '';
  if (_dbErrorKinds.contains(kind)) {
    _dbFail(kind, raw.substring(sep + 2));
  }
  _dbFail('error', raw);
}

Never _dbFail(String kind, String message) {
  stdout.writeln(
    jsonEncode({
      'error': {'kind': kind, 'message': message},
    }),
  );
  exit(1);
}

void _printDbHelp(IOSink out) {
  out.writeln(
    r'''cockpit db — query the workspace's databases (agent-friendly JSON)

Connections are registered per workspace in .cockpit/databases.json (Database
panel in the app); SQLite files found in the repo are auto-detected. The app
executes every statement — credentials never reach this CLI.

USAGE:
  cockpit db list                                  registered + detected connections
  cockpit db schema  --db <name> [<table>]         tables, or a table's columns
  cockpit db query   --db <name> --sql "<SELECT…>" [--limit N]   run a query
  cockpit db execute --db <name> --sql "<DML…>"    run DML, returns affectedRows
  cockpit db run <file.dbq>                        run a .dbq file (frontmatter picks the db)

FLAGS:
  --workspace <id|path>   target workspace when not inside a Cockpit pane
  --limit N               row cap for query (default 200; "truncated" flags the cut)

OUTPUT (single JSON line; exit 1 on error):
  {"ok":{"columns":[{"name","type"}],"rows":[[…]],"rowCount":N,"truncated":false,"elapsedMs":12}}
  {"error":{"kind":"unknown_connection","message":"…"}}

.dbq FILES:
  SQL with comment frontmatter — agents write them, the app renders them as a
  query tab (editor + result grid) and re-runs on save:
    -- db: dev-local
    -- limit: 100
    SELECT * FROM orders ORDER BY created_at DESC;''',
  );
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
  _Flags(
    this.positionals,
    this.tabId,
    this.json,
    this.force,
    this.lines,
    this.offset,
    this.fromStart,
  );
  final List<String> positionals;
  final String? tabId;
  final bool json;
  final bool force;
  final int? lines;
  final int? offset;
  final bool fromStart;

  static int _intValue(String flag, String raw) {
    final v = int.tryParse(raw);
    if (v == null || v < 0) {
      stderr.writeln('cockpit: $flag requires a non-negative integer');
      exit(2);
    }
    return v;
  }

  static _Flags parse(List<String> args) {
    final positionals = <String>[];
    String? tabId;
    var json = false;
    var force = false;
    int? lines;
    int? offset;
    var fromStart = false;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--lines' || a == '-n') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --lines requires a value');
          exit(2);
        }
        lines = _intValue('--lines', args[++i]);
      } else if (a.startsWith('--lines=')) {
        lines = _intValue('--lines', a.substring('--lines='.length));
      } else if (a == '--offset') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --offset requires a value');
          exit(2);
        }
        offset = _intValue('--offset', args[++i]);
      } else if (a.startsWith('--offset=')) {
        offset = _intValue('--offset', a.substring('--offset='.length));
      } else if (a == '--from-start') {
        fromStart = true;
      } else if (a == '--tab-id' || a == '-t') {
        if (i + 1 >= args.length) {
          stderr.writeln('cockpit: --tab-id requires a value');
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
    return _Flags(positionals, tabId, json, force, lines, offset, fromStart);
  }
}

// ---- install-skill ----------------------------------------------------------

Future<void> _cmdInstallSkill(List<String> args) async {
  final parsed = _Flags.parse(args);
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    stderr.writeln('cockpit: HOME not resolved');
    exit(1);
  }
  final dir = Directory('$home/.claude/skills/cockpit-cli');
  final file = File('${dir.path}/SKILL.md');
  if (await file.exists() && !parsed.force) {
    final current = await file.readAsString();
    if (current == _skillMarkdown) {
      stdout.writeln('cockpit: skill already installed (${file.path})');
      exit(0);
    }
  }
  await dir.create(recursive: true);
  await file.writeAsString(_skillMarkdown);
  stdout.writeln('cockpit: skill installed at ${file.path}');
  exit(0);
}

// ---- help -------------------------------------------------------------------

void _printHelp(IOSink out) {
  out.writeln(
    r'''cockpit — Cockpit's internal CLI (visible only inside the app's terminals)

A **tab** is a terminal/agent session (what this CLI addresses). A **pane** is
the split leaf that groups tabs — not addressed here. `list-panes`/`read-pane`
are legacy aliases of `list-tabs`/`read-tab`.

USAGE:
  cockpit send      [--tab-id <id>] <text>     type literal text (no Enter)
  cockpit send-key  [--tab-id <id>] <Key>...   press named key(s)
  cockpit open      [--tab-id <id>] <file>     open the file in the app's viewer
  cockpit <file>                               shortcut for `open` (e.g. cockpit .zprofile)
  cockpit read-tab  [<label|tab-id>]           read a tab's rendered output (alias: read-pane)
  cockpit read-task <task-id>                  read a task's output (even w/o tab)
  cockpit list-tabs       [--json]             list active tabs (alias: list-panes)
  cockpit list-workspaces [--json]             list workspaces (projects)
  cockpit list-tasks      [--json]             list this workspace's tasks (Task Run)
  cockpit new-tab [--cwd <dir>] [--title <name>] [--split h|v]
                                               open a new terminal tab (prints its id)
  cockpit db <list|schema|query|run|execute>   SQL databases (see `cockpit db --help`)
  cockpit redis [browse] --db <conn> ...       Redis command / open key table
  cockpit mongo [browse] --db <conn> ...       MongoDB runCommand / open browser
  cockpit install-skill   [--force]            install the Claude Code skill
  cockpit --help | --version

READ (read-tab / read-task):
  --lines N     how many lines (default 100, server cap 2000)
  --offset N    skip N lines from the anchor (pagination)
  --from-start  anchor at the start of the buffer (default: tail/end)
  Output is always chronological (top→bottom); flags only pick the window.
  read-tab without a target reads the CURRENT tab; a target may be a stable
  tab label or a tab-id.

TASKS (list-tasks / read-task):
  Task ids are stable per workspace: npm:<script> (package.json), flutter:run /
  flutter:test, json:<label> (.cockpit/tasks.json). Discover them with
  `cockpit list-tasks` — `[output]` marks tasks whose output `read-task` can
  read (ran this boot); ● marks tasks running right now. Task-output tabs in
  `list-tabs --json` also carry the task id as `taskId`.

DATABASES (db):
  Connections live per workspace in .cockpit/databases.json (+ auto-detected
  SQLite files). Output is one JSON line — made for agents. Examples:
    cockpit db list
    cockpit db schema --db dev-local orders
    cockpit db query --db dev-local --sql "SELECT * FROM orders LIMIT 5"
    cockpit db run reports/daily.dbq
  Full reference: `cockpit db --help`.

IDS:
  Workspace ids are opaque UUIDs — use `workspacePath` (list-tabs) / `path`
  (list-workspaces) when you need the folder on disk.

TARGET:
  --tab-id <id>   target tab. Default = $COCKPIT_TAB_ID (the current tab;
                  legacy fallback $COCKPIT_PANE_ID). Ids (t0, t1…) reset on every
                  app boot → find them with `cockpit list-tabs` before targeting
                  another tab (cross-tab).

KEYS (send-key):
  Enter Tab Escape Space BSpace Up Down Left Right Home End
  PageUp PageDown Delete   |   C-<letter> (e.g. C-c = Ctrl+C)

NEW-TAB:
  --cwd <dir>     working directory (default: current directory)
  --title <name>  stable tab label (send/read-tab can target it by name)
  --split h|v     h (or right) = side by side; v (or down) = stacked.
                  Omit to open as a new tab in the same pane.
  Anchored at the emitting tab's pane/workspace. Prints the new tab id.

EXAMPLES:
  cockpit send "echo hi" && cockpit send-key Enter
  id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
  cockpit send --tab-id "$id" "npm test" && cockpit send-key --tab-id "$id" Enter
  cockpit send-key C-c
  cockpit send --tab-id t3 "ls" ; cockpit send-key --tab-id t3 Enter
  cockpit .zprofile          # opens the file in the viewer (relative to tab cwd)
  cockpit open ~/.gitconfig
  cockpit read-tab Extension --lines 50        # last 50 lines of tab "Extension"
  cockpit read-tab t4 --lines 200 --from-start
  cockpit list-tasks                           # discover task ids (npm:dev, ...)
  cockpit read-task npm:dev --lines 80         # tail of task "npm:dev" output''',
  );
}

String _pad(String? s, int n) {
  final v = s ?? '';
  return v.length >= n ? v : v + ' ' * (n - v.length);
}

String _basename(String path) {
  final parts = path
      .split(Platform.isWindows ? RegExp(r'[\\/]') : '/')
      .where((p) => p.isNotEmpty)
      .toList();
  return parts.isEmpty ? path : parts.last;
}

// ---- conteúdo da skill (versiona junto com o binário) -----------------------

const String _skillMarkdown = r'''---
name: cockpit-cli
description: Drive Cockpit's multiplexed terminals from inside a tab. Use when you (an agent running in a Cockpit terminal) need to open a new terminal tab or split pane, type text or press keys into your own or another tab, read another tab's or a task's output, list the open tabs/workspaces/tasks, or query the workspace's databases (SQL over registered connections / .dbq files). Triggers on tmux-like control needs — split-window/new-window, send-keys, run a command in another tab, read a tab's scrollback, inspect a task run's output, discover tab or task ids — and on database needs: run a SQL query, inspect a schema, list connections, execute a .dbq file.
---

# cockpit — Cockpit's internal CLI

You are running inside a **Cockpit** terminal (an IDE that multiplexes
terminals). The `cockpit` command talks to the app and lets you **inject
text/keys** into any tab and **list** tabs/workspaces. It only exists inside
Cockpit tabs (it is not on the global PATH).

> **Tab vs pane.** A **tab** is a single terminal/agent session — that's the
> unit this CLI addresses (`--tab-id`). A **pane** is the split leaf that can
> hold several tabs; the CLI does not address it. `list-panes`/`read-pane` and
> `$COCKPIT_PANE_ID` are **legacy aliases** of `list-tabs`/`read-tab`/
> `$COCKPIT_TAB_ID` — prefer the new names.

## Verbs

- `cockpit send [--tab-id <id>] <text>` — type literal text (no Enter).
- `cockpit send-key [--tab-id <id>] <Key>...` — press key(s): `Enter`, `Tab`,
  `Escape`, `Space`, `BSpace`, `Up`/`Down`/`Left`/`Right`, `Home`/`End`,
  `PageUp`/`PageDown`, `Delete`, and `C-<letter>` (e.g. `C-c` = Ctrl+C).
- `cockpit new-tab [--cwd <dir>] [--title <name>] [--split h|v]` — open a new
  **terminal tab** in the app and print its id (`t12`). `--cwd` defaults to
  your current directory; `--title` sets the stable tab label (so `send`/
  `read-tab` can target it by name). Without `--split` the tab opens in the
  same pane (next to yours); `--split h` (or `right`) splits side by side,
  `--split v` (or `down`) stacks — tmux semantics. Capture the id to drive it:

  ```sh
  id=$(cockpit new-tab --cwd ~/proj --title Worker --split h)
  cockpit send --tab-id "$id" "npm test" && cockpit send-key --tab-id "$id" Enter
  ```
- `cockpit open [--tab-id <id>] <file>` — open the file in the app's viewer
  (tab next to the terminal). `cockpit <file>` is the shortcut. The path is
  resolved against the tab cwd (relative, `~` and absolute all work). Any type
  opens as text — including extensionless ones (`.zprofile`, `Makefile`).
- `cockpit db <list|schema|query|run|execute>` — query the workspace's
  databases. Connections are registered in `.cockpit/databases.json` (Database
  panel); SQLite files in the repo are auto-detected. Output is **one JSON
  line**: `{"ok":{columns,rows,rowCount,truncated,elapsedMs}}` or
  `{"error":{kind,message}}` (exit 1). The app executes everything — you never
  see credentials. Examples:
  - `cockpit db list` — available connections (name, engine, target).
  - `cockpit db schema --db dev-local` / `… --db dev-local orders` — tables /
    columns of a table.
  - `cockpit db query --db dev-local --sql "SELECT …" [--limit N]` — rows are
    arrays (column order matches `columns`); `truncated: true` means the limit
    cut the cursor — raise `--limit` if you need more.
  - `cockpit db execute --db dev-local --sql "UPDATE …"` — returns
    `affectedRows`.
  - `cockpit db run <file.dbq>` — runs a `.dbq` file (SQL with `-- db:` /
    `-- limit:` comment frontmatter). Prefer writing a `.dbq` when the human
    should see the result too: the app shows it as a query tab and re-runs it
    every time you save the file.
  - Outside a Cockpit tab, add `--workspace <id|path>`.
- `cockpit redis --db <conn> <CMD> [args...]` — Redis/cache command. One
  JSON line reply. e.g. `cockpit redis --db cache HGETALL user:42`. Covers
  Redis/Valkey/KeyDB.
- `cockpit mongo --db <conn> --command '<json>'` — MongoDB runCommand.
  The command is a runCommand document, e.g.
  `cockpit mongo --db app --command '{"find":"users","filter":{"active":true}}'`.
  Output: one JSON line `{"ok": <reply>}` / `{"error":{kind,message}}`.
  Documents use relaxed extended JSON (`{"$oid":…}`, `{"$date":…}`) both ways.
- **Browse commands open a view for the human — they return no data.** Use
  them to *show* what you found (after investigating with the commands above),
  not to query:
  - `cockpit redis browse --db <conn> [--pattern 'user:*']` — opens the
    editable Redis key table, pre-filtered. On an already-open table the
    pattern **replaces** the current filter.
  - `cockpit mongo browse --db <conn> <collection> [--filter '<json>']` —
    opens the Mongo collection browser (JSON document cards) pre-filtered.
    The filter lands in the visible filter bar, editable by the human.
- **Registering a connection** (`.cockpit/databases.json` at the workspace
  root — the file behind `cockpit db list` and the Database panel):

  ```json
  {
    "databases": [
      {"name": "dev-local", "url": "sqlite:./app.db", "savePassword": false},
      {"name": "app", "url": "postgres://user@localhost:5432/appdb", "savePassword": false},
      {"name": "cache", "url": "redis://localhost:6379/0", "savePassword": false},
      {"name": "docs", "url": "mongodb://localhost:27017/appdb", "savePassword": false}
    ]
  }
  ```

  The URL never carries the password — the human enters it in the Database
  panel (stored in the OS keychain when `savePassword` is on). A personal,
  gitignored overlay lives in `.cockpit/databases.local.json` (same shape,
  merged on top by name). The panel picks up edits on reload; `cockpit db
  list` confirms what's registered.
- `cockpit read-tab [<label|tab-id>] [--lines N] [--offset N] [--from-start]`
  (alias: `read-pane`) — read a tab's **rendered output** as plain text (no
  ANSI escapes; covers TUIs on the alt-screen too). Without a target it reads
  your **own** tab; a target may be a stable tab `label` or a tab-id. Default
  window: the **last 100 lines** (tail). `--lines N` sets the window size
  (server cap 2000); `--from-start` anchors at the beginning of the buffer
  instead of the end; `--offset N` skips N lines from the chosen anchor
  (pagination: read the last 100, then `--lines 100 --offset 100` for the 100
  before those). Output is always chronological (top→bottom) — the flags only
  pick the window.
- `cockpit read-task <task-id> [--lines N] [--offset N] [--from-start]` — same
  windowed read, but for a **task run's** output (the Task Run feature). Works
  even if no task-output tab is open, but only for tasks that ran this boot.
  Discover ids with `cockpit list-tasks` (never guess them).
- `cockpit list-tasks [--json]` — tasks of **your workspace** (the one owning
  the current tab, or `--tab-id`'s): `id`, `label`, `kind` (watch|oneShot),
  `source` (detected|manual), `running`, `hasOutput` (`read-task` has output
  to read). Ids are stable per workspace: `npm:<script>` (package.json
  scripts), `flutter:run`/`flutter:test`, `json:<label>`
  (`.cockpit/tasks.json`).
- `cockpit list-tabs [--json]` (alias: `list-panes`) — active tabs: `id`,
  `kind` (terminal|agent|file|task), `title` (dynamic), `label` (manual stable
  name, or null), `workspaceId` (opaque UUID), `workspacePath` (workspace root
  on disk), `working`, and `taskId` on task-output tabs (the id `read-task`
  accepts). Resolve a tab by its stable `label`, not the dynamic `title`.
- `cockpit list-workspaces [--json]` — open projects: `id` (opaque UUID),
  `name`, `path` (root on disk), `tabs`.

## Target (--tab-id)

Without `--tab-id`, the command acts on **your own tab** (via `$COCKPIT_TAB_ID`,
legacy fallback `$COCKPIT_PANE_ID`). To drive **another** tab, pass
`--tab-id <id>`.

> Ids (`t0`, `t1`…) are sequential and **change on every app boot**. Never
> guess an id: run `cockpit list-tabs` first and use the `id` from there.

## Usage pattern

To run a command in a tab, **send the text and then Enter** (`send` does not
add a line break):

```sh
cockpit send "npm test"
cockpit send-key Enter
```

Cross-tab (drive another tab):

```sh
cockpit list-tabs                        # find the target id, e.g. t4
cockpit send --tab-id t4 "git status"
cockpit send-key --tab-id t4 Enter
```

Interrupt a stuck process in another tab:

```sh
cockpit send-key --tab-id t4 C-c
```

Read what another tab printed (e.g. check on a worker, debug a failure):

```sh
cockpit read-tab t4 --lines 50            # last 50 lines of t4
cockpit read-tab Extension                # by stable label (last 100 lines)
cockpit read-tab t4 --lines 100 --offset 100   # the 100 lines before those
```

Read a task run's output (dev server, build, test — the Task Run feature):

```sh
cockpit list-tasks                        # ids: ● = running, [output] = readable
cockpit read-task npm:dev --lines 80      # tail of the "npm:dev" task output
```

Typical loop — dispatch work to a tab, wait, then read the result:

```sh
cockpit send --tab-id t4 "npm test" && cockpit send-key --tab-id t4 Enter
# poll `cockpit list-tabs --json` until t4 shows "working": false, then:
cockpit read-tab t4 --lines 60
```

## Common errors

- "COCKPIT_STATUS_SOCK is unset" → you are not inside a Cockpit terminal.
- "tab ... does not exist" → stale id (app reboot). Run `list-tabs` again.
- "tab ... is not a terminal" → the target is an agent/file tab, not a shell.
- "has no readable output" → read-tab target is an agent/file tab; only
  terminal and task-output tabs are readable.
- "no output recorded for task ..." → the task never ran this app boot, or the
  id is wrong — check both with `cockpit list-tasks` (`[output]` = readable).
''';
