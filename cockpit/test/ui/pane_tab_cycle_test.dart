import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/pane_tab_cycle.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_session_view.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../support/attachment_terminal_gateway.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

Widget _host(Widget child) => ModularApp(
  module: createModule(register: (_) {}),
  provide: (scope) => scope
    ..addChangeNotifier<SettingsController>(
      () => SettingsController(_Settings()),
    ),
  child: ShadcnApp(
    builder: (context, child) {
      final tokens = buildTokens(
        brightness: Brightness.dark,
        settings: const AppSettings(),
      );
      return CockpitTheme(
        colors: tokens.colors,
        typo: tokens.typo,
        syntax: tokens.syntax,
        terminal: tokens.terminal,
        child: TranslationProvider(child: ghost.TerminalScope(child: child!)),
      );
    },
    home: child,
  ),
);

Future<void> _ctrlTab(WidgetTester tester, {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  for (final engine in TerminalEngine.values) {
    (TerminalSession, AttachmentTerminalGateway) terminal() {
      final gateway = AttachmentTerminalGateway();
      final session = TerminalSession(
        id: 'term-${engine.name}',
        projectId: 'p',
        workingDirectory: '/tmp',
        gateway: gateway,
        profile: const TerminalProfile(
          id: 'shell',
          label: 'Shell',
          executable: 'sh',
        ),
        engine: engine,
      );
      return (session, gateway);
    }

    testWidgets(
      '${engine.name}: Ctrl-Tab in a pane terminal cycles the pane once and never reaches the PTY',
      (tester) async {
        final cycles = <int>[];
        final (session, gateway) = terminal();
        await tester.pumpWidget(
          _host(
            PaneTabCycleScope(
              onCycle: cycles.add,
              child: TerminalSessionView(
                session: session,
                active: true,
                focused: true,
                focusRevision: 0,
                onFocus: () {},
                onOpenFile: (_, {line}) {},
                ownerShortcuts: paneTabCycleShortcuts(cycles.add),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await _ctrlTab(tester);
        await _ctrlTab(tester, shift: true);
        expect(cycles, [1, -1]);
        expect(gateway.text, isEmpty, reason: 'no CSI 27;5;9~ leak');

        // Control: the terminal does have the keyboard.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(gateway.text, '\r');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      '${engine.name}: a terminal with its own Ctrl-Tab (.orc) keeps it; the pane does not cycle',
      (tester) async {
        final outer = <int>[];
        final inner = <int>[];
        final (session, gateway) = terminal();
        await tester.pumpWidget(
          _host(
            PaneTabCycleScope(
              onCycle: outer.add,
              child: TerminalSessionView(
                session: session,
                active: true,
                focused: true,
                focusRevision: 0,
                onFocus: () {},
                onOpenFile: (_, {line}) {},
                ownerShortcuts: paneTabCycleShortcuts(inner.add),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await _ctrlTab(tester);
        expect(inner, [1]);
        expect(outer, isEmpty);
        expect(gateway.text, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('Ctrl-Tab with focus in a non-terminal tab cycles the pane', (
    tester,
  ) async {
    final cycles = <int>[];
    await tester.pumpWidget(
      _host(
        PaneTabCycleScope(
          onCycle: cycles.add,
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await _ctrlTab(tester);
    await _ctrlTab(tester, shift: true);
    expect(cycles, [1, -1]);
  });

  testWidgets('Alt/Meta + Ctrl-Tab is not the cycle chord', (tester) async {
    final cycles = <int>[];
    await tester.pumpWidget(
      _host(
        PaneTabCycleScope(
          onCycle: cycles.add,
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _ctrlTab(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(cycles, isEmpty);
  });
}
