import 'package:cockpit/app/cockpit/ui/widgets/stable_pane_host.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _LeaseProbe extends StatefulWidget {
  const _LeaseProbe({
    super.key,
    required this.onMount,
    required this.onDispose,
  });
  final VoidCallback onMount;
  final VoidCallback onDispose;
  @override
  State<_LeaseProbe> createState() => _LeaseProbeState();
}

class _LeaseProbeState extends State<_LeaseProbe> {
  final controller = TextEditingController(text: 'session-history');
  final focus = FocusNode(canRequestFocus: false);
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: EditableText(
      controller: controller,
      focusNode: focus,
      style: const TextStyle(),
      cursorColor: const Color(0xFFFFFFFF),
      backgroundCursorColor: const Color(0xFF000000),
    ),
  );
}

void main() {
  const a = LeafPane(id: 'a', tabs: ['t1', 't2'], active: 't1');
  const b = LeafPane(id: 'b', tabs: ['t3'], active: 't3');
  const tree = SplitPane(
    id: 'split',
    dir: SplitDir.vertical,
    a: a,
    b: b,
    frac: .4,
  );

  test('projection keeps saved split geometry', () {
    final rects = paneRectangles(tree, const Size(1000, 600));
    expect(rects['a'], const Rect.fromLTWH(0, 0, 400, 600));
    expect(rects['b'], const Rect.fromLTWH(400, 0, 600, 600));
    expect(tree.frac, .4);
  });

  testWidgets(
    'repeated previews preserve one mounted lease and history per pane',
    (tester) async {
      var mounts = 0;
      var disposals = 0;
      final keys = {
        'a': GlobalKey<_LeaseProbeState>(),
        'b': GlobalKey<_LeaseProbeState>(),
      };
      Future<void> show({
        bool preview = false,
        String? selected,
        PaneNode layout = tree,
      }) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.expand(
              child: StablePaneHost(
                tree: layout,
                preview: preview,
                previewPaneId: selected,
                onResize: (_, _) {},
                paneBuilder: (pane, visible) => _LeaseProbe(
                  key: keys[pane.id],
                  onMount: () => mounts++,
                  onDispose: () => disposals++,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await show();
      final initial = keys.map(
        (key, value) => MapEntry(key, value.currentState),
      );
      for (var i = 0; i < 20; i++) {
        await show(preview: true, selected: i.isEven ? 'a' : 'b');
        for (final entry in keys.entries) {
          expect(entry.value.currentState, same(initial[entry.key]));
          expect(entry.value.currentState!.controller.text, 'session-history');
          final size = tester.getSize(
            find.byKey(entry.value, skipOffstage: false),
          );
          expect(size.width, greaterThan(0));
          expect(size.height, greaterThan(0));
        }
        await show(layout: tree.copyWith(frac: .55));
      }
      await show();
      expect(mounts, 2);
      expect(disposals, 0);
      expect(tree.frac, .4);
    },
  );
}
