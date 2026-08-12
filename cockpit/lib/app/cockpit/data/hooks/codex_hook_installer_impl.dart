import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/hook_installer_base.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Instalador dos hooks no **Codex CLI** (0.147+).
///
/// O Codex ganhou um sistema de hooks espelhado no do Claude Code — mesmos
/// nomes de evento, mesmo envelope JSON pelo stdin —, então o helper (`cockpit
/// hook`) serve os dois sem ramificação. O que muda é **onde** e o **gate de
/// confiança**:
///
/// 1. Os hooks vão em `~/.codex/hooks.json` (o mesmo append idempotente marcado
///    do Claude, preservando o que o usuário tiver lá).
/// 2. O Codex **só executa hook confiado**: cada handler tem um `trusted_hash`
///    em `[hooks.state."<chave>"]` no `~/.codex/config.toml`. Sem ele o hook é
///    ignorado **em silêncio** — nem aviso aparece. Como o hash é derivado da
///    config (não do binário), conseguimos computá-lo e gravar junto, sem
///    obrigar o usuário a aprovar na mão. É o mesmo grau de confiança que já
///    assumimos ao escrever no `settings.json` do Claude: instalamos o **nosso**
///    helper, e só ele.
///
/// Formato da chave e do hash (de `codex-rs/hooks/src/engine/discovery.rs`):
/// `"caminho-do-hooks.json:evento_snake:índice-do-grupo:índice-do-handler"`, e
/// o hash é `sha256:` sobre o JSON canônico (chaves ordenadas, sem espaços) da
/// identidade normalizada do handler.
class CodexHookInstallerImpl extends HookInstallerBase {
  const CodexHookInstallerImpl();

  @override
  String get harnessName => 'codex';

  static const String _marker = '_cockpit';
  static const String _markerValue = 'v1';

  /// Delimitadores do bloco que gerenciamos no `config.toml`. Tudo entre eles é
  /// nosso e pode ser reescrito; o resto do arquivo nunca é tocado.
  static const String _tomlBegin = '# >>> cockpit hooks (auto-gerado)';
  static const String _tomlEnd = '# <<< cockpit hooks';

  /// Eventos instrumentados, com o rótulo snake_case que o Codex usa na chave de
  /// trust. Deliberadamente **fora**: `SubagentStart`/`SubagentStop` e
  /// `PreCompact`/`PostCompact` — subagente e compactação não são o turno da
  /// aba.
  static const Map<String, String> _events = <String, String>{
    'UserPromptSubmit': 'user_prompt_submit',
    'PreToolUse': 'pre_tool_use',
    'PostToolUse': 'post_tool_use',
    'PermissionRequest': 'permission_request',
    'Stop': 'stop',
    'SessionStart': 'session_start',
    'SessionEnd': 'session_end',
  };

  /// Timeout que o Codex aplica quando o handler não declara um. `SessionEnd`
  /// tem regra própria (default 1s, teto 3s); os demais, 600s. Precisamos do
  /// valor **normalizado** porque ele entra no hash de confiança.
  static const int _defaultTimeoutSec = 600;
  static const int _sessionEndTimeoutSec = 1;

  @override
  Future<void> writeConfig({
    required String home,
    required String command,
  }) async {
    final codexDir = Directory('$home/.codex');
    // Sem `~/.codex` o Codex não está instalado: não criamos a pasta (seria
    // lixo na home de quem não usa) e saímos em silêncio.
    if (!await codexDir.exists()) return;

    // `--harness codex` viaja no payload do status: o app precisa saber de quem
    // é o `session_id` pra retomar a aba com `codex resume <id>` em vez de
    // `claude --resume <id>`. Entra no comando (e portanto no hash de trust).
    final tagged = '$command --harness codex';

    final hooksFile = File('${codexDir.path}/hooks.json');
    final placements = await _writeHooksJson(hooksFile, tagged);
    await _writeTrust(
      configFile: File('${codexDir.path}/config.toml'),
      hooksPath: hooksFile.path,
      command: tagged,
      placements: placements,
    );
    if (kDebugMode) {
      debugPrint('[codex-hook] entries instalados em ${hooksFile.path}');
    }
  }

