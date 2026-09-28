import 'package:cockpit/app/cockpit/data/telemetry/line_parser/telemetry_line_parser_impl.dart';
import 'package:cockpit/app/cockpit/data/telemetry/sqlite_telemetry_store.dart';
import 'package:cockpit/app/cockpit/data/telemetry/telemetry_db.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_line_parser.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_case.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_run.dart';
import 'package:flutter_test/flutter_test.dart';

const _flutterBlock = '''
══╡ EXCEPTION CAUGHT BY GESTURE ╞════════
The following RangeError was thrown while handling a gesture:
RangeError (index): Index out of range: index 3, length 2
When the exception was thrown, this was the stack:
#0      CartService.add (package:app/cart/cart_service.dart:87:22)
════════════════════════════════════════''';

/// Alimenta um run com texto passando pelo parser real.
Future<List<TelemetryEvent>> ingest(
  TelemetryStore store,
  TelemetryRun run,
  String text, {
  DateTime? at,
}) async {
  final p = TelemetryLineParserImpl(
    runId: run.id,
    config: const TelemetryParserConfig(),
  );
  final t = at ?? DateTime.now();
  final evs = <TelemetryEvent>[];
  var i = 0;
  for (final l in text.split('\n')) {
    evs.addAll(p.feed(l, stream: TelemetryStream.out, at: t, offset: i++));
  }
  evs.addAll(p.flush());
  return store.append(evs);
}

