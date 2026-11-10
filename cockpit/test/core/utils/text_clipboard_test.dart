import 'dart:async';

import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(await service.write('hello', operation: 'test'), isTrue);
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
    expect(await service.write('hello', operation: 'test'), isTrue);
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
    expect(await service.write('private text', operation: 'test'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 3);
    expect(failures, 1);
    broken = false;
    expect(await service.write('next', operation: 'test'), isTrue);
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
      expect(await service.write('secret', operation: 'test'), isFalse);
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
      expect(await old, isFalse);
      expect(await latest, isTrue);
      expect(writes, ['old', 'new']);
      expect(failures, 0);
      await sub.cancel();
    },
  );

  test(
    'in-flight write is serialized before newer write and reports no stale success',
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
      expect(await old, isFalse);
      expect(await latest, isTrue);
      expect(writes, ['old', 'new']);
    },
  );
}
