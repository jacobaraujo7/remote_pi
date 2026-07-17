import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('filenameLanguageOf', () {
    test('reconhece .env e variantes por nome, não por extensão', () {
      expect(filenameLanguageOf('/repo/.env'), 'dotenv');
      expect(filenameLanguageOf('/repo/.env.local'), 'dotenv');
      expect(filenameLanguageOf('/repo/.env.dev'), 'dotenv');
      expect(filenameLanguageOf('/repo/.env.qa'), 'dotenv');
      expect(filenameLanguageOf('/repo/.env.develop'), 'dotenv');
      expect(filenameLanguageOf('C:\\repo\\.env.local'), 'dotenv');
      expect(filenameLanguageOf('/repo/.ENV'), 'dotenv');
    });

    test('reconhece go.mod e go.sum', () {
      expect(filenameLanguageOf('/repo/go.mod'), 'gomod');
      expect(filenameLanguageOf('/repo/go.sum'), 'gomod');
      expect(filenameLanguageOf('/repo/main.go'), isNull);
    });

    test('reconhece Dockerfile e variantes', () {
      expect(filenameLanguageOf('/repo/Dockerfile'), 'dockerfile');
      expect(filenameLanguageOf('/repo/Containerfile'), 'dockerfile');
      expect(filenameLanguageOf('/repo/Dockerfile.dev'), 'dockerfile');
      expect(filenameLanguageOf('/repo/app.Dockerfile'), 'dockerfile');
      expect(filenameLanguageOf('/repo/docker-compose.yml'), isNull);
    });

    test('não dispara em nomes parecidos', () {
      expect(filenameLanguageOf('/repo/env.dart'), isNull);
      expect(filenameLanguageOf('/repo/environment.ts'), isNull);
      expect(filenameLanguageOf('/repo/.envrc'), isNull);
      expect(filenameLanguageOf('/repo/main.dart'), isNull);
    });
  });

  testWidgets('gramática dotenv pinta chave, string, comentário e \$VAR', (
    tester,
  ) async {
    const source =
        '# config\n'
        'export API_KEY="abc\${HOME}def"\n'
        'PLAIN=\$USER # trailing\n';
    TextSpan? span;
    await tester.pumpWidget(
      ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            span = buildCodeSpan(
              context,
              source: source,
              language: 'dotenv',
              baseStyle: const TextStyle(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(span, isNotNull);
    // Reconstrói o texto e coleta os trechos coloridos (style != base).
    final colored = <String>[];
    final full = StringBuffer();
    span!.visitChildren((v) {
      final s = v as TextSpan;
      full.write(s.text);
      if (s.style?.color != null) colored.add(s.text!);
      return true;
    });
    expect(full.toString(), source); // parse não perde nem duplica texto
    expect(colored, contains('# config')); // comment
    expect(colored, contains('API_KEY')); // attr
    expect(colored, contains('PLAIN')); // attr
    expect(colored, contains('export ')); // keyword (consome o espaço)
    expect(colored, contains('\${HOME}')); // interpolação dentro de string
    expect(colored, contains('\$USER')); // interpolação em valor nu
    expect(colored, contains('# trailing')); // comentário no fim do valor
  });

  testWidgets('gramática gomod pinta diretivas, versão e comentário', (
    tester,
  ) async {
    const source =
        'module example.com/foo\n'
        'require github.com/x/y v1.2.3 // indirect\n'
        'replace a.b/c => ../local\n';
    TextSpan? span;
    await tester.pumpWidget(
      ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            span = buildCodeSpan(
              context,
              source: source,
              language: 'gomod',
              baseStyle: const TextStyle(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(span, isNotNull);
    final colored = <String>[];
    final full = StringBuffer();
    span!.visitChildren((v) {
      final s = v as TextSpan;
      full.write(s.text);
      if (s.style?.color != null) colored.add(s.text!);
      return true;
    });
    expect(full.toString(), source);
    expect(colored, contains('module')); // diretiva
    expect(colored, contains('require')); // diretiva
    expect(colored, contains('replace')); // diretiva
    expect(colored, contains('v1.2.3')); // versão
    expect(colored, contains('=>')); // replace arrow
    expect(colored, contains('// indirect')); // comentário
  });

  testWidgets('Dockerfile usa o grammar do package e pinta instruções', (
    tester,
  ) async {
    const source =
        'FROM alpine:3.20\n'
        '# build\n'
        'RUN apk add --no-cache curl\n';
    TextSpan? span;
    await tester.pumpWidget(
      ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            span = buildCodeSpan(
              context,
              source: source,
              language: filenameLanguageOf('/repo/Dockerfile'),
              baseStyle: const TextStyle(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(span, isNotNull);
    final colored = <String>[];
    final full = StringBuffer();
    span!.visitChildren((v) {
      final s = v as TextSpan;
      full.write(s.text);
      if (s.style?.color != null) colored.add(s.text!);
      return true;
    });
    expect(full.toString(), source);
    expect(colored.join(), contains('FROM')); // instrução
    expect(colored.join(), contains('RUN')); // instrução
    expect(colored, contains('# build')); // comentário
  });
}