  /// Faz o append idempotente no `hooks.json` e devolve, por evento, o índice do
  /// grupo onde nosso handler acabou. O índice importa: ele faz parte da chave
  /// de trust, então precisa ser o real depois da escrita.
  Future<Map<String, int>> _writeHooksJson(File file, String command) async {
    Map<String, dynamic> root = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) root = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Arquivo corrompido: não dá pra preservar o que não parseia. Recomeçar
        // é melhor que abortar e deixar o status de turno morto para sempre.
        root = <String, dynamic>{};
      }
    }

    final hooksRaw = root['hooks'];
    final hooks = hooksRaw is Map
        ? Map<String, dynamic>.from(hooksRaw)
        : <String, dynamic>{};

    // Sem `matcher`: o Codex trata ausente como "todos", e omitir deixa a
    // identidade (e portanto o hash) determinística.
    final ourGroup = <String, dynamic>{
      'hooks': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'command',
          'command': command,
          _marker: _markerValue,
        },
      ],
    };

    final placements = <String, int>{};
    for (final event in _events.keys) {
      final existing = hooks[event];
      final list = existing is List
          ? List<dynamic>.from(existing)
          : <dynamic>[];
      list.removeWhere(_isOurs);
      list.add(Map<String, dynamic>.from(ourGroup));
      placements[event] = list.length - 1; // sempre o último
      hooks[event] = list;
    }

    root['hooks'] = hooks;
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(root)}\n',
    );
    return placements;
  }

  /// Reescreve o bloco de trust no `config.toml`, preservando tudo que está fora
  /// dos delimitadores.
  Future<void> _writeTrust({
    required File configFile,
    required String hooksPath,
    required String command,
    required Map<String, int> placements,
  }) async {
    var content = '';
    if (await configFile.exists()) {
      content = await configFile.readAsString();
    }
    content = _stripOurBlock(content);

    final buffer = StringBuffer()
      ..writeln(_tomlBegin)
      ..writeln('# Confia no helper de status de turno do Cockpit.')
      ..writeln('# Regerado a cada boot; edições aqui dentro são perdidas.');
    for (final entry in _events.entries) {
      final event = entry.key;
      final label = entry.value;
      final groupIndex = placements[event] ?? 0;
      final key = '$hooksPath:$label:$groupIndex:0';
      final hash = trustHash(
        eventLabel: label,
        command: command,
        timeoutSec: event == 'SessionEnd'
            ? _sessionEndTimeoutSec
            : _defaultTimeoutSec,
      );
      buffer
        ..writeln()
        ..writeln('[hooks.state."${_escapeTomlKey(key)}"]')
        ..writeln('enabled = true')
        ..writeln('trusted_hash = "$hash"');
    }
    buffer.writeln(_tomlEnd);

    final head = content.trimRight();
    final body = head.isEmpty ? '' : '$head\n\n';
    await configFile.writeAsString('$body$buffer');
  }

  /// Remove um bloco nosso anterior (delimitadores inclusos). Tolera arquivo sem
  /// bloco e bloco sem fechamento (trunca até o fim, que é o que sobraria de uma
  /// escrita interrompida).
  String _stripOurBlock(String content) {
    final begin = content.indexOf(_tomlBegin);
    if (begin < 0) return content;
    final endMark = content.indexOf(_tomlEnd, begin);
    if (endMark < 0) return content.substring(0, begin);
    final after = endMark + _tomlEnd.length;
    final rest = after < content.length ? content.substring(after) : '';
    return '${content.substring(0, begin)}${rest.startsWith('\n') ? rest.substring(1) : rest}';
  }

  /// Reproduz o `hook_hash` do Codex: serializa a identidade normalizada do
  /// handler, canonicaliza o JSON (chaves ordenadas, sem espaços) e tira o
  /// sha256, prefixado com `sha256:`.
  ///
  /// A identidade é `{event_name, matcher?, hooks: [handler normalizado]}`. Do
  /// handler entram só os campos que sobrevivem à normalização: `type`,
  /// `command`, `timeout` (já resolvido) e `async`. Campos ausentes (`matcher`,
  /// `commandWindows`, `statusMessage`, `additionalContextLimit`) não são
  /// serializados — é o que nos permite omitir `matcher` e ainda bater.
  @visibleForTesting
  String trustHash({
    required String eventLabel,
    required String command,
    required int timeoutSec,
  }) {
    final identity = <String, Object>{
      'event_name': eventLabel,
      'hooks': <Map<String, Object>>[
        <String, Object>{
          'type': 'command',
          'command': command,
          'timeout': timeoutSec,
          'async': false,
        },
      ],
    };
    final canonical = jsonEncode(_canonical(identity));
    final digest = sha256.convert(utf8.encode(canonical));
    return 'sha256:$digest';
  }

  /// JSON canônico do Codex: objetos com chaves ordenadas, arrays na ordem
  /// original. (`jsonEncode` do Dart já sai sem espaços, como o `serde_json`.)
  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return <String, Object?>{for (final k in keys) k: _canonical(value[k])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  /// Escapa a chave para uma basic string TOML. Caminhos com `\` (Windows) e
  /// aspas quebrariam o parser do Codex.
  String _escapeTomlKey(String key) =>
      key.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  /// Mesmo critério do instalador do Claude: o grupo é nosso se algum handler
  /// carrega o marcador ou aponta pro nosso helper.
  bool _isOurs(dynamic group) {
    if (group is! Map) return false;
    final inner = group['hooks'];
    if (inner is! List) return false;
    return inner.any((h) {
      if (h is! Map) return false;
      if (h[_marker] == _markerValue) return true;
      final cmd = h['command'];
      if (cmd is! String) return false;
      return cmd.contains('cockpit-hook') ||
          cmd.contains('cockpit" hook') ||
          cmd.endsWith('cockpit hook');
    });
  }
}
