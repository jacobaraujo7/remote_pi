import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/codex_terminal_launcher.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cockpit-codex-shell-');
    final cli = File('${root.path}/cockpit');
    await cli.writeAsString('#!/bin/sh\nprintf "launcher:%s\\n" "\$*"\n');
    if (!Platform.isWindows) await Process.run('chmod', ['+x', cli.path]);
  });
  tearDown(() => root.delete(recursive: true));

  test('installs app-owned launcher and proxies idempotently', () async {
    await CodexTerminalLauncher.install(root.path, 'cockpit');
    await CodexTerminalLauncher.install(root.path, 'cockpit');
    expect(await Link('${root.path}/cockpit-codex').target(), 'cockpit');
    for (final file in [
      '.zshenv',
      '.zprofile',
      '.zshrc',
      '.zlogin',
      '.zlogout',
    ]) {
      expect(File('${root.path}/codex-zsh/$file').existsSync(), isTrue);
    }
  }, skip: Platform.isWindows);

  test('does not replace an unrelated launcher', () async {
    final custom = File('${root.path}/cockpit-codex');
    await custom.writeAsString('user launcher');
    await CodexTerminalLauncher.install(root.path, 'cockpit');
    expect(await custom.readAsString(), 'user launcher');
    expect(Directory('${root.path}/codex-zsh').existsSync(), isFalse);
    final env = {CodexTerminalLauncher.environmentKey: custom.path};
    final invocation = CodexTerminalLauncher.configure(
      const TerminalProfile(id: 'bash', label: 'bash', executable: '/bin/bash'),
      env,
    );
    expect(invocation.environment, env);
  }, skip: Platform.isWindows);

  test(
    'bash command survives startup PATH changes without modifying rc files',
    () async {
      await CodexTerminalLauncher.install(root.path, 'cockpit');
      final rc = File('${root.path}/bashrc');
      const startup = 'PATH=/usr/bin:/bin\n';
      await rc.writeAsString(startup);
      final invocation = CodexTerminalLauncher.configure(
        const TerminalProfile(
          id: 'bash',
          label: 'bash',
          executable: '/bin/bash',
        ),
        {CodexTerminalLauncher.environmentKey: '${root.path}/cockpit-codex'},
      );
      final result = await Process.run('/bin/bash', [
        '--noprofile',
        '--rcfile',
        rc.path,
        '-ic',
        'codex resume "chat with spaces"',
      ], environment: invocation.environment);
      expect(result.exitCode, 0);
      expect(result.stdout, 'launcher:resume chat with spaces\n');
      expect(await rc.readAsString(), startup);
    },
    skip: Platform.isWindows,
  );

  test(
    'zsh loads user startup files and launches codex in a login shell',
    () async {
      if (!File('/bin/zsh').existsSync()) {
        markTestSkipped('Zsh unavailable');
        return;
      }
      await CodexTerminalLauncher.install(root.path, 'cockpit');
      final config = Directory('${root.path}/user config');
      await config.create();
      for (final stage in ['.zshenv', '.zprofile', '.zshrc', '.zlogin']) {
        await File(
          '${config.path}/$stage',
        ).writeAsString('print loaded:$stage\n');
      }
      final invocation = CodexTerminalLauncher.configure(
        const TerminalProfile(
          id: 'zsh',
          label: 'zsh',
          executable: '/bin/zsh',
          args: ['-l'],
        ),
        {
          CodexTerminalLauncher.environmentKey: '${root.path}/cockpit-codex',
          'ZDOTDIR': config.path,
        },
      );
      final result = await Process.run('/bin/zsh', [
        ...invocation.arguments,
        '-ic',
        r'codex resume "chat with spaces"; print "config:$ZDOTDIR"',
      ], environment: invocation.environment);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        'loaded:.zshenv\nloaded:.zprofile\nloaded:.zshrc\nloaded:.zlogin\nlauncher:resume chat with spaces\nconfig:${config.path}\n',
      );
    },
    skip: Platform.isWindows,
  );

  test('integration is absent without a scoped launcher or in WSL', () {
    const bash = TerminalProfile(
      id: 'bash',
      label: 'bash',
      executable: '/bin/bash',
      args: ['-l'],
    );
    expect(CodexTerminalLauncher.configure(bash, {}).environment, isEmpty);
    final env = {CodexTerminalLauncher.environmentKey: '${root.path}/cockpit'};
    const wsl = TerminalProfile(
      id: 'wsl:Ubuntu',
      label: 'WSL',
      executable: 'wsl.exe',
    );
    expect(CodexTerminalLauncher.configure(wsl, env).environment, env);
  });

  test(
    'zsh proxies retain the original config directory and fish keeps startup arguments',
    () async {
      await CodexTerminalLauncher.install(root.path, 'cockpit');
      final env = {
        CodexTerminalLauncher.environmentKey: '${root.path}/cockpit-codex',
        'ZDOTDIR': '/original config',
      };
      final zsh = CodexTerminalLauncher.configure(
        const TerminalProfile(
          id: 'zsh',
          label: 'zsh',
          executable: '/bin/zsh',
          args: ['-l'],
        ),
        env,
      );
      expect(zsh.arguments, ['-l']);
      expect(zsh.environment['COCKPIT_ZSH_USER_DIR'], '/original config');
      expect(zsh.environment['ZDOTDIR'], '${root.path}/codex-zsh');
      final fish = CodexTerminalLauncher.configure(
        const TerminalProfile(
          id: 'fish',
          label: 'fish',
          executable: '/bin/fish',
          args: ['-l'],
        ),
        env,
      );
      expect(fish.arguments.take(2), ['-l', '--init-command']);
      expect(fish.arguments.last, contains(r'$argv'));
      expect(env['ZDOTDIR'], '/original config');
    },
    skip: Platform.isWindows,
  );
}
