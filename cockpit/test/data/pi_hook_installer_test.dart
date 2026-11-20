import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cockpit/app/cockpit/data/hooks/pi_hook_installer_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pi extension reports identity over Unix without a TCP token', () async {
    ProcessResult version;
    try {
      version = await Process.run('node', ['--version']);
    } on ProcessException {
      markTestSkipped('Node.js unavailable for the native TypeScript fixture');
      return;
    }
    final major = int.tryParse(
      RegExp(r'^v(\d+)').firstMatch('${version.stdout}')?.group(1) ?? '',
    );
    if (major == null || major < 24) {
      markTestSkipped(
        'Node.js 24+ needed to execute the original TypeScript extension',
      );
      return;
    }
    final root = await Directory.systemTemp.createTemp('pi-wire-');
    final socketPath = '${root.path}/s';
    final server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final received = Completer<Map<String, dynamic>>();
    final subscription = server.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .then((line) {
            received.complete(jsonDecode(line) as Map<String, dynamic>);
            socket.destroy();
          });
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close();
      await root.delete(recursive: true);
    });
    await File(
      '${root.path}/extension.ts',
    ).writeAsString(PiHookInstallerImpl.source);
    final fixture = File('${root.path}/fixture.mjs');
    await fixture.writeAsString('''
import extension from './extension.ts';
const handlers = new Map();
extension({ on: (event, callback) => handlers.set(event, callback) });
await handlers.get('session_start')({}, { sessionManager: {
  getSessionId: () => 'fixture-session', getSessionFile: () => undefined,
} });
''');
    final result = await Process.run(
      'node',
      [fixture.path],
      environment: {
        'COCKPIT_TAB_ID': 'fixture-tab',
        'COCKPIT_STATUS_SOCK': socketPath,
        'COCKPIT_STATUS_TOKEN': '',
        'COCKPIT_STATUS_PORT': '',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final payload = await received.future.timeout(const Duration(seconds: 5));
    expect(payload['paneId'], 'fixture-tab');
    expect(payload['sid'], 'fixture-session');
    expect(payload['hn'], 'pi');
    expect(payload['pids'], [result.pid]);
    expect(payload['tok'], isEmpty);
  }, skip: Platform.isWindows);

  test(
    'does not create Pi configuration when Pi has never been configured',
    () async {
      final home = await Directory.systemTemp.createTemp('cockpit-pi-hook-');
      addTearDown(() => home.delete(recursive: true));
      await const PiHookInstallerImpl().writeConfig(
        home: home.path,
        command: 'unused',
      );
      expect(await Directory('${home.path}/.pi').exists(), isFalse);
    },
  );

  test(
    'installs identity extension idempotently and preserves user extensions',
    () async {
      final home = await Directory.systemTemp.createTemp('cockpit-pi-hook-');
      addTearDown(() => home.delete(recursive: true));
      final custom = File('${home.path}/.pi/agent/extensions/user.ts');
      await custom.parent.create(recursive: true);
      await custom.writeAsString('user extension');
      const installer = PiHookInstallerImpl();
      await installer.writeConfig(home: home.path, command: 'unused');
      final installed = File('${custom.parent.path}/cockpit-status.ts');
      expect(await installed.readAsString(), PiHookInstallerImpl.source);
      final modified = await installed.lastModified();
      await installer.writeConfig(home: home.path, command: 'unused');
      expect(await installed.lastModified(), modified);
      expect(await custom.readAsString(), 'user extension');
    },
  );
}
