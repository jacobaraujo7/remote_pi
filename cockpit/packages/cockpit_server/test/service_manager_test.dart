// `cockpit-server service …` sem tocar no systemd de verdade: o runner de
// comandos é injetado e grava o que seria executado; a unit vai numa pasta
// temporária no lugar do HOME.
import 'dart:io';

import 'package:cockpit_server/cockpit_server.dart';
import 'package:test/test.dart';

void main() {
  group('buildSystemdUnit', () {
    test('modo serviço: sem --exit-on-idle, com PTY e socket', () {
      final unit = buildSystemdUnit(
        serverBinary: '/home/u/.cockpit/server/bin/cockpit-server',
        ptyLibrary: '/home/u/.cockpit/server/lib/libcockpit_pty.so',
        socketPath: '/home/u/.cockpit/cockpit-server.sock',
      );
      expect(unit, contains('[Unit]'));
      expect(
        unit,
        contains(
          'ExecStart=/home/u/.cockpit/server/bin/cockpit-server '
          '--socket /home/u/.cockpit/cockpit-server.sock',
        ),
      );
      expect(
        unit,
        contains(
          'Environment=COCKPIT_PTY_DYLIB=/home/u/.cockpit/server/lib/libcockpit_pty.so',
        ),
      );
      expect(unit, isNot(contains('--exit-on-idle')));
      expect(unit, contains('Restart=on-failure'));
      expect(unit, contains('WantedBy=default.target'));
    });
  });

  group('ServiceManager', () {
    late Directory tmp;
    late List<String> calls;
    late StringBuffer out;
    late String bin;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('cockpit-service-');
      calls = [];
      out = StringBuffer();
      bin = '${tmp.path}/.cockpit/server/bin/cockpit-server';
      File(bin).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    ServiceManager manager({int lingerExit = 0}) => ServiceManager(
      home: tmp.path,
      serverBinary: bin,
      out: out,
      run: (exe, args) async {
        calls.add('$exe ${args.join(' ')}');
        if (exe == 'loginctl' && args.first == 'enable-linger') {
          return ProcessResult(0, lingerExit, '', lingerExit == 0 ? '' : 'denied');
        }
        return ProcessResult(0, 0, 'active', '');
      },
    );

    test(
      'install grava a unit, recarrega, habilita e liga o linger',
      () async {
        final code = await manager().install();
        expect(code, 0);
        final unit = File('${tmp.path}/.config/systemd/user/cockpit-server.service');
        expect(unit.existsSync(), isTrue);
        expect(unit.readAsStringSync(), contains('ExecStart=$bin'));
        expect(
          unit.readAsStringSync(),
          contains('${tmp.path}/.cockpit/server/lib/libcockpit_pty.so'),
        );
        expect(calls, [
          'systemctl --user daemon-reload',
          'systemctl --user enable --now cockpit-server.service',
          startsWith('loginctl enable-linger'),
        ]);
        expect(out.toString(), contains('starts at boot'));
      },
      skip: !Platform.isLinux ? 'systemd é Linux' : false,
    );

    test(
      'linger negado não falha o install e imprime o sudo',
      () async {
        final code = await manager(lingerExit: 1).install();
        expect(code, 0);
        expect(out.toString(), contains('sudo loginctl enable-linger'));
      },
      skip: !Platform.isLinux ? 'systemd é Linux' : false,
    );

    test(
      'uninstall desabilita, apaga a unit e recarrega',
      () async {
        final m = manager();
        await m.install();
        calls.clear();
        final code = await m.uninstall();
        expect(code, 0);
        expect(File(m.unitPath).existsSync(), isFalse);
        expect(calls, [
          'systemctl --user disable --now cockpit-server',
          'systemctl --user daemon-reload',
        ]);
      },
      skip: !Platform.isLinux ? 'systemd é Linux' : false,
    );

    test('verbo desconhecido devolve 2 com usage', () async {
      final code = await runServiceCommand(const ['bogus'], out: out);
      expect(code, 2);
      expect(out.toString(), contains('usage:'));
    });
  });
}
