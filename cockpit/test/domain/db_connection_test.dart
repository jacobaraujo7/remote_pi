import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sqlite: url canônica e path', () {
    final c = DbConnection.sqlite('dev', './app.db');
    expect(c.url, 'sqlite:./app.db');
    expect(c.sqlitePath, './app.db');
    expect(c.engine, DbEngine.sqlite);
    expect(c.displayTarget, './app.db');
  });

  test('network: monta URL com porta default e parseia de volta', () {
    final c = DbConnection.network(
      name: 'staging',
      engine: DbEngine.postgres,
      host: 'db.acme.dev',
      database: 'app_dev',
      user: 'postgres',
    );
    expect(c.url, 'postgres://postgres@db.acme.dev:5432/app_dev');
    expect(c.host, 'db.acme.dev');
    expect(c.port, 5432);
    expect(c.database, 'app_dev');
    expect(c.user, 'postgres');
    expect(c.displayTarget, 'db.acme.dev:5432');
  });

  test('mysql usa porta default 3306', () {
    final c = DbConnection.network(
      name: 'm',
      engine: DbEngine.mysql,
      host: 'h',
      database: 'd',
    );
    expect(c.port, 3306);
    expect(c.engine, DbEngine.mysql);
  });

  test('json round-trip sem nunca conter senha', () {
    final c = DbConnection.network(
      name: 'staging',
      engine: DbEngine.postgres,
      host: 'h',
      database: 'd',
      savePassword: true,
    );
    final json = c.toJson();
    expect(
      json.keys,
      unorderedEquals(['name', 'url', 'savePassword', 'access', 'agents']),
    );
    final back = DbConnection.fromJson(json);
    expect(back.name, c.name);
    expect(back.url, c.url);
    expect(back.savePassword, isTrue);
    expect(back.engine, DbEngine.postgres);
  });

  test('userinfo com senha embutida: user NÃO inclui a senha', () {
    // Handoff 2026-07-18: user inteiro no username gerava senha com ':' extra
    // no wire e re-save percent-encodava o ':'.
    final c = DbConnection.fromJson({
      'name': 'pg',
      'url': 'postgres://bhuser:bhpassword@localhost:5432/biblia',
    });
    expect(c.user, 'bhuser');
    expect(c.urlPassword, 'bhpassword');
    expect(c.database, 'biblia');
  });

  test('sem senha na URL, urlPassword é null', () {
    final c = DbConnection.network(
      name: 'x',
      engine: DbEngine.postgres,
      host: 'h',
      database: 'd',
      user: 'u',
    );
    expect(c.urlPassword, isNull);
    expect(c.user, 'u');
  });

  test('re-save de conexão vinda de URL com senha não percent-encoda user', () {
    final c = DbConnection.fromJson({
      'name': 'pg',
      'url': 'postgres://bhuser:bhpassword@localhost:5432/biblia',
    });
    // Fluxo do dialog: reconstrói a partir dos campos exibidos.
    final resaved = DbConnection.network(
      name: c.name,
      engine: c.engine,
      host: c.host,
      port: c.port,
      database: c.database,
      user: c.user,
    );
    expect(resaved.url, isNot(contains('%3A')));
    expect(resaved.user, 'bhuser');
  });

  test('mongodb+srv resolve pro engine mongo', () {
    final c = DbConnection.fromJson({
      'name': 'atlas',
      'url': 'mongodb+srv://u:p@cluster0.x.mongodb.net/?retryWrites=true',
    });
    expect(c.engine, DbEngine.mongo);
    expect(c.isSrv, isTrue);
    expect(c.displayTarget, 'cluster0.x.mongodb.net');
  });

  test('senha crua sem percent-encoding é normalizada no fromJson', () {
    final c = DbConnection.fromJson({
      'name': 'pg',
      'url': 'postgres://userdev:8nJM9g8%?FC(@host.rds.amazonaws.com:5432/db',
    });
    expect(c.engine, DbEngine.postgres);
    expect(c.host, 'host.rds.amazonaws.com');
    expect(c.port, 5432);
    expect(c.user, 'userdev');
    expect(c.urlPassword, '8nJM9g8%?FC(');
  });

  test('tls ON grava o param por engine; OFF remove preservando o resto', () {
    final pg = DbConnection.network(
      name: 'pg',
      engine: DbEngine.postgres,
      host: 'h',
      database: 'd',
      tls: true,
    );
    expect(pg.url, contains('sslmode=require'));
    expect(pg.useTls, isTrue);

    final my = DbConnection.network(
      name: 'my',
      engine: DbEngine.mysql,
      host: 'h',
      database: 'd',
      tls: true,
    );
    expect(my.url, contains('ssl-mode=REQUIRED'));
    expect(my.useTls, isTrue);

    final ms = DbConnection.network(
      name: 'ms',
      engine: DbEngine.mssql,
      host: 'h',
      database: 'd',
      tls: true,
    );
    expect(ms.url, contains('encrypt=true'));
    expect(ms.useTls, isTrue);

    final mongo = DbConnection.network(
      name: 'mg',
      engine: DbEngine.mongo,
      host: 'h',
      database: 'd',
      tls: true,
    );
    expect(mongo.url, contains('tls=true'));
    expect(mongo.useTls, isTrue);

    // OFF: remove só a chave de TLS, preserva os demais params.
    final off = DbConnection.network(
      name: 'pg',
      engine: DbEngine.postgres,
      host: 'h',
      database: 'd',
      query: 'sslmode=require&application_name=cockpit',
    );
    expect(off.url, isNot(contains('sslmode')));
    expect(off.url, contains('application_name=cockpit'));
    expect(off.useTls, isFalse);
  });

  test('redis liga TLS pelo scheme rediss://', () {
    final r = DbConnection.network(
      name: 'r',
      engine: DbEngine.redis,
      host: 'h',
      database: '0',
      tls: true,
    );
    expect(r.url, startsWith('rediss://'));
    expect(r.useTls, isTrue);
    // fromJson reconhece o scheme de volta.
    final parsed = DbConnection.fromJson({'name': 'r', 'url': r.url});
    expect(parsed.engine, DbEngine.redis);
    expect(parsed.useTls, isTrue);
  });

  test('srv implica TLS sem escrever param redundante', () {
    final c = DbConnection.fromJson({
      'name': 'atlas',
      'url': 'mongodb+srv://u:p@c.mongodb.net/?retryWrites=true',
    });
    expect(c.useTls, isTrue);
    final resaved = DbConnection.network(
      name: c.name,
      engine: c.engine,
      host: c.host,
      database: c.database,
      srv: true,
      query: c.urlQuery,
      tls: true,
    );
    expect(resaved.url, startsWith('mongodb+srv://'));
    expect(resaved.url, contains('retryWrites=true'));
    expect(resaved.url, isNot(contains('tls=true')));
  });

  test('url de engine desconhecido lança FormatException', () {
    expect(
      () => DbConnection.fromJson({'name': 'x', 'url': 'oracle://h/db'}),
      throwsFormatException,
    );
  });
}
