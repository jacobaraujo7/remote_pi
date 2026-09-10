import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/posix_host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/windows_host_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Executor de SSH falso: grava os comandos e devolve respostas roteirizadas.
/// O bootstrap remoto não é testável de outro jeito sem uma máquina de verdade
/// do outro lado — e o que precisa ser verificado aqui é justamente o TEXTO do
/// comando, que é o que difere entre os dois dialetos.
class _FakeExec {
  _FakeExec(this._replies);

  final List<(int, String, String)> Function(String command) _replies;
  final List<String> commands = [];
  final List<List<int>?> stdinPayloads = [];

  Future<(int, String, String)> call(
    String command, {
    List<int>? stdinBytes,
  }) async {
    commands.add(command);
    stdinPayloads.add(stdinBytes);
    final replies = _replies(command);
    return replies.isEmpty ? (0, '', '') : replies.first;
  }
}

/// Executa os comandos POSIX de verdade, mas com HOME isolado. Assim os testes
/// de rollback cobrem renames e o filesystem, não só substrings do shell gerado.
class _RealPosixExec {
  _RealPosixExec({required this.home, String? pathPrefix})
    : _path = [
        ?pathPrefix,
        '/usr/local/bin',
        '/opt/homebrew/bin',
        '/usr/bin',
        '/bin',
        '/usr/sbin',
        '/sbin',
      ].join(':');

  final String home;
  final String _path;

