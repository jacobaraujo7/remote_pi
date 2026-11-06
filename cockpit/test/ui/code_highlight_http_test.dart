import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Coleta (texto completo, trechos coloridos) do span produzido para [source].
Future<(String, List<String>)> _paint(
  WidgetTester tester,
  String source,
  String language,
) async {
  TextSpan? span;
  await tester.pumpWidget(
    ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Builder(
        builder: (context) {
          span = buildCodeSpan(
            context,
            source: source,
            language: language,
            baseStyle: const TextStyle(),
          );
          return const SizedBox();
        },
      ),
    ),
  );
  final colored = <String>[];
  final full = StringBuffer();
  span!.visitChildren((v) {
    final s = v as TextSpan;
    full.write(s.text);
    if (s.style?.color != null) colored.add(s.text!);
    return true;
  });
  return (full.toString(), colored);
}

Future<Map<String, TextStyle?>> _styles(
  WidgetTester tester,
  String source,
) async {
  TextSpan? span;
  await tester.pumpWidget(
    ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Builder(
        builder: (context) {
          span = buildCodeSpan(
            context,
            source: source,
            language: 'http',
            baseStyle: const TextStyle(),
          );
          return const SizedBox();
        },
      ),
    ),
  );
  final styles = <String, TextStyle?>{};
  span!.visitChildren((v) {
    final leaf = v as TextSpan;
    styles[leaf.text!] = leaf.style;
    return true;
  });
  return styles;
}

const _source = '''
@baseUrl = https://api.example.com
@token = abc123

### Listar usuários
# comentário solto
GET {{baseUrl}}/users?page=1
Accept: application/json
Authorization: Bearer {{token}}

### Criar usuário
POST {{baseUrl}}/users
Content-Type: application/json

{
  "name": "Jacob"
}

### Body de arquivo
PUT {{baseUrl}}/users/1
< ./body.json
''';

void main() {
  testWidgets('script HTTP realça JavaScript sem engolir o próximo request', (
    tester,
  ) async {
    const source = '''### Login
< {% request.variables.set('id', '42') %}
POST https://example.com/login
> {%
  client.global.set('token', response.body.token);
%}
### Próximo
GET https://example.com/next
''';
    final (full, colored) = await _paint(tester, source, 'http');
    expect(full, source);
    final joined = colored.join();
    expect(joined, contains('> {%'));
    expect(joined, contains("'token'"));
    expect(colored, contains('### Próximo'));
    expect(colored, contains('GET'));
  });

  testWidgets('pós-script após body JSON usa realce JavaScript', (
    tester,
  ) async {
    const source = '''POST https://example.com/login
Content-Type: application/json

{"key":"sample"}

> {%
  client.global.set('token', response.body.data.accessToken);
%}
''';
    final (full, colored) = await _paint(tester, source, 'http');
    expect(full, source);
    expect(colored.join(), contains('> {%'));
    expect(colored.join(), contains("'token'"));
  });
  testWidgets('texto JS comum não herda a cor do delimitador', (tester) async {
    final styles = await _styles(
      tester,
      '> {%\n  client.global.set("token", response.body.token);\n%}',
    );
    final script = styles.entries.firstWhere((e) => e.key.contains('client'));
    final delimiter = styles.entries.firstWhere((e) => e.key.contains('> {%'));
    expect(script.value?.color, isNot(delimiter.value?.color));
  });
  testWidgets(
    'gramática httpfile pinta separador, variáveis, verbo e headers',
    (tester) async {
      final (full, colored) = await _paint(tester, _source, 'http');

      expect(full, _source); // parse não perde nem duplica texto
      final joined = colored.join('\n');

      expect(colored, contains('### Listar usuários')); // section
      expect(colored, contains('### Criar usuário'));
      expect(colored, contains('@baseUrl')); // attr da variável
      expect(colored, contains('@token'));
      expect(colored, contains('# comentário solto')); // comment
      expect(colored, contains('GET')); // verbo
      expect(colored, contains('POST'));
      expect(colored, contains('PUT'));
      expect(colored, contains('{{baseUrl}}')); // interpolação na URL
      expect(colored, contains('{{token}}')); // interpolação no header
      expect(joined, contains('Accept')); // header name
      expect(joined, contains('Content-Type'));
      expect(joined, contains('< ./body.json')); // import de body
    },
  );

  testWidgets('continuação da URL recebe realce e preserva variáveis', (
    tester,
  ) async {
    const source =
        'GET https://example.test/products\n    ?page={{page}}\n    &size=20';
    final (full, colored) = await _paint(tester, source, 'http');
    expect(full, source);
    expect(colored.join(), contains('?page='));
    expect(colored, contains('{{page}}'));
    expect(colored.join(), contains('&size=20'));
  });

  testWidgets(
    'body JSON é pintado como sub-idioma sem vazar para o próximo request',
    (tester) async {
      final (_, colored) = await _paint(tester, _source, 'http');
      // A chave do JSON vem do sub-idioma json...
      expect(colored.join(), contains('"name"'));
      // ...e o request seguinte ao body continua sendo reconhecido (o body não
      // engoliu o resto do arquivo).
      expect(colored, contains('### Body de arquivo'));
      expect(colored, contains('PUT'));
    },
  );

  testWidgets('nomes de headers HTTP ficam em itálico, valores não', (
    tester,
  ) async {
    final styles = await _styles(
      tester,
      'GET https://example.com\n'
      'Content-Type: application/json\n'
      'Accept: text/plain\n'
      'Cookie: session=abc\n',
    );
    for (final name in ['Content-Type', 'Accept', 'Cookie']) {
      expect(styles[name]?.fontStyle, FontStyle.italic, reason: name);
    }
    for (final value in ['application/json', 'text/plain', 'session=abc']) {
      final fragments = styles.entries.where((e) => e.key.contains(value));
      expect(fragments, isNotEmpty, reason: value);
      expect(
        fragments.every((e) => e.value?.fontStyle != FontStyle.italic),
        isTrue,
        reason: value,
      );
    }
  });

  testWidgets('lista de headers solta (painel de resposta) também pinta', (
    tester,
  ) async {
    // O painel Headers da aba .http renderiza só `Nome: valor` por linha —
    // sem request-line nenhuma antes.
    const headers =
        'content-type: application/json\n'
        'content-length: 42\n';
    final (full, colored) = await _paint(tester, headers, 'http');
    expect(full, headers);
    expect(colored.join(), contains('content-type'));
    expect(colored.join(), contains('content-length'));
  });

  testWidgets('arquivo com sintaxe exótica degrada em realce parcial', (
    tester,
  ) async {
    const weird = '### x\n> {%\n  client.log("oi")\n%}\nGET https://a.b\n';
    final (full, colored) = await _paint(tester, weird, 'http');
    expect(full, weird);
    expect(colored, contains('GET')); // não abortou o parse inteiro
  });
}
