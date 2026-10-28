import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/terminal_status_server_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late TerminalStatusServerImpl server;
  late List<CockpitCommand> received;
  late bool afterResponse;
  late Completer<void> lifecycle;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cockpit-cmd-wire-');
    server = TerminalStatusServerImpl(configurationDirectory: directory.path);
    received = [];
    afterResponse = false;
    lifecycle = Completer<void>();
    await server.start(
      (_) {},
      onCommand: (c) async {
        received.add(c);
        return CockpitCommandResult.ok('done', () {
          afterResponse = true;
          lifecycle.complete();
        });
      },
    );
    expect(server.hookEnv, isNotEmpty);
  });
  tearDown(() async {
    await server.stop();
    await directory.delete(recursive: true);
  });

  Future<Map<String, dynamic>> send(Map<String, dynamic> command) async {
    final env = server.hookEnv;
    final socket = Platform.isWindows
        ? await Socket.connect(
            InternetAddress.loopbackIPv4,
            int.parse(env['COCKPIT_STATUS_PORT']!),
          )
        : await Socket.connect(
            InternetAddress(
              env['COCKPIT_STATUS_SOCK']!,
              type: InternetAddressType.unix,
            ),
            0,
          );
    socket.writeln(
      jsonEncode({
        'type': 'cmd',
        'cmd': 'write',
        'tabId': 'destination',
        if (env['COCKPIT_STATUS_TOKEN'] case final String token) 'tok': token,
        ...command,
      }),
    );
    await socket.flush();
    final line = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    socket.destroy();
    return (jsonDecode(line) as Map).cast<String, dynamic>();
  }

  test(
    'real command transport preserves sender independently of target and flushes before lifecycle actions',
    () async {
      final result = await send({
        'callerTabId': 'source',
        'args': {'data': 'aGk='},
      });
      expect(result['ok'], isTrue);
      expect(received.single.callerTabId, 'source');
      expect(received.single.tabId, 'destination');
      expect(received.single.args, {'data': 'aGk='});
      await lifecycle.future.timeout(const Duration(seconds: 3));
      expect(afterResponse, isTrue);
    },
  );
  test(
    'legacy outside-app commands remain decodable without inventing a sender',
    () async {
      expect((await send({}))['ok'], isTrue);
      expect(received.single.callerTabId, isNull);
      await lifecycle.future.timeout(const Duration(seconds: 3));
    },
  );
  test(
    'malformed origins never reach a handler or lose their identity by fallback',
    () async {
      for (final source in [
        '',
        42,
        true,
        ['source'],
      ]) {
        expect((await send({'callerTabId': source}))['ok'], isFalse);
      }
      expect(received, isEmpty);
      expect(afterResponse, isFalse);
    },
  );
}
