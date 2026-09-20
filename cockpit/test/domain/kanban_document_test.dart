import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/kanban_document.dart';
import 'package:cockpit/app/cockpit/domain/services/kanban_editor.dart';
import 'package:flutter_test/flutter_test.dart';

const _board = '''
---
columns: [Backlog, Doing, Done]
labels: {relay: orange, bug: red}
---

## Backlog

- [ ] Servidor órfão ao fechar o app <!-- id: k1 labels: bug -->

## Doing

- [ ] Túnel SSH no host <!-- id: k3 labels: relay -->
      O túnel sobe no host, não no cliente.

      - reusar a sessão do server

## Done

- [x] Absorver o plugin de PTY <!-- id: k2 -->
''';

void main() {
  group('parse', () {
    test('lê colunas, cards, marcadores e notas', () {
      final doc = KanbanDocument.parse(_board);

      expect(doc.isBoard, isTrue);
      expect(doc.columns.map((c) => c.name), ['Backlog', 'Doing', 'Done']);
      expect(doc.labelColors['relay'], KanbanLabelColor.orange);
      expect(doc.labelColors['bug'], KanbanLabelColor.red);

      final card = doc.columns[1].cards.single;
      expect(card.title, 'Túnel SSH no host');
      expect(card.id, 'k3');
      expect(card.labels, ['relay']);
      expect(card.checked, isFalse);
      expect(card.notes, contains('O túnel sobe no host'));
      expect(card.notes, contains('- reusar a sessão do server'));

      expect(doc.columns[2].cards.single.checked, isTrue);
    });

    test('cor desconhecida vira cinza, marcador sem frontmatter existe', () {
      final doc = KanbanDocument.parse('''
---
labels: {a: chartreuse}
---

## Col

- [ ] x <!-- labels: a, b -->
''');
      expect(doc.colorOf('a'), KanbanLabelColor.gray);
      expect(doc.colorOf('b'), KanbanLabelColor.gray);
      expect(doc.allLabels, ['a', 'b']);
      expect(doc.usageOf('b'), 1);
    });

    test('arquivo sem colunas não é board e não lança', () {
      final doc = KanbanDocument.parse('só um texto\n\ncom parágrafos');
      expect(doc.isBoard, isFalse);
      expect(doc.columns, isEmpty);
    });

    test('bloco desconhecido vira card não reconhecido, sem sumir', () {
      final doc = KanbanDocument.parse('''
## Col

um parágrafo solto

- [ ] card de verdade
''');
      final cards = doc.columns.single.cards;
      expect(cards.first.recognized, isFalse);
      expect(cards.first.title, 'um parágrafo solto');
      expect(cards.last.recognized, isTrue);
    });

    test('`##` dentro de cerca de código não vira coluna', () {
      final doc = KanbanDocument.parse('''
## Col

- [ ] card
      ```md
      ## não é coluna
      ```
''');
      expect(doc.columns.length, 1);
    });

    test('frontmatter sem fechamento é conteúdo, não frontmatter', () {
      final doc = KanbanDocument.parse('---\nlabels: {a: red}\n\n## Col\n');
      expect(doc.frontmatterEnd, 0);
      expect(doc.labelColors, isEmpty);
    });
  });

  group('mover card', () {
    test('avançar move de coluna e marca [x] só na última', () {
      var doc = KanbanDocument.parse(_board);
      final card = doc.columns[1].cards.single;

      doc = KanbanDocument.parse(KanbanEditor.advanceCard(doc, card));
      expect(doc.columns[1].cards, isEmpty);
      expect(
        doc.columns[2].cards.map((c) => c.title),
        contains('Túnel SSH no host'),
      );
      expect(
        doc.columns[2].cards.firstWhere((c) => c.id == 'k3').checked,
        isTrue,
      );
    });

    test('avançar até o fim pula as intermediárias e marca [x]', () {
      var doc = KanbanDocument.parse(_board);
      final card = doc.columns[0].cards.first;
      final id = card.id;

      doc = KanbanDocument.parse(KanbanEditor.advanceToEnd(doc, card));
      expect(doc.columns[1].cards.any((c) => c.id == id), isFalse);
      final moved = doc.columns[2].cards.firstWhere((c) => c.id == id);
      expect(moved.checked, isTrue);
    });

    test('avançar até o fim na última coluna não muda nada', () {
      final doc = KanbanDocument.parse(_board);
      final done = doc.columns[2].cards.single;
      expect(KanbanEditor.advanceToEnd(doc, done), doc.content);
    });

    test('avançar na última coluna volta uma e desmarca', () {
      var doc = KanbanDocument.parse(_board);
      final done = doc.columns[2].cards.single;

      doc = KanbanDocument.parse(KanbanEditor.advanceCard(doc, done));
      final moved = doc.columns[1].cards.firstWhere((c) => c.id == 'k2');
      expect(moved.checked, isFalse);
    });

    test('o corpo do card viaja junto e intacto', () {
      var doc = KanbanDocument.parse(_board);
      final card = doc.columns[1].cards.single;
      final notes = card.notes;

      doc = KanbanDocument.parse(KanbanEditor.moveCard(doc, card, 0));
      final moved = doc.columns[0].cards.firstWhere((c) => c.id == 'k3');
      expect(moved.notes, notes);
    });

    test('mover pro fim da mesma coluna (sem atIndex) leva o card pro fim', () {
      var doc = KanbanDocument.parse(
        _board.replaceFirst(
          '<!-- id: k1 labels: bug -->\n',
          '<!-- id: k1 labels: bug -->\n\n- [ ] Segundo <!-- id: k4 -->\n',
        ),
      );
      expect(doc.columns[0].cards.map((c) => c.id), ['k1', 'k4']);

      doc = KanbanDocument.parse(
        KanbanEditor.moveCard(doc, doc.columns[0].cards.first, 0),
      );
      expect(doc.columns[0].cards.map((c) => c.id), ['k4', 'k1']);
      expect(doc.columns[1].cards.single.id, 'k3');
    });

    test('mover não toca no resto do arquivo', () {
      final doc = KanbanDocument.parse(_board);
      final card = doc.columns[1].cards.single;
      final after = KanbanEditor.moveCard(doc, card, 0);

      expect(after, contains('columns: [Backlog, Doing, Done]'));
      expect(after, contains('Servidor órfão ao fechar o app'));
      expect(after, contains('- [x] Absorver o plugin de PTY'));
    });
  });

  group('cards', () {
    test('addCard nasce com id e sem [x] fora da última coluna', () {
      final doc = KanbanDocument.parse(_board);
      final after = KanbanDocument.parse(
        KanbanEditor.addCard(doc, 0, 'Novo card'),
      );
      final card = after.columns[0].cards.last;
      expect(card.title, 'Novo card');
      expect(card.checked, isFalse);
      expect(card.id, isNotNull);
    });

    test('addCard na última coluna nasce marcado', () {
      final doc = KanbanDocument.parse(_board);
      final after = KanbanDocument.parse(
        KanbanEditor.addCard(doc, 2, 'Já feito'),
      );
      expect(after.columns[2].cards.last.checked, isTrue);
    });

    test('id é único mesmo com ids já usados', () {
      final doc = KanbanDocument.parse(_board);
      final after = KanbanDocument.parse(KanbanEditor.addCard(doc, 0, 'Outro'));
      final ids = after.columns.expand((c) => c.cards).map((c) => c.id);
      expect(ids.toSet().length, ids.length);
    });

    test('renomear preserva marcadores e estado', () {
      final doc = KanbanDocument.parse(_board);
      final card = doc.columns[1].cards.single;
      final after = KanbanDocument.parse(
        KanbanEditor.setCardTitle(doc, card, 'Outro título'),
      );
      final renamed = after.columns[1].cards.single;
      expect(renamed.title, 'Outro título');
      expect(renamed.labels, ['relay']);
      expect(renamed.id, 'k3');
      expect(renamed.notes, isNotEmpty);
    });

    test('toggleLabel liga e desliga', () {
      var doc = KanbanDocument.parse(_board);
      var card = doc.columns[1].cards.single;

      doc = KanbanDocument.parse(KanbanEditor.toggleLabel(doc, card, 'bug'));
      card = doc.columns[1].cards.single;
      expect(card.labels, ['relay', 'bug']);

      doc = KanbanDocument.parse(KanbanEditor.toggleLabel(doc, card, 'relay'));
      expect(doc.columns[1].cards.single.labels, ['bug']);
    });

    test('editar a nota não mexe no título', () {
      final doc = KanbanDocument.parse(_board);
      final card = doc.columns[1].cards.single;
      final after = KanbanDocument.parse(
        KanbanEditor.setCardNotes(doc, card, 'nota nova\ncom duas linhas'),
      );
      final edited = after.columns[1].cards.single;
      expect(edited.title, 'Túnel SSH no host');
      expect(edited.notes, 'nota nova\ncom duas linhas');
    });

    test('apagar card remove só ele', () {
      final doc = KanbanDocument.parse(_board);
      final after = KanbanDocument.parse(
        KanbanEditor.deleteCard(doc, doc.columns[1].cards.single),
      );
      expect(after.columns[1].cards, isEmpty);
      expect(after.columns[0].cards.length, 1);
      expect(after.columns[2].cards.length, 1);
    });

    test('card não reconhecido é imune à edição de texto', () {
      final doc = KanbanDocument.parse('## Col\n\nparágrafo solto\n');
      final card = doc.columns.single.cards.single;
      expect(KanbanEditor.setCardTitle(doc, card, 'x'), doc.content);
      expect(KanbanEditor.toggleLabel(doc, card, 'bug'), doc.content);
    });

    test('card não reconhecido ainda pode ser movido inteiro', () {
      final doc = KanbanDocument.parse('## A\n\nparágrafo solto\n\n## B\n');
      final card = doc.columns[0].cards.single;
      final after = KanbanDocument.parse(KanbanEditor.moveCard(doc, card, 1));
      expect(after.columns[0].cards, isEmpty);
      expect(after.columns[1].cards.single.title, 'parágrafo solto');
    });
  });

  group('colunas', () {
    test('adicionar e renomear', () {
      var doc = KanbanDocument.parse(_board);
      doc = KanbanDocument.parse(KanbanEditor.addColumn(doc, 'Review'));
      expect(doc.columns.map((c) => c.name).last, 'Review');

      doc = KanbanDocument.parse(KanbanEditor.renameColumn(doc, 1, 'Fazendo'));
      expect(doc.columns[1].name, 'Fazendo');
      expect(doc.columns[1].cards.single.title, 'Túnel SSH no host');
    });

    test('mover coluna troca de lugar com os cards junto', () {
      var doc = KanbanDocument.parse(_board);
      doc = KanbanDocument.parse(KanbanEditor.moveColumn(doc, 0, 1));
      expect(doc.columns.map((c) => c.name), ['Doing', 'Backlog', 'Done']);
      expect(doc.columns[0].cards.single.id, 'k3');
      expect(doc.columns[1].cards.single.id, 'k1');
    });

    test('apagar coluna movendo os cards pra anterior', () {
      final doc = KanbanDocument.parse(_board);
      final after = KanbanDocument.parse(
        KanbanEditor.deleteColumn(doc, 1, moveCardsToPrevious: true),
      );
      expect(after.columns.map((c) => c.name), ['Backlog', 'Done']);
      expect(
        after.columns[0].cards.map((c) => c.id),
        containsAll(['k1', 'k3']),
      );
    });

    test('apagar coluna com os cards dentro', () {
      final doc = KanbanDocument.parse(_board);
      final after = KanbanDocument.parse(
        KanbanEditor.deleteColumn(doc, 1, moveCardsToPrevious: false),
      );
      expect(after.columns.map((c) => c.name), ['Backlog', 'Done']);
      expect(after.content, isNot(contains('Túnel SSH')));
    });

    test('apagar a última coluna desmarca quem ia junto', () {
      var doc = KanbanDocument.parse(_board);
      doc = KanbanDocument.parse(
        KanbanEditor.deleteColumn(doc, 2, moveCardsToPrevious: true),
      );
      expect(doc.columns.map((c) => c.name), ['Backlog', 'Doing']);
      expect(
        doc.columns[1].cards.firstWhere((c) => c.id == 'k2').checked,
        isFalse,
      );
    });
  });

  group('comentários', () {
    const withComments = '''
## Doing

- [ ] Card <!-- id: k1 -->
      A nota do card.

      <!-- comment: 2026-09-06T19:22 -->
      O mais novo.

      <!-- comment: 2026-09-05T10:00 -->
      O mais antigo,
      em duas linhas.
''';

    test('separa nota e comentários no primeiro marcador', () {
      final card = KanbanDocument.parse(
        withComments,
      ).columns.single.cards.single;

      expect(card.notes, 'A nota do card.');
      expect(card.comments.length, 2);
      expect(card.comments.first.text, 'O mais novo.');
      expect(card.comments.first.createdAt, '2026-09-06T19:22');
      expect(card.comments.last.text, 'O mais antigo,\nem duas linhas.');
    });

    test('o novo entra no topo, sem tocar nos anteriores', () {
      var doc = KanbanDocument.parse(withComments);
      doc = KanbanDocument.parse(
        KanbanEditor.addComment(
          doc,
          doc.columns.single.cards.single,
          'Recém-chegado',
          now: DateTime(2026, 9, 7, 8, 30),
        ),
      );

      final card = doc.columns.single.cards.single;
      expect(card.comments.map((c) => c.text), [
        'Recém-chegado',
        'O mais novo.',
        'O mais antigo,\nem duas linhas.',
      ]);
      expect(card.comments.first.createdAt, '2026-09-07T08:30');
      // A nota fica onde estava.
      expect(card.notes, 'A nota do card.');
    });

    test('primeiro comentário de um card que só tinha nota', () {
      var doc = KanbanDocument.parse(_board);
      final target = doc.columns[1].cards.single;
      final notes = target.notes;

      doc = KanbanDocument.parse(
        KanbanEditor.addComment(
          doc,
          target,
          'Olá',
          now: DateTime(2026, 1, 2, 3, 4),
        ),
      );
      final card = doc.columns[1].cards.single;
      expect(card.comments.single.text, 'Olá');
      expect(card.notes, notes);
    });

    test('comentário em card sem nota nenhuma', () {
      var doc = KanbanDocument.parse('## A\n\n- [ ] seco <!-- id: k9 -->\n');
      doc = KanbanDocument.parse(
        KanbanEditor.addComment(
          doc,
          doc.columns.single.cards.single,
          'primeiro',
          now: DateTime(2026, 1, 1, 0, 0),
        ),
      );
      final card = doc.columns.single.cards.single;
      expect(card.title, 'seco');
      expect(card.notes, isEmpty);
      expect(card.comments.single.text, 'primeiro');
    });

    test('editar a nota NÃO apaga os comentários', () {
      var doc = KanbanDocument.parse(withComments);
      doc = KanbanDocument.parse(
        KanbanEditor.setCardNotes(
          doc,
          doc.columns.single.cards.single,
          'nota trocada',
        ),
      );
      final card = doc.columns.single.cards.single;
      expect(card.notes, 'nota trocada');
      expect(card.comments.length, 2);
      expect(card.comments.first.text, 'O mais novo.');
    });

    test('mover o card leva os comentários junto', () {
      var doc = KanbanDocument.parse('$withComments\n## Done\n');
      doc = KanbanDocument.parse(
        KanbanEditor.moveCard(doc, doc.columns[0].cards.single, 1),
      );
      expect(doc.columns[0].cards, isEmpty);
      expect(doc.columns[1].cards.single.comments.length, 2);
    });

    test('apagar um comentário deixa os outros', () {
      var doc = KanbanDocument.parse(withComments);
      final card = doc.columns.single.cards.single;
      doc = KanbanDocument.parse(
        KanbanEditor.deleteComment(doc, card, card.comments.first),
      );
      final after = doc.columns.single.cards.single;
      expect(after.comments.single.text, 'O mais antigo,\nem duas linhas.');
      expect(after.notes, 'A nota do card.');
    });

    test('comentário vazio é ignorado', () {
      final doc = KanbanDocument.parse(withComments);
      expect(
        KanbanEditor.addComment(doc, doc.columns.single.cards.single, '   '),
        doc.content,
      );
    });
  });

  group('fim de linha (Windows)', () {
    const crlf = '## A\r\n\r\n- [ ] um card <!-- id: k1 -->\r\n\r\n## B\r\n';

    test('arquivo CRLF continua CRLF depois de editar', () {
      final doc = KanbanDocument.parse(crlf);
      expect(doc.eol, '\r\n');
      expect(doc.columns.map((c) => c.name), ['A', 'B']);

      // Sem preservar o terminador, mover UM card reescreveria todas as linhas
      // do arquivo — o oposto da emenda de três linhas que o formato promete.
      final after = KanbanEditor.advanceCard(doc, doc.columns[0].cards.single);
      expect(after.contains('\r\n'), isTrue);
      expect(after.contains(RegExp('(?<!\r)\n')), isFalse);
      expect(
        KanbanDocument.parse(after).columns[1].cards.single.title,
        'um card',
      );
    });

    test('arquivo LF continua LF', () {
      final doc = KanbanDocument.parse(_board);
      expect(doc.eol, '\n');
      final after = KanbanEditor.addCard(doc, 0, 'novo');
      expect(after.contains('\r'), isFalse);
    });

    test('CRLF sobrevive a nota, comentário e frontmatter', () {
      var doc = KanbanDocument.parse(crlf);
      final card = doc.columns[0].cards.single;

      for (final content in [
        KanbanEditor.setCardNotes(doc, card, 'linha 1\nlinha 2'),
        KanbanEditor.addComment(doc, card, 'oi', now: DateTime(2026, 1, 1)),
        KanbanEditor.setBoardTitle(doc, 'Quadro'),
        KanbanEditor.upsertLabel(doc, 'bug', KanbanLabelColor.red),
      ]) {
        expect(content.contains(RegExp('(?<!\r)\n')), isFalse, reason: content);
      }

      // E o conteúdo continua íntegro depois de reparsear.
      doc = KanbanDocument.parse(
        KanbanEditor.setCardNotes(doc, card, 'linha 1\nlinha 2'),
      );
      expect(doc.columns[0].cards.single.notes, 'linha 1\nlinha 2');
    });
  });

  group('título do quadro', () {
    test('lê do frontmatter, com ou sem aspas', () {
      expect(
        KanbanDocument.parse('---\ntitle: Roadmap\n---\n\n## A\n').title,
        'Roadmap',
      );
      expect(
        KanbanDocument.parse('---\ntitle: "Meu quadro"\n---\n\n## A\n').title,
        'Meu quadro',
      );
      expect(KanbanDocument.parse('## A\n').title, isNull);
      expect(KanbanDocument.parse('---\ntitle:\n---\n\n## A\n').title, isNull);
    });

    test('comentário YAML no fim da linha não entra no título', () {
      expect(
        KanbanDocument.parse(
          '---\ntitle: Roadmap   # o rótulo da aba\n---\n\n## A\n',
        ).title,
        'Roadmap',
      );
      // Regra do YAML: `#` colado no texto NÃO abre comentário.
      expect(
        KanbanDocument.parse('---\ntitle: Sprint#4\n---\n\n## A\n').title,
        'Sprint#4',
      );
      // Com espaço antes, abre — e aspas são a saída, como em YAML de verdade.
      expect(
        KanbanDocument.parse('---\ntitle: Sprint #4\n---\n\n## A\n').title,
        'Sprint',
      );
      expect(
        KanbanDocument.parse('---\ntitle: "Sprint #4"\n---\n\n## A\n').title,
        'Sprint #4',
      );
    });

    test('comentário YAML não quebra o mapa de marcadores', () {
      final doc = KanbanDocument.parse(
        '---\nlabels: {bug: red}   # cores\n---\n\n## A\n',
      );
      expect(doc.colorOf('bug'), KanbanLabelColor.red);
      expect(doc.labelColors.length, 1);
    });

    test('grava, troca e apaga sem tocar no resto', () {
      var doc = KanbanDocument.parse(_board);
      expect(doc.title, isNull);

      doc = KanbanDocument.parse(KanbanEditor.setBoardTitle(doc, 'Roadmap'));
      expect(doc.title, 'Roadmap');
      // O que já estava no frontmatter e no corpo continua lá.
      expect(doc.labelColors['relay'], KanbanLabelColor.orange);
      expect(doc.columns.map((c) => c.name), ['Backlog', 'Doing', 'Done']);
      expect(doc.columns[1].cards.single.notes, isNotEmpty);

      doc = KanbanDocument.parse(KanbanEditor.setBoardTitle(doc, 'Outro'));
      expect(doc.title, 'Outro');
      // Trocar não duplica a linha.
      expect(
        RegExp('^title:', multiLine: true).allMatches(doc.content).length,
        1,
      );

      doc = KanbanDocument.parse(KanbanEditor.setBoardTitle(doc, null));
      expect(doc.title, isNull);
      expect(doc.labelColors['relay'], KanbanLabelColor.orange);
    });

    test('cria frontmatter quando o arquivo não tem', () {
      final doc = KanbanDocument.parse('## A\n\n- [ ] x\n');
      final after = KanbanDocument.parse(
        KanbanEditor.setBoardTitle(doc, 'Novo'),
      );
      expect(after.title, 'Novo');
      expect(after.columns.single.cards.single.title, 'x');
    });

    test('apagar num arquivo sem frontmatter é no-op', () {
      final doc = KanbanDocument.parse('## A\n');
      expect(KanbanEditor.setBoardTitle(doc, null), doc.content);
    });
  });

  group('marcadores', () {
    test('criar e recolorir escreve no frontmatter', () {
      var doc = KanbanDocument.parse(_board);
      doc = KanbanDocument.parse(
        KanbanEditor.upsertLabel(doc, 'ui', KanbanLabelColor.purple),
      );
      expect(doc.colorOf('ui'), KanbanLabelColor.purple);

      doc = KanbanDocument.parse(
        KanbanEditor.upsertLabel(doc, 'ui', KanbanLabelColor.blue),
      );
      expect(doc.colorOf('ui'), KanbanLabelColor.blue);
      expect(doc.labelColors.length, 3);
    });

    test('apagar marcador limpa os cards que o usavam', () {
      var doc = KanbanDocument.parse(_board);
      doc = KanbanDocument.parse(KanbanEditor.deleteLabel(doc, 'relay'));

      expect(doc.labelColors.containsKey('relay'), isFalse);
      expect(doc.columns[1].cards.single.labels, isEmpty);
      expect(doc.usageOf('relay'), 0);
    });

    test('cria frontmatter quando o arquivo não tem', () {
      final doc = KanbanDocument.parse('## Col\n\n- [ ] x\n');
      final after = KanbanDocument.parse(
        KanbanEditor.upsertLabel(doc, 'bug', KanbanLabelColor.red),
      );
      expect(after.colorOf('bug'), KanbanLabelColor.red);
      expect(after.columns.single.cards.single.title, 'x');
    });
  });

  // A skill é o que o agente lê para escrever `.kanban` na mão. Se o exemplo
  // dela deixar de casar com o parser, ele passa a produzir arquivos tortos —
  // e documentação errada é pior que documentação nenhuma.
  group('exemplo da skill', () {
    test('o board de exemplo em cli/text/skill.md parseia como descrito', () {
      final skill = File('cli/text/skill.md').readAsStringSync();
      final start = skill.indexOf('## Board files');
      expect(start, greaterThan(0), reason: 'seção do .kanban sumiu da skill');

      final fence = RegExp(
        r'```markdown\n(.*?)```',
        dotAll: true,
      ).firstMatch(skill.substring(start));
      expect(fence, isNotNull, reason: 'exemplo de .kanban sumiu da skill');

      final doc = KanbanDocument.parse(fence!.group(1)!);

      expect(doc.title, 'Roadmap');
      expect(doc.colorOf('relay'), KanbanLabelColor.orange);
      expect(doc.colorOf('bug'), KanbanLabelColor.red);
      expect(doc.columns.map((c) => c.name), ['Doing', 'Done']);

      final doing = doc.columns.first.cards.single;
      expect(doing.id, 'k3');
      expect(doing.labels, ['relay', 'infra']);
      expect(doing.checked, isFalse);
      expect(doing.notes, 'Free markdown note, indented under the title.');
      // O mais novo primeiro, como a skill promete.
      expect(doing.comments.map((c) => c.text), [
        'Newest comment.',
        'Older comment.',
      ]);
      expect(doing.comments.first.createdAt, '2026-09-07T08:30');

      // Última coluna = concluído, também como a skill promete.
      expect(doc.columns.last.cards.single.checked, isTrue);
    });
  });

  group('blockedBy', () {
    const board = '''
## Backlog

- [ ] Publish <!-- id: k3 labels: cd, mobile blockedBy: k1, k2 -->
- [ ] Test on device <!-- id: k2 blockedBy: k1 labels: mobile -->
- [ ] Sem id ainda

## Done

- [x] Pipeline <!-- id: k1 -->
''';

    test('lê blockedBy em qualquer ordem com labels, sem misturar', () {
      final doc = KanbanDocument.parse(board);
      final publish = doc.cardById('k3')!;
      expect(publish.labels, ['cd', 'mobile']);
      expect(publish.blockedBy, ['k1', 'k2']);
      final test = doc.cardById('k2')!;
      expect(test.labels, ['mobile']);
      expect(test.blockedBy, ['k1']);
    });

    test('bloqueio é derivado: bloqueador na última coluna não bloqueia', () {
      final doc = KanbanDocument.parse(board);
      expect(doc.isBlocked(doc.cardById('k2')!), isFalse, reason: 'k1 done');
      expect(doc.isBlocked(doc.cardById('k3')!), isTrue, reason: 'k2 pendente');
      expect(doc.blocksCount(doc.cardById('k1')!), 2);
      expect(doc.blocksCount(doc.cardById('k2')!), 1);
    });

    test(
      'setBlockedBy grava ids, atribui id a quem não tem e preserva labels',
      () {
        final doc = KanbanDocument.parse(board);
        final semId = doc.columns[0].cards[2];
        final content = KanbanEditor.setBlockedBy(doc, semId, [
          doc.cardById('k3')!,
          semId, // ignorado: não bloqueia a si mesmo
        ]);
        final next = KanbanDocument.parse(content);
        final card = next.columns[0].cards[2];
        expect(card.id, 'k4');
        expect(card.blockedBy, ['k3']);
        // Limpar mantém o id e os labels do card alvo.
        final cleared = KanbanDocument.parse(
          KanbanEditor.setBlockedBy(next, next.cardById('k3')!, const []),
        );
        final k3 = cleared.cardById('k3')!;
        expect(k3.blockedBy, isEmpty);
        expect(k3.labels, ['cd', 'mobile']);
      },
    );

    test('id desconhecido não bloqueia e aparece em unknownBlockers', () {
      final doc = KanbanDocument.parse(
        '## A\n\n- [ ] X <!-- id: k1 blockedBy: k9 -->\n\n## Done\n',
      );
      final x = doc.cardById('k1')!;
      expect(doc.isBlocked(x), isFalse);
      expect(doc.unknownBlockers(x), ['k9']);
    });
  });
}
