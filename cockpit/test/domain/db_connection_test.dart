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

  test('url de engine desconhecido lança FormatException', () {
    expect(
      () => DbConnection.fromJson({'name': 'x', 'url': 'oracle://h/db'}),
      throwsFormatException,
    );
  });
}
