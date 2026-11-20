import 'dart:io';

import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';

/// App-owned launcher and startup integration. No user shell configuration is
/// edited. The exported Bash function / Zsh proxy / Fish init survives version
/// managers changing PATH while retaining the user's normal shell startup.
abstract class CodexTerminalLauncher {
  static const launcherName = 'cockpit-codex';
  static const environmentKey = 'COCKPIT_CODEX_LAUNCHER';

  static Future<void> install(String directory, String cliName) async {
    if (Platform.isWindows) return;
    final target = File('$directory/$cliName');
    if (!await target.exists()) return;
    final alias = Link('$directory/$launcherName');
    final type = await FileSystemEntity.type(alias.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await alias.create(cliName);
    } else if (type != FileSystemEntityType.link ||
        await alias.target() != cliName) {
      // An unrelated user-provided launcher always wins.
      return;
    }
    final zsh = Directory('$directory/codex-zsh');
    await zsh.create(recursive: true);
    for (final stage in [
      '.zshenv',
      '.zprofile',
      '.zshrc',
      '.zlogin',
      '.zlogout',
    ]) {
      final file = File('${zsh.path}/$stage');
      final source = _zshProxy(stage);
      if (!await file.exists() || await file.readAsString() != source) {
        await file.writeAsString(source);
      }
    }
  }

  static ({List<String> arguments, Map<String, String> environment}) configure(
    TerminalProfile profile,
    Map<String, String> environment,
  ) {
    final launcher = environment[environmentKey];
    final arguments = profile.args;
    if (Platform.isWindows ||
        profile.wslDistro != null ||
        launcher == null ||
        !_isOwnedLauncher(launcher) ||
        arguments.any((arg) => arg == '-c' || arg == '--command')) {
      return (arguments: arguments, environment: environment);
    }
    final name = profile.executable.split('/').last;
    if (name == 'zsh' &&
        arguments.any((arg) => arg == '-f' || arg == '--no-rcs')) {
      return (arguments: arguments, environment: environment);
    }
    final updated = <String, String>{...environment};
    switch (name) {
      case 'bash':
        updated['BASH_FUNC_codex%%'] =
            r'() { command "$COCKPIT_CODEX_LAUNCHER" "$@"; }';
      case 'zsh':
        final proxies = Directory('${File(launcher).parent.path}/codex-zsh');
        if (!proxies.existsSync()) break;
        final original =
            environment['ZDOTDIR'] ?? Platform.environment['ZDOTDIR'];
        updated['COCKPIT_ZSH_USER_DIR'] =
            original ?? Platform.environment['HOME'] ?? '';
        updated['COCKPIT_ZSH_USER_DIR_SET'] = original == null ? '0' : '1';
        updated['COCKPIT_ZSH_PROXY_DIR'] = proxies.path;
        updated['ZDOTDIR'] = proxies.path;
      case 'fish':
        return (
          arguments: [
            ...arguments,
            '--init-command',
            r'if not functions -q codex; function codex; command "$COCKPIT_CODEX_LAUNCHER" $argv; end; end',
          ],
          environment: updated,
        );
    }
    return (arguments: arguments, environment: updated);
  }

  static bool _isOwnedLauncher(String path) {
    try {
      return File(path).existsSync() &&
          Link(path).existsSync() &&
          Link(path).targetSync() == 'cockpit';
    } on FileSystemException {
      return false;
    }
  }

  static String _zshProxy(String stage) =>
      '''# Managed by Cockpit; only used by its terminal processes.
if [ "\$COCKPIT_ZSH_USER_DIR_SET" = 1 ]; then
  export ZDOTDIR="\$COCKPIT_ZSH_USER_DIR"
else
  unset ZDOTDIR
fi
if [ -r "\${ZDOTDIR:-\$HOME}/$stage" ]; then
  . "\${ZDOTDIR:-\$HOME}/$stage"
fi
export COCKPIT_ZSH_USER_DIR="\${ZDOTDIR:-\$HOME}"
if [ "\${ZDOTDIR+x}" = x ]; then
  export COCKPIT_ZSH_USER_DIR_SET=1
else
  export COCKPIT_ZSH_USER_DIR_SET=0
fi
${stage == '.zshrc' ? r'''
if ! typeset -f codex >/dev/null 2>&1; then
  function codex { command "$COCKPIT_CODEX_LAUNCHER" "$@"; }
fi
''' : ''}
${stage == '.zlogout' || stage == '.zlogin'
          ? ''
          : stage == '.zshrc'
          ? r'''
if [ -o login ]; then
  export ZDOTDIR="$COCKPIT_ZSH_PROXY_DIR"
fi
'''
          : r'export ZDOTDIR="$COCKPIT_ZSH_PROXY_DIR"'}
''';
}
