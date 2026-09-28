import 'package:cockpit/app/cockpit/data/telemetry/fingerprint.dart';
import 'package:cockpit/app/cockpit/data/telemetry/line_parser/telemetry_line_parser_impl.dart';
import 'package:cockpit/app/cockpit/data/telemetry/redaction.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_line_parser.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:flutter_test/flutter_test.dart';

List<TelemetryEvent> parse(
  String text, {
  TelemetryParserConfig config = const TelemetryParserConfig(),
  TelemetryStream stream = TelemetryStream.out,
}) {
  final p = TelemetryLineParserImpl(runId: 'r_1', config: config);
  final at = DateTime(2026, 9, 23, 12);
  final out = <TelemetryEvent>[];
  var i = 0;
  for (final line in text.split('\n')) {
    out.addAll(p.feed(line, stream: stream, at: at, offset: i++));
  }
  out.addAll(p.flush());
  return out;
}

void main() {
  group('limpeza', () {
    test('strip ANSI e descarta alt-screen', () {
      final ev = parse(
        '\x1b[31mERROR\x1b[0m boom\n'
        '\x1b[?1049h(tela de TUI) Error: falso\n'
        'ainda no alt\n'
        '\x1b[?1049l\n'
        'de volta',
      );
      expect(ev.map((e) => e.body), ['ERROR boom', 'de volta']);
      expect(ev.first.severity, TelemetrySeverity.error);
    });

    test('unwrap de prefixos empilhados (compose + timestamp + flutter)', () {
      final ev = parse(
        'api-1  | 2026-09-23T12:00:00.000Z {"level":"warn","msg":"slow"}\n'
        'flutter: {"level":"debug","msg":"cart add","itemId":"sku-88"}\n'
        'I/flutter ( 1234): {"level":"info","msg":"android"}\n'
        '[0] listening on :3000',
      );
      expect(ev[0].body, 'slow');
      expect(ev[0].attrs['service'], 'api-1');
      expect(ev[0].severity, TelemetrySeverity.warn);
      expect(ev[1].body, 'cart add');
      expect(ev[1].attrs['itemId'], 'sku-88');
      expect(ev[2].body, 'android');
      expect(ev[3].body, 'listening on :3000');
      expect(ev[3].severity, TelemetrySeverity.info);
    });
  });

  group('JSON Lines', () {
    test('pino com nível numérico e err aninhado', () {
      final ev = parse(
        '{"level":50,"time":1758632475810,"name":"api","err":{"type":"Error",'
        '"message":"connect ECONNREFUSED 127.0.0.1:5432","code":"ECONNREFUSED",'
        '"stack":"Error: connect ECONNREFUSED 127.0.0.1:5432\\n    at TCPConnectWrap.afterConnect [as oncomplete] (node:net:1555:16)\\n    at pool.connect (/Users/j/shop/backend/src/db.ts:12:9)"},'
        '"msg":"db connect failed"}',
        config: const TelemetryParserConfig(
          projectRoots: ['/Users/j/shop/backend'],
        ),
      ).single;
      expect(ev.severity, TelemetrySeverity.error);
      expect(ev.body, 'db connect failed');
      expect(ev.error!.type, 'Error');
      expect(ev.error!.message, 'connect ECONNREFUSED 127.0.0.1:5432');
      expect(ev.error!.projectFrame!.location, 'src/db.ts:12');
      expect(ev.attrs['service'], 'api');
      expect(ev.fingerprint, isNotNull);
      expect(ev.ts.millisecondsSinceEpoch, 1758632475810);
    });

    test('campos desconhecidos viram attrs; probe é lido', () {
      final ev = parse(
        '{"level":"debug","msg":"x","probe":"cart","items":2}',
      ).single;
      expect(ev.probe, 'cart');
      expect(ev.attrs['items'], 2);
      expect(ev.attrs.containsKey('msg'), isFalse);
    });

    test('objeto que não é log (sem msg) ainda entra como evento', () {
      final ev = parse('{"a":1}').single;
      expect(ev.attrs['a'], 1);
      expect(ev.severity, TelemetrySeverity.info);
    });
  });

  group('blocos de erro', () {
    test('Flutter EXCEPTION CAUGHT (com prefixo flutter:)', () {
      final ev = parse('''
flutter: ══╡ EXCEPTION CAUGHT BY GESTURE ╞═══════════════════════════════════════════════
flutter: The following RangeError was thrown while handling a gesture:
flutter: RangeError (index): Index out of range: index 3, length 2
flutter:
flutter: When the exception was thrown, this was the stack:
flutter: #0      List.[] (dart:core-patch/growable_array.dart:264:36)
flutter: #1      CartService.add (package:app/cart/cart_service.dart:87:22)
flutter: #2      CartBadge._onTap (package:app/cart/cart_badge.dart:41:9)
flutter: #3      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1176:21)
flutter: ════════════════════════════════════════════════════════════════════════════════
flutter: depois''');
      expect(ev, hasLength(2));
      final e = ev.first;
      expect(e.error!.type, 'RangeError');
      expect(e.error!.message, 'Index out of range: index 3, length 2');
      expect(e.error!.frames, hasLength(4));
      expect(e.error!.frames.first.inProject, isFalse);
      expect(e.error!.projectFrame!.location, 'lib/cart/cart_service.dart:87');
      expect(e.rawLineOffset, 0);
      expect(ev.last.body, 'depois');
    });

    test('Another exception reaproveita frames e dá o MESMO fingerprint', () {
      final ev = parse(
        '''
══╡ EXCEPTION CAUGHT BY GESTURE ╞════════
The following RangeError was thrown while handling a gesture:
RangeError (index): Index out of range: index 3, length 2
When the exception was thrown, this was the stack:
#0      CartService.add (package:app/cart/cart_service.dart:87:22)
════════════════════════════════════════
Another exception was thrown: RangeError (index): Index out of range: index 3, length 2''',
      );
      expect(ev, hasLength(2));
      expect(ev[1].error!.frames, isNotEmpty);
      expect(ev[1].fingerprint, ev[0].fingerprint);
    });

    test('Dart Unhandled exception em duas linhas', () {
      final ev = parse('''
Unhandled exception:
Null check operator used on a null value
#0      _CheckoutPageState.build (package:app/checkout/checkout_page.dart:120:41)
#1      StatefulElement.build (package:flutter/src/widgets/framework.dart:5592:27)
<asynchronous suspension>
next line''');
      expect(ev, hasLength(2));
      expect(
        ev.first.error!.message,
        'Null check operator used on a null value',
      );
      expect(
        ev.first.error!.projectFrame!.location,
        'lib/checkout/checkout_page.dart:120',
      );
    });

    test('Node: Error + at frames + propriedades indentadas', () {
      final ev = parse(
        '''
Error: connect ECONNREFUSED 127.0.0.1:5432
    at TCPConnectWrap.afterConnect [as oncomplete] (node:net:1555:16)
    at pool.connect (/app/src/db.ts:12:9) {
  errno: -61,
  code: 'ECONNREFUSED'
}
[nodemon] app crashed''',
        config: const TelemetryParserConfig(projectRoots: ['/app']),
      );
      expect(ev, hasLength(2));
      expect(ev.first.error!.type, 'Error');
      expect(ev.first.error!.projectFrame!.location, 'src/db.ts:12');
      expect(ev.last.body, '[nodemon] app crashed');
      expect(ev.last.severity, TelemetrySeverity.error);
    });

    test('Python traceback (frame mais interno primeiro)', () {
      final ev = parse('''
Traceback (most recent call last):
  File "app.py", line 12, in <module>
    main()
  File "/usr/lib/python3.12/site-packages/flask/app.py", line 100, in run
    x()
  File "shop/orders.py", line 41, in create
    qty = int(payload["qty"])
ValueError: invalid literal for int() with base 10: 'abc'
ok''');
      final e = ev.first;
      expect(e.error!.type, 'ValueError');
      expect(e.error!.message, contains('invalid literal'));
      expect(e.error!.frames.first.file, 'shop/orders.py');
      expect(e.error!.projectFrame!.location, 'shop/orders.py:41');
      expect(ev.last.body, 'ok');
    });

    test('Rust panic com backtrace', () {
      final ev = parse('''
thread 'main' panicked at src/main.rs:12:5:
index out of bounds: the len is 2 but the index is 3
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
fim''');
      expect(ev.first.error!.type, 'Panic');
      expect(ev.first.error!.message, contains('index out of bounds'));
      expect(ev.first.error!.projectFrame!.location, 'src/main.rs:12');
      expect(ev.first.severity, TelemetrySeverity.fatal);
      expect(ev.last.body, 'fim');
    });

    test('Go panic', () {
      final ev = parse('''
panic: runtime error: index out of range [3] with length 2

goroutine 1 [running]:
main.run(...)
        /app/main.go:12 +0x1d
main.main()
        /app/main.go:8 +0x15
exit status 2''', config: const TelemetryParserConfig(projectRoots: ['/app']));
      expect(ev.first.error!.type, 'Panic');
      expect(ev.first.error!.projectFrame!.location, 'main.go:12');
      expect(ev.last.body, 'exit status 2');
    });

    test('flutter test [E]', () {
      final ev = parse('''
00:08 +11 -1: CartServiceTest adds item beyond capacity [E]
  RangeError (index): Index out of range: index 3, length 2
  package:app/cart/cart_service.dart 87:22  CartService.add
  test/cart/cart_service_test.dart 33:5     main.<fn>.<fn>

00:08 +11 -1: Some tests failed.''');
      final e = ev.first;
      expect(e.error!.type, 'Test failed');
      expect(
        e.error!.message,
        startsWith('CartServiceTest adds item beyond capacity: RangeError'),
      );
      expect(e.error!.frames, hasLength(2));
      expect(e.error!.projectFrame!.location, 'lib/cart/cart_service.dart:87');
    });

    test('pytest FAILED em uma linha', () {
      final ev = parse(
        'FAILED tests/test_x.py::test_y - AssertionError: 1 != 2',
      ).single;
      expect(ev.error!.type, 'Test failed');
      expect(
        ev.error!.message,
        'tests/test_x.py::test_y: AssertionError: 1 != 2',
      );
    });

    test('flush fecha bloco pendente no fim do run', () {
      final p = TelemetryLineParserImpl(
        runId: 'r',
        config: const TelemetryParserConfig(),
      );
      final at = DateTime(2026);
      expect(
        p.feed(
          'TypeError: x is not a function',
          stream: TelemetryStream.err,
          at: at,
        ),
        isEmpty,
      );
      expect(
        p.feed('    at f (/a/b.js:1:2)', stream: TelemetryStream.err, at: at),
        isEmpty,
      );
      final out = p.flush();
      expect(out.single.error!.type, 'TypeError');
      expect(out.single.stream, TelemetryStream.err);
    });
  });

  group('linha crua', () {
    test('severidade chutada, sem falso positivo em "0 errors"', () {
      final ev = parse('''
Compiled successfully with 0 errors
webpack compiled with 1 warning
[nodemon] app crashed - waiting for file changes
DEBUG something
plain line''');
      expect(ev.map((e) => e.severity), [
        TelemetrySeverity.info,
        TelemetrySeverity.warn,
        TelemetrySeverity.error,
        TelemetrySeverity.debug,
        TelemetrySeverity.info,
      ]);
      expect(ev.every((e) => e.error == null), isTrue);
    });
  });

  group('fingerprint', () {
    TelemetryError err(String msg, {String loc = 'lib/a.dart:1'}) =>
        TelemetryError(
          type: 'RangeError',
          message: msg,
          frames: [
            TelemetryFrame(
              raw: '',
              file: loc.split(':').first,
              line: int.parse(loc.split(':').last),
              inProject: true,
            ),
          ],
        );

    test('estável sob ids, números, caminhos e strings', () {
      final a = fingerprintOf(
        err('order 91c0 failed for /Users/j/x/y.dart "abc" at 12:30'),
      );
      final b = fingerprintOf(
        err('order 7f2e failed for /tmp/z/w.dart "xyz" at 09:01'),
      );
      expect(a, b);
    });

    test('diferente sob frame diferente', () {
      expect(
        fingerprintOf(err('x')),
        isNot(fingerprintOf(err('x', loc: 'lib/b.dart:9'))),
      );
    });

    test('normalizeMessage', () {
      expect(
        normalizeMessage('Index out of range: index 3, length 2'),
        'index out of range: index *, length *',
      );
    });
  });

  group('redação', () {
    test('chaves sensíveis e padrões no texto', () {
      final r = redactAttrs({
        'Authorization': 'Bearer abc',
        'nested': {'password': 'x', 'ok': 'y'},
        'text':
            'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghijklmnop fim',
        'url': 'https://h/?api_key=SECRET123&x=1',
      });
      expect(r['Authorization'], redacted);
      expect((r['nested'] as Map)['password'], redacted);
      expect((r['nested'] as Map)['ok'], 'y');
      expect(r['text'], 'token $redacted fim');
      expect(r['url'], 'https://h/?api_key=$redacted&x=1');
    });
  });
}
