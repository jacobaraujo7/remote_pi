import 'dart:convert';

import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/shell_command.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decodifica o `-EncodedCommand` (base64 de UTF-16LE) de volta pra texto.
String _decodeUtf16Le(String b64) {
  final bytes = base64.decode(b64);
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}

void main() {
  const env = <String, String>{'ComSpec': r'C:\Windows\system32\cmd.exe'};

  group('shellInvocationFor', () {
    test('sem perfil no Windows: cmd /d /s /c', () {
      final inv = shellInvocationFor(
        'git status --short',
        isWindows: true,
        environment: env,
      );
      expect(inv.executable, r'C:\Windows\system32\cmd.exe');
      expect(inv.arguments, ['/d', '/s', '/c', 'git status --short']);
    });

    test('perfil cmd: /d /s /c com o executável do perfil', () {
      final inv = shellInvocationFor(
        'dir',
        profile: const TerminalProfile(
          id: TerminalProfile.cmdId,
          label: 'cmd',
          executable: 'cmd.exe',
        ),
        isWindows: true,
        environment: env,
      );
      expect(inv.executable, 'cmd.exe');
      expect(inv.arguments, ['/d', '/s', '/c', 'dir']);
    });

    for (final (id, exe) in [
      (TerminalProfile.powershellId, 'powershell.exe'),
      (TerminalProfile.pwshId, 'pwsh.exe'),
    ]) {
      test('perfil $id: -EncodedCommand com preâmbulo UTF-8', () {
        final inv = shellInvocationFor(
          'Start-Process calc.exe',
          profile: TerminalProfile(id: id, label: id, executable: exe),
          isWindows: true,
          environment: env,
        );
        expect(inv.executable, exe);
        expect(inv.arguments.take(5), [
          '-NoLogo',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
        ]);
        final script = _decodeUtf16Le(inv.arguments.last);
        expect(script, startsWith('[Console]::OutputEncoding'));
        expect(script, endsWith('\nStart-Process calc.exe'));
      });
    }

    test('perfil WSL: -d <distro> -- sh -lc', () {
      final inv = shellInvocationFor(
        'ls -la',
        profile: const TerminalProfile(
          id: '${TerminalProfile.wslPrefix}Ubuntu',
          label: 'Ubuntu (WSL)',
          executable: 'wsl.exe',
          args: ['-d', 'Ubuntu'],
        ),
        isWindows: true,
        environment: env,
      );
      expect(inv.executable, 'wsl.exe');
      expect(inv.arguments, ['-d', 'Ubuntu', '--', 'sh', '-lc', 'ls -la']);
    });

    test('login shell POSIX: -lc', () {
      final inv = shellInvocationFor(
        'echo hi',
        profile: const TerminalProfile(
          id: TerminalProfile.loginShellId,
          label: 'zsh (login)',
          executable: '/bin/zsh',
          args: ['-l'],
        ),
        isWindows: false,
        environment: env,
      );
      expect(inv.executable, '/bin/zsh');
      expect(inv.arguments, ['-lc', 'echo hi']);
    });

    test('perfil custom decide pelo nome do executável', () {
      final ps = shellInvocationFor(
        'Get-Date',
        profile: const TerminalProfile(
          id: 'custom:abc',
          label: 'meu pwsh',
          executable: r'C:\Program Files\PowerShell\7\pwsh.exe',
          args: ['-NoLogo'],
          builtIn: false,
        ),
        isWindows: true,
        environment: env,
      );
      expect(ps.arguments.last, isNot('Get-Date'));
      expect(ps.arguments, contains('-EncodedCommand'));

      final fish = shellInvocationFor(
        'echo hi',
        profile: const TerminalProfile(
          id: 'custom:def',
          label: 'fish',
          executable: '/opt/homebrew/bin/fish',
          builtIn: false,
        ),
        isWindows: false,
        environment: env,
      );
      expect(fish.arguments, ['-lc', 'echo hi']);
    });

    test(
      'perfil "o host decide" (executável vazio) cai no shell da plataforma',
      () {
        final inv = shellInvocationFor(
          'whoami',
          profile: TerminalProfile.hostLoginShell,
          isWindows: true,
          environment: env,
        );
        expect(inv.executable, r'C:\Windows\system32\cmd.exe');
        expect(inv.arguments, ['/d', '/s', '/c', 'whoami']);
      },
    );
  });
}
