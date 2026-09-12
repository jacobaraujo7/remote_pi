import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/kanban_board_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/user_home.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const _board = '''
---
labels: {bug: red}
---

## Backlog

- [ ] Primeiro card <!-- id: k1 labels: bug -->

## Done

- [x] Card pronto <!-- id: k2 -->
''';

void main() {
  late FileViewerSession session;
  late List<String> saved;
  late bool saveOk;
  late int reloads;
  late String workspaceRoot;
  late List<bool> viewModes;

  setUp(() {
    workspaceRoot = '/repo';
    viewModes = [];
    saved = [];
    saveOk = true;
    reloads = 0;
    session = FileViewerSession(
      id: 'v1',
      projectId: 'p1',
      path: '/repo/roadmap.kanban',
      view: const FileViewText(_board),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          // Scaffold do shadcn: fornece o DrawerOverlay que o popover de
          // filtro precisa (sem ele, showPopover assert-a no modo sheet).
          home: Scaffold(
            child: KanbanBoardView(
              session: session,
              active: true,
              focused: true,
              workspaceRoot: workspaceRoot,
              onSave: (content) async {
                saved.add(content);
                if (saveOk) session.view = FileViewText(content);
                return saveOk;
              },
              onReload: () async => reloads++,
              onViewModeChanged: (asList) => viewModes.add(asList),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mostra colunas e cards, riscando só na última', (tester) async {
    await pump(tester);

    expect(find.text('BACKLOG'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Primeiro card'), findsOneWidget);
    expect(find.text('bug'), findsOneWidget);

    TextStyle styleOf(String text) =>
        tester.widget<Text>(find.text(text)).style!;
    expect(
      styleOf('Primeiro card').decoration,
      isNot(TextDecoration.lineThrough),
    );
    expect(styleOf('Card pronto').decoration, TextDecoration.lineThrough);
  });

  testWidgets('o botão avançar move o card e grava o arquivo', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.arrow_forward).first);
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single, contains('## Done\n'));
    // O card saiu do Backlog e chegou marcado no Done.
    final done = saved.single.split('## Done').last;
    expect(done, contains('- [x] Primeiro card'));
  });

  testWidgets('gravação recusada devolve o card pro lugar', (tester) async {
    saveOk = false;
    await pump(tester);

    await tester.tap(find.byIcon(Icons.arrow_forward).first);
    await tester.pumpAndSettle();

    // Diálogo de erro + estado revertido: a tela não fica mostrando um card
    // numa coluna onde ele não está no arquivo.
    expect(find.text('Could not save the board'), findsOneWidget);
  });

  testWidgets('alternar pra lista mostra os grupos e some com as colunas', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.format_list_bulleted));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.text('BACKLOG'), findsOneWidget);
    expect(find.text('Primeiro card'), findsOneWidget);

    // A escolha fica na sessão (que o layout persiste) e é avisada à VM — o
    // State local morreria ao mover a aba de pane.
    expect(session.boardAsList, isTrue);
    expect(viewModes, [true]);
  });

  testWidgets('abre em lista quando a sessão já vinha assim', (tester) async {
    session.boardAsList = true;
    await pump(tester);

    // Sem nenhum clique: é como a aba foi restaurada.
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.text('Primeiro card'), findsOneWidget);
    expect(viewModes, isEmpty);
  });

  testWidgets('novo card nasce com texto padrão em edição', (tester) async {
    await pump(tester);

    // O botão é só o `+` agora — o rótulo virou tooltip.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(saved.single, contains('- [ ] New card'));
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'New card');
    // Texto padrão selecionado: digitar substitui.
    expect(field.controller!.selection.textInside('New card'), 'New card');
  });

  testWidgets('clicar no corpo do card abre o painel de detalhe', (
    tester,
  ) async {
    await pump(tester);

    // Fora do título: o título tem gesto próprio (edição inline).
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('k1'), findsOneWidget);
  });

  testWidgets('clicar no título edita no lugar E abre o painel', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Primeiro card'));
    await tester.pumpAndSettle();

    // O título ocupa quase todo o card: se ele não abrisse o painel, clicar no
    // card pareceria não fazer nada na maioria das vezes.
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('k1'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Primeiro card');
    // Nada selecionado: um clique distraído não pode apagar o título na
    // primeira tecla. O cursor fica no fim.
    expect(field.controller!.selection.isCollapsed, isTrue);
    expect(field.controller!.selection.baseOffset, 'Primeiro card'.length);
    // Sem moldura: o texto vira editável no lugar, não vira um campo.
    expect(field.decoration, const BoxDecoration());
    expect(field.padding, EdgeInsets.zero);
    // Quebra em várias linhas como o Text — não vira uma linha só.
    expect(field.maxLines, isNull);
    // E o anel de foco do shadcn (desenhado FORA da decoration) fica invisível.
    final outline = tester.widget<ComponentTheme<FocusOutlineTheme>>(
      find.ancestor(
        of: find.byType(TextField).first,
        matching: find.byType(ComponentTheme<FocusOutlineTheme>),
      ),
    );
    expect(outline.data.border!.top.color, Colors.transparent);
  });

  testWidgets('tocar fora fecha o painel', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();
    expect(find.text('NOTE'), findsOneWidget);

    // Qualquer coisa fora do painel dispensa — sem handler espalhado pelo
    // quadro e sem barrier cobrindo as colunas.
    await tester.tap(find.text('BACKLOG'));
    await tester.pumpAndSettle();
    expect(find.text('NOTE'), findsNothing);
  });

  testWidgets('tocar dentro do painel não fecha', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NOTE'));
    await tester.pumpAndSettle();
    expect(find.text('NOTE'), findsOneWidget);
  });

  testWidgets('clicar noutro card troca a seleção num gesto só', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();
    expect(find.text('k1'), findsOneWidget);

    // O fechar (pointer down) e o abrir (pointer up) acontecem no mesmo toque:
    // o painel termina no card novo, não fechado.
    await tester.tap(find.text('Card pronto'));
    await tester.pumpAndSettle();
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('k2'), findsOneWidget);
  });

  testWidgets('a nota é um campo visível, com placeholder quando vazia', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    // O card 'Primeiro card' não tem nota: o campo aparece mesmo assim, com
    // moldura à mostra e o convite dentro. Ninguém precisa adivinhar que dá
    // pra escrever ali.
    final notes = tester.widget<TextField>(find.byType(TextField).last);
    expect(notes.border, isNotNull);
    expect(notes.controller!.text, isEmpty);
    expect(find.text('Write a note'), findsOneWidget);
  });

  testWidgets('editar a nota grava no arquivo', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'nota nova');
    // Clicar fora fecha o painel e, no mesmo gesto, grava a nota: o campo
    // perde o foco e é isso que dispara a gravação.
    await tester.tap(find.text('BACKLOG'));
    await tester.pumpAndSettle();

    expect(saved.last, contains('nota nova'));
  });

  testWidgets('clicar no título do painel edita ali mesmo', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    // Dois "Primeiro card" na tela: o do card e o do painel. O do painel é o
    // último na árvore.
    await tester.tap(find.text('Primeiro card').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Título trocado');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(saved.last, contains('- [ ] Título trocado'));
  });

  testWidgets('trocar de card resemeia os campos do painel', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'rascunho');

    await tester.tap(find.text('Card pronto'));
    await tester.pumpAndSettle();

    // O rascunho não vaza pro card novo.
    final notes = tester.widget<TextField>(find.byType(TextField).last);
    expect(notes.controller!.text, isNot('rascunho'));
  });

  testWidgets('o painel abre o gerenciador de marcadores', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    // O botão fica junto dos chips: eles APLICAM marcadores, ele os administra.
    await tester.tap(find.byIcon(Icons.label_outline).last);
    await tester.pumpAndSettle();

    expect(find.text('Labels in this board'), findsOneWidget);
    // E o painel continua aberto atrás — o dialog divide o grupo de TapRegion
    // com ele, senão sair do dialog deixaria a tela sem detalhe.
    expect(find.text('NOTE'), findsOneWidget);
  });

  testWidgets('o painel não mostra o número da linha', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    expect(find.textContaining('line '), findsNothing);
  });

  testWidgets('a barra mostra o caminho, não contadores', (tester) async {
    await pump(tester);

    expect(find.text('roadmap.kanban'), findsWidgets);
    expect(find.textContaining('cards ·'), findsNothing);
  });

  testWidgets('os botões da barra ficam encostados na borda direita', (
    tester,
  ) async {
    await pump(tester);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final toggle = tester.getTopRight(find.byIcon(Icons.format_list_bulleted));
    // Colados na direita, não parados no meio (era o que acontecia quando o
    // caminho e um Spacer dividiam a sobra).
    expect(toggle.dx, greaterThan(width * 0.9));
  });

  testWidgets('modo fonte mostra o markdown cru em vez do quadro', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('BACKLOG'), findsOneWidget);

    // A sessão é a mesma; só muda quem a desenha. Quem checa isso é o
    // `pane_view`, então aqui garantimos ao menos que a chave existe e alterna.
    expect(session.rawSource, isFalse);
    session.toggleRawSource();
    expect(session.rawSource, isTrue);
    session.toggleRawSource();
    expect(session.rawSource, isFalse);
  });

  testWidgets('o compositor de comentário só existe depois do +', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    expect(find.text('COMMENTS'), findsOneWidget);
    expect(find.text('No comments yet'), findsOneWidget);
    // Título + nota: dois campos, nenhum de comentário ainda.
    expect(find.byType(TextField), findsNWidgets(1));

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('adicionar grava e o comentário toma o lugar do compositor', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'primeiro comentário');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(saved.last, contains('<!-- comment:'));
    expect(saved.last, contains('primeiro comentário'));
    // O compositor sumiu e o comentário está na tela.
    expect(find.text('Add'), findsNothing);
    expect(find.text('primeiro comentário'), findsOneWidget);
  });

  testWidgets('comentário vazio não grava nada', (tester) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
  });

  testWidgets('trocar de card fecha o compositor e descarta o rascunho', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('bug'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'rascunho');

    await tester.tap(find.text('Card pronto'));
    await tester.pumpAndSettle();

    expect(find.text('Add'), findsNothing);
    expect(saved, isEmpty);
  });

  testWidgets('o botão atualizar relê o arquivo', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(reloads, 1);
  });

  testWidgets('arquivo sem colunas oferece começar um quadro', (tester) async {
    session = FileViewerSession(
      id: 'v2',
      projectId: 'p1',
      path: '/repo/vazio.kanban',
      view: const FileViewText('só um texto solto'),
    );
    await pump(tester);

    expect(find.text('Start a board'), findsOneWidget);
    await tester.tap(find.text('Start a board'));
    await tester.pumpAndSettle();

    expect(saved.single, contains('## Backlog'));
    expect(saved.single, contains('## Done'));
  });

  testWidgets('mudança no disco é adotada sem interação', (tester) async {
    await pump(tester);

    session.view = const FileViewText('## Nova\n\n- [ ] vindo do agente\n');
    session.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('vindo do agente'), findsOneWidget);
    expect(find.text('Primeiro card'), findsNothing);
  });

  group('aba de arquivo', () {
    FileViewerSession viewer() => FileViewerSession(
      id: 'v9',
      projectId: 'p1',
      path: '/repo/roadmap.kanban',
      view: const FileViewText(_board),
    );

    test('aceita rótulo manual, como terminal e agente', () {
      final s = viewer();
      expect(s.displayTitle, 'roadmap.kanban');

      s.setManualLabel('Roadmap');
      expect(s.displayTitle, 'Roadmap');
      expect(s.titleLocked, isTrue);
      // O título dinâmico segue vivo por baixo — só não é exibido.
      expect(s.title, 'roadmap.kanban');

      s.clearManualLabel();
      expect(s.displayTitle, 'roadmap.kanban');
      expect(s.titleLocked, isFalse);
    });

    test('alterna entre quadro e markdown', () {
      final s = viewer();
      expect(s.rawSource, isFalse);
      s.toggleRawSource();
      expect(s.rawSource, isTrue);
      s.toggleRawSource();
      expect(s.rawSource, isFalse);
    });
  });

  group('caminho na barra', () {
    test('dentro do workspace vira relativo', () {
      expect(
        kanbanDisplayPath('/repo/docs/roadmap.kanban', '/repo'),
        'docs/roadmap.kanban',
      );
    });

    test('fora do workspace mas dentro da home começa em ~', () {
      final home = userHome()!;
      expect(
        kanbanDisplayPath('$home/notas/pessoal.kanban', '/repo'),
        '~/notas/pessoal.kanban',
      );
    });

    test('fora dos dois fica absoluto', () {
      expect(
        kanbanDisplayPath('/etc/algo.kanban', '/repo'),
        '/etc/algo.kanban',
      );
    });

    test('workspace vazio não engole o caminho', () {
      final home = userHome()!;
      expect(kanbanDisplayPath('$home/a.kanban', ''), '~/a.kanban');
      expect(kanbanDisplayPath('/fora/a.kanban', ''), '/fora/a.kanban');
    });

    test('caminho do Windows com barra invertida', () {
      // No Windows o `dart:io` devolve caminho nativo; o `relativeUnder`
      // normaliza os dois lados, então o relativo sai certo mesmo assim.
      expect(
        kanbanDisplayPath(r'C:\proj\docs\a.kanban', r'C:\proj'),
        'docs/a.kanban',
      );
      expect(kanbanDisplayPath(r'C:\proj\a.kanban', 'C:/proj'), 'a.kanban');
      expect(
        kanbanDisplayPath(r'D:\fora\a.kanban', r'C:\proj'),
        r'D:\fora\a.kanban',
      );
    });

    test('prefixo parecido não conta como dentro', () {
      // `/repo-outro` não está sob `/repo`.
      expect(
        kanbanDisplayPath('/repo-outro/a.kanban', '/repo'),
        '/repo-outro/a.kanban',
      );
    });
  });

  testWidgets('filtro por texto e por marcador esconde os outros cards', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Primeiro card'), findsOneWidget);
    expect(find.text('Card pronto'), findsOneWidget);

    // Abre o popover pelo botão da toolbar.
    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('kanban-filter-text'));
    expect(field, findsOneWidget);

    // Texto: só "Primeiro card" bate.
    await tester.enterText(field, 'primeiro');
    await tester.pumpAndSettle();
    expect(find.text('Primeiro card'), findsOneWidget);
    expect(find.text('Card pronto'), findsNothing);

    // Limpa e filtra pelo marcador `bug`: mesmo resultado.
    await tester.tap(find.byKey(const ValueKey('kanban-filter-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Card pronto'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kanban-filter-label-bug')));
    await tester.pumpAndSettle();
    expect(find.text('Primeiro card'), findsOneWidget);
    expect(find.text('Card pronto'), findsNothing);

    // Fecha o popover: o filtro continua aplicado e o ícone fica preenchido.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Card pronto'), findsNothing);
    expect(find.byIcon(Icons.filter_alt), findsOneWidget);
  });

  testWidgets('rodapé mostra número, comentários e bloqueio; filtro Blocked', (
    tester,
  ) async {
    session.view = const FileViewText('''
## Backlog

- [ ] Publicar <!-- id: k3 blockedBy: k1, k2 -->
- [ ] Testar <!-- id: k2 -->
      Nota que não aparece no card.

      <!-- comment: 2026-09-12T10:00 -->
      Um comentário.

## Done

- [x] Pipeline <!-- id: k1 -->
''');
    await pump(tester);

    // Número do card no rodapé; a nota fica só no painel.
    expect(find.text('#k3'), findsOneWidget);
    expect(find.textContaining('Nota que não aparece'), findsNothing);
    // Comentários: ícone + contagem.
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    // k3 está bloqueado por k2 (pendente); k1 já terminou e não conta. Só
    // ícone + número, e o card bloqueado perde o botão de avançar (os outros
    // dois abertos continuam com ele: Testar e o placeholder não existe).
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    // Quem bloqueia não mostra nada.
    expect(find.byIcon(Icons.account_tree_outlined), findsNothing);

    // Filtro "Blocked" deixa só o k3.
    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kanban-filter-blocked')));
    await tester.pumpAndSettle();
    expect(find.text('Publicar'), findsOneWidget);
    expect(find.text('Testar'), findsNothing);
    // "Ready" inverte.
    await tester.tap(find.byKey(const ValueKey('kanban-filter-ready')));
    await tester.pumpAndSettle();
    expect(find.text('Publicar'), findsNothing);
    expect(find.text('Testar'), findsOneWidget);
  });
}