void main() {
  late SqliteTelemetryStore store;

  setUp(() async {
    store = await SqliteTelemetryStore.open(':memory:');
  });
  tearDown(() => store.close());

  Future<TelemetryRun> openApp({DateTime? at, String? pane}) => store.openRun(
    key: TelemetryRun.keyFor(cwd: '/ws/app', command: 'flutter run'),
    project: 'app',
    source: TelemetryRunSource.task,
    cwd: '/ws/app',
    command: 'flutter run',
    name: 'app',
    taskKey: 'app',
    paneId: pane ?? 't3',
    startedAt: at,
  );

  test('run: abre, lista, fecha com exit code', () async {
    final r = await openApp();
    expect(r.id, startsWith('r_'));
    expect(r.isLive, isTrue);
    expect((await store.runs(onlyLive: true)).single.id, r.id);
    await store.closeRun(r.id, exitCode: 1);
    final again = (await store.run(r.id))!;
    expect(again.exitCode, 1);
    expect(again.isLive, isFalse);
    expect(await store.runs(onlyLive: true), isEmpty);
  });

  test('append devolve ids, redige segredo e calcula fingerprint', () async {
    final r = await openApp();
    final saved = await ingest(store, r, '''
{"level":"info","msg":"login ok","Authorization":"Bearer abc","user":"u1"}
$_flutterBlock''');
    expect(saved, hasLength(2));
    expect(saved.first.id, startsWith('ev_'));
    final back = (await store.event(saved.first.id!))!;
    expect(back.attrs['Authorization'], '[redacted]');
    expect(back.attrs['user'], 'u1');
    final err = (await store.event(saved.last.id!))!;
    expect(err.fingerprint, isNotNull);
    expect(err.error!.projectFrame!.location, 'lib/cart/cart_service.dart:87');
    expect(err.rawLineOffset, 1);
  });

  test('cases agrupa, conta e marca new no run mais recente', () async {
    final r1 = await openApp(at: DateTime(2026, 9, 22, 10));
    // mesmo parser (é por run): o "Another exception" reaproveita os frames
    await ingest(
      store,
      r1,
      '$_flutterBlock\nAnother exception was thrown: RangeError (index): Index out of range: index 3, length 2',
      at: DateTime(2026, 9, 22, 10, 1),
    );
    await store.closeRun(
      r1.id,
      exitCode: 0,
      endedAt: DateTime(2026, 9, 22, 11),
    );

    final r2 = await openApp(at: DateTime(2026, 9, 23, 12));
    await ingest(store, r2, _flutterBlock, at: DateTime(2026, 9, 23, 12, 1));
    await ingest(
      store,
      r2,
      '''
Unhandled exception:
Null check operator used on a null value
#0      _S.build (package:app/checkout/checkout_page.dart:120:41)''',
      at: DateTime(2026, 9, 23, 12, 2),
    );

    final cases = await store.cases(const TelemetryQuery());
    expect(cases, hasLength(2));
    final nullCheck = cases.firstWhere(
      (c) => c.type == 'Error' || c.message.contains('Null check'),
    );
    final range = cases.firstWhere((c) => c.type == 'RangeError');
    expect(range.count, 3);
    expect(range.runs.map((x) => x.runId), [r2.id, r1.id]);
    expect(range.isNew, isFalse);
    expect(nullCheck.isNew, isTrue);
    expect(range.location, 'lib/cart/cart_service.dart:87');
    expect(range.runs.first.live, isTrue);

    final onlyNew = await store.cases(const TelemetryQuery(onlyNew: true));
    expect(onlyNew.map((c) => c.fingerprint), [nullCheck.fingerprint]);

    // caseById por prefixo curto
    final byShort = await store.caseById(range.shortId);
    expect(byShort!.fingerprint, range.fingerprint);
  });

  test(
    'triagem: resolved some, volta como regressão; ignored some da CLI',
    () async {
      final r1 = await openApp(at: DateTime(2026, 9, 22, 10));
      await ingest(store, r1, _flutterBlock, at: DateTime(2026, 9, 22, 10, 1));
      final fp = (await store.cases(const TelemetryQuery())).single.fingerprint;

      await store.triage(
        fp,
        TelemetryTriageStatus.resolved,
        by: TelemetryTriageActor.agent,
      );
      expect(await store.cases(const TelemetryQuery()), isEmpty);
      expect(
        (await store.cases(
          const TelemetryQuery(includeResolved: true),
        )).single.status,
        TelemetryTriageStatus.resolved,
      );

      // reaparece depois da triagem → regressão
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final r2 = await openApp();
      await ingest(store, r2, _flutterBlock);
      final again = (await store.cases(const TelemetryQuery())).single;
      expect(again.isRegression, isTrue);
      expect(again.status, TelemetryTriageStatus.open);
      expect(again.triage!.by, TelemetryTriageActor.agent);
      expect(
        (await store.cases(
          const TelemetryQuery(onlyNew: true),
        )).single.fingerprint,
        fp,
      );

      await store.triage(
        fp,
        TelemetryTriageStatus.ignored,
        by: TelemetryTriageActor.human,
        reason: 'ruído',
      );
      expect(await store.cases(const TelemetryQuery()), isEmpty);
      expect(
        await store.events(
          const TelemetryQuery(minSeverity: TelemetrySeverity.error),
        ),
        isEmpty,
      );
      expect(
        await store.events(
          const TelemetryQuery(
            minSeverity: TelemetrySeverity.error,
            includeIgnored: true,
          ),
        ),
        isNotEmpty,
      );

      await store.triage(
        fp,
        TelemetryTriageStatus.open,
        by: TelemetryTriageActor.human,
      );
      expect(await store.cases(const TelemetryQuery()), hasLength(1));
    },
  );

  test('events: filtros de severidade, probe, texto e contexto', () async {
    final r = await openApp();
    final saved = await ingest(store, r, '''
ready on :3000
{"level":"debug","msg":"cart add","probe":"cart","items":2}
{"level":"warn","msg":"slow query","ms":812}
Error: connect ECONNREFUSED 127.0.0.1:5432
    at pool.connect (src/db.ts:12:9)
after''');
    expect(saved, hasLength(5));
    final warnUp = await store.events(
      const TelemetryQuery(minSeverity: TelemetrySeverity.warn),
    );
    expect(warnUp.map((e) => e.body), [
      'slow query',
      'connect ECONNREFUSED 127.0.0.1:5432',
    ]);
    final probes = await store.events(const TelemetryQuery(probe: 'cart'));
    expect(probes.single.attrs['items'], 2);
    final any = await store.events(const TelemetryQuery(probe: '*'));
    expect(any, hasLength(1));
    final text = await store.events(const TelemetryQuery(text: 'slow'));
    expect(text.single.body, 'slow query');

    final errId = warnUp.last.id!;
    final ctx = await store.context(errId, before: 2, after: 1);
    expect(ctx.map((e) => e.body), [
      'cart add',
      'slow query',
      'connect ECONNREFUSED 127.0.0.1:5432',
      'after',
    ]);
  });

  test('marcas, clear e retenção', () async {
    final old = await openApp(at: DateTime(2026, 1, 1));
    await ingest(store, old, _flutterBlock, at: DateTime(2026, 1, 1));
    await store.closeRun(old.id, endedAt: DateTime(2026, 1, 1, 1));
    final fresh = await openApp();
    await ingest(store, fresh, _flutterBlock);

    await store.markStart('bug', at: DateTime(2026, 9, 23, 12));
    await store.markEnd('bug', at: DateTime(2026, 9, 23, 12, 5));
    final m = (await store.mark('bug'))!;
    expect(m.$1, DateTime(2026, 9, 23, 12));
    expect(m.$2, DateTime(2026, 9, 23, 12, 5));

    // retenção por idade apaga só o run antigo e encerrado
    await store.vacuum(const TelemetryRetention(maxAge: Duration(days: 30)));
    expect((await store.runs()).map((r) => r.id), [fresh.id]);

    // clear por fingerprint apaga eventos, run continua
    final fp = (await store.cases(const TelemetryQuery())).single.fingerprint;
    await store.clear(fingerprint: fp);
    expect(await store.cases(const TelemetryQuery()), isEmpty);
    expect(await store.runs(), hasLength(1));
    expect(await store.sizeInBytes(), greaterThan(0));
  });

  test('TelemetryDb síncrono: FTS disponível e lote grande rápido', () {
    final db = TelemetryDb.memory();
    addTearDown(db.dispose);
    final run = db.openRun({
      'key': 'k',
      'project': 'p',
      'source': 'wrapper',
      'cwd': '/x',
      'command': 'c',
      'started_at': DateTime.now().millisecondsSinceEpoch,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = [
      for (var i = 0; i < 10000; i++)
        {
          'run_id': run['id'],
          'ts': now + i,
          'stream': 'out',
          'severity': 2,
          'body': 'line $i token=$i',
        },
    ];
    final sw = Stopwatch()..start();
    final ids = db.append(batch);
    sw.stop();
    expect(ids, hasLength(10000));
    expect(sw.elapsedMilliseconds, lessThan(1000));
    // ignore: avoid_print
    print('fts=${db.hasFts} 10k append=${sw.elapsedMilliseconds}ms');
    final found = db.events({'text': 'line 9999', 'limit': 5});
    expect(found.any((e) => e['body'] == 'line 9999 token=[redacted]'), isTrue);
  });
}
