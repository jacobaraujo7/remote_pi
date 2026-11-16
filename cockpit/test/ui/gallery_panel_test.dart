import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:cockpit/app/cockpit/ui/widgets/gallery_panel.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('renders one card per template and fires onCreate on tap', (
    tester,
  ) async {
    GalleryTemplate? created;
    // Oito cards não cabem na viewport padrão de teste (800x600); sem isso o
    // último card do ListView nem é construído.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(child: GalleryPanel(onCreate: (t) => created = t)),
        ),
      ),
    );
    await tester.pump();

    for (final t in GalleryTemplate.values) {
      expect(find.byKey(ValueKey('gallery-${t.name}')), findsOneWidget);
    }
    expect(find.text('.kanban'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-kanban')));
    await tester.pump();
    expect(created, GalleryTemplate.kanban);

    await tester.tap(find.byKey(const ValueKey('gallery-board')));
    await tester.pump();
    expect(created, GalleryTemplate.board);
  });
}
