import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/cockpit/domain/services/http_script_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/http_viewmodel.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements HttpRequestRunner {
  _Transport({this.body = '{"token":"abc"}'});
  final String body;
  final sent = <HttpRequestSpec>[];

  @override
  Future<Result<HttpResponseResult, HttpRequestError>> send(
    HttpRequestSpec spec, {
    required String baseDir,
    Duration timeout = const Duration(seconds: 30),
    bool followRedirects = true,
  }) async {
    sent.add(spec);
    return Success(
      HttpResponseResult(
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: [(name: 'Content-Type', value: 'application/json')],
        bodyBytes: Uint8List.fromList(body.codeUnits),
        elapsed: Duration.zero,
        requestLabel: spec.label,
      ),
    );
  }
}

void main() {
  test('parser keeps scripts separate from body and file import', () {
    final doc = HttpDocument.parse('''
### Upload
POST https://example.test
Content-Type: application/json

{"id": 1}
< {% request.variables.set('id', '2'); %}
> {% client.log(response.status); %}
''');
    final request = doc.requests.single;
    expect(request.body, '{"id": 1}');
    expect(request.bodyFile, isNull);
    expect(request.preScript, contains("request.variables.set('id', '2')"));
    expect(request.postScript, contains('response.status'));
  });

  test('pre, post, tests and globals chain across requests', () async {
    final doc = HttpDocument.parse('''
@token = inline
### First
GET https://example.test/first
> {%
  client.global.set('token', response.body.token);
  client.log(response.headers.valueOf('CONTENT-TYPE'));
  client.test('status', () => client.assert(response.status === 200, 'bad status'));
%}

### Second
GET https://example.test/{{token}}/{{id}}
< {%
  request.variables.set('token', client.global.get('token'));
  request.variables.set('id', 42);
%}
''');
    final transport = _Transport();
    final session = HttpScriptSession();
    final first = await session.run(
      transport,
      doc,
      doc.requests.first,
      baseDir: '/tmp',
    );
    expect(first.failed, isFalse);
    expect(first.tests.single.passed, isTrue);
    expect(first.logs, ['application/json']);
    final second = await session.run(
      transport,
      doc,
      doc.requests.last,
      baseDir: '/tmp',
      environment: {'token': 'environment'},
    );
    expect(second.failed, isFalse);
    expect(transport.sent.last.url, 'https://example.test/abc/42');
  });

  test('pre error prevents sending; failed test retains response', () async {
    final doc = HttpDocument.parse('''
### Pre
GET https://example.test/pre
< {% throw new Error('stop'); %}

### Post
GET https://example.test/post
> {% client.test('fails', () => client.assert(false, 'nope')); %}
''');
    final transport = _Transport();
    final session = HttpScriptSession();
    final pre = await session.run(
      transport,
      doc,
      doc.requests.first,
      baseDir: '/tmp',
    );
    expect(pre.scriptError, contains('stop'));
    expect(transport.sent, isEmpty);
    final post = await session.run(
      transport,
      doc,
      doc.requests.last,
      baseDir: '/tmp',
    );
    expect(post.response, isNotNull);
    expect(post.failed, isTrue);
    expect(post.tests.single.message, contains('nope'));
  });

  test('text response is exposed as a string to post scripts', () async {
    final doc = HttpDocument.parse('''
GET https://example.test/text
> {% client.test('text', () => client.assert(response.body === 'hello')); %}
''');
    final result = await HttpScriptSession().run(
      _Transport(body: 'hello'),
      doc,
      doc.requests.single,
      baseDir: '/tmp',
    );
    expect(result.tests.single.passed, isTrue);
  });

  test(
    'post script reads nested login token without changing the response',
    () async {
      final doc = HttpDocument.parse('''
POST https://example.test/signin

{"key":"sample"}
> {% client.global.set('accessToken', response.body.data.accessToken); %}
''');
      final session = HttpScriptSession();
      final login = await session.run(
        _Transport(body: '{"data":{"accessToken":"sample-token"}}'),
        doc,
        doc.requests.single,
        baseDir: '/tmp',
      );
      expect(login.failed, isFalse);
      expect(login.response, isNotNull);

      final next = HttpDocument.parse(
        'GET https://example.test/{{accessToken}}',
      );
      final transport = _Transport();
      await session.run(transport, next, next.requests.single, baseDir: '/tmp');
      expect(transport.sent.single.url, 'https://example.test/sample-token');
    },
  );

  test(
    'Run All waits for post script before resolving the next request',
    () async {
      const source = '''
### First
GET https://example.test/first
> {% client.global.set('runAllToken', response.body.token); %}

### Second
GET https://example.test/{{runAllToken}}
''';
      final doc = HttpDocument.parse(source);
      final transport = _Transport();
      final state = HttpTabState()..syncSource(source, doc.requests.length);
      await state.runRequests(
        transport,
        doc.requests,
        baseDir: '/tmp',
        document: doc,
      );
      expect(transport.sent.last.url, 'https://example.test/abc');
      expect(
        state.outcomes.every(
          (item) => item.status == HttpRequestRunStatus.success,
        ),
        isTrue,
      );
    },
  );
}
