import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:cockpit/app/cockpit/ui/session/diff_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/diff_viewer.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  DiffViewerSession sessionWith(FileDiff diff) => DiffViewerSession(
    id: 'd1',
    projectId: 'p1',
    path: '/repo/a.txt',
    diff: diff,
  );

  Widget hostSession(
    DiffViewerSession session, {
    Future<String> Function(DiffViewerSession)? loadContent,
  }) => TranslationProvider(
    child: ShadcnApp(
      theme: buildTheme(
        brightness: Brightness.dark,
      ).copyWith(platform: () => TargetPlatform.windows),
      home: Scaffold(
        // Box limitado (como um pane) — pega regressão de largura infinita.
        child: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: DiffViewer(
              session: session,
              loadModifiedContent:
                  loadContent ?? (_) async => 'line1\nCHANGED\nline3\n',
            ),
          ),
        ),
      ),
    ),
  );

  Widget host(FileDiff diff) => hostSession(sessionWith(diff));

  testWidgets('modified diff renderiza sem exceção de layout', (tester) async {
    final diff = FileDiff(
      path: '/repo/a.txt',
      kind: FileDiffKind.modified,
      beforeRevision: '1111111111111111',
      afterRevision: '2222222222222222',
      hunks: const [
        DiffHunk(
          header: '@@ -1,3 +1,3 @@',
          lines: [
            DiffLine(
              kind: DiffLineKind.context,
              text: 'line1',
              oldLine: 1,
              newLine: 1,
            ),
            DiffLine(kind: DiffLineKind.removed, text: 'line2', oldLine: 2),
            DiffLine(kind: DiffLineKind.added, text: 'CHANGED', newLine: 2),
            DiffLine(
              kind: DiffLineKind.context,
              text: 'line3',
              oldLine: 3,
              newLine: 3,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(host(diff));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CHANGED'), findsOneWidget);
    expect(find.text('line2'), findsOneWidget);
    expect(find.text('Original 11111111'), findsOneWidget);
    expect(find.text('Modified 22222222'), findsOneWidget);
    expect(find.text('repo'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
  });

  testWidgets('binário mostra mensagem', (tester) async {
    await tester.pumpWidget(host(const FileDiff.binary('/repo/bin.dat')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Binary file'), findsOneWidget);
  });

  testWidgets('binário histórico mantém as refs da comparação', (tester) async {
    await tester.pumpWidget(
      host(
        const FileDiff(
          path: '/repo/bin.dat',
          kind: FileDiffKind.binary,
          beforeRevision: '1111111111111111',
          afterRevision: '2222222222222222',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Original 11111111'), findsOneWidget);
    expect(find.text('Modified 22222222'), findsOneWidget);
  });

  testWidgets('unchanged mostra No changes', (tester) async {
    await tester.pumpWidget(host(const FileDiff.unchanged('/repo/a.txt')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No changes.'), findsOneWidget);
  });

  testWidgets('select alterna Inline e Modified content completo', (
    tester,
  ) async {
    final diff = FileDiff(
      path: '/repo/a.txt',
      kind: FileDiffKind.modified,
      hunks: const [
        DiffHunk(
          header: '@@ -1,2 +1,2 @@',
          lines: [
            DiffLine(
              kind: DiffLineKind.context,
              text: 'SAME',
              oldLine: 1,
              newLine: 1,
            ),
            DiffLine(kind: DiffLineKind.removed, text: 'OLD', oldLine: 2),
            DiffLine(kind: DiffLineKind.added, text: 'NEW', newLine: 2),
          ],
        ),
      ],
    );
    final session = sessionWith(diff);
    await tester.pumpWidget(
      hostSession(
        session,
        loadContent: (_) async => 'outside hunk\nNEW\nlast line\n',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diff-view-mode-select')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(MenuButton, 'Inline'));
    await tester.pumpAndSettle();
    expect(session.viewMode, DiffViewMode.inline);
    expect(find.byKey(const Key('diff-inline-old-1')), findsOneWidget);
    expect(find.byKey(const Key('diff-inline-new-1')), findsOneWidget);
    expect(find.byKey(const Key('diff-inline-old-2')), findsOneWidget);
    expect(find.byKey(const Key('diff-inline-new-2')), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
    expect(find.text('OLD'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);

    await tester.tap(find.byKey(const Key('diff-view-mode-select')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(MenuButton, 'Modified content'));
    await tester.pump();
    await tester.pump();
    expect(session.viewMode, DiffViewMode.modifiedContent);
    expect(find.text('outside hunk'), findsOneWidget);
    expect(find.text('last line'), findsOneWidget);
    expect(find.text('OLD'), findsNothing);
  });

  testWidgets('linha longa pode ser alcançada no scroll horizontal', (
    tester,
  ) async {
    final longLine = 'wide line ${List.filled(300, 'x').join()}';
    await tester.pumpWidget(
      host(
        FileDiff(
          path: '/repo/a.txt',
          kind: FileDiffKind.modified,
          hunks: [
            DiffHunk(
              header: '@@ -1 +1 @@',
              lines: [
                DiffLine(
                  kind: DiffLineKind.removed,
                  text: longLine,
                  oldLine: 1,
                ),
                DiffLine(kind: DiffLineKind.added, text: longLine, newLine: 1),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = tester
        .widgetList<Scrollbar>(find.byType(Scrollbar))
        .where((bar) => bar.scrollbarOrientation == ScrollbarOrientation.bottom)
        .toList();
    expect(horizontal, hasLength(2));
    final left = horizontal[0].controller!;
    final right = horizontal[1].controller!;
    final halfWidth = (tester.getSize(find.byType(DiffViewer)).width - 1) / 2;
    expect(left.position.viewportDimension, closeTo(halfWidth, 1));
    expect(right.position.viewportDimension, closeTo(halfWidth, 1));
    expect(left.position.maxScrollExtent, greaterThan(0));
    left.jumpTo(120);
    await tester.pump();
    expect(right.offset, closeTo(120, 0.5));
    right.jumpTo(40);
    await tester.pump();
    expect(left.offset, closeTo(40, 0.5));
  });

  testWidgets('lado a lado mantém a rolagem vertical alinhada', (tester) async {
    await tester.pumpWidget(
      host(
        FileDiff(
          path: '/repo/a.txt',
          kind: FileDiffKind.modified,
          hunks: [
            DiffHunk(
              header: '@@ -1,60 +1,60 @@',
              lines: [
                for (var i = 1; i <= 60; i++)
                  DiffLine(
                    kind: DiffLineKind.context,
                    text: 'line $i',
                    oldLine: i,
                    newLine: i,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panes = tester.widgetList<ListView>(find.byType(ListView)).toList();
    expect(panes, hasLength(2));
    final left = panes[0].controller!;
    final right = panes[1].controller!;
    left.jumpTo(180);
    await tester.pump();
    expect(right.offset, closeTo(180, 0.5));
  });

  testWidgets('arquivo removido não tenta ler conteúdo modificado', (
    tester,
  ) async {
    final session = sessionWith(
      const FileDiff(
        path: '/repo/a.txt',
        kind: FileDiffKind.deleted,
        hunks: [
          DiffHunk(
            header: '@@ -1 +0,0 @@',
            lines: [
              DiffLine(kind: DiffLineKind.removed, text: 'OLD', oldLine: 1),
            ],
          ),
        ],
      ),
    );
    session.setViewMode(DiffViewMode.modifiedContent);
    await tester.pumpWidget(
      hostSession(
        session,
        loadContent: (_) => throw StateError('should not read'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('deleted'), findsOneWidget);
  });

  test('preview mantém modo e ignora leitura antiga', () {
    const oldDiff = FileDiff(
      path: '/repo/old.txt',
      kind: FileDiffKind.modified,
    );
    const newDiff = FileDiff(
      path: '/repo/new.txt',
      kind: FileDiffKind.modified,
    );
    final session = sessionWith(oldDiff);
    session.setViewMode(DiffViewMode.modifiedContent);
    session.startModifiedContentLoad();
    session.replaceDiff(newDiff, '/repo/new.txt');
    session.completeModifiedContentLoad(oldDiff, 'stale');
    expect(session.viewMode, DiffViewMode.modifiedContent);
    expect(session.modifiedContent, isNull);
    session.startModifiedContentLoad();
    session.completeModifiedContentLoad(newDiff, 'fresh');
    expect(session.modifiedContent, 'fresh');
  });
}
