import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

CockpitThemeSpec parse(String source) => CockpitThemeSpec.fromJson(
  jsonDecode(source) as Map<String, Object?>,
  resolveBase: builtInThemeById,
  fallbackBase: cockpitDefaultTheme,
);

void main() {
  group('parseHexColor', () {
    test('aceita #RGB, #RRGGBB e #RRGGBBAA', () {
      expect(parseHexColor('#f00', path: 'x'), const Color(0xFFFF0000));
      expect(parseHexColor('#2F6FF0', path: 'x'), const Color(0xFF2F6FF0));
      // Alpha vai no FIM no JSON e no INÍCIO no Color do Dart.
      expect(parseHexColor('#2F6FF033', path: 'x'), const Color(0x332F6FF0));
    });

    test('round-trip preserva a cor', () {
      for (final color in [
        const Color(0xFF0D0D0F),
        const Color(0x99000000),
        const Color(0x332F6FF0),
      ]) {
        expect(parseHexColor(encodeHexColor(color), path: 'x'), color);
      }
    });

    test('cor inválida vira ThemeParseError com o caminho do campo', () {
      expect(
        () => parseHexColor('#ggg', path: 'variants.dark.ui.accent'),
        throwsA(
          isA<ThemeParseError>()
              .having((e) => e.kind, 'kind', ThemeParseErrorKind.badColor)
              .having((e) => e.path, 'path', 'variants.dark.ui.accent'),
        ),
      );
    });
  });

  group('CockpitThemeSpec.fromJson', () {
    test('tema mínimo herda todo o resto do tema nativo', () {
      final theme = parse('''
        {
          "id": "acme.minimal",
          "name": "Minimal",
          "variants": { "dark": { "ui": { "accent": "#FF0088" } } }
        }
      ''');

      final dark = theme.variantFor(Brightness.dark);
      expect(dark.ui.accent, const Color(0xFFFF0088));
      // Não declarado → vem da base, incluindo syntax e terminal.
      expect(dark.ui.bg, AppColors.dark.bg);
      expect(dark.syntax.keyword, SyntaxColors.githubDark.keyword);
      expect(dark.terminal.background, cockpitTerminalThemeDark.background);
    });

    test('extends usa o built-in nomeado como base', () {
      final theme = parse('''
        {
          "id": "acme.on-cockpit",
          "name": "On Cockpit",
          "extends": "cockpit",
          "variants": { "dark": { "ui": { "accent": "#FF0088" } } }
        }
      ''');

      expect(
        theme.variantFor(Brightness.dark).syntax.keyword,
        SyntaxColors.githubDark.keyword,
      );
    });

    test('extends desconhecido falha apontando o campo', () {
      expect(
        () => parse('''
          {
            "id": "acme.x", "name": "X", "extends": "nope",
            "variants": { "dark": {} }
          }
        '''),
        throwsA(
          isA<ThemeParseError>()
              .having((e) => e.kind, 'kind', ThemeParseErrorKind.unknownBase)
              .having((e) => e.value, 'value', 'nope'),
        ),
      );
    });

    test('tema só-dark serve o variant dark também no light', () {
      final theme = parse('''
        {
          "id": "acme.dark-only", "name": "Dark Only",
          "variants": { "dark": { "ui": { "accent": "#FF0088" } } }
        }
      ''');

      expect(theme.hasLight, isFalse);
      expect(
        theme.variantFor(Brightness.light).ui.accent,
        const Color(0xFFFF0088),
      );
    });

    test('sem variants é erro', () {
      expect(
        () => parse('{"id": "a", "name": "A", "variants": {}}'),
        throwsA(
          isA<ThemeParseError>().having(
            (e) => e.kind,
            'kind',
            ThemeParseErrorKind.noVariants,
          ),
        ),
      );
    });

    test('export é autônomo: reimportar dá o mesmo tema', () {
      final original = parse('''
        {
          "id": "acme.on-cockpit", "name": "On Cockpit",
          "extends": "cockpit",
          "variants": { "dark": { "ui": { "accent": "#FF0088" } } }
        }
      ''');

      final reimported = parse(jsonEncode(original.toJson()));
      final a = original.variantFor(Brightness.dark);
      final b = reimported.variantFor(Brightness.dark);
      expect(b.ui.accent, a.ui.accent);
      expect(b.syntax.keyword, a.syntax.keyword);
      expect(b.terminal.background, a.terminal.background);
      // O export não carrega `extends`, então não depende do built-in existir.
      expect(reimported.toJson().containsKey('extends'), isFalse);
    });
  });

  group('temas built-in', () {
    // Luminância relativa: comparar isso é mais honesto que comparar hex, e é
    // o que o olho de fato lê como "mais fundo" / "mais alto".
    double lum(Color c) => c.computeLuminance();

    test('Cockpit: o chrome é mais fundo que o corpo da aba', () {
      for (final b in Brightness.values) {
        final ui = cockpitDefaultTheme.variantFor(b).ui;
        expect(
          lum(ui.bg),
          lessThan(lum(ui.panel)),
          reason:
              'chrome (bg) devia ser mais fundo que o conteúdo (panel) em $b',
        );
      }
    });

    test('Cockpit 2: inverte — o corpo da aba é mais fundo que o chrome', () {
      for (final b in Brightness.values) {
        final ui = cockpit2Theme.variantFor(b).ui;
        expect(
          lum(ui.panel),
          lessThan(lum(ui.bg)),
          reason: 'a inversão é a razão de existir do Cockpit 2 ($b)',
        );
      }
    });

    test(
      'Cockpit 2: as camadas elevadas ficam acima do chrome E do conteúdo',
      () {
        for (final b in Brightness.values) {
          final ui = cockpit2Theme.variantFor(b).ui;
          // panel2 = composer/cards/seleção. Aparece sobre o chrome claro e sobre
          // o conteúdo escuro; tem de ler como elevação nos dois.
          expect(lum(ui.panel2), greaterThan(lum(ui.panel)));
          expect(lum(ui.panel2), greaterThan(lum(ui.bg)));
        }
      },
    );

    test('Cockpit 2: o terminal acompanha o fundo da aba', () {
      for (final b in Brightness.values) {
        final variant = cockpit2Theme.variantFor(b);
        expect(variant.terminal.background, variant.ui.panel);
      }
    });

    test('built-ins sem paleta própria usam o realce GitHub', () {
      // O `background` é do TEMA (ver o teste do campo unificado), então a
      // comparação é sobre as cores do código. Flexoki é a exceção: a paleta
      // de syntax *é* o esquema.
      for (final theme in builtInThemes) {
        if (theme.id == 'flexoki') continue;
        for (final (b, github) in [
          (Brightness.dark, SyntaxColors.githubDark),
          (Brightness.light, SyntaxColors.githubLight),
        ]) {
          final syntax = theme.variantFor(b).syntax;
          expect(
            syntax.copyWith(background: github.background),
            github,
            reason: 'realce divergiu em ${theme.id} ($b)',
          );
        }
      }
    });

    test('Flexoki usa a paleta Flexoki de syntax', () {
      for (final (b, flexoki) in [
        (Brightness.dark, SyntaxColors.flexokiDark),
        (Brightness.light, SyntaxColors.flexokiLight),
      ]) {
        final syntax = flexokiTheme.variantFor(b).syntax;
        expect(
          syntax.copyWith(background: flexoki.background),
          flexoki,
          reason: 'realce Flexoki divergiu em $b',
        );
      }
    });

    test('código, terminal e aba dividem o mesmo campo', () {
      // Viewer, editor e terminal são conteúdo dentro da aba: pintar cada um
      // com um preto diferente deixava a emenda à mostra entre abas vizinhas.
      for (final theme in builtInThemes) {
        for (final b in Brightness.values) {
          final v = theme.variantFor(b);
          expect(
            v.syntax.background,
            v.ui.panel,
            reason: 'fundo do código fora do campo em ${theme.id} ($b)',
          );
          expect(
            v.terminal.background,
            v.ui.panel,
            reason: 'fundo do terminal fora do campo em ${theme.id} ($b)',
          );
        }
      }
    });

    test('tema importado sem `syntax`/`terminal` segue o próprio campo', () {
      // Um tema de três tokens não pode herdar o fundo do código da BASE — ele
      // ficaria com o campo do Cockpit dentro das próprias superfícies.
      final theme = parse('''
        {
          "id": "acme.so-ui", "name": "So UI",
          "variants": { "dark": { "ui": { "panel": "#101820" } } }
        }
      ''');
      final v = theme.variantFor(Brightness.dark);
      expect(v.ui.panel, const Color(0xFF101820));
      expect(v.syntax.background, const Color(0xFF101820));
      expect(v.terminal.background, const Color(0xFF101820));
      // E o realce herdado continua sendo o da base.
      expect(v.syntax.keyword, SyntaxColors.githubDark.keyword);
    });

    test('tema importado pode declarar um fundo de código proprio', () {
      final theme = parse('''
        {
          "id": "acme.proprio", "name": "Proprio",
          "variants": {
            "dark": {
              "ui": { "panel": "#101820" },
              "syntax": { "background": "#000000" }
            }
          }
        }
      ''');
      final v = theme.variantFor(Brightness.dark);
      expect(v.syntax.background, const Color(0xFF000000));
      // O terminal, que nao foi declarado, segue a aba.
      expect(v.terminal.background, const Color(0xFF101820));
    });

    test(
      'Violet herda a estrutura de superfícies do Cockpit que o originou',
      () {
        // A razão de o Violet ser derivado (e não escrito à mão) é essa: ele
        // acompanha a calibragem do Cockpit correspondente de graça. Se alguém
        // reescrever o Violet com hexes soltos, esta comparação denuncia.
        for (final (base, violet) in [
          (cockpitDefaultTheme, violet1Theme),
          (cockpit2Theme, violet2Theme),
        ]) {
          for (final b in Brightness.values) {
            final a = base.variantFor(b).ui;
            final v = violet.variantFor(b).ui;
            // Mesma ORDEM de superfícies (quem é mais fundo, quem é mais alto).
            expect(
              lum(v.panel).compareTo(lum(v.bg)),
              lum(a.panel).compareTo(lum(a.bg)),
              reason: 'chrome x conteúdo divergiu em \${violet.id} ($b)',
            );
            expect(
              lum(v.panel2) > lum(v.panel),
              lum(a.panel2) > lum(a.panel),
              reason: 'elevação divergiu em \${violet.id} ($b)',
            );
          }
        }
      },
    );

    test('Violet tinge os neutros mas preserva as cores semânticas', () {
      for (final (base, violet) in [
        (cockpitDefaultTheme, violet1Theme),
        (cockpit2Theme, violet2Theme),
      ]) {
        for (final b in Brightness.values) {
          final a = base.variantFor(b).ui;
          final v = violet.variantFor(b).ui;
          // Vermelho tem de continuar lendo como vermelho: erro e status de git
          // carregam informação, não gosto.
          expect(v.error, a.error);
          expect(v.warn, a.warn);
          expect(v.online, a.online);
          expect(v.gitDeleted, a.gitDeleted);
          expect(v.gitStaged, a.gitStaged);
          // E a marca de fato mudou.
          expect(v.accent, isNot(a.accent));
          expect(v.bg, isNot(a.bg));
        }
      }
    });

    test('Violet: o terminal segue a aba e o cursor segue a marca', () {
      for (final (base, violet) in [
        (cockpitDefaultTheme, violet1Theme),
        (cockpit2Theme, violet2Theme),
      ]) {
        for (final b in Brightness.values) {
          final variant = violet.variantFor(b);
          expect(variant.terminal.background, variant.ui.panel);
          expect(variant.terminal.cursor, variant.ui.accent);
          // As 16 cores ANSI ficam intactas: `blue` precisa continuar azul
          // (cada brilho tem a sua, daí comparar com a base do mesmo brilho).
          expect(variant.terminal.blue, base.variantFor(b).terminal.blue);
          expect(variant.terminal.red, base.variantFor(b).terminal.red);
        }
      }
    });

    test('Midnight muda de arranjo conforme o brilho — de propósito', () {
      // Escuro: inverte (conteúdo afunda), como o Cockpit 2.
      final dark = midnightTheme.variantFor(Brightness.dark).ui;
      expect(
        lum(dark.panel),
        lessThan(lum(dark.bg)),
        reason: 'no escuro o Midnight herda a inversão do Cockpit 2',
      );

      // Claro: NÃO inverte. A inversão não sobrevive ao modo claro — o chrome
      // precisaria ficar quase branco para o conteúdo caber acima, e a tela
      // vira dois cinzas iguais. Aqui os painéis voltam a ser a moldura.
      final light = midnightTheme.variantFor(Brightness.light).ui;
      expect(
        lum(light.bg),
        lessThan(lum(light.panel)),
        reason: 'no claro o Midnight volta ao arranjo do Cockpit 1',
      );

      // E os painéis do claro são mais fundos que os do Cockpit 1: é o que
      // devolve a hierarquia que o modo claro perde.
      expect(lum(light.bg), lessThan(lum(cockpitDefaultTheme.light!.ui.bg)));
    });

    test('nenhum built-in deixa o texto fraco abaixo de 3:1', () {
      // Mexer em superfície come contraste de `text3` (placeholder, metadado,
      // timestamp). Já aconteceu duas vezes; este teste é a rede.
      for (final theme in builtInThemes) {
        for (final b in Brightness.values) {
          final ui = theme.variantFor(b).ui;
          for (final surface in [ui.bg, ui.panel, ui.panel2]) {
            expect(
              contrastRatio(ui.text3, surface),
              greaterThanOrEqualTo(3.0),
              reason: 'text3 ilegível em ${theme.id} sobre $surface ($b)',
            );
          }
        }
      }
    });

    test('a marca nunca se confunde com um estado (erro / aviso)', () {
      // Num tema quente a marca invade o território dos estados, e aí eles
      // param de avisar: o usuário vê "a cor do app", não "deu ruim". Já
      // aconteceu duas vezes — o Rosê teve de ir para o magenta, e o Sun teve
      // de deslocar o próprio `warn` para o laranja.
      double hueOf(Color c) => HSLColor.fromColor(c).hue;
      double satOf(Color c) => HSLColor.fromColor(c).saturation;
      double gap(Color a, Color b) {
        final d = (hueOf(a) - hueOf(b)).abs();
        return d > 180 ? 360 - d : d; // matiz é circular
      }

      for (final theme in builtInThemes) {
        for (final b in Brightness.values) {
          final ui = theme.variantFor(b).ui;

          // Marca acromática (o branco/preto do Pantera) não se confunde com
          // vermelho: a distinção ali é de SATURAÇÃO, não de matiz — e o matiz
          // de um cinza é um número sem significado. O que se cobra é que ela
          // seja mesmo cinza, e não um cinza puxado para o vermelho.
          if (satOf(ui.accent) < 0.05) {
            expect(
              satOf(ui.accent),
              lessThan(0.05),
              reason: 'marca acromática esperada em ${theme.id} ($b)',
            );
            continue;
          }

          expect(
            gap(ui.accent, ui.error),
            greaterThanOrEqualTo(20),
            reason: 'marca perto demais do erro em ${theme.id} ($b)',
          );
          expect(
            gap(ui.accent, ui.warn),
            greaterThanOrEqualTo(20),
            reason: 'marca perto demais do aviso em ${theme.id} ($b)',
          );
          // E os dois estados também têm de se distinguir entre si: deslocar o
          // aviso para longe da marca não pode empurrá-lo para cima do erro.
          expect(
            gap(ui.warn, ui.error),
            greaterThanOrEqualTo(20),
            reason: 'aviso perto demais do erro em ${theme.id} ($b)',
          );
        }
      }
    });

    test('toda fronteira entre superfícies é perceptível', () {
      // Painel, conteúdo, elevado e hover são quatro regiões; se duas encostam
      // sem nada entre elas, o widget que mora numa desaparece dentro da outra.
      // O Sun claro nasceu com painel e elevado a 1,008 — cards e composer
      // invisíveis.
      //
      // A fronteira pode ser feita de duas maneiras. Quase todos os temas usam
      // **degrau de superfície**. O Pantera usa **borda**: painel e conteúdo
      // são o mesmo preto, e quem separa é o traço. As duas valem; o que não
      // vale é não ter nenhuma das duas.
      const pisoSuperficie = 1.03;
      const pisoBorda = 1.3;

      for (final theme in builtInThemes) {
        for (final b in Brightness.values) {
          final ui = theme.variantFor(b).ui;

          // Painel x conteúdo: existe borda desenhada entre eles (rail, árvore
          // e tab strip têm `Border`), então aqui a borda é alternativa válida.
          final degrau = contrastRatio(ui.bg, ui.panel);
          if (degrau < pisoSuperficie) {
            expect(
              contrastRatio(ui.border, ui.bg),
              greaterThanOrEqualTo(pisoBorda),
              reason:
                  'sem degrau E sem borda entre painel e conteúdo em '
                  '${theme.id} ($b)',
            );
            expect(
              contrastRatio(ui.border, ui.panel),
              greaterThanOrEqualTo(pisoBorda),
              reason: 'borda invisível sobre o conteúdo em ${theme.id} ($b)',
            );
          }

          // Elevado e hover NÃO têm borda para se apoiar: um card sem contorno
          // e um hover que não responde seriam defeito em qualquer tema.
          for (final campo in [ui.bg, ui.panel]) {
            expect(
              contrastRatio(ui.panel2, campo),
              greaterThanOrEqualTo(pisoSuperficie),
              reason: 'elevado colapsou em ${theme.id} ($b)',
            );
          }
          expect(
            contrastRatio(ui.panel3, ui.panel2),
            greaterThanOrEqualTo(pisoSuperficie),
            reason: 'hover colapsou no elevado em ${theme.id} ($b)',
          );
        }
      }
    });

    test('a paleta ANSI continua legível sobre o campo', () {
      // O terminal passou a herdar o fundo da aba, então o campo mudou embaixo
      // de uma paleta que não mudou junto. `brightBlack` é o piso natural
      // (existe para ser apagado) e é quem encosta no limite primeiro — 3:1 é
      // onde ele para de ser "apagado" e vira "ilegível".
      for (final theme in builtInThemes) {
        for (final b in Brightness.values) {
          final t = theme.variantFor(b).terminal;
          final tinta = {
            'foreground': t.foreground,
            'brightBlack': t.brightBlack,
            'red': t.red,
            'green': t.green,
            'yellow': t.yellow,
            'blue': t.blue,
            'magenta': t.magenta,
            'cyan': t.cyan,
            'cursor': t.cursor,
          };
          for (final cor in tinta.entries) {
            expect(
              contrastRatio(cor.value, t.background),
              greaterThanOrEqualTo(3.0),
              reason: '${cor.key} ilegível no terminal de ${theme.id} ($b)',
            );
          }
        }
      }
    });

    test('painel com tom não deixa o campo claro sem tom', () {
      // Branco puro não recebe tom: em HSL, `L = 1.0` é branco em qualquer
      // matiz. Num tema colorido isso deixa painéis tingidos e conteúdo cru —
      // o código e o terminal viram um recorte colado por cima do tema.
      //
      // A regra é sobre o TOM, não sobre uma lista de ids: tema cujo painel é
      // neutro (o Cockpit oficial, o Pantera) não tem tom a levar para o campo,
      // e branco puro ali é a resposta certa.
      double satOf(Color c) => HSLColor.fromColor(c).saturation;
      for (final theme in builtInThemes) {
        final ui = theme.variantFor(Brightness.light).ui;
        if (satOf(ui.bg) < 0.2) continue; // painel neutro: nada a levar
        expect(
          ui.panel,
          isNot(const Color(0xFFFFFFFF)),
          reason: 'painel com tom e campo em branco puro em ${theme.id}',
        );
      }
    });

    test('todo built-in traz os dois variants', () {
      for (final theme in builtInThemes) {
        expect(theme.hasDark && theme.hasLight, isTrue, reason: theme.id);
      }
    });
  });

  group('docs/theme.schema.json', () {
    // O schema é um arquivo separado do código que o implementa, então ele pode
    // silenciosamente desencontrar: token novo no Dart, schema velho no editor.
    // Estes testes fazem esse desencontro virar falha de CI.
    late Map<String, Object?> schema;

    setUpAll(() {
      schema =
          jsonDecode(File('docs/theme.schema.json').readAsStringSync())
              as Map<String, Object?>;
    });

    Set<String> schemaTokens(String definition) {
      final defs = schema['definitions']! as Map<String, Object?>;
      final node = defs[definition]! as Map<String, Object?>;
      return (node['properties']! as Map<String, Object?>).keys.toSet();
    }

    test('os tokens do schema são exatamente os que o codec serializa', () {
      expect(schemaTokens('ui'), AppColors.dark.toJson().keys.toSet());
      expect(
        schemaTokens('syntax'),
        SyntaxColors.oneDark.toJson().keys.toSet(),
      );
      expect(
        schemaTokens('terminal'),
        terminalThemeToJson(cockpitTerminalThemeDark).keys.toSet(),
      );
    });

    test('o enum de `extends` lista todos os built-in', () {
      final props = schema['properties']! as Map<String, Object?>;
      final ext = props['extends']! as Map<String, Object?>;
      expect(
        (ext['enum']! as List).cast<String>().toSet(),
        builtInThemes.map((t) => t.id).toSet(),
      );
    });

    test('o \$id do schema é a URL que o export escreve', () {
      expect(schema[r'$id'], themeSchemaUrl);
    });

    test('o exemplo dos docs é um tema válido', () {
      final example = File('docs/theme.example.json').readAsStringSync();
      final theme = parse(example);
      expect(theme.id, 'acme.aurora');
      expect(theme.hasDark && theme.hasLight, isTrue);
      // E aponta pro mesmo schema.
      expect(
        (jsonDecode(example) as Map<String, Object?>)[r'$schema'],
        themeSchemaUrl,
      );
    });
  });

  group('onColor', () {
    test('escolhe claro sobre fundo escuro e escuro sobre fundo claro', () {
      expect(onColor(const Color(0xFF2F6FF0)), const Color(0xFFFFFFFF));
      expect(onColor(const Color(0xFFFFE066)), const Color(0xFF1A1A1F));
    });

    test('sobre a marca de todo built-in, escolhe o lado mais legível', () {
      // O ponto da função: em vez de branco fixo, medir. Um accent claro (o
      // roxo do Violet) tem de receber texto escuro.
      for (final theme in builtInThemes) {
        for (final b in Brightness.values) {
          final accent = theme.variantFor(b).ui.accent;
          final chosen = onColor(accent);
          final other = chosen == const Color(0xFFFFFFFF)
              ? const Color(0xFF1A1A1F)
              : const Color(0xFFFFFFFF);
          expect(
            contrastRatio(chosen, accent),
            greaterThanOrEqualTo(contrastRatio(other, accent)),
            reason: 'escolha pior sobre o accent de \${theme.id} ($b)',
          );
          // E o resultado tem de ser utilizável, não só "o melhor dos dois".
          expect(contrastRatio(chosen, accent), greaterThan(4.0));
        }
      }
    });
  });
}
