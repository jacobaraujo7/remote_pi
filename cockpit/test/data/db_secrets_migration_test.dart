import 'dart:io';

import 'package:cockpit/app/cockpit/data/db/db_secrets_impl.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cofre único por máquina (plano 62, 2ª rodada).
///
/// Antes eram dois na mesma máquina: workspace local no cofre do SO, cliente
/// remoto no arquivo. Como o `cockpit-server` é headless e nunca teve acesso ao
/// cofre do SO, a senha digitada no host não valia para cliente nenhum — o
/// usuário salvava com sucesso e o remoto seguia dizendo que não existia.
void main() {
  late Directory dir;
  late DbSecretStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cockpit-secrets-migration');
    store = DbSecretStore(path: '${dir.path}/db-secrets.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a chave local é a MESMA que o host usa', () {
    // O ponto do plano inteiro: o que o app grava num workspace local é o que
    // o cockpit-server procura ao atender um cliente remoto.
    expect(
      DbQueryService.secretKey('/srv/proj', 'dev-local'),
      DbSecretStore.keyFor('/srv/proj', 'dev-local'),
    );
  });

  test('a chave não depende mais do workspaceId', () {
    // Era a causa raiz: o id é gerado por máquina, então cada cliente
    // procurava numa chave diferente.
    final deUmCliente = DbQueryService.secretKey('/srv/proj', 'dev');
    final deOutro = DbQueryService.secretKey('/srv/proj', 'dev');
    expect(deUmCliente, deOutro);
    expect(deUmCliente, isNot(contains('cockpit.db.')));
  });

  test('passphrase SSH não colide com senha de banco', () {
    expect(
      DbQueryService.sshSecretKey('/srv/proj', 'dev'),
      isNot(DbQueryService.secretKey('/srv/proj', 'dev')),
    );
  });

  test('lê do cofre novo sem tocar no legado', () async {
    final legacy = _SpyLegacy();
    final secrets = DbSecretsImpl(store: store, legacy: legacy);

    await secrets.write('k', 'valor');

    expect(await secrets.read('k', legacyKey: 'antiga'), 'valor');
    expect(legacy.reads, isEmpty, reason: 'não deve consultar o cofre do SO');
  });

  test('migra do cofre do SO na primeira leitura e apaga de lá', () async {
    final legacy = _SpyLegacy({'cockpit.db.w1.dev': 'senha-do-keychain'});
    final secrets = DbSecretsImpl(store: store, legacy: legacy);
    const key = 'chave-nova';

    expect(
      await secrets.read(key, legacyKey: 'cockpit.db.w1.dev'),
      'senha-do-keychain',
    );

    // Ficou no cofre único — é o que o cockpit-server lê.
    expect(store.readKey(key), 'senha-do-keychain');
    // E saiu do antigo, para não haver duas fontes divergindo.
    expect(legacy.values, isEmpty);

    // Segunda leitura já não consulta o legado.
    legacy.reads.clear();
    expect(await secrets.read(key, legacyKey: 'cockpit.db.w1.dev'), isNotNull);
    expect(legacy.reads, isEmpty);
  });

  test('cofre do SO indisponível não derruba a leitura', () async {
    // Keychain trancado, prompt recusado, Secret Service ausente no Linux: o
    // certo é seguir sem senha (o usuário redigita), não estourar a query.
    final secrets = DbSecretsImpl(store: store, legacy: _ThrowingLegacy());
    expect(await secrets.read('k', legacyKey: 'antiga'), isNull);
  });
}

class _SpyLegacy implements FlutterSecureStorage {
  _SpyLegacy([Map<String, String>? seed]) : values = {...?seed};
  final Map<String, String> values;
  final reads = <String>[];

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic wOptions, dynamic mOptions, dynamic webOptions}) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _ThrowingLegacy implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('cofre do SO indisponível');
}
