import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/services/http_curl.dart';
import 'package:flutter_test/flutter_test.dart';

// Have a real shell parse the command, using an argument recorder as curl.
Future<List<String>> arguments(String command) async {
  final result = await Process.run('bash', [
    '-c',
    "curl() { printf '%s\\0' \"\$@\"; };\n$command",
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).split('\x00')..removeLast();
}

void main() {
  test('matches only the request containing the cursor', () {
    final doc = HttpDocument.parse('''
@host = https://example.test

### First
GET {{host}}/first
Accept: application/json

### Invalid
GET

### Second
POST {{host}}/second

payload
''');
    expect(HttpCurl.requestIndexAtLine(doc, 0), -1);
    expect(HttpCurl.requestIndexAtLine(doc, 3), 0);
    expect(HttpCurl.requestIndexAtLine(doc, 4), 0);
    expect(HttpCurl.requestIndexAtLine(doc, 6), -1);
    expect(HttpCurl.requestIndexAtLine(doc, 7), -1);
    expect(HttpCurl.requestIndexAtLine(doc, 10), 1);
    expect(HttpCurl.requestIndexAtLine(doc, 12), 1);
    expect(HttpCurl.requestIndexAtLine(doc, 99), -1);
    expect(HttpCurl.requestIndexAtLine(HttpDocument.parse('GET'), 0), -1);
  });

  test(
    'exports resolved URL, repeated headers and literal multiline body',
    () async {
      final doc = HttpDocument.parse('''
@host = https://example.test
POST {{host}}/items
  ?page=1
  &tag[]=two
Authorization: Bearer {{token}}
X-Tag: first
X-Tag: second
Content-Type: application/json

{
  "name": "O'Reilly",
  "literal": "\$(printf injected) `printf injected` \\ path"
}
''');
      final request = doc.resolveRequest(
        doc.requests.single,
        environment: {'token': 'environment'},
        globals: {'token': 'global'},
        requestVariables: {'token': 'script'},
        overrides: {'token': 'override'},
      );
      expect(await arguments(HttpCurl.generate(request)), [
        '--globoff',
        '--request',
        'POST',
        '--url',
        'https://example.test/items?page=1&tag[]=two',
        '--header',
        'Authorization: Bearer override',
        '--header',
        'X-Tag: first',
        '--header',
        'X-Tag: second',
        '--header',
        'Content-Type: application/json',
        '--data-raw',
        request.body,
      ]);
    },
  );

  test(
    'resolves body files against the HTTP directory without reading them',
    () async {
      final doc = HttpDocument.parse(
        "PUT https://example.test/upload\n< ./payload's file.bin\n",
      );
      expect(
        await arguments(
          HttpCurl.generate(doc.requests.single, baseDir: '/project/api'),
        ),
        [
          '--globoff',
          '--request',
          'PUT',
          '--url',
          'https://example.test/upload',
          '--data-binary',
          "@/project/api/payload's file.bin",
        ],
      );
    },
  );

  test('HEAD uses curl head mode and scripts are not exported', () async {
    final doc = HttpDocument.parse('''
< {% request.variables.set('token', 'secret'); %}
HEAD https://example.test/{{token}}
> {% client.log('response'); %}
''');
    expect(await arguments(HttpCurl.generate(doc.requests.single)), [
      '--globoff',
      '--head',
      '--url',
      'https://example.test/{{token}}',
    ]);
  });

  test('leading @ in a literal body stays literal', () async {
    final doc = HttpDocument.parse('POST https://example.test\n\n@literal');
    expect(
      (await arguments(HttpCurl.generate(doc.requests.single))).sublist(5),
      ['--data-raw', '@literal'],
    );
  });
}
