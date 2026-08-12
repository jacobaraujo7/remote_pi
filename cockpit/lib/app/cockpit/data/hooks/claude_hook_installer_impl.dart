import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/hook_installer_base.dart';
import 'package:flutter/foundation.dart';

/// Instalador dos hooks no **Claude Code** (`~/.claude/settings.json`).
///
/// A materialização da CLI e a resolução do comando ficam na
/// [HookInstallerBase]; aqui mora só o formato do `settings.json`:
///
/// - Faz **append idempotente** de um entry marcado (`_cockpit`) em cada evento,
///   sem nunca reescrever a lista (preserva hooks do usuário/iTerm2/plugins).
///   Re-rodar remove o entry antigo nosso e re-adiciona — não duplica. É por
///   aqui que a migração acontece: o entry velho apontando pro `cockpit-hook` é
///   removido e substituído no boot seguinte ao update.
class ClaudeHookInstallerImpl extends HookInstallerBase {
  const ClaudeHookInstallerImpl();

  @override
  String get harnessName => 'claude';

  /// Marcador que identifica entries de nossa autoria (para idempotência/cleanup).
  static const String _marker = '_cockpit';
  static const String _markerValue = 'v1';

  /// Eventos de ciclo de vida que instrumentamos. working: UserPromptSubmit/
  /// PreToolUse/PostToolUse (exceto PreToolUse de ferramenta interativa —
  /// AskUserQuestion/ExitPlanMode — que vira waiting); waiting/idle:
  /// Notification; idle: Stop/SessionStart/SessionEnd. (Mapeamento real mora
  /// no `cockpit hook`.)
  static const List<String> _events = <String>[
    'UserPromptSubmit',
    'PreToolUse',
    'PostToolUse',
    'Notification',
    'Stop',
    'SessionStart',
    'SessionEnd',
  ];

  @override
  Future<void> writeConfig({
    required String home,
    required String command,
  }) async {
    final file = File('$home/.claude/settings.json');
    Map<String, dynamic> root = <String, dynamic>{};
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) root = Map<String, dynamic>.from(decoded);
    } else {
      await file.parent.create(recursive: true);
    }

    final hooksRaw = root['hooks'];
    final hooks = hooksRaw is Map
        ? Map<String, dynamic>.from(hooksRaw)
        : <String, dynamic>{};

    // `command` já vem com o caminho normalizado em forward slashes por
    // `hookPath` (crítico no Windows: o Claude Code roda hooks via Git Bash,
    // que trata `\` como escape e quebraria o caminho) e citado quando tem
    // espaço.
    final ourGroup = <String, dynamic>{
      'matcher': '',
      'hooks': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'command',
          'command': command,
          _marker: _markerValue,
        },
      ],
    };

    var changed = false;
    for (final event in _events) {
      final existing = hooks[event];
      final list = existing is List
          ? List<dynamic>.from(existing)
          : <dynamic>[];
      final before = list.length;
      list.removeWhere(_isOurs); // tira entries antigos nossos
      list.add(Map<String, dynamic>.from(ourGroup));
      // mudou se removeu algo diferente do que readicionamos ou se cresceu
      if (list.length != before || before == 0) changed = true;
      hooks[event] = list;
    }

    root['hooks'] = hooks;
    // Sempre regrava (idempotente no conteúdo lógico; barato).
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(root)}\n',
    );
    if (kDebugMode && changed) {
      debugPrint('[claude-hook] entries instalados em ${file.path}');
    }
  }

  /// Um matcher-group é nosso se algum hook interno carrega o marcador **ou**
  /// aponta pro helper (`cockpit-hook` legado ou `<cli> hook`). O segundo
  /// critério limpa entries legados (escritos por versões antigas do
  /// instalador, sem marcador, e/ou com caminho em barra invertida que o Git
  /// Bash não resolvia) — senão acumulam a cada boot. É também o que **migra**
  /// quem estava no binário separado: o entry velho sai aqui e o novo entra no
  /// lugar, no primeiro boot depois do update.
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
