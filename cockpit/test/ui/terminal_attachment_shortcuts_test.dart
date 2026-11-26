import 'package:cockpit/app/cockpit/ui/widgets/adaptive_terminal_pane.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  for (final engine in TerminalEngine.values) {
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      testWidgets(
        '${engine.name} ${modifier.keyLabel}+V invokes shared paste exactly once',
        (tester) async {
          final terminal = createTerminalController(engine);
          final focus = FocusNode();
          var pasted = 0;
          final output = <int>[];
          terminal.onOutput = output.addAll;
          await tester.pumpWidget(
            ModularApp(
              module: createModule(register: (_) {}),
              provide: (scope) => scope
                ..addChangeNotifier<SettingsController>(
                  () => SettingsController(_Settings()),
                ),
              child: ShadcnApp(
                home: AdaptiveTerminalPane(
                  terminal: terminal,
                  active: true,
                  focusNode: focus,
                  theme: xterm.TerminalThemes.defaultTheme,
                  textStyle: const xterm.TerminalStyle(fontFamily: 'Ahem'),
                  onPaste: () => pasted++,
                ),
              ),
            ),
          );
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
          await tester.sendKeyUpEvent(modifier);
          await tester.pump();
          expect(pasted, 1);
          expect(output, isEmpty);
          await tester.pumpWidget(const SizedBox());
          focus.dispose();
          terminal.dispose();
        },
      );
    }
  }
}
