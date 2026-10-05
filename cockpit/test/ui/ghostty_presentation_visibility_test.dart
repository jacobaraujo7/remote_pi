// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';

import 'package:flterm/flterm.dart' as ghost;
import 'package:flterm/src/controller/terminal_controller.dart'
    show ViewAttachment;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hidden frame source coalesces output into one full refresh', () {
    final controller = ghost.TerminalController();
    final attachment = ViewAttachment(controller);
    addTearDown(() {
      attachment.dispose();
      controller.dispose();
    });
    var invalidations = 0;
    attachment.frameChanges.addListener(() => invalidations++);

    attachment.setPresentationActive(active: false);
    for (var i = 0; i < 100; i++) {
      controller.write(Uint8List.fromList(utf8.encode('line $i\r\n')));
    }
    expect(invalidations, 0);
    expect(controller.scrollbackRows, greaterThan(0));

    attachment.setPresentationActive(active: true);
    expect(invalidations, 1);

    controller.write(Uint8List.fromList(utf8.encode('visible')));
    expect(invalidations, 2);
  });

  testWidgets('hidden Ghostty view keeps its attachment and catches up', (
    tester,
  ) async {
    final controller = ghost.TerminalController();
    final focus = FocusNode();
    final scroll = ghost.TerminalScrollController();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);

    Widget view(bool active) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 800,
        height: 160,
        child: Offstage(
          offstage: !active,
          child: ghost.TerminalView(
            controller: controller,
            presentationActive: active,
            focusNode: focus,
            scrollController: scroll,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(true));
    await tester.pump();
    final mountedState = tester.state(
      find.byType(ghost.TerminalView, skipOffstage: false),
    );
    await tester.pumpWidget(view(false));
    for (var i = 0; i < 100; i++) {
      controller.write(Uint8List.fromList(utf8.encode('line $i\r\n')));
    }
    await tester.pump();
    expect(controller.scrollbackRows, greaterThan(0));
    expect(
      tester.state(find.byType(ghost.TerminalView, skipOffstage: false)),
      same(mountedState),
    );

    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(ghost.TerminalView)), same(mountedState));
    expect(scroll.hasClients, isTrue);
    expect(scroll.position.maxScrollExtent, greaterThan(0));

    controller.selectAll();
    expect(controller.selectedText(), contains('line 99'));
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pumpWidget(view(false));
    for (var i = 100; i < 120; i++) {
      controller.write(Uint8List.fromList(utf8.encode('line $i\r\n')));
    }
    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(scroll.position.pixels, 0);
    expect(controller.selectedText(), contains('line 99'));

    await tester.pumpWidget(view(false));
    controller.write(Uint8List.fromList(utf8.encode('\x1b[?1049hALT')));
    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(controller.activeScreen, ghost.TerminalScreen.alternate);
    controller.write(Uint8List.fromList(utf8.encode('\x1b[?1049l')));
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('split Ghostty views retain independent controller leases', (
    tester,
  ) async {
    final first = ghost.TerminalController();
    final second = ghost.TerminalController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget split(bool firstActive) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 800,
        height: 320,
        child: Column(
          children: [
            for (final (index, controller) in [first, second].indexed)
              Expanded(
                child: Offstage(
                  offstage: (index == 0) != firstActive,
                  child: ghost.TerminalView(
                    key: ValueKey(index),
                    controller: controller,
                    presentationActive: (index == 0) == firstActive,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(split(true));
    await tester.pumpWidget(split(false));
    first.write(Uint8List.fromList(utf8.encode('hidden first\r\n')));
    await tester.pumpWidget(split(true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(ghost.TerminalView, skipOffstage: false),
      findsNWidgets(2),
    );
  });
}
