import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ssh = SshTunnelConfig(
    host: 'bastion.acme.dev',
    user: 'deploy',
    keyPath: '~/.ssh/id_ed25519',
  );

  group('SshTunnelConfig', () {
    test('json round-trip preserva tudo e nunca carrega segredo', () {
      final json = ssh.copyWith(port: 2222, savePassphrase: true).toJson();
      expect(json['host'], 'bastion.acme.dev');
      expect(json['port'], 2222);
      expect(json['user'], 'deploy');
      expect(json['keyPath'], '~/.ssh/id_ed25519');
      expect(json['savePassphrase'], isTrue);
      // O que NÃO pode estar lá: qualquer forma de passphrase/chave.
      expect(json.keys, isNot(contains('passphrase')));
      expect(json.keys, isNot(contains('key')));

      final back = SshTunnelConfig.fromJson(json);
      expect(back, ssh.copyWith(port: 2222, savePassphrase: true));
    });

    test(
      'savePassphrase é sempre explícito (desligar não deixa true velho)',
      () {
        // A lição do savePassword: omitir no false deixava o valor antigo.
        expect(
          ssh.copyWith(savePassphrase: false).toJson()['savePassphrase'],
          isFalse,
        );
      },
    );

    test('bloco malformado vira null em vez de explodir', () {
      expect(SshTunnelConfig.fromJson(null), isNull);
      expect(SshTunnelConfig.fromJson('nope'), isNull);
      expect(SshTunnelConfig.fromJson({'host': 'h'}), isNull); // sem user/key
      expect(
        SshTunnelConfig.fromJson({'host': 'h', 'user': 'u', 'keyPath': ''}),
        isNull,
      );
    });

    test('porta default 22 quando ausente ou inválida', () {
      expect(
        SshTunnelConfig.fromJson({
          'host': 'h',
          'user': 'u',
          'keyPath': 'k',
        })!.port,
        22,
      );
      expect(
        SshTunnelConfig.fromJson({
          'host': 'h',
          'user': 'u',
          'keyPath': 'k',
          'port': 0,
        })!.port,
        22,
      );
    });
  });

  group('DbConnection + ssh', () {
    test('round-trip com bloco ssh no databases.json', () {
      final conn = DbConnection.network(
        name: 'prod',
        engine: DbEngine.postgres,
        host: 'localhost',
        database: 'app',
        user: 'postgres',
        ssh: ssh,
      );
      final back = DbConnection.fromJson(conn.toJson());
      expect(back.ssh, ssh);
      expect(back.hasSshTunnel, isTrue);
      // displayTarget continua mostrando o alvo REAL, não a ponta do túnel.
      expect(back.displayTarget, 'localhost:5432');
    });

    test('json legado (pré-plano 54) continua carregando sem túnel', () {
      final legacy = DbConnection.fromJson({
        'name': 'old',
        'url': 'postgres://u@h:5432/db',
        'savePassword': false,
      });
      expect(legacy.ssh, isNull);
      expect(legacy.hasSshTunnel, isFalse);
      // Sem túnel, a chave nem aparece no arquivo.
      expect(legacy.toJson().keys, isNot(contains('ssh')));
    });

    test('copyWith: omitido preserva o túnel, null explícito remove', () {
      final conn = DbConnection.network(
        name: 'p',
        engine: DbEngine.postgres,
        host: 'h',
        database: 'd',
        ssh: ssh,
      );
      expect(conn.copyWith(name: 'outro').ssh, ssh);
      expect(conn.copyWith(ssh: null).ssh, isNull);
    });

    test('withEndpoint redireciona host/porta preservando o resto', () {
      final conn = DbConnection.network(
        name: 'p',
        engine: DbEngine.postgres,
        host: 'db.internal',
        database: 'app',
        user: 'postgres',
        password: 's3cr3t',
        query: 'application_name=cockpit',
        tls: true,
        ssh: ssh,
      );
      final local = conn.withEndpoint('127.0.0.1', 55432);
      expect(local.host, '127.0.0.1');
      expect(local.port, 55432);
      expect(local.user, 'postgres');
      expect(local.urlPassword, 's3cr3t');
      expect(local.database, 'app');
      // Query params sobrevivem à reescrita — inclusive o TLS, que sem isso
      // seria silenciosamente rebaixado ao entrar no túnel.
      expect(local.url, contains('application_name=cockpit'));
      expect(local.useTls, isTrue);
      // O túnel não viaja na cópia — ela já está dentro dele.
      expect(local.ssh, isNull);
    });

    test('sqlite não aceita túnel (é arquivo local)', () {
      expect(DbEngine.sqlite.supportsSshTunnel, isFalse);
      for (final e in DbEngine.values.where((e) => e != DbEngine.sqlite)) {
        expect(e.supportsSshTunnel, isTrue, reason: e.name);
      }
    });
  });
}
