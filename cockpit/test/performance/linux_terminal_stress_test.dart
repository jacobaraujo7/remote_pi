import 'dart:collection';

import 'package:cockpit/app/core/terminal/pty_output_scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames {
  final callbacks = ListQueue<VoidCallback>();
  void schedule(VoidCallback callback) => callbacks.addLast(callback);
}

void main() {
  test('40 noisy terminals drain fairly with a bounded global queue', () {
    const terminals = 40;
    const bytesPerTerminal = 256 * 1024;
    final frames = _Frames();
    final scheduler = PtyOutputScheduler(
      maxCharsPerFrame: 64 * 1024,
      maxSliceChars: 4 * 1024,
      maxWorkPerFrame: const Duration(milliseconds: 4),
      scheduleFrame: frames.schedule,
      clockMicros: () => 0,
    );
    final received = List<int>.filled(terminals, 0);
    final firstProgressFrame = List<int>.filled(terminals, -1);
    var frame = 0;
    var highWater = 0;
    final payload = 'x' * bytesPerTerminal;
    final sources = List.generate(
      terminals,
      (index) => PtyOutputCoalescer(
        scheduler: scheduler,
        maxPendingChars: bytesPerTerminal + 1,
        onFlush: (chunk) {
          received[index] += chunk.length;
          if (firstProgressFrame[index] < 0) firstProgressFrame[index] = frame;
        },
        onAcknowledge: () {},
      )..add(payload),
    );
    highWater = scheduler.pendingChars;

    while (frames.callbacks.isNotEmpty) {
      frame++;
      frames.callbacks.removeFirst()();
    }

    expect(received, everyElement(bytesPerTerminal));
    expect(firstProgressFrame, everyElement(inInclusiveRange(1, 3)));
    expect(highWater, terminals * bytesPerTerminal);
    expect(scheduler.pendingChars, 0);
    for (final source in sources) {
      source.dispose();
    }
  });
}
