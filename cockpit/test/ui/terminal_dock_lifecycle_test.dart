import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/adaptive_terminal_pane.dart';
import 'package:cockpit/app/cockpit/ui/widgets/stable_pane_host.dart';
import 'package:cockpit/app/cockpit/ui/widgets/pane_view.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Body extends StatefulWidget {
  const _Body({super.key, required this.terminal, required this.active});
  final CockpitTerminalController terminal;
  final bool active;
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final focus = FocusNode();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdaptiveTerminalPane(
    terminal: widget.terminal,
    active: widget.active,
    focusNode: focus,
    theme: xterm.TerminalThemes.defaultTheme,
    textStyle: const xterm.TerminalStyle(fontFamily: 'Ahem'),
  );
}

class _DockVm extends Fake implements CockpitViewModel {
  _DockVm(this.onMove);
  final VoidCallback onMove;
  String? target;
  String? focusedPane;
  @override
  void moveTabToPane(String source, String tabId, String targetPane) {
    expect(source, 'left');
    expect(tabId, 'terminal');
    target = targetPane;
    onMove();
  }

  @override
  void focus(String paneId) {
    focusedPane = paneId;
  }
}

void main() {
  for (final engine in TerminalEngine.values) {
    testWidgets(
      '${engine.name}: terminal moves into orchestration dock without reattachment',
      (tester) async {
        final terminal = createTerminalController(engine);
        terminal.write('kept session history\r\n');
        final moved = ValueNotifier(false);
        final vm = _DockVm(() => moved.value = true);
        Widget body(String id, bool active) => id == 'terminal'
            ? _Body(
                key: const ValueKey('terminal-body'),
                terminal: terminal,
                active: active,
              )
            : const ColoredBox(
                key: ValueKey('app-body'),
                color: Color(0xff151515),
              );
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
                  child: child!,
                );
              },
              home: ValueListenableBuilder<bool>(
                valueListenable: moved,
                builder: (_, value, _) {
                  final right = LeafPane(
                    id: 'right',
                    tabs: value
                        ? ['orchestration', 'terminal']
                        : ['orchestration'],
                    active: value ? 'terminal' : 'orchestration',
                  );
                  final tree = value
                      ? right
                      : SplitPane(
                          id: 'split',
                          dir: SplitDir.vertical,
                          frac: .5,
                          a: const LeafPane(
                            id: 'left',
                            tabs: ['terminal'],
                            active: 'terminal',
                          ),
                          b: right,
                        );
                  return StablePaneHost(
                    tree: tree,
                    onResize: (_, _) {},
                    paneBuilder: (pane, _) => PaneDropZone(
                      paneId: pane.id,
                      vm: vm,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 40,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: pane.id == 'left'
                                  ? const Draggable<TabDragData>(
                                      key: ValueKey('drag-terminal'),
                                      data: TabDragData(
                                        paneId: 'left',
                                        tabId: 'terminal',
                                      ),
                                      feedback: SizedBox(
                                        width: 180,
                                        height: 40,
                                      ),
                                      child: SizedBox(
                                        width: 180,
                                        height: 40,
                                        child: ColoredBox(
                                          color: Color(0xff333333),
                                        ),
                                      ),
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                          const Expanded(
                            child: ColoredBox(color: Color(0xff333333)),
                          ),
                        ],
                      ),
                    ),
                    tabBodyBuilder: (pane, id, visible) => PaneDropZone(
                      paneId: pane.id,
                      vm: vm,
                      stripHeight: 0,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) => vm.focus(pane.id),
                        child: body(id, visible),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        final original = tester.state(find.byType(_Body));
        final appElement = tester.element(
          find.byKey(const ValueKey('app-body')),
        );
        await tester.drag(
          find.byKey(const ValueKey('drag-terminal')),
          const Offset(560, 280),
        );
        await tester.pump();
        expect(vm.target, 'right');
        expect(tester.takeException(), isNull);
        expect(tester.state(find.byType(_Body)), same(original));

        for (var i = 0; i < 12; i++) {
          moved.value = !moved.value;
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.state(find.byType(_Body)), same(original));
        }
        expect(
          tester.element(
            find.byKey(const ValueKey('app-body'), skipOffstage: false),
          ),
          same(appElement),
        );
        await tester.tap(find.byType(_Body));
        await tester.pump(const Duration(milliseconds: 400));
        expect((original as _BodyState).focus.hasFocus, isTrue);
        expect(vm.focusedPane, 'right');
        expect(tester.takeException(), isNull);
        expect(
          terminal.plainLines().join('\n'),
          contains('kept session history'),
        );
        await tester.pumpWidget(const SizedBox());
        terminal.dispose();
        moved.dispose();
      },
    );
  }
}
