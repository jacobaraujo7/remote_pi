import 'package:cockpit/app/cockpit/ui/widgets/stable_tab_stack.dart';
import 'dart:convert';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/stable_pane_host.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_pane.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final engine in TerminalEngine.values) {
    testWidgets(
      '${engine.name}: closing selected tab and pane retains native siblings',
      (tester) async {
        final controllers = {
          for (final id in ['first', 'second', 'other'])
            id: createTerminalController(engine),
        };
        final focus = {for (final id in controllers.keys) id: FocusNode()};
        var tabs = ['first', 'second'];
        var selected = 'first';
        var preview = true;
        var rightOnly = false;
        Widget terminal(String id, bool visible) {
          final controller = controllers[id]!;
          if (controller is GhosttyTerminalController) {
            return ghost.TerminalView(
              key: GlobalObjectKey(controller.controller),
              controller: controller.controller,
              scrollController: controller.scrollController,
              focusNode: focus[id],
              presentationActive: visible,
              showKeyboard: false,
            );
          }
          return TerminalPane(
            key: ValueKey('native-$id'),
            terminal: (controller as XtermTerminalController).terminal,
            active: visible,
            focusNode: focus[id]!,
            textStyle: const xterm.TerminalStyle(),
            theme: xterm.TerminalThemes.defaultTheme,
            onKeyEvent: (_) => KeyEventResult.ignored,
          );
        }

        Future<void> show() async {
          final left = LeafPane(id: 'left', tabs: tabs, active: selected);
          const right = LeafPane(id: 'right', tabs: ['other'], active: 'other');
          final tree = rightOnly
              ? right
              : SplitPane(
                  id: 'split',
                  dir: SplitDir.vertical,
                  frac: .5,
                  a: left,
                  b: right,
                );
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(size: Size(900, 500)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: ghost.TerminalScope(
                  child: StablePaneHost(
                    tree: tree,
                    preview: preview,
                    previewPaneId: rightOnly ? 'right' : 'left',
                    onResize: (_, _) {},
                    paneBuilder: (pane, visible) => StableTabStack(
                      index: pane.tabs.indexOf(pane.active),
                      children: [
                        for (final id in pane.tabs)
                          KeyedSubtree(
                            key: ValueKey('body-$id'),
                            child: terminal(id, visible && id == pane.active),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        }

        await show();
        final second = tester.state(
          find
              .byType(
                engine == TerminalEngine.ghostty
                    ? ghost.TerminalView
                    : TerminalPane,
                skipOffstage: false,
              )
              .at(1),
        );
        tabs = ['second'];
        selected = 'second';
        await show();
        expect(tester.takeException(), isNull);
        expect(
          tester.state(
            find
                .byType(
                  engine == TerminalEngine.ghostty
                      ? ghost.TerminalView
                      : TerminalPane,
                  skipOffstage: false,
                )
                .first,
          ),
          same(second),
        );
        controllers['first']!.dispose();
        controllers['second']!.write('remaining-tab-alive\r\n');
        preview = false;
        await show();
        rightOnly = true;
        await show();
        controllers['second']!.dispose();
        controllers['other']!.write('remaining-pane-alive\r\n');
        expect(
          controllers['other']!.plainLines().join('\n'),
          contains('remaining-pane-alive'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        controllers['other']!.dispose();
        for (final node in focus.values) {
          node.dispose();
        }
      },
    );
    testWidgets(
      '${engine.name}: native views survive terminal/box/graph projection',
      (tester) async {
        final controllers = {
          'left': createTerminalController(engine),
          'right': createTerminalController(engine),
        };
        final focus = {'left': FocusNode(), 'right': FocusNode()};
        final outputs = {'left': <int>[], 'right': <int>[]};
        for (final entry in controllers.entries) {
          entry.value.onOutput = outputs[entry.key]!.addAll;
          entry.value.write('${entry.key}-history\r\n');
        }
        addTearDown(() {
          for (final c in controllers.values) {
            c.dispose();
          }
          for (final f in focus.values) {
            f.dispose();
          }
        });
        const tree = SplitPane(
          id: 'split',
          dir: SplitDir.vertical,
          frac: .4,
          a: LeafPane(id: 'left', tabs: ['l'], active: 'l'),
          b: LeafPane(id: 'right', tabs: ['r'], active: 'r'),
        );
        Future<void> show({bool preview = false, String? selected}) async {
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(size: Size(900, 500)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: ghost.TerminalScope(
                  child: StablePaneHost(
                    tree: tree,
                    preview: preview,
                    previewPaneId: selected,
                    onResize: (_, _) {},
                    paneBuilder: (pane, visible) {
                      final controller = controllers[pane.id]!;
                      if (controller is GhosttyTerminalController) {
                        return ghost.TerminalView(
                          key: ValueKey('view-${pane.id}'),
                          controller: controller.controller,
                          scrollController: controller.scrollController,
                          presentationActive: visible,
                          focusNode: focus[pane.id],
                          showKeyboard: false,
                        );
                      }
                      return TerminalPane(
                        key: ValueKey('view-${pane.id}'),
                        terminal:
                            (controller as XtermTerminalController).terminal,
                        active: visible,
                        focusNode: focus[pane.id]!,
                        textStyle: const xterm.TerminalStyle(),
                        theme: xterm.TerminalThemes.defaultTheme,
                        onKeyEvent: (_) => KeyEventResult.ignored,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        }

        await show();
        final states = {
          for (final id in controllers.keys)
            id: tester.state(
              find.byKey(ValueKey('view-$id'), skipOffstage: false),
            ),
        };
        for (var i = 0; i < 12; i++) {
          await show(preview: true, selected: i.isEven ? 'left' : 'right');
          controllers['left']!.write('background-$i\r\n');
          for (final id in controllers.keys) {
            expect(
              tester.state(
                find.byKey(ValueKey('view-$id'), skipOffstage: false),
              ),
              same(states[id]),
            );
          }
          await show();
          expect(tester.takeException(), isNull);
        }
        controllers['right']!.paste('right-only');
        expect(utf8.decode(outputs['right']!), contains('right-only'));
        expect(utf8.decode(outputs['left']!), isNot(contains('right-only')));
        expect(
          controllers['left']!.plainLines().join('\n'),
          contains('background-11'),
        );
        expect(
          controllers['right']!.plainLines().join('\n'),
          contains('right-history'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
