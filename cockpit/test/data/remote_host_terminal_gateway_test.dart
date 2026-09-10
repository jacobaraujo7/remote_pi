@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_host_terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integração da Wave 2 (plano 58): o gateway de terminal REMOTO, via túnel
/// SSH real. Requer:
/// - `./tool/build-sidecar.sh` (binário/dylib em build/wave0/);
/// - `ssh <COCKPIT_TEST_SSH_HOST>` sem senha (env; ex.: `jacob@localhost`
///   com a própria chave em authorized_keys).
/// Sem essas condições o teste é pulado (o backend já tem e2e dedicado).
void main() {
  final target = Platform.environment['COCKPIT_TEST_SSH_HOST'];
  final binary = File('build/wave0/cockpit-server');

  test('terminal remoto via SSH: eco, ack, kill', () async {
    if (target == null || !binary.existsSync()) {
      markTestSkipped(
        'defina COCKPIT_TEST_SSH_HOST e rode tool/build-sidecar.sh',
      );
      return;
    }

    final connector = RemoteHostConnector(
      RemoteHost(id: 't', name: 'test', sshTarget: target),
      localServerBinaryResolver: ({String? os, String? arch}) =>
          binary.absolute.path,
    );
    addTearDown(connector.dispose);

    final gateway = RemoteHostTerminalGateway(connector);
    final collected = StringBuffer();
    final sub = gateway.output.listen((data) {
      collected.write(utf8.decode(data, allowMalformed: true));
      gateway.acknowledgeOutput();
    });
    addTearDown(sub.cancel);

    // Working directory vazio = HOME remota do servidor.
    gateway.start(
      workingDirectory: '',
      profile: const TerminalProfile(
        id: 'login-shell',
        label: 'sh',
        executable: '/bin/sh',
      ),
    );
    gateway.write(utf8.encode('echo remote-\$((21*2))\n'));

    await _until(() => collected.toString().contains('remote-42'));
    expect(collected.toString(), contains('remote-42'));

    await gateway.kill();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _until(bool Function() test) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) fail('condição não satisfeita');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
