import 'dart:convert';

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

  Future<(int, String, String)> call(
    String command, {
    List<int>? stdinBytes,
  }) async {
    commands.add(command);
    final replies = _replies(command);
    return replies.isEmpty ? (0, '', '') : replies.first;
  }
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

    test('não instala a partir do host — é caminho de Windows', () async {
      final exec = _FakeExec((_) => [(0, '', '')]);
      expect(await shellWith(exec).installFromHost(), isFalse);
      expect(shellWith(exec).installsFromHostBundle, isFalse);
    });
  });
}
