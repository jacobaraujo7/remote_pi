import 'dart:async';
import 'package:cockpit/app/cockpit/ui/document/open_files_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'boot arguments, macOS pull and live Finder events share the owned router',
    () async {
      const channel = MethodChannel('cockpit/open_files');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            call.method == 'pull' ? ['/work/pulled.orchestration'] : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      OpenFilesChannel.pendingFromArguments = ['/work/argument.orc'];
      await OpenFilesChannel.bind();
      expect(OpenFilesChannel.pendingFromArguments, isEmpty);
      final paths = <String>[];
      final arrived = Completer<void>();
      final detach = OpenFilesChannel.attachOrchestration((path) async {
        paths.add(path);
        if (paths.length == 3) arrived.complete();
      });
      addTearDown(detach);
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        'cockpit/open_files',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('open', ['/work/live.ORC']),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      await arrived.future.timeout(const Duration(seconds: 2));
      expect(paths, [
        '/work/argument.orc',
        '/work/pulled.orchestration',
        '/work/live.ORC',
      ]);
    },
  );
}
