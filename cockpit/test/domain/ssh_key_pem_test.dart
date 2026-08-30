import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Detecção de chave encriptada (plano 54, passo 4). É o que decide se o
/// dialog mostra o campo de passphrase e se o serviço precisa de segredo —
/// errar aqui significa ou pedir senha à toa, ou tentar conectar sem ela.
///
/// Fixtures geradas com `ssh-keygen` (ed25519 limpa, ed25519 e RSA com
/// passphrase `hunter2`) — chaves de teste, sem valor fora daqui.
void main() {
  const plain = 'test/fixtures/ssh/plain_ed25519';
  const encryptedEd = 'test/fixtures/ssh/encrypted_ed25519';
  const encryptedRsa = 'test/fixtures/ssh/encrypted_rsa';

  const inspector = SshKeyPemInspector();

  test('chave sem passphrase é reconhecida como limpa', () async {
    expect(await inspector.needsPassphrase(plain), isFalse);
  });

  test('openssh-key-v1 com cipher é reconhecida como encriptada', () async {
    expect(await inspector.needsPassphrase(encryptedEd), isTrue);
    expect(await inspector.needsPassphrase(encryptedRsa), isTrue);
  });

  test(
    'arquivo ausente não trava o dialog (erro real vem no connect)',
    () async {
      expect(await inspector.needsPassphrase('/nope/missing_key'), isFalse);
    },
  );

  test('read de chave ausente vira ssh_key_missing acionável', () async {
    await expectLater(
      SshKeyPem.read('/nope/missing_key'),
      throwsA(
        isA<SshTunnelException>().having(
          (e) => e.kind,
          'kind',
          'ssh_key_missing',
        ),
      ),
    );
  });

  group('parse', () {
    test('chave limpa decodifica sem passphrase', () async {
      final pem = await SshKeyPem.read(plain);
      expect(SshKeyPem.parse(pem, null), isNotEmpty);
    });

    test('encriptada sem passphrase → ssh_credential_required', () async {
      final pem = await SshKeyPem.read(encryptedEd);
      expect(
        () => SshKeyPem.parse(pem, null),
        throwsA(
          isA<SshTunnelException>().having(
            (e) => e.kind,
            'kind',
            'ssh_credential_required',
          ),
        ),
      );
    });

    test(
      'encriptada com passphrase errada → ssh_credential_required',
      () async {
        final pem = await SshKeyPem.read(encryptedEd);
        expect(
          () => SshKeyPem.parse(pem, 'wrong'),
          throwsA(
            isA<SshTunnelException>().having(
              (e) => e.kind,
              'kind',
              'ssh_credential_required',
            ),
          ),
        );
      },
    );

    test('encriptada com a passphrase certa decodifica', () async {
      final pem = await SshKeyPem.read(encryptedEd);
      expect(SshKeyPem.parse(pem, 'hunter2'), isNotEmpty);
    });
  });

  test('expand resolve ~ e deixa path absoluto intacto', () {
    expect(SshKeyPem.expand('/etc/key'), '/etc/key');
    final expanded = SshKeyPem.expand('~/.ssh/id_ed25519');
    expect(expanded, isNot(startsWith('~')));
    expect(expanded, endsWith('/.ssh/id_ed25519'));
  });
}
