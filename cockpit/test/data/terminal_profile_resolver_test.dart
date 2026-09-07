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
      expect(
        resolver.profileById(TerminalProfile.cmdId)!.executable,
        r'C:\Windows\System32\cmd.exe',
      );
    });

    test(
      'sem wsl.exe (runner lança) → só PowerShell + cmd, sem erro',
      () async {
        final runner = _FakeRunner(const {}); // wsl.exe não casa → lança 127
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'windows',
          isWindowsArm: false,
          runProcess: runner.call,
          executableExists: (exe) async => exe == 'powershell.exe',
        );

        final ids = (await resolver.discover()).map((p) => p.id).toList();
        expect(ids, [TerminalProfile.powershellId, TerminalProfile.cmdId]);
      },
    );

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

    // Regressão: o pwsh era um `else if` do powershell.exe, e como este último
    // sempre existe no Windows, o PowerShell 7 nunca era oferecido — nem no
    // seletor do `+`, nem nas Configurações.
    test('os dois PowerShell instalados → DOIS perfis, o 7 primeiro', () async {
      final runner = _FakeRunner(const {});
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: false,
        runProcess: runner.call,
        executableExists: (exe) async =>
            exe == 'powershell.exe' || exe == 'pwsh.exe',
      );

      final ids = (await resolver.discover()).map((p) => p.id).toList();

      expect(ids, [
        TerminalProfile.pwshId,
        TerminalProfile.powershellId,
        TerminalProfile.cmdId,
      ]);
      expect(
        resolver.profileById(TerminalProfile.pwshId)!.executable,
        'pwsh.exe',
      );
      expect(
        resolver.profileById(TerminalProfile.powershellId)!.executable,
        'powershell.exe',
      );
      // Rótulos precisam desambiguar: "PowerShell" solto não diria qual é qual.
      expect(
        resolver.profileById(TerminalProfile.pwshId)!.label,
        'PowerShell 7',
      );
      expect(
        resolver.profileById(TerminalProfile.powershellId)!.label,
        'Windows PowerShell',
      );
    });

    test(
      'padrão de quem nunca escolheu segue o 5.1, mesmo com o 7 instalado',
      () async {
        final runner = _FakeRunner(const {});
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'windows',
          isWindowsArm: false,
          runProcess: runner.call,
          executableExists: (exe) async =>
              exe == 'powershell.exe' || exe == 'pwsh.exe',
        );
        await resolver.discover();

        // Listar o 7 primeiro NÃO pode trocar o shell de quem já usa o app.
        expect(
          resolver.effectiveDefault(null).id,
          TerminalProfile.powershellId,
        );
        // Mas escolher o 7 é respeitado.
        expect(
          resolver.effectiveDefault(TerminalProfile.pwshId).id,
          TerminalProfile.pwshId,
        );
      },
    );

    test('só o pwsh instalado → perfil do 7, sem inventar o 5.1', () async {
      final runner = _FakeRunner(const {});
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'windows',
        isWindowsArm: false,
        runProcess: runner.call,
        executableExists: (exe) async => exe == 'pwsh.exe',
      );

      expect(resolver.profileById(TerminalProfile.pwshId), isNull); // sem cache
      final ids = (await resolver.discover()).map((p) => p.id).toList();

      expect(ids, [TerminalProfile.pwshId, TerminalProfile.cmdId]);
      expect(resolver.profileById(TerminalProfile.powershellId), isNull);
      expect(
        resolver.profileById(TerminalProfile.pwshId)!.executable,
        'pwsh.exe',
      );
    });
  });

  group('TerminalProfileResolverImpl · POSIX', () {
    test(
      'login shell vem primeiro; sh/dash filtrados; bash+zsh de /etc/shells incluídos',
      () async {
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'macos',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/opt/homebrew/bin/fish',
          executableExists: (exe) async => true,
          extraProbePaths: const [], // desativa sonda Homebrew neste teste
          readEtcShells: () async => [
            '/bin/sh', // excluído — shell de sistema
            '/bin/dash', // excluído — shell de sistema
            '/bin/bash',
            '/bin/zsh',
            '/opt/homebrew/bin/fish', // duplicata do login shell — ignorada
          ],
        );

        final profiles = await resolver.discover();
        // fish (login shell) + bash + zsh = 3 entradas; sh e dash filtrados
        expect(profiles, hasLength(3));

        final fish = profiles.first;
        expect(fish.id, '${TerminalProfile.posixPrefix}/opt/homebrew/bin/fish');
        expect(fish.executable, '/opt/homebrew/bin/fish');
        expect(fish.args, ['-l']);
        expect(fish.label, 'fish');

        final ids = profiles.map((p) => p.id).toList();
        expect(ids, [
          '${TerminalProfile.posixPrefix}/opt/homebrew/bin/fish',
          '${TerminalProfile.posixPrefix}/bin/bash',
          '${TerminalProfile.posixPrefix}/bin/zsh',
        ]);
      },
    );

    test(
      'login shell é incluído mesmo que não seja um shell interativo padrão',
      () async {
        // Raro, mas possível: usuário com /bin/sh como login shell (containers).
        // O login shell deve aparecer independente do filtro _kInteractiveShells.
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'linux',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/bin/sh',
          executableExists: (exe) async => true,
          extraProbePaths: const [],
          readEtcShells: () async => const [],
        );

        final profiles = await resolver.discover();
        expect(profiles, hasLength(1));
        expect(profiles.first.executable, '/bin/sh');
      },
    );

    test(
      'fish encontrado via extraProbePaths mesmo sem estar em /etc/shells',
      () async {
        // Caso real no macOS: fish instalado via Homebrew mas /etc/shells
        // não atualizado manualmente.
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'macos',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/bin/zsh',
          executableExists: (exe) async =>
              exe == '/bin/zsh' || exe == '/opt/homebrew/bin/fish',
          extraProbePaths: const ['/opt/homebrew/bin/fish'],
          readEtcShells: () async => ['/bin/zsh'],
        );

        final profiles = await resolver.discover();
        final ids = profiles.map((p) => p.id).toList();
        expect(
          ids,
          contains('${TerminalProfile.posixPrefix}/opt/homebrew/bin/fish'),
        );
        expect(ids, contains('${TerminalProfile.posixPrefix}/bin/zsh'));
        // fish não deve aparecer antes do login shell (zsh)
        expect(ids.first, '${TerminalProfile.posixPrefix}/bin/zsh');
      },
    );

    test('shells que não existem no disco são excluídos', () async {
      const installed = {'/bin/bash', '/bin/zsh'};
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'linux',
        runProcess: _FakeRunner(const {}).call,
        loginShell: () async => '/bin/bash',
        executableExists: (exe) async => installed.contains(exe),
        extraProbePaths: const [],
        readEtcShells: () async => ['/bin/bash', '/bin/zsh', '/usr/bin/fish'],
      );

      final profiles = await resolver.discover();
      final ids = profiles.map((p) => p.id).toList();
      expect(ids, [
        '${TerminalProfile.posixPrefix}/bin/bash',
        '${TerminalProfile.posixPrefix}/bin/zsh',
      ]);
      // fish não existe no disco — não aparece
      expect(
        ids,
        isNot(contains('${TerminalProfile.posixPrefix}/usr/bin/fish')),
      );
    });

    test('/etc/shells ausente → apenas o login shell', () async {
      final resolver = TerminalProfileResolverImpl(
        operatingSystem: 'macos',
        runProcess: _FakeRunner(const {}).call,
        loginShell: () async => '/bin/zsh',
        executableExists: (exe) async => exe == '/bin/zsh',
        extraProbePaths: const [],
        readEtcShells: () async => const [],
      );

      final profiles = await resolver.discover();
      expect(profiles, hasLength(1));
      expect(profiles.first.id, '${TerminalProfile.posixPrefix}/bin/zsh');
      expect(profiles.first.label, 'zsh');
    });

    test(
      'customPaths incluídos mesmo sem estarem em /etc/shells (bypass do filtro interativo)',
      () async {
        // Caso do fish em prefix pessoal: não está em /etc/shells, não é detectado
        // pelo extraProbePaths — só chega via customPaths.
        const fishPath = '/Users/silas/.homebrew/bin/fish';
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'macos',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/bin/zsh',
          executableExists: (exe) async => exe == '/bin/zsh' || exe == fishPath,
          extraProbePaths: const [],
          readEtcShells: () async => ['/bin/zsh'],
          customPaths: const [fishPath],
        );

        final profiles = await resolver.discover();
        final ids = profiles.map((p) => p.id).toList();
        // zsh (login shell, primeiro) + fish (custom path) = 2
        expect(profiles, hasLength(2));
        expect(ids.first, '${TerminalProfile.posixPrefix}/bin/zsh');
        expect(ids, contains('${TerminalProfile.posixPrefix}$fishPath'));
      },
    );

    test(
      'addCustomProfile após discover adiciona ao cache; removeCustomProfile remove',
      () async {
        const fishPath = '/Users/silas/.homebrew/bin/fish';
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'macos',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/bin/zsh',
          executableExists: (exe) async => exe == '/bin/zsh',
          extraProbePaths: const [],
          readEtcShells: () async => ['/bin/zsh'],
        );
        await resolver.discover();

        final profile = TerminalProfile(
          id: '${TerminalProfile.posixPrefix}$fishPath',
          label: 'fish',
          executable: fishPath,
          args: const ['-l'],
        );
        // Adicionar
        resolver.addCustomProfile(profile);
        expect(
          resolver.cachedProfiles.map((p) => p.id),
          contains('${TerminalProfile.posixPrefix}$fishPath'),
        );
        // Idempotente
        resolver.addCustomProfile(profile);
        expect(
          resolver.cachedProfiles
              .where((p) => p.id == '${TerminalProfile.posixPrefix}$fishPath')
              .length,
          1,
        );
        // Remover
        resolver.removeCustomProfile('${TerminalProfile.posixPrefix}$fishPath');
        expect(
          resolver.cachedProfiles.map((p) => p.id),
          isNot(contains('${TerminalProfile.posixPrefix}$fishPath')),
        );
      },
    );

    test(
      'addCustomProfile antes do discover → no-op (cache ainda não existe)',
      () async {
        final resolver = TerminalProfileResolverImpl(
          operatingSystem: 'macos',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/bin/zsh',
          executableExists: (exe) async => true,
          extraProbePaths: const [],
          readEtcShells: () async => ['/bin/zsh'],
        );
        // Chama antes do discover — não deve inicializar _cache como lista vazia
        // (o que impediria o discover de rodar depois).
        const profile = TerminalProfile(
          id: 'posix:/some/shell',
          label: 'shell',
          executable: '/some/shell',
        );
        resolver.addCustomProfile(profile);

        // discover ainda deve funcionar e popular o cache normalmente.
        final profiles = await resolver.discover();
        expect(profiles, isNotEmpty);
        // O perfil adicionado antes do discover NÃO aparece (foi no-op).
        expect(profiles.map((p) => p.id), isNot(contains('posix:/some/shell')));
      },
    );
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

    test(
      'id nulo → fallback de plataforma (PowerShell no Windows x64)',
      () async {
        final r = await windows();
        expect(r.effectiveDefault(null).id, TerminalProfile.powershellId);
      },
    );

    test(
      'Windows ARM → fallback é cmd (PTY do powershell instável no ARM)',
      () async {
        final r = await windows(arm: true);
        expect(r.effectiveDefault(null).id, TerminalProfile.cmdId);
      },
    );

    test('POSIX id nulo → primeiro perfil (login shell)', () async {
      final r = TerminalProfileResolverImpl(
        operatingSystem: 'linux',
        runProcess: _FakeRunner(const {}).call,
        loginShell: () async => '/usr/bin/zsh',
        executableExists: (exe) async => true,
        extraProbePaths: const [],
        readEtcShells: () async => ['/bin/bash', '/usr/bin/zsh'],
      );
      await r.discover();
      // Login shell (/usr/bin/zsh) sempre vem primeiro
      expect(
        r.effectiveDefault(null).id,
        '${TerminalProfile.posixPrefix}/usr/bin/zsh',
      );
    });

    test(
      'POSIX id legado "login-shell" → fallback pro primeiro perfil',
      () async {
        final r = TerminalProfileResolverImpl(
          operatingSystem: 'macos',
          runProcess: _FakeRunner(const {}).call,
          loginShell: () async => '/bin/zsh',
          executableExists: (exe) async => true,
          extraProbePaths: const [],
          readEtcShells: () async => ['/bin/bash', '/bin/zsh'],
        );
        await r.discover();
        // 'login-shell' não existe mais no cache → cai no _platformFallback → primeiro
        expect(
          r.effectiveDefault(TerminalProfile.loginShellId).id,
          '${TerminalProfile.posixPrefix}/bin/zsh',
        );
      },
    );
  });
}
