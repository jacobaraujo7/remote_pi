import 'package:cockpit/app/core/terminal/pty_output_scheduler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Janela oculta (outra mesa do macOS, minimizada): o Flutter não produz
/// frames, mas a saída do PTY precisa continuar sendo consumida — senão o ack
/// para, o pipe enche e o processo filho bloqueia no write.
void main() {
  test('sem frame, drena por timer e mantém o ack fluindo', () {
    fakeAsync((async) {
      final frames = <VoidCallback>[];
      final scheduler = PtyOutputScheduler(
        scheduleFrame: frames.add, // frame agendado que NUNCA chega
        hiddenDrainInterval: const Duration(milliseconds: 100),
      );
      final flushed = <String>[];
      var acks = 0;
      final source = PtyOutputCoalescer(
        scheduler: scheduler,
        onAcknowledge: () => acks++,
        onFlush: flushed.add,
      );
      source.add('hello');
      expect(flushed, isEmpty, reason: 'nada drenado antes do frame/timer');
      async.elapse(const Duration(milliseconds: 99));
      expect(flushed, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      expect(flushed, ['hello'], reason: 'watchdog drenou sem frame');
      expect(acks, greaterThan(0));

      // Frame atrasado chegando depois do timer não drena duas vezes nem
      // quebra nada.
      for (final f in frames) {
        f();
      }
      expect(flushed, ['hello']);

      // Segundo chunk: novo ciclo, mesmo comportamento.
      source.add('world');
      async.elapse(const Duration(milliseconds: 101));
      expect(flushed, ['hello', 'world']);
      source.dispose();
    });
  });

  test('com frame chegando antes, o timer não dispara em dobro', () {
    fakeAsync((async) {
      VoidCallback? pending;
      final scheduler = PtyOutputScheduler(
        scheduleFrame: (drain) => pending = drain,
        hiddenDrainInterval: const Duration(milliseconds: 100),
      );
      final flushed = <String>[];
      final source = PtyOutputCoalescer(
        scheduler: scheduler,
        onAcknowledge: () {},
        onFlush: flushed.add,
      );
      source.add('a');
      async.elapse(const Duration(milliseconds: 16));
      pending!(); // o frame veio
      expect(flushed, ['a']);
      async.elapse(const Duration(milliseconds: 200));
      expect(flushed, ['a'], reason: 'timer cancelado pelo frame');
      source.dispose();
    });
  });

  test('output apenas oculto não pede frame e continua dando ack', () {
    fakeAsync((async) {
      final frames = <VoidCallback>[];
      final flushed = <String>[];
      var acknowledgements = 0;
      final scheduler = PtyOutputScheduler(
        scheduleFrame: frames.add,
        hiddenDrainInterval: const Duration(milliseconds: 100),
      );
      final source = PtyOutputCoalescer(
        scheduler: scheduler,
        onAcknowledge: () => acknowledgements++,
        onFlush: flushed.add,
      )..visible = false;

      source.add('hidden output');
      expect(frames, isEmpty);
      async.elapse(const Duration(milliseconds: 101));
      expect(flushed, ['hidden output']);
      expect(acknowledgements, greaterThan(0));

      source.add('becomes visible');
      expect(frames, isEmpty);
      source.visible = true;
      expect(frames, hasLength(1));
      frames.single();
      expect(flushed, ['hidden output', 'becomes visible']);
      expect(scheduler.pendingChars, 0);
      source.dispose();
    });
  });

  test('timer drains do not queue duplicate callbacks without vsync', () {
    fakeAsync((async) {
      final frames = <VoidCallback>[];
      final flushed = <String>[];
      final scheduler = PtyOutputScheduler(
        scheduleFrame: frames.add,
        maxSliceChars: 1,
        maxCharsPerFrame: 1,
        hiddenDrainInterval: const Duration(milliseconds: 100),
      );
      final source = PtyOutputCoalescer(
        scheduler: scheduler,
        onAcknowledge: () {},
        onFlush: flushed.add,
      );

      source.add('abc');
      expect(frames, hasLength(1));
      async.elapse(const Duration(milliseconds: 301));
      expect(flushed.join(), 'abc');
      expect(frames, hasLength(1));

      source.add('d');
      expect(frames, hasLength(1));
      frames.single();
      expect(flushed.join(), 'abcd');
      source.dispose();
    });
  });
}
