import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = '''
@baseUrl = https://api.example.com
@token = abc123
@usersUrl = {{baseUrl}}/users

### Listar usuários
# só um comentário
GET {{usersUrl}}?page=1
Accept: application/json
Authorization: Bearer {{token}}

### Criar usuário
POST {{baseUrl}}/users
Content-Type: application/json

{
  "name": "Jacob",
  "note": "# isto não é comentário"
}

### Upload
PUT {{baseUrl}}/users/1
< ./body.json
''';

void main() {
  group('parse', () {
    final doc = HttpDocument.parse(_source);

    test('lê as variáveis do arquivo', () {
      expect(doc.variables, {
        'baseUrl': 'https://api.example.com',
        'token': 'abc123',
        'usersUrl': '{{baseUrl}}/users',
      });
    });

    test('separa os requests pelo ### e guarda o nome', () {
      expect(doc.requests.map((r) => r.name), [
        'Listar usuários',
        'Criar usuário',
        'Upload',
      ]);
      expect(doc.requests.map((r) => r.method), ['GET', 'POST', 'PUT']);
      expect(doc.requests.map((r) => r.requestLine), [6, 11, 20]);
    });

    test('headers ficam na ordem, sem o body', () {
      final r = doc.requests.first;
      expect(r.headers, [
        (name: 'Accept', value: 'application/json'),
        (name: 'Authorization', value: 'Bearer {{token}}'),
      ]);
      expect(r.body, isNull);
    });

    test('body literal preserva # interno e corta linhas em branco do fim', () {
      final r = doc.requests[1];
      expect(
        r.body,
        '{\n  "name": "Jacob",\n  "note": "# isto não é comentário"\n}',
      );
    });

    test('< arquivo vira bodyFile, não body', () {
      final r = doc.requests[2];
      expect(r.bodyFile, './body.json');
      expect(r.body, isNull);
    });
  });

  test('interpola variáveis, inclusive entre si', () {
    final doc = HttpDocument.parse(_source);
    final r = doc.resolveRequest(doc.requests.first);
    expect(r.url, 'https://api.example.com/users?page=1');
    expect(r.headers.last.value, 'Bearer abc123');
    expect(HttpDocument.unresolvedIn(r), isEmpty);
  });

  test('parâmetros em linhas seguintes compõem a URL sem virar body', () {
    const source = '''@baseUrl = https://shop.example
GET {{baseUrl}}/api/products
    ?page=1
    &pageSize=20
    &category=electronics
    &sortBy=price
    &sortOrder=asc
    &includeInactive=false
Accept: application/json
''';
    final document = HttpDocument.parse(source);
    final request = document.requests.single;
    expect(
      request.url,
      '{{baseUrl}}/api/products?page=1&pageSize=20&category=electronics&sortBy=price&sortOrder=asc&includeInactive=false',
    );
    expect(request.body, isNull);
    expect(request.headers.single.name, 'Accept');
    expect(
      document.resolveRequest(request).url,
      'https://shop.example/api/products?page=1&pageSize=20&category=electronics&sortBy=price&sortOrder=asc&includeInactive=false',
    );
  });

  test('parâmetros no body não alteram a URL', () {
    final document = HttpDocument.parse(
      'POST https://example.test/x\n\n?page=1\n&size=2\n',
    );
    final request = document.requests.single;
    expect(request.url, 'https://example.test/x');
    expect(request.body, '?page=1\n&size=2');
  });

  test('variável desconhecida sobra intacta e é reportada', () {
    final doc = HttpDocument.parse('GET https://a.b/{{missing}}\n');
    final r = doc.resolveRequest(doc.requests.single);
    expect(r.url, 'https://a.b/{{missing}}');
    expect(HttpDocument.unresolvedIn(r), ['missing']);
  });

  test('ambiente resolve placeholders e variável local pode sobrescrever', () {
    final doc = HttpDocument.parse(
      '@host = https://local.example\nGET {{host}}/x?token={{token}}\n',
    );
    final resolved = doc.resolveRequest(
      doc.requests.single,
      environment: {'host': 'https://env.example', 'token': 'secret'},
    );
    expect(resolved.url, 'https://local.example/x?token=secret');
    expect(HttpDocument.unresolvedIn(resolved), isEmpty);
  });

  test(
    'sobrescrita temporária vence ambiente, global, @ e variável de script',
    () {
      final doc = HttpDocument.parse('''
@host = https://local.example
@path = {{host}}/items
GET {{path}}/{{id}}
X-Token: {{token}}

{"enabled": {{enabled}}}
''');
      final overrides = {
        'host': 'https://temporary.example',
        'id': '42',
        'token': 'temporary',
        'enabled': 'true',
      };
      final resolved = doc.resolveRequest(
        doc.requests.single,
        environment: {'host': 'https://environment.example', 'id': '1'},
        globals: {'token': 'global'},
        requestVariables: {'id': '2'},
        overrides: overrides,
      );
      expect(resolved.url, 'https://temporary.example/items/42');
      expect(resolved.headers.single.value, 'temporary');
      expect(resolved.body, '{"enabled": true}');
      expect(
        doc.interpolate('{{path}}', overrides: overrides),
        'https://temporary.example/items',
      );
      expect(doc.variables['host'], 'https://local.example');
    },
  );

  test('variável indefinida aceita override vazio e volta a undefined', () {
    const source = 'GET https://example.test/{{missing}}';
    final doc = HttpDocument.parse(source);
    expect(HttpDocument.unresolvedPlaceholders(source), hasLength(1));
    expect(
      HttpDocument.unresolvedPlaceholders(source, overrides: {'missing': ''}),
      isEmpty,
    );
    expect(
      doc.resolveRequest(doc.requests.single, overrides: {'missing': ''}).url,
      'https://example.test/',
    );
    expect(
      doc.resolveRequest(doc.requests.single).url,
      contains('{{missing}}'),
    );
  });

  test('destaca apenas placeholders sem valor, fora de comentários', () {
    const source = '// {{comentario}}\nGET {{host}}/x?token={{token}}\n';
    final missing = HttpDocument.unresolvedPlaceholders(
      source,
      environment: {'host': 'https://example.com'},
    );
    expect(missing.map((m) => m.name), ['token']);
    expect(
      source.substring(missing.single.start, missing.single.end),
      '{{token}}',
    );
  });

  test('variáveis do script resolvem só a seção que foi executada', () {
    const source = '''
### Primeira
GET https://example.test/users?limit={{pageLimit}}

### Segunda
GET https://example.test/other?limit={{pageLimit}}
''';
    final missing = HttpDocument.unresolvedPlaceholders(
      source,
      requestVariablesByIndex: {
        0: {'pageLimit': '7'},
      },
    );
    expect(
      HttpDocument.parse(source).interpolate(
        '{{pageLimit}}',
        requestVariables: {'pageLimit': '7'},
      ),
      '7',
    );
    expect(missing.map((item) => item.name), ['pageLimit']);
    expect(
      source.substring(missing.single.start, missing.single.end),
      '{{pageLimit}}',
    );
    expect(missing.single.start, source.lastIndexOf('{{pageLimit}}'));
    expect(HttpDocument.unresolvedPlaceholders(source), hasLength(2));
  });

  test('globais de outra request resolvem placeholders em outro arquivo', () {
    const source = 'GET https://example.test/{{accessToken}}/{{missing}}\n';
    final missing = HttpDocument.unresolvedPlaceholders(
      source,
      globals: {'accessToken': 'token-from-login'},
    );
    expect(missing.map((item) => item.name), ['missing']);

    final document = HttpDocument.parse(source);
    final resolved = document.resolveRequest(
      document.requests.single,
      globals: {'accessToken': 'token-from-login'},
    );
    expect(resolved.url, 'https://example.test/token-from-login/{{missing}}');
  });

  test('casa o cursor com o request corrente', () {
    final doc = HttpDocument.parse(_source);
    expect(doc.requestIndexAtLine(0), 0); // preâmbulo cai no primeiro
    expect(doc.requestIndexAtLine(6), 0);
    expect(doc.requestIndexAtLine(12), 1);
    expect(doc.requestIndexAtLine(_source.split('\n').length - 2), 2);
  });

  test('arquivo de um request só, sem ###', () {
    final doc = HttpDocument.parse('POST https://a.b\nX-A: 1\n\nhello\n');
    final r = doc.requests.single;
    expect(r.method, 'POST');
    expect(r.headers.single, (name: 'X-A', value: '1'));
    expect(r.body, 'hello');
    expect(r.label, 'POST https://a.b');
    expect(r.requestLine, 0);
  });

  test('arquivo vazio ou só comentário não vira request', () {
    expect(HttpDocument.parse('').requests, isEmpty);
    expect(HttpDocument.parse('# nada aqui\n\n').requests, isEmpty);
  });

  test('# @name nomeia o request sem ###', () {
    final doc = HttpDocument.parse('# @name login\nPOST https://a.b/login\n');
    expect(doc.requests.single.name, 'login');
  });

  test('versão HTTP/1.1 na request-line é aceita e descartada', () {
    final doc = HttpDocument.parse('GET https://a.b/x HTTP/1.1\n');
    expect(doc.requests.single.url, 'https://a.b/x');
  });
}
