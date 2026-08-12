import 'package:cockpit/app/core/utils/quiet_period_debouncer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rajada contínua dispara uma vez depois da quietude', () {
    fakeAsync((async) {
      var calls = 0;
      final debouncer = QuietPeriodDebouncer(
        delay: const Duration(seconds: 1),
        onQuiet: () => calls++,
        clockMicros: () => async.elapsed.inMicroseconds,
      );

      for (var i = 0; i < 100; i++) {
        debouncer.trigger();
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(calls, 0);
      expect(debouncer.isPending, isTrue);

      async.elapse(const Duration(milliseconds: 990));
      expect(calls, 1);
      expect(debouncer.isPending, isFalse);

      debouncer.dispose();
    });
  });

  test('dispose cancela callback pendente', () {
    fakeAsync((async) {
      var calls = 0;
      final debouncer = QuietPeriodDebouncer(
        delay: const Duration(seconds: 1),
        onQuiet: () => calls++,
        clockMicros: () => async.elapsed.inMicroseconds,
      );
      debouncer.trigger();
      debouncer.dispose();
      async.elapse(const Duration(seconds: 2));
      expect(calls, 0);
    });
  });
}
