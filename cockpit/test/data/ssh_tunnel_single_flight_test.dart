import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoHostKeys implements SshHostKeyStore {
  @override
  String? trusted(String endpoint) => null;
  @override
  Future<void> trust(String endpoint, String fingerprint) async {}
  @override
  Future<void> forget(String endpoint) async {}
}

/// Chave que não existe: a abertura falha **antes** de qualquer socket, então
/// estes testes não tocam a rede — o que interessa aqui é o future voltar.
const _config = SshTunnelConfig(
  host: 'bastion.invalid',
  user: 'ninguem',
  keyPath: '/caminho/que/nao/existe/id_ed25519',
);

/// O bug que estes testes travam: o registro de "abertura em voo" era limpo com
/// `.whenComplete(() => _map.remove(key))` — em corpo de arrow. `Map.remove`
/// devolve o valor removido, que é o **próprio future**, e `whenComplete` então
/// passava a esperar o future que ele mesmo completa. Resultado: o primeiro
/// chamador nunca recebia resposta (nem sucesso nem erro), enquanto os
/// seguintes achavam o túnel já no cache e funcionavam — o sintoma era "a UI
/// trava pra sempre mas a CLI responde rápido".
void main() {
  late SshTunnelImpl tunnel;

  setUp(() => tunnel = SshTunnelImpl(_NoHostKeys()));
  tearDown(() => tunnel.closeAll());

  test('ensure devolve o erro em vez de pendurar', () async {
    await expectLater(
      tunnel
          .ensure(_config, targetHost: 'db.interno', targetPort: 5432)
          .timeout(const Duration(seconds: 10)),
      throwsA(isA<SshTunnelException>()),
    );
  });

  test('ensureSocks devolve o erro em vez de pendurar', () async {
    await expectLater(
      tunnel.ensureSocks(_config).timeout(const Duration(seconds: 10)),
      throwsA(isA<SshTunnelException>()),
    );
  });

  test(
    'falhar não deixa a abertura registrada: a 2ª tentativa também responde',
    () async {
      for (var i = 0; i < 2; i++) {
        await expectLater(
          tunnel.ensureSocks(_config).timeout(const Duration(seconds: 10)),
          throwsA(isA<SshTunnelException>()),
          reason: 'tentativa $i',
        );
      }
    },
  );

  test(
    'chamadas simultâneas compartilham a abertura e todas respondem',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          tunnel
              .ensureSocks(_config)
              .timeout(const Duration(seconds: 10))
              .then<Object?>((v) => v, onError: (Object e) => e),
      ]);
      expect(results, everyElement(isA<SshTunnelException>()));
    },
  );
}
