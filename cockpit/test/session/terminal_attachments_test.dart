import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:cockpit/app/cockpit/data/terminal/local_terminal_attachments.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_attachments.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_attachment_service.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/terminal_attachments_fakes.dart';
import '../support/attachment_terminal_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sh = TerminalProfile(
    id: 'login-shell',
    label: 'sh',
    executable: '/bin/sh',
  );
  for (final engine in TerminalEngine.values) {
    test(
      'partial batch failure keeps both successful files in ${engine.name}',
      () async {
        // macOS: systemTemp fica em /var, symlink de /private/var; a store
        // resolve o root, entao o teste precisa comparar o caminho resolvido.
        final root = Directory(
          await (await Directory.systemTemp.createTemp(
            'cockpit-partial-',
          )).resolveSymbolicLinks(),
        );
        final first = File(p.join(root.path, 'first.txt'));
        final missing = File(p.join(root.path, 'removed.txt'));
        final last = File(p.join(root.path, 'last.txt'));
        await first.writeAsString('first content');
        await missing.writeAsString('removed after selection');
        await last.writeAsString('last content');
        final selected = [first.path, missing.path, last.path];
        await missing.delete();
        final clipboard = FakeClipboard();
        final gateway = AttachmentTerminalGateway();
        final session = TerminalSession(
          id: 'batch',
          projectId: 'p',
          workingDirectory: root.path,
          attachmentProjectRoot: root.path,
          gateway: gateway,
          profile: sh,
          engine: engine,
          attachmentService: TerminalAttachmentService(
            clipboard,
            const LocalTerminalAttachmentStore(),
            FakePathConverter(),
          ),
        );
        try {
          await session.importDroppedPaths(selected);
          expect(
            session.attachmentFeedback?.notice,
            TerminalAttachmentNotice.failed,
          );
          expect(session.attachmentFeedback?.detail, contains(missing.path));
          final saved =
              await Directory(p.join(root.path, '.cockpit', 'attachments'))
                  .list(recursive: true)
                  .where((entry) => entry is File)
                  .cast<File>()
                  .toList();
          expect(saved, hasLength(2));
          final firstCopy = saved.singleWhere(
            (f) => p.basename(f.path) == 'first.txt',
          );
          final lastCopy = saved.singleWhere(
            (f) => p.basename(f.path) == 'last.txt',
          );
          expect(await firstCopy.readAsString(), 'first content');
          expect(await lastCopy.readAsString(), 'last content');
          expect(gateway.text, "'${firstCopy.path}' '${lastCopy.path}' ");
          expect(gateway.text, isNot(contains('removed.txt')));
          clipboard.content = const TerminalClipboardContent(
            text: 'next paste',
          );
          await session.pasteFromClipboard();
          expect(gateway.text, endsWith('next paste'));
        } finally {
          await session.dispose();
          await root.delete(recursive: true);
        }
      },
    );
    test(
      '20 rapid image pastes preserve snapshots and order in ${engine.name}',
      () async {
        final clipboard = FakeClipboard();
        final store = FakeAttachmentStore();
        final started = Completer<void>();
        final release = Completer<void>();
        final received = <int>[];
        store.beforeComplete = () async {
          final value = store.receivedImage!.single;
          received.add(value);
          if (!started.isCompleted) started.complete();
          await release.future;
          store.result = TerminalImportResult([
            '/project/.cockpit/attachments/$value/clipboard.png',
          ], []);
        };
        final gateway = AttachmentTerminalGateway();
        final session = TerminalSession(
          id: 'rapid',
          projectId: 'p',
          workingDirectory: '/project',
          attachmentProjectRoot: '/project',
          gateway: gateway,
          profile: sh,
          engine: engine,
          attachmentService: TerminalAttachmentService(
            clipboard,
            store,
            FakePathConverter(),
          ),
        );
        try {
          final pending = <Future<void>>[];
          for (var i = 0; i < 20; i++) {
            clipboard.content = TerminalClipboardContent(
              image: Uint8List.fromList([i]),
            );
            pending.add(session.pasteFromClipboard());
          }
          clipboard.content = const TerminalClipboardContent(
            text: 'changed afterwards',
          );
          await started.future;
          expect(store.calls, 1);
          release.complete();
          await Future.wait(pending);
          expect(received, List.generate(20, (i) => i));
          expect(store.calls, 20);
          expect(
            gateway.text,
            List.generate(
              20,
              (i) => "'/project/.cockpit/attachments/$i/clipboard.png' ",
            ).join(),
          );
          expect(gateway.text, isNot(contains('\r')));
          expect(gateway.text, isNot(contains('\n')));
        } finally {
          if (!release.isCompleted) release.complete();
          await session.dispose();
        }
      },
    );
    test(
      'pathless workspace persists screenshot and dropped files in spawn directory in ${engine.name}',
      () async {
        final root = Directory(
          await (await Directory.systemTemp.createTemp(
            'cockpit-pathless-',
          )).resolveSymbolicLinks(),
        );
        final source = File(p.join(root.path, 'source.png'));
        final pixels = Uint8List.fromList([137, 80, 78, 71]);
        await source.writeAsBytes(pixels);
        final clipboard = FakeClipboard()
          ..content = TerminalClipboardContent(image: pixels);
        final gateway = AttachmentTerminalGateway();
        final session = TerminalSession(
          id: 'system-terminal',
          projectId: '__cockpit__',
          workingDirectory: root.path,
          gateway: gateway,
          profile: sh,
          engine: engine,
          attachmentService: TerminalAttachmentService(
            clipboard,
            const LocalTerminalAttachmentStore(),
            FakePathConverter(),
          ),
        );
        try {
          await session.pasteFromClipboard();
          expect(
            session.attachmentFeedback?.notice,
            TerminalAttachmentNotice.referenced,
          );
          await session.importDroppedPaths([source.path]);
          expect(
            session.attachmentFeedback?.notice,
            TerminalAttachmentNotice.referenced,
          );
          final saved =
              await Directory(p.join(root.path, '.cockpit', 'attachments'))
                  .list(recursive: true)
                  .where((entry) => entry is File)
                  .cast<File>()
                  .toList();
          expect(saved, hasLength(2));
          expect(saved.map((f) => p.basename(f.path)).toSet(), {
            'clipboard.png',
            'source.png',
          });
          for (final file in saved) {
            expect(await file.readAsBytes(), pixels);
            expect(gateway.text, contains(file.path));
          }
          expect(gateway.text, isNot(contains('\r')));
          expect(gateway.text, isNot(contains('\n')));
        } finally {
          await session.dispose();
          await root.delete(recursive: true);
        }
      },
    );
    test(
      'clipboard and drop share pipeline and bracketed paste in ${engine.name}',
      () async {
        final clipboard = FakeClipboard();
        final store = FakeAttachmentStore();
        final gateway = AttachmentTerminalGateway();
        final session = TerminalSession(
          id: 't',
          projectId: 'p',
          workingDirectory: '/project',
          gateway: gateway,
          profile: sh,
          engine: engine,
          attachmentProjectRoot: '/project',
          attachmentService: TerminalAttachmentService(
            clipboard,
            store,
            FakePathConverter(),
          ),
        );
        session.terminal.write('\x1b[?2004h');
        clipboard.content = const TerminalClipboardContent(text: 'plain text');
        await session.pasteFromClipboard();
        expect(gateway.text, '\x1b[200~plain text\x1b[201~');
        gateway.bytes.clear();
        await session.importDroppedPaths(['/source/file']);
        expect(store.receivedPaths, ['/source/file']);
        expect(
          gateway.text,
          "\x1b[200~'/project/.cockpit/attachments/one/a.png' \x1b[201~",
        );
        expect(gateway.text, isNot(contains('\r')));
        await session.dispose();
      },
    );
    test(
      'closing ${engine.name} session during import prevents delivery',
      () async {
        final store = FakeAttachmentStore();
        final gate = Completer<void>();
        store.beforeComplete = () => gate.future;
        final gateway = AttachmentTerminalGateway();
        final session = TerminalSession(
          id: 't',
          projectId: 'p',
          workingDirectory: '/project',
          gateway: gateway,
          profile: sh,
          engine: engine,
          attachmentProjectRoot: '/project',
          attachmentService: TerminalAttachmentService(
            FakeClipboard(),
            store,
            FakePathConverter(),
          ),
        );
        final pending = session.importDroppedPaths(['/source/file']);
        await Future<void>.delayed(Duration.zero);
        expect(store.calls, 1);
        await session.dispose();
        gate.complete();
        await pending;
        expect(gateway.bytes, isEmpty);
      },
    );
  }
  test(
    'queued operations preserve gesture order and capture clipboard before copying',
    () async {
      final clipboard = FakeClipboard();
      final store = FakeAttachmentStore();
      final gate = Completer<void>();
      store.beforeComplete = () => gate.future;
      final gateway = AttachmentTerminalGateway();
      final session = TerminalSession(
        id: 't',
        projectId: 'p',
        workingDirectory: '/project',
        gateway: gateway,
        profile: sh,
        attachmentProjectRoot: '/project',
        attachmentService: TerminalAttachmentService(
          clipboard,
          store,
          FakePathConverter(),
        ),
      );
      final first = session.importDroppedPaths(['/source/file']);
      clipboard.content = const TerminalClipboardContent(text: 'captured');
      final second = session.pasteFromClipboard();
      clipboard.content = const TerminalClipboardContent(text: 'changed later');
      gate.complete();
      await Future.wait([first, second]);
      expect(
        gateway.text,
        "'/project/.cockpit/attachments/one/a.png' captured",
      );
      await session.dispose();
    },
  );
}
