import 'dart:io';

import 'package:cockpit/app/core/data/terminal/terminal_profile_resolver_impl.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runner falso: casa por `'<exe> <args>'`, conta chamadas e devolve o
/// `ProcessResult` configurado. Sem match → lança como um exec ausente (127),
/// espelhando o `Process.run` real.
class _FakeRunner {
  _FakeRunner(this.responses);
  final Map<String, ProcessResult> responses;
  final calls = <String>[];

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    final res = responses['$exe ${args.join(' ')}'];
    if (res == null) throw ProcessException(exe, args, 'not found', 127);
    return res;
  }
}

/// Bytes UTF-16LE (com BOM opcional) — reproduz a saída real do `wsl.exe -l -q`.
List<int> _utf16le(String s, {bool bom = true}) {
  final out = <int>[];
  if (bom) out.addAll(const [0xFF, 0xFE]);
  for (final cu in s.codeUnits) {
    out.add(cu & 0xFF);
    out.add((cu >> 8) & 0xFF);
  }
  return out;
}

ProcessResult _bytesOk(List<int> stdout) => ProcessResult(1, 0, stdout, '');

void main() {
  group('TerminalProfileResolverImpl · Windows', () {
    test('lista PowerShell + cmd + uma entrada por distro WSL', () async {
      final runner = _FakeRunner({
        'wsl.exe -l -q': _bytesOk(_utf16le('Ubuntu\r\nDebian\r\n')),
      });
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: false,
        environment: const {'ComSpec': r'C:\Windows\System32\cmd.exe'},
        runProcess: runner.call,
        executableExists: (exe) async => exe == 'powershell.exe',
      );

      final profiles = await resolver.discover();
      final ids = profiles.map((p) => p.id).toList();

      expect(ids, [
        TerminalProfile.powershellId,
        TerminalProfile.cmdId,
        'wsl:Ubuntu',
        'wsl:Debian',
      ]);
      final wslUbuntu = resolver.profileById('wsl:Ubuntu')!;
      expect(wslUbuntu.executable, 'wsl.exe');
      expect(wslUbuntu.args, ['-d', 'Ubuntu']);
      expect(wslUbuntu.label, 'Ubuntu (WSL)');
      expect(resolver.profileById(TerminalProfile.cmdId)!.executable,
          r'C:\Windows\System32\cmd.exe');
    });

    test('sem wsl.exe (runner lança) → só PowerShell + cmd, sem erro', () async {
      final runner = _FakeRunner(const {}); // wsl.exe não casa → lança 127
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: false,
        runProcess: runner.call,
        executableExists: (exe) async => exe == 'powershell.exe',
      );

      final ids = (await resolver.discover()).map((p) => p.id).toList();
      expect(ids, [TerminalProfile.powershellId, TerminalProfile.cmdId]);
    });

    test('wsl.exe com exitCode != 0 → nenhum perfil WSL', () async {
      final runner = _FakeRunner({
        'wsl.exe -l -q': ProcessResult(1, 1, const <int>[], 'WSL not enabled'),
      });
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: false,
        runProcess: runner.call,
        executableExists: (exe) async => exe == 'powershell.exe',
      );

      final ids = (await resolver.discover()).map((p) => p.id).toList();
      expect(ids, isNot(contains('wsl:Ubuntu')));
      expect(ids, [TerminalProfile.powershellId, TerminalProfile.cmdId]);
    });

    test('powershell.exe ausente → cai no pwsh.exe (PowerShell 7+)', () async {
      final runner = _FakeRunner(const {});
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: false,
        runProcess: runner.call,
        executableExists: (exe) async => exe == 'pwsh.exe',
      );

      final ps = resolver.profileById(TerminalProfile.powershellId);
      await resolver.discover();
      final ps2 = resolver.profileById(TerminalProfile.powershellId)!;
      expect(ps, isNull); // antes do discover não há cache
      expect(ps2.executable, 'pwsh.exe');
    });
  });

  group('TerminalProfileResolverImpl · POSIX', () {
    test('descobre um único perfil login-shell via resolveLoginShell', () async {
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'macos',
        runProcess: _FakeRunner(const {}).call,
        loginShell: () async => '/opt/homebrew/bin/fish',
      );

      final profiles = await resolver.discover();
      expect(profiles, hasLength(1));
      final p = profiles.single;
      expect(p.id, TerminalProfile.loginShellId);
      expect(p.executable, '/opt/homebrew/bin/fish');
      expect(p.args, ['-l']);
      expect(p.label, 'fish (login)');
    });
  });

  group('TerminalProfileResolverImpl · effectiveDefault', () {
    Future<TerminalProfileResolverImpl> windows({bool arm = false}) async {
      final r = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: arm,
        runProcess: _FakeRunner({
          'wsl.exe -l -q': _bytesOk(_utf16le('Ubuntu\r\n')),
        }).call,
        executableExists: (exe) async => exe == 'powershell.exe',
      );
      await r.discover();
      return r;
    }

    test('id configurado e existente → esse perfil', () async {
      final r = await windows();
      expect(r.effectiveDefault('wsl:Ubuntu').id, 'wsl:Ubuntu');
    });

    test('id configurado mas ausente → fallback de plataforma', () async {
      final r = await windows();
      expect(r.effectiveDefault('wsl:Fedora').id, TerminalProfile.powershellId);
    });

    test('id nulo → fallback de plataforma (PowerShell no Windows x64)', () async {
      final r = await windows();
      expect(r.effectiveDefault(null).id, TerminalProfile.powershellId);
    });

    test('Windows ARM → fallback é cmd (PTY do powershell instável no ARM)',
        () async {
      final r = await windows(arm: true);
      expect(r.effectiveDefault(null).id, TerminalProfile.cmdId);
    });

    test('POSIX id nulo → fallback login-shell', () async {
      final r = TerminalProfileResolverImpl(
        operatingSystem: 'linux',
        runProcess: _FakeRunner(const {}).call,
        loginShell: () async => '/usr/bin/zsh',
      );
      await r.discover();
      expect(r.effectiveDefault(null).id, TerminalProfile.loginShellId);
    });
  });
}
