import 'package:cockpit/app/cockpit/domain/services/http_code_navigation.dart';
import 'package:cockpit/app/cockpit/domain/services/http_environment_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source =
      '@local = https://local.test\n'
      'GET {{host}}/users\n'
      'Accept: {{token}}\n'
      'GET {{local}}/health\n';
  const catalog = HttpEnvironmentCatalog(
    {
      'dev': {'host': 'https://api.test', 'token': 'abc'},
    },
    {
      'dev': {
        'host': HttpEnvironmentDefinition('/api/http-client.env.json', 4),
        'token': HttpEnvironmentDefinition(
          '/api/http-client.private.env.json',
          2,
        ),
      },
    },
  );

  HttpCodeLink? link(int offset, {int line = 1}) => HttpCodeNavigation.linkAt(
    displayText: source,
    offset: offset,
    sourceText: source,
    sourcePath: '/api/requests.http',
    sourceLine: line,
    environment: 'dev',
    catalog: catalog,
  );

  test('referência abre a definição que forneceu o valor', () {
    final host = link(source.indexOf('host'));
    expect(host?.path, '/api/http-client.env.json');
    expect(host?.line, 4);
    final token = link(source.indexOf('token'), line: 2);
    expect(token?.path, '/api/http-client.private.env.json');
    expect(token?.line, 2);
    final local = link(source.lastIndexOf('local'), line: 3);
    expect(local?.path, '/api/requests.http');
    expect(local?.line, 1);
  });

  test('verbo abre URL resolvida e metadados não são links', () {
    expect(link(source.indexOf('GET'))?.url, 'https://api.test/users');
    expect(link(source.indexOf('Accept'), line: 2), isNull);
    expect(link(source.indexOf('abc'), line: 2), isNull);
    expect(
      link(source.lastIndexOf('GET'), line: 3)?.url,
      'https://local.test/health',
    );
  });

  test('variável sem definição e URL sem resolução não abrem', () {
    const missing = 'GET {{unknown}}/users';
    final variable = HttpCodeNavigation.linkAt(
      displayText: missing,
      offset: missing.indexOf('unknown'),
      sourceText: missing,
      sourcePath: '/api/requests.http',
      sourceLine: 0,
      environment: 'dev',
      catalog: catalog,
    );
    expect(variable, isNull);
    expect(
      HttpCodeNavigation.linkAt(
        displayText: missing,
        offset: 1,
        sourceText: missing,
        sourcePath: '/api/requests.http',
        sourceLine: 0,
        environment: 'dev',
        catalog: catalog,
      ),
      isNull,
    );
  });

  test('verbo inclui parâmetros de URL em linhas seguintes', () {
    const request = 'GET https://api.test/users\n?active=true\n&limit=2';
    final target = HttpCodeNavigation.linkAt(
      displayText: request,
      offset: 1,
      sourceText: request,
      sourcePath: '/api/requests.http',
      sourceLine: 0,
      environment: null,
      catalog: const HttpEnvironmentCatalog({}),
    );
    expect(target?.url, 'https://api.test/users?active=true&limit=2');
  });

  test('verbo usa sobrescrita temporária ao abrir URL', () {
    final target = HttpCodeNavigation.linkAt(
      displayText: source,
      offset: source.indexOf('GET'),
      sourceText: source,
      sourcePath: '/api/requests.http',
      sourceLine: 1,
      environment: 'dev',
      catalog: catalog,
      overrides: {'host': 'https://temporary.test'},
    );
    expect(target?.url, 'https://temporary.test/users');
  });
}
