import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/widgets/graph_box_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  const terminalBox = GraphBox(
    id: 'box-terminal',
    title: 'Terminal',
    role: '',
    harness: '',
    model: '',
    position: Offset(110, 130),
    tabId: 'terminal',
  );

  Future<void> openEditor(
    WidgetTester tester,
    void Function(GraphBoxEditDraft?) onResult,
  ) async {
    await tester.pumpWidget(
      TickerMode(
        enabled: true,
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: Builder(
              builder: (context) => PrimaryButton(
                onPressed: () async => onResult(
                  await showGraphBoxEditor(
                    context,
                    terminalBox,
                    canStart: true,
                  ),
                ),
                child: const Text('Configure terminal'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Configure terminal'));
    await tester.pumpAndSettle();
  }

  testWidgets('a plain terminal saves its box without context or CLI', (
    tester,
  ) async {
    GraphBoxEditDraft? result;
    await openEditor(tester, (value) => result = value);
    expect(find.text('Salvar e iniciar CLI'), findsNothing);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(result, (role: '', harness: '', model: '', start: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a CLI can start without a context prompt', (tester) async {
    GraphBoxEditDraft? result;
    await openEditor(tester, (value) => result = value);
    await tester.tap(find.text('codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar e iniciar CLI'));
    await tester.pumpAndSettle();
    expect(result, (role: '', harness: 'codex', model: '', start: true));
    expect(tester.takeException(), isNull);
  });
}
