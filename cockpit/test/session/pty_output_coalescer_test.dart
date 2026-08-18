import 'dart:collection';

import 'package:cockpit/app/core/terminal/pty_output_scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _ManualFrames {
  final callbacks = ListQueue<VoidCallback>();

  void schedule(VoidCallback callback) => callbacks.addLast(callback);

  void run() => callbacks.removeFirst()();
}

PtyOutputScheduler _scheduler(
  _ManualFrames frames, {
  int maxCharsPerFrame = 8,
  int maxSliceChars = 4,
  Duration maxWorkPerFrame = const Duration(milliseconds: 4),
  int Function()? clockMicros,
}) => PtyOutputScheduler(
  maxCharsPerFrame: maxCharsPerFrame,
  maxSliceChars: maxSliceChars,
  maxWorkPerFrame: maxWorkPerFrame,
  scheduleFrame: frames.schedule,
  clockMicros: clockMicros ?? () => 0,
);

void main() {
  test('todas as fontes compartilham um único budget por frame', () {
    final frames = _ManualFrames();
    final scheduler = _scheduler(frames);
    final first = <String>[];
    final second = <String>[];

    final a = PtyOutputCoalescer(
      scheduler: scheduler,
      maxPendingChars: 32,
      onFlush: first.add,
      onAcknowledge: () {},
    );
    final b = PtyOutputCoalescer(
      scheduler: scheduler,
      maxPendingChars: 32,
      onFlush: second.add,
      onAcknowledge: () {},
    );

    a.add('aaaaaaaa');
    b.add('bbbbbbbb');

    // N fontes geram um único callback global, não N callbacks independentes.
    expect(frames.callbacks, hasLength(1));
    expect(scheduler.pendingChars, 16);

    frames.run();

    // Round-robin: cada fonte recebeu um slice; o total não passou de 8.
    expect(first, ['aaaa']);
    expect(second, ['bbbb']);
    expect(scheduler.pendingChars, 8);
    expect(frames.callbacks, hasLength(1));

    frames.run();
    expect(first.join(), 'aaaaaaaa');
    expect(second.join(), 'bbbbbbbb');
    expect(scheduler.pendingChars, 0);
    expect(frames.callbacks, isEmpty);

    a.dispose();
    b.dispose();
  });

  test('muitas fontes ruidosas avançam com fairness e budget global', () {
    final frames = _ManualFrames();
    final scheduler = _scheduler(
      frames,
      maxCharsPerFrame: 64,
      maxSliceChars: 4,
    );
    const sourceCount = 32;
    const payload = 'abcdefghijklmnop';
    var frame = 0;
    final workPerFrame = <int, int>{};
    final outputs = List.generate(sourceCount, (_) => StringBuffer());
    final sources = List.generate(
      sourceCount,
      (index) => PtyOutputCoalescer(
        scheduler: scheduler,
        onFlush: (slice) {
          outputs[index].write(slice);
          workPerFrame.update(
            frame,
            (value) => value + slice.length,
            ifAbsent: () => slice.length,
          );
        },
        onAcknowledge: () {},
      )..add(payload),
    );

    // 32 fontes x 16 chars = 512 chars. Com budget 64, devem terminar em 8
    // frames; round-robin garante que todas progridam antes de qualquer fonte
    // receber seu segundo slice.
    while (frames.callbacks.isNotEmpty) {
      frame++;
      frames.run();
      expect(workPerFrame[frame], lessThanOrEqualTo(64));
      if (frame == 2) {
        expect(outputs.every((buffer) => buffer.length == 4), isTrue);
      }
    }

    expect(frame, 8);
    expect(outputs.map((buffer) => buffer.toString()), everyElement(payload));
    expect(scheduler.pendingChars, 0);
    for (final source in sources) {
      source.dispose();
    }
  });

  test('cinco terminais concorrentes não monopolizam um frame', () {
    final frames = _ManualFrames();
    final scheduler = _scheduler(
      frames,
      maxCharsPerFrame: 20,
      maxSliceChars: 4,
    );
    final outputs = List.generate(5, (_) => StringBuffer());
    final workPerFrame = <int, int>{};
    var frame = 0;
    final sources = List.generate(
      outputs.length,
      (index) => PtyOutputCoalescer(
        scheduler: scheduler,
        onFlush: (slice) {
          outputs[index].write(slice);
          workPerFrame.update(
            frame,
            (value) => value + slice.length,
            ifAbsent: () => slice.length,
          );
        },
        onAcknowledge: () {},
      )..add('abcdefghijkl'),
    );

    while (frames.callbacks.isNotEmpty) {
      frame++;
      frames.run();
      expect(workPerFrame[frame], lessThanOrEqualTo(20));
      if (frame == 1) {
        expect(outputs.every((buffer) => buffer.length == 4), isTrue);
      }
    }

    expect(
      outputs.map((buffer) => buffer.toString()),
      everyElement('abcdefghijkl'),
    );
    expect(scheduler.pendingChars, 0);
    for (final source in sources) {
      source.dispose();
    }
  });

  test('budget de tempo adia fontes restantes sem perder dados', () {
    final frames = _ManualFrames();
    var now = 0;
    final scheduler = _scheduler(frames, clockMicros: () => now);
    final flushOrder = <String>[];

    PtyOutputCoalescer source(String value) => PtyOutputCoalescer(
      scheduler: scheduler,
      onFlush: (batch) {
        flushOrder.add(batch);
        now += 5000; // um slice consumiu mais que os 4 ms permitidos.
      },
      onAcknowledge: () {},
    )..add(value);

    final a = source('aaaa');
    final b = source('bbbb');

    frames.run();
    expect(flushOrder, ['aaaa']);
    expect(scheduler.pendingChars, 4);
    expect(frames.callbacks, hasLength(1));

    frames.run();
    expect(flushOrder, ['aaaa', 'bbbb']);
    expect(scheduler.pendingChars, 0);

    a.dispose();
    b.dispose();
  });

  test('high-water pausa ack e low-water retoma o produtor', () {
    final frames = _ManualFrames();
    final scheduler = _scheduler(frames, maxCharsPerFrame: 4, maxSliceChars: 4);
    final flushes = <String>[];
    var acks = 0;
    final coalescer = PtyOutputCoalescer(
      scheduler: scheduler,
      maxPendingChars: 8,
      resumePendingChars: 3,
      onFlush: flushes.add,
      onAcknowledge: () => acks++,
    );

    coalescer.add('abcd');
    expect(acks, 1);
    coalescer.add('efgh');
    expect(coalescer.ackPaused, isTrue);
    expect(acks, 1);

    frames.run();
    expect(coalescer.pendingLength, 4);
    expect(coalescer.ackPaused, isTrue);
    expect(acks, 1);

    frames.run();
    expect(flushes.join(), 'abcdefgh');
    expect(coalescer.ackPaused, isFalse);
    expect(acks, 2);

    coalescer.dispose();
  });

  test('slice nunca divide um surrogate pair UTF-16', () {
    final frames = _ManualFrames();
    final scheduler = _scheduler(frames, maxCharsPerFrame: 1, maxSliceChars: 1);
    final flushes = <String>[];
    final coalescer = PtyOutputCoalescer(
      scheduler: scheduler,
      onFlush: flushes.add,
      onAcknowledge: () {},
    );

    coalescer.add('😀x');
    frames.run();
    expect(flushes, ['😀']);
    frames.run();
    expect(flushes.join(), '😀x');

    coalescer.dispose();
  });

  test('dispose descarta backlog sem flush síncrono e libera read pausado', () {
    final frames = _ManualFrames();
    final scheduler = _scheduler(frames);
    final flushes = <String>[];
    var acks = 0;
    final coalescer = PtyOutputCoalescer(
      scheduler: scheduler,
      maxPendingChars: 4,
      onFlush: flushes.add,
      onAcknowledge: () => acks++,
    );

    coalescer.add('pending');
    expect(coalescer.ackPaused, isTrue);
    coalescer.dispose();

    expect(flushes, isEmpty);
    expect(acks, 1);
    expect(scheduler.pendingChars, 0);
    // O callback já postado vira no-op seguro.
    frames.run();
    expect(flushes, isEmpty);
  });

  test('drained completa depois do último slice', () async {
    final frames = _ManualFrames();
    final scheduler = _scheduler(frames);
    final coalescer = PtyOutputCoalescer(
      scheduler: scheduler,
      onFlush: (_) {},
      onAcknowledge: () {},
    );
    coalescer.add('abcdefgh');
    var completed = false;
    coalescer.drained.then((_) => completed = true);

    frames.run();
    await Future<void>.delayed(Duration.zero);
    expect(completed, isTrue);

    coalescer.dispose();
  });
}
