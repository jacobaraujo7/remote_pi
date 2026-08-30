import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:cockpit/app/cockpit/data/remote/ssh_known_hosts.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host novo no desktop morria em `Host key verification failed`: o app roda o
/// ssh com `BatchMode=yes`, que não pode perguntar, e sem política de host key
/// o ssh recusa. Agora o humano decide — e a recusa dele é respeitada.
void main() {
  const host = RemoteHost(
    id: '1',
    name: 'iMac',
    sshTarget: 'flutterando@192.168.18.10',
  );

  RemoteHostConnector connector({
    required SshKnownHosts knownHosts,
    HostKeyPrompt? prompt,
  }) => RemoteHostConnector(
    host,
    localServerBinaryResolver: ({String? arch}) => null,
    hostKeyPrompt: prompt,
    knownHosts: knownHosts,
  );

  test('host desconhecido e prompt recusado não conecta', () async {
    final known = _FakeKnownHosts();
    final c = connector(
      knownHosts: known,
      prompt: (_, _) async => HostKeyVerdict.reject,
    );

    await expectLater(
      c.ensure(),
      throwsA(
        isA<RemoteHostException>().having(
          (e) => e.kind,
          'kind',
          RemoteHostErrorKind.hostKeyUnknown,
        ),
      ),
    );
    // Recusou = não grava nada. Um "trust" aqui seria TOFU cego, que é
    // exatamente o que este caminho existe para evitar.
    expect(known.trusted, isEmpty);
    await c.dispose();
  });

  test('sem ninguém pra perguntar, falha em vez de confiar sozinho', () async {
    final known = _FakeKnownHosts();
    final c = connector(knownHosts: known); // prompt null (CLI/teste)

    await expectLater(
      c.ensure(),
      throwsA(
        isA<RemoteHostException>().having(
          (e) => e.kind,
          'kind',
          RemoteHostErrorKind.hostKeyUnknown,
        ),
      ),
    );
    expect(known.trusted, isEmpty);
    await c.dispose();
  });

  test('destino com porta custom usa a forma [host]:porta do known_hosts', () {
    expect(SshKnownHosts.targetOf('example.com', 22), 'example.com');
    expect(SshKnownHosts.targetOf('example.com', 2222), '[example.com]:2222');
  });

  test('a chave escolhida sobrevive ao round-trip do JSON', () {
    const withKey = RemoteHost(
      id: '1',
      name: 'iMac',
      sshTarget: 'flutterando@192.168.18.10',
      identityFile: '/Users/jacob/.ssh/id_ed25519',
    );
    expect(
      RemoteHost.fromJson(withKey.toJson()).identityFile,
      '/Users/jacob/.ssh/id_ed25519',
    );

    // Registro antigo (sem o campo) segue válido: o ssh decide como sempre.
    final legacy = RemoteHost.fromJson({
      'id': '2',
      'name': 'old',
      'ssh': 'user@host',
      'port': 22,
      'auth': 'key',
    });
    expect(legacy.identityFile, isNull);
  });
}

/// `known_hosts` sem tocar no disco nem no `ssh-keygen` do sistema.
class _FakeKnownHosts implements SshKnownHosts {
  final List<String> trusted = [];

  @override
  Future<SshHostKeyStatus> lookup(String host, int port) async =>
      SshHostKeyStatus.unknown;

  @override
  Future<List<String>> scan(String host, int port) async => const [
    '192.168.18.10 ssh-ed25519 AAAAC3Nza...',
  ];

  @override
  Future<String?> fingerprintOf(List<String> keys) async =>
      '256 SHA256:abc123 192.168.18.10 (ED25519)';

  @override
  Future<void> trust(List<String> keys) async => trusted.addAll(keys);
}
