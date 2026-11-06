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

  test('variável desconhecida sobra intacta e é reportada', () {
    final doc = HttpDocument.parse('GET https://a.b/{{missing}}\n');
    final r = doc.resolveRequest(doc.requests.single);
    expect(r.url, 'https://a.b/{{missing}}');
    expect(HttpDocument.unresolvedIn(r), ['missing']);
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
