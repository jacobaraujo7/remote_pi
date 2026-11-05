import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/settings/ui/neovim_settings_viewmodel.dart';
import 'package:cockpit/app/settings/ui/settings_page.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _SettingsStore implements SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

class _NeovimGateway implements NeovimGateway {
  @override
  Future<String?> executable({bool refresh = false}) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('new pattern keeps focus and empty extra row disappears', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);
    final settings = SettingsController(_SettingsStore());
    final neovim = NeovimSettingsViewModel(_NeovimGateway());
    await tester.pumpWidget(
      ModularApp(
        module: createModule(register: (_) {}),
        provide: (scope) => scope
          ..addChangeNotifier<SettingsController>(() => settings)
          ..addChangeNotifier<NeovimSettingsViewModel>(() => neovim),
        child: TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.light),
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Explorer'));
    await tester.pumpAndSettle();

    final initialFields = find.byType(TextField).evaluate().length;
    final parent = find.byType(TextField).at(initialFields - 2);
    await tester.ensureVisible(parent);
    await tester.pumpAndSettle();
    await tester.tap(parent);
    tester.testTextInput.enterText('n');
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(initialFields + 2));
    expect((tester.widget<TextField>(parent).focusNode?.hasFocus), isTrue);
    tester.testTextInput.enterText('new.ts');
    await tester.pump();
    expect(tester.widget<TextField>(parent).controller?.text, 'new.ts');
    expect((tester.widget<TextField>(parent).focusNode?.hasFocus), isTrue);

    tester.testTextInput.enterText('');
    tester.widget<TextField>(parent).focusNode?.unfocus();
    await tester.pump();
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(initialFields));
    expect(
      settings.settings.fileNestingPatterns.containsKey('new.ts'),
      isFalse,
    );
  });
}
