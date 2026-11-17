import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/http/http_request_runner_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String base;
  final runner = HttpRequestRunnerImpl();

  setUpAll(() async {
    // O flutter_test_config inicializa o binding, que instala um HttpClient
    // falso (responde 400 a tudo). Este teste fala com um servidor real.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      switch (req.uri.path) {
        case '/json':
          req.response.headers.contentType = ContentType.json;
          req.response.write('{"hello":"world"}');
        case '/echo':
          final body = await utf8.decodeStream(req);
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'method': req.method,
              'body': body,
              'contentType': req.headers.value('content-type'),
              'auth': req.headers.value('authorization'),
            }),
          );
        case '/text':
          req.response.write('plain');
        case '/404':
          req.response.statusCode = 404;
          req.response.write('nope');
        default:
          req.response.statusCode = 500;
      }
      await req.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  HttpRequestSpec specOf(String source) {
    final doc = HttpDocument.parse(source);
    return doc.resolveRequest(doc.requests.single);
  }

  Future<HttpResponseResult> ok(String source, {String baseDir = ''}) async {
    final r = await runner.send(specOf(source), baseDir: baseDir);
    return switch (r) {
      Success(:final value) => value,
      Failure(:final error) => fail('esperava sucesso, veio ${error.kind}'),
    };
  }

  HttpRequestError failureOf(Result<HttpResponseResult, HttpRequestError> r) =>
      switch (r) {
        Failure(:final error) => error,
        Success() => fail('esperava falha'),
      };

  test('GET devolve status, headers, corpo e JSON indentado', () async {
    final res = await ok('GET $base/json\nAccept: application/json\n');
    expect(res.statusCode, 200);
    expect(res.isJson, isTrue);
    expect(res.bodyText, '{"hello":"world"}');
    expect(res.prettyJson, '{\n  "hello": "world"\n}');
    expect(res.elapsed, greaterThanOrEqualTo(Duration.zero));
    expect(res.truncated, isFalse);
  });

  test('POST manda body e headers do arquivo', () async {
    final res = await ok(
      'POST $base/echo\n'
      'Content-Type: application/json\n'
      'Authorization: Bearer t0k3n\n'
      '\n'
      '{"a":1}\n',
    );
    final echoed = jsonDecode(res.bodyText) as Map<String, Object?>;
    expect(echoed['method'], 'POST');
    expect(echoed['body'], '{"a":1}');
    expect(echoed['auth'], 'Bearer t0k3n');
    // `set` e não `add`: o Content-Type do arquivo não pode sair duplicado.
    expect(echoed['contentType'], 'application/json');
  });

  test('< arquivo é resolvido contra a pasta do .http', () async {
    final dir = await Directory.systemTemp.createTemp('http_runner');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/body.json').writeAsString('{"from":"file"}');

    final res = await ok(
      'POST $base/echo\nContent-Type: application/json\n< ./body.json\n',
      baseDir: dir.path,
    );
    expect(jsonDecode(res.bodyText)['body'], '{"from":"file"}');
  });

  test('4xx é resposta, não erro', () async {
    final res = await ok('GET $base/404\n');
    expect(res.statusCode, 404);
    expect(res.bodyText, 'nope');
    expect(res.prettyJson, isNull); // não é JSON → aba cai no texto cru
  });

  test('variável não resolvida falha antes de abrir socket', () async {
    final r = await runner.send(specOf('GET $base/{{missing}}\n'), baseDir: '');
    final e = failureOf(r);
    expect(e.kind, HttpRequestErrorKind.unresolvedVariable);
    expect(e.variable, 'missing');
  });

  test('URL sem esquema é inválida', () async {
    final r = await runner.send(specOf('GET example.com/x\n'), baseDir: '');
    expect(failureOf(r).kind, HttpRequestErrorKind.invalidUrl);
  });

  test('body de arquivo inexistente vira erro tipado com o caminho', () async {
    final r = await runner.send(
      specOf('POST $base/echo\n< ./sumiu.json\n'),
      baseDir: Directory.systemTemp.path,
    );
    final e = failureOf(r);
    expect(e.kind, HttpRequestErrorKind.bodyFileUnreadable);
    expect(e.path, contains('sumiu.json'));
  });

  test('conexão recusada vira connectionFailed', () async {
    final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close(force: true);
    final r = await runner.send(
      specOf('GET http://127.0.0.1:$port/x\n'),
      baseDir: '',
    );
    expect(failureOf(r).kind, HttpRequestErrorKind.connectionFailed);
  });
}
