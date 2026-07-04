import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:cockpit/app/cockpit/ui/session/diff_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/diff_viewer.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  DiffViewerSession sessionWith(FileDiff diff) => DiffViewerSession(
    id: 'd1',
    projectId: 'p1',
    path: '/repo/a.txt',
    diff: diff,
  );

  Widget host(FileDiff diff) => ShadcnApp(
    theme: buildTheme(brightness: Brightness.dark),
    home: Scaffold(
      // Box limitado (como um pane) — pega regressão de largura infinita.
      child: SizedBox(
        width: 400,
        height: 300,
        child: DiffViewer(session: sessionWith(diff)),
      ),
    ),
  );

  testWidgets('modified diff renderiza sem exceção de layout', (tester) async {
    final diff = FileDiff(
      path: '/repo/a.txt',
      kind: FileDiffKind.modified,
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
  });

  testWidgets('binário mostra mensagem', (tester) async {
    await tester.pumpWidget(host(const FileDiff.binary('/repo/bin.dat')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Binary file'), findsOneWidget);
  });

  testWidgets('unchanged mostra No changes', (tester) async {
    await tester.pumpWidget(host(const FileDiff.unchanged('/repo/a.txt')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No changes.'), findsOneWidget);
  });
}
