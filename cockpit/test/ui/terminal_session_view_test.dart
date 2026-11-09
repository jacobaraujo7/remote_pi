import 'dart:io' show Platform;
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_find_bar.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/orchestration_multiplexer.dart';
import 'package:cockpit/app/cockpit/ui/widgets/adaptive_terminal_pane.dart';
import 'package:cockpit/app/cockpit/ui/widgets/stable_pane_host.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_session_view.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flterm/flterm.dart' as ghost;
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

class _Gateway extends AttachmentTerminalGateway {
  final sizes = <(int, int)>[];
  @override
  void resize(int rows, int columns) => sizes.add((rows, columns));
}

void main() {
  for (final engine in TerminalEngine.values) {
    testWidgets(
      '${engine.name}: shared renderer keeps sessions and find shortcuts across inner tab/split changes',
      (tester) async {
        final mux = OrchestrationMultiplexer<TerminalSession>(
          instanceId: 'doc',
          projectId: 'worktree',
        );
        final gateways = {
          for (final id in ['one', 'two']) id: _Gateway(),
        };
        final sessions = {
          for (final id in gateways.keys)
            id: TerminalSession(
              id: id,
              owner: mux.owner,
              projectId: 'worktree',
              workingDirectory: '/worktree',
              gateway: gateways[id]!,
              profile: const TerminalProfile(
                id: 'shell',
                label: 'Shell',
                executable: 'sh',
              ),
              engine: engine,
            ),
        };
        mux.attach(sessions['one']!);
        mux.attach(sessions['two']!);
        mux.setActive(true);
        mux.reveal('one');
        final overviewHeight = ValueNotifier(100.0);
        await tester.pumpWidget(
          ModularApp(
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
                  child: TranslationProvider(
                    child: ghost.TerminalScope(child: child!),
                  ),
                );
              },
              home: ValueListenableBuilder<double>(
                valueListenable: overviewHeight,
                builder: (_, height, _) => Column(
                  children: [
                    SizedBox(
                      height: height,
                      child: const Text('Boxes / Graph'),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: mux,
                        builder: (_, _) => mux.tree == null
                            ? const SizedBox()
                            : StablePaneHost(
                                active: mux.active,
                                tree: mux.tree!,
                                onResize: mux.resize,
                                paneBuilder: (_, _) => const SizedBox(),
                                tabBodyBuilder: (pane, id, visible) =>
                                    TerminalSessionView(
                                      key: ValueKey('owned-$id'),
                                      session: mux.session(id)!,
                                      active: visible,
                                      focused:
                                          visible && mux.keyboardTabId == id,
                                      focusRevision: mux.focusRevision,
                                      onFocus: () => mux.reveal(id),
                                      onOpenFile: (_, {line}) {},
                                    ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final firstState = tester.state(
          find.byKey(const ValueKey('owned-one'), skipOffstage: false),
        );
        final secondState = tester.state(
          find.byKey(const ValueKey('owned-two'), skipOffstage: false),
        );
        sessions['one']!.terminal.write('retained history\r\n');
        await tester.pump();
        await tester.pump();
        final focusedPane = tester.widget<AdaptiveTerminalPane>(
          find.descendant(
            of: find.byKey(const ValueKey('owned-one')),
            matching: find.byType(AdaptiveTerminalPane),
          ),
        );
        expect(focusedPane.focusNode.hasFocus, isTrue);
        final inputBeforeFind = List<int>.of(gateways['one']!.bytes);
        final modifier = Platform.isMacOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(find.byType(TerminalFindBar), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(TerminalFindBar), findsNothing);
        expect(gateways['one']!.bytes, inputBeforeFind);
        if (Platform.isMacOS) {
          // Cmd-F is app find; Ctrl-F remains readline's forward-char.
          final beforeReadline = gateways['one']!.bytes.length;
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(find.byType(TerminalFindBar), findsNothing);
          expect(gateways['one']!.bytes.skip(beforeReadline), contains(0x06));
        }
        mux.reveal('two', focus: false);
        await tester.pump();
        final secondPane = tester.widget<AdaptiveTerminalPane>(
          find.descendant(
            of: find.byKey(const ValueKey('owned-two')),
            matching: find.byType(AdaptiveTerminalPane),
          ),
        );
        expect(secondPane.focusNode.hasFocus, isFalse);
        final hiddenResizes = gateways['one']!.sizes.length;
        for (var i = 0; i < 8; i++) {
          overviewHeight.value = 120 + i * 5;
          await tester.pump();
        }
        expect(gateways['one']!.sizes.length, hiddenResizes);
        expect(
          tester.state(
            find.byKey(const ValueKey('owned-one'), skipOffstage: false),
          ),
          same(firstState),
        );
        expect(
          tester.state(
            find.byKey(const ValueKey('owned-two'), skipOffstage: false),
          ),
          same(secondState),
        );
        expect(
          sessions['one']!.terminal.plainLines().join(' '),
          contains('retained history'),
        );
        final left = mux.paneOf('one')!.id;
        // Build a second pane by attaching a new owned shell, then move an
        // existing terminal across the internal split without reparenting it.
        final third = TerminalSession(
          id: 'three',
          owner: mux.owner,
          projectId: 'worktree',
          workingDirectory: '/worktree',
          gateway: _Gateway(),
          profile: const TerminalProfile(
            id: 'shell',
            label: 'Shell',
            executable: 'sh',
          ),
          engine: engine,
        );
        mux.attach(third, split: SplitDir.vertical);
        await tester.pump();
        final right = mux.paneOf('three')!.id;
        mux.move('one', right);
        await tester.pump();
        expect(mux.paneOf('two')!.id, left);
        expect(
          tester.state(
            find.byKey(const ValueKey('owned-one'), skipOffstage: false),
          ),
          same(firstState),
        );
        mux.detach('one');
        await tester.pump();
        await tester.runAsync(() => sessions['one']!.dispose());
        expect(
          tester.state(
            find.byKey(const ValueKey('owned-two'), skipOffstage: false),
          ),
          same(secondState),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        mux.dispose();
        await tester.runAsync(() async {
          await sessions['two']!.dispose();
          await third.dispose();
        });
        overviewHeight.dispose();
      },
    );
  }
}
