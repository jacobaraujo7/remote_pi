import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/panel_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('panel offers the Neovim edit action on Linux', (tester) async {
    final session = FileViewerSession(
      id: 'panel',
      projectId: 'project',
      path: '/workspace/dashboard.panel',
      view: const FileViewText('<h1>Dashboard</h1>'),
    );
    var edits = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: PanelView(
              session: session,
              onCall: (_, _) async => const {},
              editSourceLabel: 'Editar com Neovim',
              onEditSource: () => edits++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Editar com Neovim'), findsOneWidget);
    await tester.tap(find.text('Editar com Neovim'));
    expect(edits, 1);
  });
}