  Future<(int, String, String)> call(
    String command, {
    List<int>? stdinBytes,
  }) async {
    final process = await Process.start(
      '/bin/sh',
      ['-c', command],
      environment: {'HOME': home, 'PATH': _path},
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    if (stdinBytes != null) process.stdin.add(stdinBytes);
    await process.stdin.close();
    final code = await process.exitCode;
    return (code, await stdout, await stderr);
  }
}

ClientBundle _posixTestBundle(Directory root) {
  final bin = Directory('${root.path}/bin')..createSync();
  final lib = Directory('${root.path}/lib')..createSync();
  final server = File('${bin.path}/cockpit-server')
    ..writeAsStringSync('new-server');
  File('${bin.path}/cockpit').writeAsStringSync('new-cli');
  File('${lib.path}/libcockpit_pty.dylib').writeAsStringSync('new-pty');
  return ClientBundle(root: root.path, serverBinary: server.path);
}

/// Desfaz o `-EncodedCommand`: base64 → UTF-16LE → script. É assim que os
/// testes olham o que de fato roda no host.
String _decodePowerShell(String command) {
  final marker = '-EncodedCommand ';
  final b64 = command.substring(command.indexOf(marker) + marker.length).trim();
  final bytes = base64.decode(b64);
  final units = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}

const _posixProbe = HostProbe(
  family: HostOsFamily.posix,
  os: 'darwin',
  arch: 'arm64',
  home: '/Users/jacob',
);

const _windowsProbe = HostProbe(
  family: HostOsFamily.windows,
  os: 'windows',
  arch: 'x64',
  home: r'C:\Users\jacob',
);

void main() {
  group('probeHost', () {
    test('identifica POSIX pelo uname, num único comando', () async {
      final exec = _FakeExec((_) => [(0, 'Darwin arm64\n/Users/jacob', '')]);
      final probe = await probeHost(exec.call);

      expect(probe!.family, HostOsFamily.posix);
      expect(probe.os, 'darwin');
      expect(probe.arch, 'arm64');
      expect(probe.home, '/Users/jacob');
      // O probe substituiu o `printf %s "$HOME"` que o SshTunnel fazia: se
      // voltar a custar dois round-trips, o caminho POSIX ficou mais lento.
      expect(exec.commands, hasLength(1));
    });

    test('Linux x86_64 vira x64', () async {
      final exec = _FakeExec((_) => [(0, 'Linux x86_64\n/home/j', '')]);
      final probe = await probeHost(exec.call);
      expect(probe!.os, 'linux');
      expect(probe.arch, 'x64');
    });

    test('aarch64 vira arm64', () async {
      final exec = _FakeExec((_) => [(0, 'Linux aarch64\n/home/j', '')]);
      expect((await probeHost(exec.call))!.arch, 'arm64');
    });

    test('cai pro PowerShell quando o uname falha', () async {
      final exec = _FakeExec(
        (cmd) => cmd.startsWith('uname')
            // O cmd.exe responde na codepage local; o conteúdo não importa,
            // o que importa é o exit != 0.
            ? [(1, '', "'uname' não é reconhecido")]
            : [(0, '{"arch":"x64","home":"C:\\\\Users\\\\jacob"}', '')],
      );
      final probe = await probeHost(exec.call);

      expect(probe!.family, HostOsFamily.windows);
      expect(probe.os, 'windows');
      expect(probe.home, r'C:\Users\jacob');
      expect(exec.commands, hasLength(2));
    });

    test('nao confia em 2 linhas quando o exit code nao e zero', () async {
      // Regressao do iPad: o `run` do dartssh2 mescla stderr no stdout, entao
      // o erro do `cmd.exe` ("'uname' nao e reconhecido...", DUAS linhas) tinha
      // a forma exata de um POSIX que respondeu. Quem separa os dois casos e
      // o exit code — por isso ele nao pode ser presumido zero.
      final exec = _FakeExec(
        (cmd) => cmd.startsWith('uname')
            ? [(1, "'uname' nao e reconhecido\\nou externo, em lotes.", '')]
            : [(0, '{"arch":"x64","home":"C:\\\\Users\\\\jacob"}', '')],
      );
      final probe = await probeHost(exec.call);

      expect(probe!.family, HostOsFamily.windows);
      expect(probe.home, r'C:\Users\jacob');
    });

    test('devolve null quando nenhum dialeto responde', () async {
      final exec = _FakeExec((_) => [(127, '', 'no shell')]);
      expect(await probeHost(exec.call), isNull);
    });
  });

  group('windowsPowerShellCommand (D1)', () {
    test('embrulha em -EncodedCommand com base64 de UTF-16LE', () {
      final command = windowsPowerShellCommand("'olá'");
      expect(command, startsWith('powershell -NoProfile -EncodedCommand '));
      expect(_decodePowerShell(command), contains("'olá'"));
    });

    test('injeta o preâmbulo de UTF-8 — mata o CP-850 na origem', () {
      final script = _decodePowerShell(windowsPowerShellCommand('whoami'));
      expect(script, startsWith('[Console]::OutputEncoding'));
    });

    test('não deixa aspas nem espaço vazarem para o argv', () {
      // Caminho com espaço é o caso que quebrava em comando de texto: nosso
      // argv → ssh → cmd → PowerShell, quatro níveis de escape.
      final command = windowsPowerShellCommand(
        r'Test-Path "C:\Users\John Smith\.cockpit"',
      );
      final b64 = command.split('-EncodedCommand ').last;
      expect(b64, isNot(contains(' ')));
      expect(b64, isNot(contains('"')));
      expect(_decodePowerShell(command), contains(r'C:\Users\John Smith'));
    });
  });

  group('WindowsHostShell', () {
    WindowsHostShell shellWith(_FakeExec exec) =>
        WindowsHostShell(probe: _windowsProbe, exec: exec.call);

    test('readEndpoint devolve porta e token do rendezvous', () async {
      final exec = _FakeExec(
        (_) => [(0, '{"v":1,"port":51515,"token":"abc123"}', '')],
      );
      final endpoint = await shellWith(exec).readEndpoint();

      expect(endpoint, isA<TcpEndpoint>());
      expect((endpoint! as TcpEndpoint).port, 51515);
      expect(endpoint.token, 'abc123');
    });

    test('readEndpoint devolve null sem servidor (arquivo ausente)', () async {
      final exec = _FakeExec((_) => [(0, '', '')]);
      expect(await shellWith(exec).readEndpoint(), isNull);
    });

    test('readEndpoint tolera JSON pela metade (escrita em curso)', () async {
      final exec = _FakeExec((_) => [(0, '{"v":1,"por', '')]);
      expect(await shellWith(exec).readEndpoint(), isNull);
    });

    test('startServer usa WMI, não Start-Process (spike 2026-08-26)', () async {
      final exec = _FakeExec((_) => [(0, 'started', '')]);
      await shellWith(exec).startServer(idleSeconds: 120);

      final script = _decodePowerShell(exec.commands.single);
      // A sessão do sshd roda dentro de um Job Object com kill-on-close: todo
      // filho morre junto. Só quem não nasce como filho sobrevive.
      expect(script, contains('Win32_Process'));
      expect(script, contains('Create'));
      expect(script, isNot(contains('Start-Process')));
      // O WMI não redireciona stdout/stderr — sem o cmd /c o boot.log fica
      // vazio e um servidor que não sobe não deixa rastro.
      // `/s` não é detalhe: sem ele o cmd remove a primeira e a última aspas
      // da linha, e a última é a do caminho do log — o redirect sumia junto.
      expect(script, contains('cmd.exe /s /c'));
      expect(script, contains('--exit-on-idle 120'));
      expect(script, contains('--idle-keeps-sessions'));
    });

    test('killServer filtra pelo caminho, não pelo nome', () async {
      final exec = _FakeExec((_) => [(0, '', '')]);
      await shellWith(exec).killServer();

      final script = _decodePowerShell(exec.commands.single);
      // Matar por nome derrubaria o sidecar da GUI de quem está sentado na
      // máquina, junto com os terminais locais dele.
      expect(script, contains('ExecutablePath'));
      expect(script, contains(r'.cockpit\server\bin\cockpit-server.exe'));
    });

    test('installFromHost devolve false sem Cockpit no host (D2)', () async {
      final exec = _FakeExec((_) => [(0, 'missing', '')]);
      expect(await shellWith(exec).installFromHost(), isFalse);
    });

    test('installFromHost copia LOCALMENTE, sem tráfego pelo SSH', () async {
      final exec = _FakeExec((_) => [(0, 'ok', '')]);
      expect(await shellWith(exec).installFromHost(), isTrue);

      final script = _decodePowerShell(exec.commands.single);
      expect(script, contains('Copy-Item'));
      expect(script, contains('cockpit-server-bundle'));
    });

    test('serverSha256 usa Get-FileHash', () async {
      final hash = 'A' * 64;
      final exec = _FakeExec((_) => [(0, hash, '')]);
      expect(await shellWith(exec).serverSha256(), hash.toLowerCase());
      expect(_decodePowerShell(exec.commands.single), contains('Get-FileHash'));
    });

    test('serverSha256 devolve null com saída inesperada', () async {
      final exec = _FakeExec((_) => [(0, 'não achei', '')]);
      expect(await shellWith(exec).serverSha256(), isNull);
    });

    test('instalar a partir do cliente é recusado (D2)', () async {
      final exec = _FakeExec((_) => [(0, '', '')]);
      expect(
        () => shellWith(exec).installFromClient(
          const ClientBundle(root: '/tmp/b', serverBinary: '/tmp/b/bin/s'),
        ),
        throwsA(isA<HostShellException>()),
      );
    });
  });

  group('PosixHostShell (comportamento preservado)', () {
    PosixHostShell shellWith(_FakeExec exec) =>
        PosixHostShell(probe: _posixProbe, exec: exec.call);

    test('readEndpoint é determinístico e não gasta SSH', () async {
      final exec = _FakeExec((_) => [(0, '', '')]);
      final endpoint = await shellWith(exec).readEndpoint();

      expect(endpoint, isA<UnixSocketEndpoint>());
      expect(
        (endpoint! as UnixSocketEndpoint).path,
        '/Users/jacob/.cockpit/cockpit-server.sock',
      );
      // A ausência de servidor segue sendo descoberta pelo túnel, como antes
      // do plano 61 — é o que preserva a latência de abertura.
      expect(exec.commands, isEmpty);
    });

    test('startServer segue no nohup, com log de arranque', () async {
      final exec = _FakeExec((_) => [(0, 'started', '')]);
      await shellWith(exec).startServer(idleSeconds: 120);

      final command = exec.commands.single;
      expect(command, contains('nohup'));
      expect(command, contains('libcockpit_pty.dylib'));
      expect(command, contains('--exit-on-idle 120'));
      expect(command, contains('server-boot.log'));
    });

    test('startServer no Linux pede a .so', () async {
      final exec = _FakeExec((_) => [(0, 'started', '')]);
      await PosixHostShell(
        probe: const HostProbe(
          family: HostOsFamily.posix,
          os: 'linux',
          arch: 'x64',
          home: '/home/j',
        ),
        exec: exec.call,
      ).startServer(idleSeconds: 120);

      expect(exec.commands.single, contains('libcockpit_pty.so'));
    });

    test('serverInstalled exige executável e manifesto completo', () async {
      final exec = _FakeExec((_) => [(0, 'yes', '')]);
      expect(await shellWith(exec).serverInstalled(), isTrue);
      expect(exec.commands.single, contains('test -x'));
      expect(exec.commands.single, contains('bundle.manifest'));
    });

    test('freshness lê o digest do manifesto instalado', () async {
      final hash = 'B' * 64;
      final exec = _FakeExec((_) => [(0, hash, '')]);
      expect(await shellWith(exec).bundleManifestSha256(), hash.toLowerCase());
      expect(exec.commands.single, contains('bundle.manifest'));
    });

    test(
      'instala no staging, verifica manifesto e só então troca o live',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'cockpit-posix-install',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final bin = Directory('${root.path}/bin')..createSync();
        final lib = Directory('${root.path}/lib')..createSync();
        final server = File('${bin.path}/cockpit-server')
          ..writeAsStringSync('server');
        File('${bin.path}/cockpit').writeAsStringSync('cli');
        File('${lib.path}/libcockpit_pty.dylib').writeAsStringSync('pty');
        final exec = _FakeExec((_) => [(0, '', '')]);

        await shellWith(exec).installFromClient(
          ClientBundle(root: root.path, serverBinary: server.path),
        );

        final manifestIndex = exec.commands.indexWhere(
          (command) =>
              command.contains('cat >') && command.contains('bundle.manifest'),
        );
        final swapIndex = exec.commands.indexWhere(
          (command) => command.contains('sha256sum -c bundle.manifest'),
        );
        expect(manifestIndex, greaterThan(0));
        expect(swapIndex, greaterThan(manifestIndex));
        expect(exec.commands.first, contains('while ! mkdir'));
        expect(exec.commands.first, contains('server.install.lock'));
        expect(exec.commands.first, contains('-mmin +10'));
        expect(exec.commands.first, contains('attempt" -ge 30'));
        final staleCleanupIndex = exec.commands.indexWhere(
          (command) => command.contains('server.staging-*'),
        );
        expect(staleCleanupIndex, greaterThan(0));
        expect(staleCleanupIndex, lessThan(manifestIndex));
        expect(exec.commands[swapIndex], contains('server.previous-'));
        expect(
          exec.commands[swapIndex],
          contains('no_nest_rename "\$HOME/.cockpit/server.staging-'),
        );
        expect(exec.commands[swapIndex], contains('mv -T -- "\$1" "\$2"'));
        expect(exec.commands[swapIndex], contains('os.rename'));
        expect(exec.commands[swapIndex], contains('perl -e'));
        expect(
          exec.commands[swapIndex],
          contains('needs GNU mv -T, python3, or perl'),
        );
        expect(exec.commands[swapIndex], isNot(contains('mv "\$1" "\$2"')));
        expect(exec.commands[swapIndex], contains('"\$HOME/.cockpit/server"'));
        expect(
          exec.commands[swapIndex],
          isNot(contains('mv "\$HOME/.cockpit/server.staging-')),
        );
        expect(
          exec.commands[swapIndex],
          contains('live directory changed during promotion'),
        );
        expect(
          exec.commands.last,
          contains('rm -rf "\$HOME/.cockpit/server.install.lock"'),
        );
        final manifestText = utf8.decode(exec.stdinPayloads[manifestIndex]!);
        expect(manifestText, contains('  bin/cockpit-server\n'));
        expect(manifestText, contains('  bin/cockpit\n'));
        expect(manifestText, contains('  lib/libcockpit_pty.dylib\n'));
      },
    );

    test('upload interrompido não promove staging parcial', () async {
      final root = Directory.systemTemp.createTempSync('cockpit-posix-fail');
      addTearDown(() => root.deleteSync(recursive: true));
      final bin = Directory('${root.path}/bin')..createSync();
      final lib = Directory('${root.path}/lib')..createSync();
      final server = File('${bin.path}/cockpit-server')
        ..writeAsStringSync('server');
      File('${lib.path}/libcockpit_pty.dylib').writeAsStringSync('pty');
      final exec = _FakeExec(
        (command) => command.contains('libcockpit_pty.dylib')
            ? [(1, '', 'network cut')]
            : [(0, '', '')],
      );

      await expectLater(
        shellWith(exec).installFromClient(
          ClientBundle(root: root.path, serverBinary: server.path),
        ),
        throwsA(
          isA<HostShellException>().having(
            (error) => error.detail,
            'detail',
            'network cut',
          ),
        ),
      );

      expect(
        exec.commands,
        isNot(contains(contains('sha256sum -c bundle.manifest'))),
      );
      final cleanupIndex = exec.commands.indexWhere(
        (command) =>
            command.contains('rm -rf "\$HOME/.cockpit/server.staging-'),
      );
      expect(cleanupIndex, greaterThan(0));
      expect(exec.commands[cleanupIndex], contains('server.previous-'));
      expect(exec.commands.last, contains('server.install.lock'));
      expect(exec.commands.last, contains('rm -rf'));
    });

    test('lock ocupado/timeout impede qualquer upload ou promoção', () async {
      final root = Directory.systemTemp.createTempSync('cockpit-posix-locked');
      addTearDown(() => root.deleteSync(recursive: true));
      final bin = Directory('${root.path}/bin')..createSync();
      final server = File('${bin.path}/cockpit-server')
        ..writeAsStringSync('server');
      final exec = _FakeExec(
        (command) => command.contains('while ! mkdir')
            ? [(75, '', 'install lock timed out')]
            : [(0, '', '')],
      );

      await expectLater(
        shellWith(exec).installFromClient(
          ClientBundle(root: root.path, serverBinary: server.path),
        ),
        throwsA(
          isA<HostShellException>().having(
            (error) => error.detail,
            'detail',
            'install lock timed out',
          ),
        ),
      );

      expect(exec.commands, hasLength(1));
      expect(exec.stdinPayloads, everyElement(isNull));
    });

    test('falha na promoção repara backup antes de soltar o lock', () async {
      final root = Directory.systemTemp.createTempSync(
        'cockpit-posix-rollback',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final bin = Directory('${root.path}/bin')..createSync();
      final server = File('${bin.path}/cockpit-server')
        ..writeAsStringSync('server');
      final exec = _FakeExec(
        (command) => command.contains('sha256sum -c bundle.manifest')
            ? [(76, '', 'cut between renames')]
            : [(0, '', '')],
      );

      await expectLater(
        shellWith(exec).installFromClient(
          ClientBundle(root: root.path, serverBinary: server.path),
        ),
        throwsA(isA<HostShellException>()),
      );

      final promotionIndex = exec.commands.indexWhere(
        (command) => command.contains('sha256sum -c bundle.manifest'),
      );
      final recoveryIndex = exec.commands.lastIndexWhere(
        (command) =>
            !command.contains('sha256sum -c bundle.manifest') &&
            command.contains(
              'no_nest_rename "\$HOME/.cockpit/server.previous-',
            ) &&
            command.contains('"\$HOME/.cockpit/server"'),
      );
      final releaseIndex = exec.commands.lastIndexWhere(
        (command) =>
            command.contains('rm -rf "\$HOME/.cockpit/server.install.lock"'),
      );
      expect(recoveryIndex, greaterThan(promotionIndex));
      expect(releaseIndex, greaterThan(recoveryIndex));
      expect(
        exec.commands[recoveryIndex],
        isNot(contains('rm -rf "\$HOME/.cockpit/server.previous-')),
      );
    });

    test(
      'guard de promoção põe live inesperado em conflito sem aninhar backup',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'cockpit-posix-guard-fs',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final home = Directory('${root.path}/home')..createSync();
        final cockpit = Directory('${home.path}/.cockpit')..createSync();
        final live = Directory('${cockpit.path}/server')..createSync();
        File('${live.path}/known-good').writeAsStringSync('old');
        final fakeBin = Directory('${root.path}/fake-bin')..createSync();
        final fakeMv = File('${fakeBin.path}/mv')
          ..writeAsStringSync(r'''#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "mv (GNU coreutils) test double"
  exit 0
fi
if [ "$1" = "-T" ] && [ "$2" = "--" ]; then
  source=$3
  destination=$4
  case "$source" in
    "$HOME/.cockpit/server.staging-"*)
      if [ "$destination" = "$HOME/.cockpit/server" ]; then
        # A corrida acontece dentro da primitiva, depois de qualquer guard.
        mkdir -p "$destination"
        printf '%s' unexpected > "$destination/unexpected"
        exit 1
      fi
      ;;
  esac
  exec /bin/mv "$source" "$destination"
fi
exec /bin/mv "$@"
''');
        Process.runSync('/bin/chmod', ['+x', fakeMv.path]);
        final bundleRoot = Directory('${root.path}/bundle')..createSync();
        final exec = _RealPosixExec(home: home.path, pathPrefix: fakeBin.path);
        final shell = PosixHostShell(probe: _posixProbe, exec: exec.call);

        await expectLater(
          shell.installFromClient(_posixTestBundle(bundleRoot)),
          throwsA(isA<HostShellException>()),
        );

        expect(File('${live.path}/known-good').readAsStringSync(), 'old');
        expect(
          live.listSync().where(
            (entity) => entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('server.previous-'),
          ),
          isEmpty,
        );
        final conflicts = cockpit
            .listSync()
            .where(
              (entity) => entity.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('server.conflict-'),
            )
            .toList();
        expect(conflicts, hasLength(1));
        expect(
          File('${conflicts.single.path}/unexpected').readAsStringSync(),
          'unexpected',
        );
        expect(
          cockpit.listSync().where(
            (entity) => entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('server.previous-'),
          ),
          isEmpty,
        );
        final stages = cockpit
            .listSync()
            .whereType<Directory>()
            .where(
              (directory) => directory.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('server.staging-'),
            )
            .toList();
        expect(stages, hasLength(1));
        expect(
          File('${stages.single.path}/bin/cockpit-server').readAsStringSync(),
          'new-server',
        );
      },
      skip: Platform.isWindows,
    );

    test(
      'recovery anterior recusa live surgido no rename sem aninhar backup',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'cockpit-posix-prior-recovery-race',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final home = Directory('${root.path}/home')..createSync();
        final cockpit = Directory('${home.path}/.cockpit')..createSync();
        final prior = Directory('${cockpit.path}/server.previous-interrupted')
          ..createSync();
        File('${prior.path}/known-good').writeAsStringSync('old');
        final fakeBin = Directory('${root.path}/fake-bin')..createSync();
        final fakeMv = File('${fakeBin.path}/mv')
          ..writeAsStringSync(r'''#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "mv (GNU coreutils) test double"
  exit 0
fi
if [ "$1" = "-T" ] && [ "$2" = "--" ]; then
  source=$3
  destination=$4
  case "$source" in
    "$HOME/.cockpit/server.previous-"*)
      if [ "$destination" = "$HOME/.cockpit/server" ]; then
        mkdir -p "$destination"
        printf '%s' raced > "$destination/unexpected"
        exit 1
      fi
      ;;
  esac
  exec /bin/mv "$source" "$destination"
fi
exec /bin/mv "$@"
''');
        Process.runSync('/bin/chmod', ['+x', fakeMv.path]);
        final bundleRoot = Directory('${root.path}/bundle')..createSync();
        final exec = _RealPosixExec(home: home.path, pathPrefix: fakeBin.path);
        final shell = PosixHostShell(probe: _posixProbe, exec: exec.call);

        await expectLater(
          shell.installFromClient(_posixTestBundle(bundleRoot)),
          throwsA(isA<HostShellException>()),
        );

        expect(File('${prior.path}/known-good').readAsStringSync(), 'old');
        expect(
          File('${cockpit.path}/server/unexpected').readAsStringSync(),
          'raced',
        );
        expect(
          Directory(
            '${cockpit.path}/server/server.previous-interrupted',
          ).existsSync(),
          isFalse,
        );
        expect(
          cockpit.listSync().where(
            (entity) => entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('server.staging-'),
          ),
          isEmpty,
        );
      },
      skip: Platform.isWindows,
    );

    test(
      'finally preserva live ambíguo e restaura backup sem aninhamento',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'cockpit-posix-finally-fs',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final home = Directory('${root.path}/home')..createSync();
        final cockpit = Directory('${home.path}/.cockpit')..createSync();
        final live = Directory('${cockpit.path}/server')..createSync();
        File('${live.path}/known-good').writeAsStringSync('old');
        final bundleRoot = Directory('${root.path}/bundle')..createSync();
        final realExec = _RealPosixExec(home: home.path);

        Future<(int, String, String)> interruptedExec(
          String command, {
          List<int>? stdinBytes,
        }) async {
          if (command.contains('sha256sum -c bundle.manifest')) {
            final stage = cockpit.listSync().whereType<Directory>().singleWhere(
              (directory) => directory.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('server.staging-'),
            );
            final token = stage.path
                .split(Platform.pathSeparator)
                .last
                .substring('server.staging-'.length);
            live.renameSync('${cockpit.path}/server.previous-$token');
            live.createSync();
            File('${live.path}/unexpected').writeAsStringSync('ambiguous');
            return (76, '', 'simulated transport cut between renames');
          }
          return realExec.call(command, stdinBytes: stdinBytes);
        }

        final shell = PosixHostShell(probe: _posixProbe, exec: interruptedExec);
        await expectLater(
          shell.installFromClient(_posixTestBundle(bundleRoot)),
          throwsA(isA<HostShellException>()),
        );

        expect(File('${live.path}/known-good').readAsStringSync(), 'old');
        expect(
          live.listSync().where(
            (entity) => entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('server.previous-'),
          ),
          isEmpty,
        );
        final conflicts = cockpit
            .listSync()
            .where(
              (entity) => entity.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('server.conflict-'),
            )
            .toList();
        expect(conflicts, hasLength(1));
        expect(
          File('${conflicts.single.path}/unexpected').readAsStringSync(),
          'ambiguous',
        );
        expect(
          cockpit.listSync().where(
            (entity) => entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('server.previous-'),
          ),
          isEmpty,
        );
      },
      skip: Platform.isWindows,
    );

    test('não instala a partir do host — é caminho de Windows', () async {
      final exec = _FakeExec((_) => [(0, '', '')]);
      expect(await shellWith(exec).installFromHost(), isFalse);
      expect(shellWith(exec).installsFromHostBundle, isFalse);
    });
  });
}
