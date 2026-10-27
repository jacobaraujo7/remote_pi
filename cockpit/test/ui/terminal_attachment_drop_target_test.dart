import 'package:cockpit/app/cockpit/domain/services/terminal_attachment_service.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_attachment_drop_target.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../support/terminal_attachments_fakes.dart';
import '../support/attachment_terminal_gateway.dart';

void main() {
  testWidgets('native drop broadcast reaches only the visible workspace/tab', (
    tester,
  ) async {
    final stores = List.generate(3, (_) => FakeAttachmentStore());
    final sessions = List.generate(
      3,
      (i) => TerminalSession(
        id: 't$i',
        projectId: 'p',
        workingDirectory: '/p',
        gateway: AttachmentTerminalGateway(),
        profile: const TerminalProfile(
          id: 'login-shell',
          label: 'sh',
          executable: '/bin/sh',
        ),
        attachmentProjectRoot: '/p',
        attachmentService: TerminalAttachmentService(
          FakeClipboard(),
          stores[i],
          FakePathConverter(),
        ),
      ),
    );
    addTearDown(() async {
      for (final session in sessions) {
        await session.dispose();
      }
    });
    Widget target(int index) => TerminalAttachmentDropTarget(
      session: sessions[index],
      active: true,
      child: const ColoredBox(
        color: Color(0xff000000),
        child: SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          home: SizedBox(
            width: 600,
            height: 300,
            child: IndexedStack(
              index: 0,
              children: [
                IndexedStack(index: 0, children: [target(0), target(1)]),
                target(2),
              ],
            ),
          ),
        ),
      ),
    );
    final position = tester.getCenter(
      find.byType(TerminalAttachmentDropTarget).first,
    );
    final callbacks = tester
        .widgetList<DropTarget>(find.byType(DropTarget, skipOffstage: false))
        .toList();
    for (final callback in callbacks) {
      callback.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile('/source/file')],
          localPosition: position,
          globalPosition: position,
        ),
      );
    }
    await tester.pump();
    await tester.pump();
    expect(stores.map((s) => s.calls), [1, 0, 0]);
    expect(find.text('Local references inserted.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'split drop is delivered only under the pointer, inactive target rejects it',
    (tester) async {
      final stores = List.generate(2, (_) => FakeAttachmentStore());
      final sessions = List.generate(
        2,
        (i) => TerminalSession(
          id: 't$i',
          projectId: 'p',
          workingDirectory: '/p',
          gateway: AttachmentTerminalGateway(),
          profile: const TerminalProfile(
            id: 'login-shell',
            label: 'sh',
            executable: '/bin/sh',
          ),
          attachmentProjectRoot: '/p',
          attachmentService: TerminalAttachmentService(
            FakeClipboard(),
            stores[i],
            FakePathConverter(),
          ),
        ),
      );
      addTearDown(() async {
        for (final session in sessions) {
          await session.dispose();
        }
      });
      Widget target(int i, bool active) => Expanded(
        child: TerminalAttachmentDropTarget(
          session: sessions[i],
          active: active,
          child: const ColoredBox(
            color: Color(0xff000000),
            child: SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            home: Row(children: [target(0, true), target(1, false)]),
          ),
        ),
      );
      final callbacks = tester
          .widgetList<DropTarget>(find.byType(DropTarget))
          .toList();
      final position = tester.getCenter(
        find.byType(TerminalAttachmentDropTarget).last,
      );
      for (final callback in callbacks) {
        callback.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile('/source/file')],
            localPosition: position,
            globalPosition: position,
          ),
        );
      }
      await tester.pump();
      expect(stores.map((s) => s.calls), [0, 0]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
