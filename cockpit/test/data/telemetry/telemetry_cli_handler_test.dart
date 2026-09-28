import 'dart:convert';

import 'package:cockpit/app/cockpit/data/telemetry/line_parser/telemetry_line_parser_impl.dart';
import 'package:cockpit/app/cockpit/data/telemetry/sqlite_telemetry_store.dart';
import 'package:cockpit/app/cockpit/data/telemetry/telemetry_ingest_impl.dart';
import 'package:cockpit/app/cockpit/data/telemetry/telemetry_store_registry.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/telemetry_cli_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TelemetryStoreRegistry registry;
  late TelemetryIngestImpl ingest;
  late TelemetryCliHandler cli;
  DateTime? lastEdit;

  final project = Project(
    id: 'ws1',
    name: 'shop',
    path: '/ws/shop',
    colorValue: 0,
    createdAt: DateTime(2026),
  );

  setUp(() {
    registry = TelemetryStoreRegistry(
      opener: (_) => SqliteTelemetryStore.open(':memory:'),
    );
    ingest = TelemetryIngestImpl(
      registry,
      const TelemetryLineParserFactoryImpl(),
      startOtlp: false,
    );
    ingest.registerWorkspace(
      const TelemetryWorkspace(
        id: 'ws1',
        name: 'shop',
        path: '/ws/shop',
        roots: ['/ws/shop'],
      ),
    );
    cli = TelemetryCliHandler(
      registry,
      ingest,
      lastEditAt: (_) => lastEdit,
      rootsOf: (_) => const ['/ws/shop'],
    );
  });
  tearDown(() => registry.closeAll());

  Future<Map<String, Object?>> call(
    String cmd, [
    Map<String, dynamic> args = const {},
  ]) async {
    final r = await cli.handle(
      CockpitCommand(cmd: cmd, tabId: 't9', args: args),
      project,
      '/ws/shop',
    );
    expect(r.ok, isTrue, reason: 'cmd $cmd failed: ${r.error}');
    return ((r.data as Map?) ?? const {}).cast<String, Object?>();
  }

  /// Simula o wrapper: open → ingest (lotes) → close.
  Future<String> wrapperRun(List<String> lines, {int exit = 1}) async {
    final open = await call('telemetry-open', {
      'cwd': '/ws/shop',
      'command': 'flutter test',
    });
    final run = open['run'] as String;
    expect((open['env'] as Map)['COCKPIT_RUN_ID'], run);
    await call('telemetry-ingest', {
      'run': run,
      'stream': 'out',
      'lines': lines,
    });
    final closed = await call('telemetry-close', {
      'run': run,
      'exit_code': exit,
    });
    expect(closed['run'], run);
    return run;
  }

  test('wrapper: open/ingest/close e resumo de erros', () async {
    final open = await call('telemetry-open', {
      'cwd': '/ws/shop',
      'command': 'flutter test',
    });
    final run = open['run'] as String;
    await call('telemetry-ingest', {
      'run': run,
      'lines': [
        '00:08 +11 -1: CartServiceTest adds item [E]',
        '  RangeError (index): Index out of range: index 3, length 2',
        '  package:app/cart/cart_service.dart 87:22  CartService.add',
        '',
        'DeprecationWarning: old api',
      ],
    });
    // stderr chega separado no modo pipes
    await call('telemetry-ingest', {
      'run': run,
      'stream': 'err',
      'data': base64Encode(
        utf8.encode('Error: boom\n    at f (src/a.ts:1:1)\n'),
      ),
    });
    final closed = await call('telemetry-close', {'run': run, 'exit_code': 1});
    expect(closed['errors'], 2);
    expect(closed['warnings'], 1);
    expect(ingest.session(run), isNull);

    final errors = await call('telemetry-errors', {'run': run});
    final cases = (errors['cases'] as List).cast<Map>();
    expect(cases, hasLength(2));
    expect(cases.every((c) => (c['id'] as String).startsWith('e_')), isTrue);
    expect(cases.map((c) => c['type']), containsAll(['Test failed', 'Error']));
    expect(errors['total'], 2);
    expect(errors.containsKey('truncated'), isFalse);

    final warnToo = await call('telemetry-errors', {
      'run': run,
      'level': 'warn',
    });
    expect((warnToo['cases'] as List), hasLength(3));
  });

  test('show: caso com último evento, contexto e log correlacionado', () async {
    final run = await wrapperRun([
      '{"level":"debug","msg":"cart add","itemId":"sku-88","items":2}',
      'RangeError (index): Index out of range: index 3, length 2',
      '#0      CartService.add (package:app/cart/cart_service.dart:87:22)',
      'after',
    ]);
    final errors = await call('telemetry-errors');
    final id = ((errors['cases'] as List).single as Map)['id'] as String;
    final show = await call('telemetry-show', {'id': id});
    final c = show['case'] as Map;
    expect(c['location'], 'lib/cart/cart_service.dart:87');
    expect((show['last'] as Map)['error'], isA<Map>());
    expect(((show['last'] as Map)['error'] as Map)['frames'], isNotEmpty);
    expect((show['correlated'] as Map)['attrs'], {
      'itemId': 'sku-88',
      'items': 2,
    });
    expect((show['runs'] as List).single, containsPair('run', run));
    expect((show['context'] as List), isNotEmpty);

    final byRun = await call('telemetry-show', {'id': run});
    expect((byRun['run'] as Map)['exit_code'], 1);
    expect((byRun['cases'] as List), hasLength(1));
  });

  test(
    'triage pela CLI: resolve some, --include-resolved mostra, reopen volta',
    () async {
      await wrapperRun(['Error: x', '    at f (src/a.ts:1:1)']);
      final id =
          (((await call('telemetry-errors'))['cases'] as List).single
                  as Map)['id']
              as String;
      final t = await call('telemetry-triage', {
        'id': id,
        'status': 'resolve',
        'reason': 'fixed',
      });
      expect(t['status'], 'resolved');
      expect(((await call('telemetry-errors'))['cases'] as List), isEmpty);
      final inc = await call('telemetry-errors', {'include_resolved': true});
      expect(((inc['cases'] as List).single as Map)['status'], 'resolved');
      final shown = await call('telemetry-show', {'id': id});
      expect((shown['triage'] as Map)['by'], 'agent');
      await call('telemetry-triage', {'id': id, 'status': 'reopen'});
      expect(((await call('telemetry-errors'))['cases'] as List), hasLength(1));
    },
  );

  test('janelas: --since-edit e --new; logs exclui erros por nível', () async {
    await wrapperRun(['{"level":"info","msg":"old"}']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    lastEdit = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await wrapperRun([
      '{"level":"info","msg":"fresh"}',
      'Error: new one',
      '    at g (src/b.ts:2:2)',
    ]);
    final logs = await call('telemetry-logs', {'since_edit': true});
    expect((logs['events'] as List).map((e) => (e as Map)['body']), [
      'fresh',
      'new one',
    ]);
    final onlyNew = await call('telemetry-errors', {'new': true});
    expect((onlyNew['cases'] as List), hasLength(1));
    final runs = await call('telemetry-runs');
    expect((runs['runs'] as List), hasLength(2));
    expect(((runs['runs'] as List).first as Map)['source'], 'wrapper');
  });

  test('wait --fingerprint: hit quando reaparece, ok quando some', () async {
    await wrapperRun(['Error: flaky', '    at f (src/a.ts:1:1)']);
    final id =
        (((await call('telemetry-errors'))['cases'] as List).single
                as Map)['id']
            as String;

    // reaparece durante a espera → hit
    final hitF = call('telemetry-wait', {
      'fingerprint': id,
      'absent': '5s',
      'timeout': '5s',
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await wrapperRun(['Error: flaky', '    at f (src/a.ts:1:1)']);
    expect((await hitF)['result'], 'hit');

    // só atividade sem o erro → ok após `absent`
    final okF = call('telemetry-wait', {
      'fingerprint': id,
      'absent': '1s',
      'timeout': '5s',
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await wrapperRun(['{"level":"info","msg":"cart add"}'], exit: 0);
    expect((await okF)['result'], 'ok');
  });

  test('teto de resposta: lista grande vem truncada com dica', () async {
    final lines = <String>[];
    for (var i = 0; i < 400; i++) {
      lines
        ..add(
          'Error: failure number $i in a fairly long message to fill the payload ${'x' * 120}',
        )
        ..add('    at fn$i (src/file$i.ts:$i:1)');
    }
    await wrapperRun(lines);
    final r = await call('telemetry-errors', {'limit': 400});
    expect(r['truncated'], isTrue);
    expect(r['hint'], isNotNull);
    expect(
      jsonEncode(r['cases']).length,
      lessThanOrEqualTo(kTelemetryReplyCap),
    );
    expect(r['total'], 400);
  });
}
