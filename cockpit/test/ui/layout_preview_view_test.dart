import 'package:cockpit/app/cockpit/ui/widgets/layout_preview_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const _source = '''
panes:
  - name: Frontend
    cwd: frontend
    command: npm run dev
  - name: Backend
    cwd: backend
    split: right
    command: claude
  - name: Sign
    command: ./sign.sh
    platforms: [windows]
''';

Future<void> _pump(
  WidgetTester tester, {
  required String source,
  VoidCallback? onApply,
  List<LayoutApplyAction> alternatives = const [],
}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Scaffold(
          child: LayoutPreviewView(
            path: '/home/j/app/dev.ckp',
            source: source,
            hostOs: 'macos',
            primary: LayoutApplyAction(
              label: 'Apply to app',
              onApply: onApply ?? () {},
            ),
            alternatives: alternatives,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('lista os panes com o comando e o cwd resolvido', (tester) async {
    await _pump(tester, source: _source);

    expect(find.text('dev'), findsOneWidget);
    expect(find.text('Frontend'), findsOneWidget);
    expect(find.text('Backend'), findsOneWidget);
    // O comando é o ponto do preview: tem que estar na tela, literal.
    expect(find.text('npm run dev'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);
    // cwd resolvido contra a pasta do arquivo, não o relativo do YAML.
    expect(find.text('/home/j/app/frontend'), findsOneWidget);
    expect(find.text('/home/j/app/backend'), findsOneWidget);
  });

  testWidgets('pane de outro SO aparece como não criado aqui', (tester) async {
    await _pump(tester, source: _source);
    expect(find.text('Sign'), findsOneWidget);
    expect(find.text('./sign.sh'), findsOneWidget);
    expect(find.text('windows'), findsOneWidget);
  });

  testWidgets('arquivo inválido mostra o erro E o conteúdo', (tester) async {
    await _pump(tester, source: 'panes: []\n');
    expect(
      find.textContaining('non-empty "panes" list'),
      findsOneWidget,
      reason: 'o erro do parser aparece',
    );
    expect(find.textContaining('panes: []'), findsOneWidget);
  });

  testWidgets('Apply dispara a ação primária', (tester) async {
    var applied = 0;
    await _pump(tester, source: _source, onApply: () => applied++);
    await tester.tap(find.text('Apply to app'));
    await tester.pump();
    expect(applied, 1);
  });

  testWidgets('Apply fica desabilitado quando o layout não parseia', (
    tester,
  ) async {
    var applied = 0;
    await _pump(tester, source: ': : :', onApply: () => applied++);
    await tester.tap(find.text('Apply to app'), warnIfMissed: false);
    await tester.pump();
    expect(applied, 0);
  });
}
