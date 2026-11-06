import 'package:cockpit/app/cockpit/domain/services/http_environment_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = <String, String>{
    '/api/http-client.env.json': '''{
      "dev": {"host": "parent", "token": "public", "shared": "root", "client": {"port": 8080}},
      "prod": {"host": "production"}
    }''',
    '/api/http-client.private.env.json':
        '{"dev": {"token": "root-secret", "host": "root-private"}}',
    '/api/auth/http-client.env.json':
        '{"dev": {"host": "auth", "shared": "child"}}',
    '/api/auth/http-client.private.env.json':
        '{"dev": {"token": "auth-secret"}, "staging": {"host": "stage"}}',
  };
  Future<String?> read(String path) async => files[path];

  test(
    'arquivo filho combina ancestrais e prioriza seu próprio nível',
    () async {
      final catalog = await HttpEnvironmentCatalog.load(
        httpPath: '/api/auth/auth.http',
        rootPath: '/api',
        readText: read,
      );
      expect(catalog.names, ['dev', 'prod', 'staging']);
      expect(catalog.valuesFor('dev'), {
        'host': 'auth',
        'token': 'auth-secret',
        'shared': 'child',
        'client.port': '8080',
      });
      expect(catalog.valuesFor('prod'), {'host': 'production'});
    },
  );

  test('arquivo pai não lê ambientes da pasta filha', () async {
    final catalog = await HttpEnvironmentCatalog.load(
      httpPath: '/api/index.http',
      rootPath: '/api',
      readText: read,
    );
    expect(catalog.names, ['dev', 'prod']);
    expect(catalog.valuesFor('dev')['host'], 'root-private');
    expect(catalog.valuesFor('dev')['token'], 'root-secret');
    expect(catalog.valuesFor(null), isEmpty);
  });

  test('JSON inválido e arquivo ausente não impedem os demais', () async {
    final catalog = await HttpEnvironmentCatalog.load(
      httpPath: '/api/auth/auth.http',
      rootPath: '/api',
      readText: (path) async =>
          path == '/api/http-client.env.json' ? '{incompleto' : files[path],
    );
    expect(catalog.valuesFor('dev')['host'], 'auth');
    expect(catalog.valuesFor('dev')['token'], 'auth-secret');
  });

  test('caminhos Windows e POSIX mantêm a fronteira da raiz', () {
    expect(
      HttpEnvironmentCatalog.directoriesFor(
        r'C:\api\auth\nested\auth.http',
        r'C:\api',
      ),
      [r'C:\api', r'C:\api\auth', r'C:\api\auth\nested'],
    );
    expect(
      HttpEnvironmentCatalog.directoriesFor('/api/auth/auth.http', '/api'),
      ['/api', '/api/auth'],
    );
  });
}
