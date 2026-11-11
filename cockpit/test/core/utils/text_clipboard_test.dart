import 'dart:async';

import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasteboard/pasteboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'desktop Pasteboard and service write through the same platform channel',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      // pasteboard 0.4.0 uses one shared IO implementation for all desktop OSes.
      Pasteboard.writeText('package');
      expect(
        await TextClipboardService().write('service', operation: 'test'),
        TextClipboardResult.copied,
      );
      expect(calls.map((call) => call.method), [
        'Clipboard.setData',
        'Clipboard.setData',
      ]);
      expect(calls.map((call) => call.arguments), [
        {'text': 'package'},
        {'text': 'service'},
      ]);
    },
  );

  final busy = PlatformException(
    code: 'Clipboard error',
    message: 'Unable to open clipboard',
    details: 5,
  );

  test('successful text write returns true without delay', () async {
    final writes = <String>[];
    final service = TextClipboardService(
      writer: (text) async => writes.add(text),
      delay: (_) async => fail('unexpected delay'),
    );
    expect(
      await service.write('hello', operation: 'test'),
      TextClipboardResult.copied,
    );
    expect(writes, ['hello']);
  });

  test('transient opening failure retries at 50 and 150 ms', () async {
    var calls = 0;
    final delays = <Duration>[];
    final service = TextClipboardService(
      writer: (_) async {
        if (++calls < 3) throw busy;
      },
      delay: (d) async => delays.add(d),
    );
    expect(
      await service.write('hello', operation: 'test'),
      TextClipboardResult.copied,
    );
    expect(calls, 3);
    expect(delays, [
      const Duration(milliseconds: 50),
      const Duration(milliseconds: 150),
    ]);
  });

  test('exhaustion reports a single failure and queue recovers', () async {
    var broken = true;
    var calls = 0;
    var failures = 0;
    final service = TextClipboardService(
      writer: (_) async {
        calls++;
        if (broken) throw busy;
      },
      delay: (_) async {},
    );
    final subscription = service.failures.listen((_) => failures++);
    expect(
      await service.write('private text', operation: 'test'),
      TextClipboardResult.failed,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 3);
    expect(failures, 1);
    broken = false;
    expect(
      await service.write('next', operation: 'test'),
      TextClipboardResult.copied,
    );
    await subscription.cancel();
  });

  test('permanent platform and unexpected errors never retry', () async {
    for (final error in [
      PlatformException(code: 'permission', message: 'denied'),
      StateError('failure'),
    ]) {
      var calls = 0;
      final service = TextClipboardService(
        writer: (_) async {
          calls++;
          throw error;
        },
        delay: (_) async => fail('must not retry'),
      );
      expect(
        await service.write('secret', operation: 'test'),
        TextClipboardResult.failed,
      );
      expect(calls, 1);
    }
  });

  test(
    'new copy cancels old retry and never writes stale text afterward',
    () async {
      final sleeping = Completer<void>();
      final reachedWait = Completer<void>();
      final writes = <String>[];
      var failures = 0;
      final service = TextClipboardService(
        writer: (text) async {
          writes.add(text);
          if (text == 'old') throw busy;
        },
        delay: (_) {
          reachedWait.complete();
          return sleeping.future;
        },
      );
      final sub = service.failures.listen((_) => failures++);
      final old = service.write('old', operation: 'test');
      await reachedWait.future;
      final latest = service.write('new', operation: 'test');
      sleeping.complete();
      expect(await old, TextClipboardResult.superseded);
      expect(await latest, TextClipboardResult.copied);
      expect(writes, ['old', 'new']);
      expect(failures, 0);
      await sub.cancel();
    },
  );

  test(
    'completed in-flight write reports copied and newer text is written last',
    () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      final writes = <String>[];
      final service = TextClipboardService(
        writer: (text) async {
          writes.add(text);
          if (text == 'old') {
            started.complete();
            await pending.future;
          }
        },
      );
      final old = service.write('old', operation: 'test');
      await started.future;
      final latest = service.write('new', operation: 'test');
      expect(writes, ['old']);
      pending.complete();
      expect(await old, TextClipboardResult.copied);
      expect(await latest, TextClipboardResult.copied);
      expect(writes, ['old', 'new']);
    },
  );

  test(
    'queued request superseded before IO has its own explicit outcome',
    () async {
      final pending = Completer<void>();
      final writes = <String>[];
      final service = TextClipboardService(
        writer: (text) async {
          writes.add(text);
          if (text == 'first') await pending.future;
        },
      );
      final first = service.write('first', operation: 'test');
      final skipped = service.write('middle', operation: 'test');
      final latest = service.write('last', operation: 'test');
      pending.complete();
      expect(await first, TextClipboardResult.copied);
      expect(await skipped, TextClipboardResult.superseded);
      expect(await latest, TextClipboardResult.copied);
      expect(writes, ['first', 'last']);
    },
  );
}
