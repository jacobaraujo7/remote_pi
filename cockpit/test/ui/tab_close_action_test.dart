import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/actions/tab_actions.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// O X do título e o ⌘W passam pela MESMA regra ([requestCloseTab]): um
/// caminho que esquecesse o diálogo descartaria trabalho em silêncio.
void main() {
  FileViewerSession session({required bool dirty}) {
    final s = FileViewerSession(
      id: 'v1',
      projectId: 'p1',
      path: '/repo/a.dart',
      view: const FileViewText('x'),
    );
    if (dirty) s.setDirty(true);
    return s;
  }

  /// Monta a árvore e devolve um contexto vivo abaixo do TranslationProvider.
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('aba limpa fecha direto, sem perguntar', (tester) async {
    final ctx = await pump(tester);
    var closed = 0;

    final ok = await requestCloseTab(
      ctx,
      session(dirty: false),
      () => closed++,
    );
    await tester.pumpAndSettle();

    expect(ok, isTrue);
    expect(closed, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('aba suja pergunta e só fecha com a resposta', (tester) async {
    final ctx = await pump(tester);
    var closed = 0;

    final pending = requestCloseTab(ctx, session(dirty: true), () => closed++);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(closed, 0, reason: 'não pode fechar antes da resposta');

    // "Descartar" fecha sem salvar.
    await tester.tap(find.text(ctx.t.cockpit.confirmDialog.dontSave));
    await tester.pumpAndSettle();

    expect(await pending, isTrue);
    expect(closed, 1);
  });

  testWidgets('cancelar mantém a aba aberta', (tester) async {
    final ctx = await pump(tester);
    var closed = 0;

    final pending = requestCloseTab(ctx, session(dirty: true), () => closed++);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ctx.t.common.cancel));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    expect(closed, 0);
  });
}
