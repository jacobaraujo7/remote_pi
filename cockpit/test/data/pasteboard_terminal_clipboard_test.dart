import 'dart:io';
import 'package:cockpit/app/cockpit/data/terminal/pasteboard_terminal_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows clipboard channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const clipboard = PasteboardTerminalClipboard();
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PasteboardTerminalClipboard.channel, null),
    );
    test(
      'Windows snapshot preserves file/image/text representations and sequence',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              PasteboardTerminalClipboard.channel,
              (call) async => {
                'files': ['C:\\file.pdf'],
                'image': Uint8List.fromList([1]),
                'text': 'file',
                'sequence': 42,
              },
            );
        final content = await clipboard.read();
        expect(content.files, ['C:\\file.pdf']);
        expect(content.image, [1]);
        expect(content.text, 'file');
        expect(content.sequence, 42);
      },
    );
    test(
      'Windows image ownership check rejects clipboard sequence changes',
      () async {
        var sequence = 42;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              PasteboardTerminalClipboard.channel,
              (call) async => call.method == 'sequence'
                  ? sequence
                  : {
                      'image': Uint8List.fromList([1]),
                      'sequence': sequence,
                    },
            );
        final content = await clipboard.read();
        expect(await clipboard.stillContainsImage(content), isTrue);
        sequence++;
        expect(await clipboard.stillContainsImage(content), isFalse);
      },
    );
    test('native clipboard errors remain observable to the session', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PasteboardTerminalClipboard.channel,
            (call) async => throw PlatformException(
              code: 'clipboard_read_failed',
              message: 'busy',
            ),
          );
      await expectLater(clipboard.read(), throwsA(isA<PlatformException>()));
    });
  }, skip: !Platform.isWindows);
}
