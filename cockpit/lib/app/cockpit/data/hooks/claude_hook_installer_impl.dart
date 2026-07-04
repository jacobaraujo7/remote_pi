import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/claude_hook_installer.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Implementação do [ClaudeHookInstaller].
///
/// 1. Copia o helper `cockpit-hook` empacotado no app (compilado pelo
///    `macos/build_hook.sh` / passo de build do Windows) para um caminho estável
///    (`~/.cockpit/bin/cockpit-hook[.exe]`) — o `settings.json` aponta pra cópia,
///    não pro bundle (sobrevive a update/move). Recopia só quando o tamanho muda.
/// 2. Faz **append idempotente** de um entry marcado (`_cockpit`) em cada evento
///    de hook, sem nunca reescrever a lista (preserva hooks do usuário/iTerm2/
///    plugins). Re-rodar remove o entry antigo nosso e re-adiciona — não duplica.
class ClaudeHookInstallerImpl implements ClaudeHookInstaller {
  ClaudeHookInstallerImpl();

  /// Marcador que identifica entries de nossa autoria (para idempotência/cleanup).
  static const String _marker = '_cockpit';
  static const String _markerValue = 'v1';

  /// Eventos de ciclo de vida que instrumentamos. working: UserPromptSubmit/
  /// PreToolUse/PostToolUse; waiting/idle: Notification; idle: Stop/SessionStart/
  /// SessionEnd. (Mapeamento real mora no `cockpit-hook`.)
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
  Future<Result<void, String>> ensureInstalled() async {
    final home = remotePiHome();
    if (home == null) {
      return const Failure<void, String>('HOME não resolvido');
    }
    try {
      final helperPath = await _ensureHelper(home);
      if (helperPath == null) {
        return const Failure<void, String>(
          'helper cockpit-hook não encontrado',
        );
      }
      await _installHooks(home: home, helperPath: helperPath);
      // CLI interna `cockpit`: materializa o binário e, se veio, instala a skill
      // que ensina o agente a usá-lo. Best-effort — não é fatal pro boot.
      await _ensureCli(home);
      return const Success<void, String>(null);
    } catch (e) {
      return Failure<void, String>('$e');
    }
  }

  /// Copia o helper empacotado para `~/.cockpit/bin/cockpit-hook[.exe]`.
  /// Recopia só se o tamanho difere. Devolve o caminho, ou `null` se o binário
  /// não está no bundle (ex.: dev sem o passo de build) e não há cópia prévia.
  Future<String?> _ensureHelper(String home) async {
    final name = Platform.isWindows ? 'cockpit-hook.exe' : 'cockpit-hook';
    return _materialize(home, bundledName: name, destName: name);
  }

  /// Materializa a CLI interna `cockpit` em `~/.cockpit/bin/cockpit[.exe]` (o
  /// fonte é empacotado como `cockpit-cli` pra não colidir com `cockpit.app`) e,
  /// se materializou, roda `cockpit install-skill` (idempotente) pra a skill
  /// nascer instalada. Silencioso: falha aqui não pode derrubar o boot.
  Future<void> _ensureCli(String home) async {
    final bundledName = Platform.isWindows ? 'cockpit-cli.exe' : 'cockpit-cli';
    final destName = Platform.isWindows ? 'cockpit.exe' : 'cockpit';
    final path = await _materialize(
      home,
      bundledName: bundledName,
      destName: destName,
    );
    if (path == null) return;
    try {
      await Process.run(path, <String>['install-skill']);
    } catch (_) {
      /* best-effort */
    }
  }

  /// Copia um binário empacotado ([bundledName]) para `~/.cockpit/bin/[destName]`.
  /// Recopia só se o tamanho difere. Devolve o caminho, ou `null` se não está no
  /// bundle (ex.: dev sem o passo de build) e não há cópia prévia.
  Future<String?> _materialize(
    String home, {
    required String bundledName,
    required String destName,
  }) async {
    final destDir = Directory('$home/.cockpit/bin');
    final dest = File('${destDir.path}/$destName');

    final bundled = _bundledHelper(bundledName);
    if (bundled != null && await bundled.exists()) {
      final srcLen = await bundled.length();
      final upToDate = await dest.exists() && await dest.length() == srcLen;
      if (!upToDate) {
        await destDir.create(recursive: true);
        await bundled.copy(dest.path);
        await _chmodExec(dest.path);
      }
      return dest.path;
    }

    // Dev / sem bundle: usa cópia pré-existente (colocada manualmente).
    if (await dest.exists()) return dest.path;
    return null;
  }

  /// Caminho do helper empacotado no app, por plataforma:
  /// - macOS: `…/Contents/MacOS/<app>` → `…/Contents/Resources/cockpit-hook`
  /// - Windows/Linux: ao lado do executável (`<dir>/cockpit-hook[.exe]`)
  File? _bundledHelper(String name) {
    try {
      final exe = File(Platform.resolvedExecutable);
      if (Platform.isMacOS) {
        final contents = exe.parent.parent; // Contents/MacOS → Contents
        return File('${contents.path}/Resources/$name');
      }
      return File('${exe.parent.path}/$name');
    } catch (_) {
      return null;
    }
  }

  Future<void> _chmodExec(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (_) {
      /* best-effort */
    }
  }

  Future<void> _installHooks({
    required String home,
    required String helperPath,
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

    final ourGroup = <String, dynamic>{
      'matcher': '',
      'hooks': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'command',
          'command': helperPath,
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

  /// Um matcher-group é nosso se algum hook interno carrega o marcador.
  bool _isOurs(dynamic group) {
    if (group is! Map) return false;
    final inner = group['hooks'];
    if (inner is! List) return false;
    return inner.any((h) => h is Map && h[_marker] == _markerValue);
  }
}
