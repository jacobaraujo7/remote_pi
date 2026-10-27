import 'dart:typed_data';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_attachments.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_attachment_service.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/terminal_attachments_fakes.dart';

const sh = TerminalProfile(
  id: 'login-shell',
  label: 'sh',
  executable: '/bin/sh',
);
const ps = TerminalProfile(
  id: 'powershell',
  label: 'ps',
  executable: 'powershell.exe',
);
const cmd = TerminalProfile(id: 'cmd', label: 'cmd', executable: 'cmd.exe');
const wsl = TerminalProfile(
  id: 'wsl:Ubuntu',
  label: 'Ubuntu',
  executable: 'wsl.exe',
);

void main() {
  late FakeClipboard clipboard;
  late FakeAttachmentStore store;
  late FakePathConverter converter;
  late TerminalAttachmentService service;
  late List<String> pasted;
  late List<List<int>> keys;
  late List<TerminalAttachmentFeedback> feedback;
  bool alive = true;
  setUp(() {
    clipboard = FakeClipboard();
    store = FakeAttachmentStore();
    converter = FakePathConverter();
    service = TerminalAttachmentService(clipboard, store, converter);
    pasted = [];
    keys = [];
    feedback = [];
    alive = true;
  });
  Future<void> deliver(
    TerminalClipboardContent content, {
    HarnessKind? harness,
    TerminalProfile profile = sh,
    bool remote = false,
    bool isWindows = false,
    bool nativeCurrent = true,
  }) => service.deliver(
    content: content,
    target: TerminalAttachmentTarget(
      projectRoot: '/project',
      profile: profile,
      harness: harness,
      remote: remote,
      isWindows: isWindows,
    ),
    isAlive: () => alive,
    paste: pasted.add,
    sendKeys: keys.add,
    feedback: feedback.add,
    nativeTargetIsCurrent: () => nativeCurrent,
  );

  test(
    'text is passed verbatim without importing or sending control keys',
    () async {
      await deliver(const TerminalClipboardContent(text: 'hello\nworld'));
      expect(pasted, ['hello\nworld']);
      expect(store.calls, 0);
      expect(keys, isEmpty);
    },
  );
  test('empty clipboard never sends Ctrl+V', () async {
    await deliver(const TerminalClipboardContent());
    expect(pasted, isEmpty);
    expect(keys, isEmpty);
    expect(store.calls, 0);
  });
  test('copied files take precedence over both bitmap and text', () async {
    await deliver(
      TerminalClipboardContent(
        files: ['/original/a.png'],
        image: Uint8List.fromList([1]),
        text: 'not this',
      ),
    );
    expect(store.receivedPaths, ['/original/a.png']);
    expect(store.receivedImage, isNull);
    expect(pasted.single, contains('/project/.cockpit/attachments/'));
    expect(keys, isEmpty);
  });
  for (final harness in HarnessKind.values) {
    test('clipboard image policy for ${harness.name}', () async {
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1, 2])),
        harness: harness,
      );
      expect(store.receivedImage, [1, 2]);
      switch (harness) {
        case HarnessKind.claudeCode || HarnessKind.codex || HarnessKind.pi:
          expect(keys, [
            [0x16],
          ]);
          expect(pasted, isEmpty);
        case HarnessKind.gitHubCopilot:
          expect(keys, [
            [0x1b, 0x76],
          ]);
          expect(pasted, isEmpty);
        default:
          expect(keys, isEmpty);
          expect(pasted.single, contains('a.png'));
      }
    });
    test(
      'dropped image never modifies clipboard or emits native shortcut: ${harness.name}',
      () async {
        await deliver(
          const TerminalClipboardContent(files: ['/original/a.png']),
          harness: harness,
        );
        expect(keys, isEmpty);
        expect(pasted.single, contains('a.png'));
      },
    );
  }
  test(
    'Windows Claude image paste uses Alt+V, not the text paste shortcut',
    () async {
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1, 2])),
        harness: HarnessKind.claudeCode,
        profile: ps,
        isWindows: true,
      );
      expect(keys, [
        [0x1b, 0x76],
      ]);
      expect(pasted, isEmpty);
      expect(feedback.last.notice, TerminalAttachmentNotice.nativeImage);
    },
  );
  for (final harness in [HarnessKind.codex, HarnessKind.pi]) {
    test(
      'Windows ${harness.name} preserves its Ctrl+V image shortcut',
      () async {
        await deliver(
          TerminalClipboardContent(image: Uint8List.fromList([1, 2])),
          harness: harness,
          profile: ps,
          isWindows: true,
        );
        expect(keys, [
          [0x16],
        ]);
        expect(pasted, isEmpty);
      },
    );
  }
  test('clipboard changed while saving: use saved image reference', () async {
    clipboard.unchanged = false;
    await deliver(
      TerminalClipboardContent(image: Uint8List.fromList([1])),
      harness: HarnessKind.codex,
    );
    expect(keys, isEmpty);
    expect(pasted, hasLength(1));
  });
  test(
    'native clipboard failure still inserts successfully imported image',
    () async {
      clipboard.failCheck = true;
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1])),
        harness: HarnessKind.codex,
      );
      expect(keys, isEmpty);
      expect(pasted, hasLength(1));
      expect(feedback.last.notice, TerminalAttachmentNotice.referenced);
    },
  );
  test(
    'foreground harness changed while importing: never send its old shortcut',
    () async {
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1])),
        harness: HarnessKind.codex,
        nativeCurrent: false,
      );
      expect(keys, isEmpty);
      expect(pasted, hasLength(1));
    },
  );
  test('failed import cannot send image shortcut', () async {
    store.result = const TerminalImportResult([], ['disk full']);
    await deliver(
      TerminalClipboardContent(image: Uint8List.fromList([1])),
      harness: HarnessKind.pi,
    );
    expect(keys, isEmpty);
    expect(pasted, isEmpty);
    expect(feedback.last.detail, 'disk full');
  });
  test(
    'partial success inserts only successful paths in order and reports failure',
    () async {
      store.result = const TerminalImportResult(
        ['/one.pdf', '/two.txt'],
        ['missing'],
      );
      await deliver(
        const TerminalClipboardContent(
          files: ['/one.pdf', '/missing', '/two.txt'],
        ),
      );
      expect(pasted, ["'/one.pdf' '/two.txt' "]);
      expect(feedback.last.detail, 'missing');
    },
  );
  test(
    'remote text works while remote files/images are explicitly rejected',
    () async {
      await deliver(const TerminalClipboardContent(text: 'text'), remote: true);
      await deliver(
        const TerminalClipboardContent(
          files: ['/a.pdf'],
          text: 'must not leak',
        ),
        remote: true,
      );
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1])),
        remote: true,
      );
      expect(pasted, ['text']);
      expect(store.calls, 0);
      expect(keys, isEmpty);
      expect(feedback.last.notice, TerminalAttachmentNotice.remoteUnavailable);
    },
  );
  test(
    'disposed session receives neither paths, native keys nor feedback after copy',
    () async {
      store.beforeComplete = () async {
        alive = false;
      };
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1])),
        harness: HarnessKind.codex,
      );
      expect(pasted, isEmpty);
      expect(keys, isEmpty);
      expect(feedback, hasLength(1));
    },
  );
  test(
    'WSL converts and verifies paths for the target distribution, avoids clipboard-native paste',
    () async {
      await deliver(
        TerminalClipboardContent(image: Uint8List.fromList([1])),
        profile: wsl,
        harness: HarnessKind.codex,
      );
      expect(converter.calls.single.$2, 'Ubuntu');
      expect(pasted.single, "'/mnt/c/project/image.png' ");
      expect(keys, isEmpty);
    },
  );
  test(
    'WSL inaccessible path is reported without inserting a Windows path',
    () async {
      converter.fail = true;
      await deliver(
        const TerminalClipboardContent(files: ['/source/a.png']),
        profile: wsl,
      );
      expect(pasted, isEmpty);
      expect(feedback.last.detail, contains('inaccessible'));
    },
  );
  test('path quoting respects POSIX, PowerShell and CMD', () {
    expect(
      quoteTerminalPath("/a/b'c \u00e9.png", sh),
      "'/a/b'\\''c \u00e9.png'",
    );
    expect(quoteTerminalPath("C:\\a b\\it's.png", ps), "'C:\\a b\\it''s.png'");
    expect(quoteTerminalPath(r'C:\a b\x&y.png', cmd), '"C:\\a b\\x&y.png"');
  });
  test('terminal control characters are rejected for every shell', () {
    for (final profile in [sh, ps, cmd, wsl]) {
      for (final path in ['/a\nb', '/a\rb', '/a\x1bb']) {
        expect(() => quoteTerminalPath(path, profile), throwsFormatException);
      }
    }
  });
  test('CMD expansion cannot silently change the path', () {
    for (final path in [r'C:\%TEMP%\x', r'C:\a!b\x']) {
      expect(() => quoteTerminalPath(path, cmd), throwsFormatException);
    }
  });
}
