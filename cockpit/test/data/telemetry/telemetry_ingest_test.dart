import 'package:cockpit/app/cockpit/data/telemetry/line_parser/telemetry_line_parser_impl.dart';
import 'package:cockpit/app/cockpit/data/telemetry/sqlite_telemetry_store.dart';
import 'package:cockpit/app/cockpit/data/telemetry/telemetry_ingest_impl.dart';
import 'package:cockpit/app/cockpit/data/telemetry/telemetry_store_registry.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TelemetryStoreRegistry registry;
  late TelemetryIngestImpl ingest;
  final opened = <String>[];

  setUp(() {
    opened.clear();
    registry = TelemetryStoreRegistry(
      opener: (id) {
        opened.add(id);
        return SqliteTelemetryStore.open(':memory:');
      },
    );
    ingest = TelemetryIngestImpl(
      registry,
      const TelemetryLineParserFactoryImpl(),
      startOtlp: false,
    );
    ingest.registerWorkspace(
      const TelemetryWorkspace(
        id: 'ws-mono',
        name: 'shop',
        path: '/ws/shop',
        roots: ['/ws/shop/app', '/ws/shop/backend'],
      ),
    );
    ingest.registerWorkspace(
      const TelemetryWorkspace(
        id: 'ws-single',
        name: 'site',
        path: '/ws/site',
        roots: ['/ws/site'],
      ),
    );
  });
  tearDown(() => registry.closeAll());

  test('colliding store run IDs preserve app and workspace sessions', () async {
    final sessions = await Future.wait([
      ingest.openAppRun(version: 'acceptance'),
      ingest.openWrapperRun(
        cwd: '/ws/shop/app',
        command: 'worker A',
        workspaceId: 'ws-mono',
        ownerId: 'orc-A',
        paneId: 'A1',
      ),
      ingest.openWrapperRun(
        cwd: '/ws/site',
        command: 'worker B',
        workspaceId: 'ws-single',
        ownerId: 'orc-B',
        paneId: 'B1',
      ),
    ]);
    final live = sessions.cast<TelemetryIngestSession>();
    expect(live.map((s) => s.runId).toSet(), hasLength(1));
    expect(ingest.session(live.first.runId), isNull);
    final routingKeys = <String>{};
    for (final session in live) {
      expect(
        ingest.session(session.runId, workspaceId: session.workspaceId),
        same(session),
      );
      final attributes = session.childEnvironment['OTEL_RESOURCE_ATTRIBUTES']!;
      final key = attributes.split(',').first.substring('cockpit.run='.length);
      routingKeys.add(key);
      expect(ingest.runFor(runId: key), key);
      ingest.addEvents(key, [
        TelemetryEvent(
          runId: key,
          ts: DateTime.now(),
          stream: TelemetryStream.out,
          severity: TelemetrySeverity.info,
          body: session.workspaceId,
        ),
      ]);
    }
    expect(routingKeys, hasLength(3));
    expect(ingest.runFor(runId: live.first.runId), isNull);
    expect(ingest.runFor(runId: 'unknown', serviceName: 'worker A'), isNull);
    for (final session in live) {
      await session.close();
      final store = await registry.forWorkspace(session.workspaceId);
      final events = await store.events(TelemetryQuery(runId: session.runId));
      expect(events.map((e) => e.body), [session.workspaceId]);
      expect(events.single.runId, session.runId);
      expect(
        ingest.session(session.runId, workspaceId: session.workspaceId),
        isNull,
      );
    }
  });

  test('explicit workspace wins over a nested registered root', () async {
    ingest.registerWorkspace(
      const TelemetryWorkspace(
        id: 'nested',
        name: 'nested',
        path: '/ws/shop/app/nested',
        roots: ['/ws/shop/app/nested'],
      ),
    );
    final session = (await ingest.openWrapperRun(
      cwd: '/ws/shop/app/nested',
      command: 'owned',
      workspaceId: 'ws-mono',
      ownerId: 'orc-A',
      paneId: 'A1',
    ))!;
    expect(session.workspaceId, 'ws-mono');
    expect(session.ownerId, 'orc-A');
    expect(session.paneId, 'A1');
    expect(
      await ingest.openWrapperRun(
        cwd: '/ws/site',
        command: 'foreign',
        workspaceId: 'ws-mono',
      ),
      isNull,
    );
    await session.close();
  });

  test('owned error notices retain document and terminal identity', () async {
    final notice = ingest.notices.first;
    final session = (await ingest.openWrapperRun(
      cwd: '/ws/shop/app',
      command: 'owned',
      workspaceId: 'ws-mono',
      ownerId: 'orc-A',
      paneId: 'A1',
    ))!;
    session.add('Error: owned failure\n');
    await session.close(exitCode: 1);
    final received = await notice;
    expect(received.workspaceId, 'ws-mono');
    expect(received.ownerId, 'orc-A');
    expect(received.paneId, 'A1');
  });

  const appTask = TaskDefinition(
    id: 'flutter:run',
    label: 'app',
    cwd: '/ws/shop/app',
    command: 'flutter',
    args: ['run'],
    kind: TaskKind.watch,
  );

  test(
    'resolve: multi-root usa o nome da root; raiz única usa o workspace',
    () {
      expect(ingest.resolve('/ws/shop/app/lib')!.project, 'app');
      expect(ingest.resolve('/ws/shop/backend')!.project, 'backend');
      expect(ingest.resolve('/ws/site/src')!.project, 'site');
      expect(ingest.resolve('/ws/site/src')!.ws.id, 'ws-single');
      expect(ingest.resolve('/elsewhere'), isNull);
    },
  );

  test(
    'abre run no store do workspace, injeta env e grava eventos por chunks',
    () async {
      final session = (await ingest.openTaskRun(
        appTask,
        command: 'flutter run',
      ))!;
      expect(opened, ['ws-mono']);
      expect(session.runId, startsWith('r_'));
      expect(session.childEnvironment['COCKPIT_RUN_ID'], session.runId);
      expect(session.childEnvironment['OTEL_SERVICE_NAME'], 'app');
      expect(
        session.childEnvironment['OTEL_RESOURCE_ATTRIBUTES'],
        contains('cockpit.project=app'),
      );
      expect(
        session.childEnvironment.containsKey('OTEL_EXPORTER_OTLP_ENDPOINT'),
        isFalse,
      );

      // chunks cortados no meio da linha e com \r\n (PTY)
      session
        ..add('flutter: {"level":"info","msg":"app sta')
        ..add(
          'rted"}\r\nflutter: RangeError (index): Index out of range: index 3, length 2\r\n',
        )
        ..add(
          'flutter: #0      CartService.add (package:app/cart/cart_service.dart:87:22)\r\n',
        )
        ..add('tail sem newline');
      await session.close(exitCode: 0);

      final store = await registry.forWorkspace('ws-mono');
      final run = (await store.run(session.runId))!;
      expect(run.exitCode, 0);
      expect(run.project, 'app');
      expect(run.taskKey, 'flutter:run');
      expect(run.key, 'name:app');

      final events = await store.events(TelemetryQuery(runId: run.id));
      expect(events.map((e) => e.body), [
        'app started',
        'Index out of range: index 3, length 2',
        'tail sem newline',
      ]);
      expect(
        events[1].error!.projectFrame!.location,
        'lib/cart/cart_service.dart:87',
      );
      expect(events[1].rawLineOffset, 1);
      expect(events[0].stream, TelemetryStream.out);

      final cases = await store.cases(const TelemetryQuery());
      expect(cases.single.project, 'app');
      expect(cases.single.isNew, isTrue);
    },
  );

  test('telemetry:false e cwd fora dos workspaces não abrem run', () async {
    const off = TaskDefinition(
      id: 'x',
      label: 'x',
      cwd: '/ws/shop/app',
      command: 'noisy',
      telemetryEnabled: false,
    );
    expect(await ingest.openTaskRun(off, command: 'noisy'), isNull);
    const foreign = TaskDefinition(
      id: 'y',
      label: 'y',
      cwd: '/tmp/other',
      command: 'x',
    );
    expect(await ingest.openTaskRun(foreign, command: 'x'), isNull);
    expect(opened, isEmpty);
  });

  test('restart = run novo com a mesma chave; "new" só no primeiro', () async {
    final s1 = (await ingest.openTaskRun(appTask, command: 'flutter run'))!;
    s1.add('Error: boom\n    at f (/ws/shop/app/lib/a.js:1:1)\n');
    await s1.close(exitCode: 1);
    final s2 = (await ingest.openTaskRun(appTask, command: 'flutter run'))!;
    s2.add('Error: boom\n    at f (/ws/shop/app/lib/a.js:1:1)\n');
    await s2.close(exitCode: 1);

    final store = await registry.forWorkspace('ws-mono');
    final runs = await store.runs(key: 'name:app');
    expect(runs.map((r) => r.id), [s2.runId, s1.runId]);
    final c = (await store.cases(const TelemetryQuery())).single;
    expect(c.count, 2);
    expect(c.isNew, isFalse);
    expect(c.location, 'lib/a.js:1');
  });

  test('notices: um aviso por lote com os fingerprints de erro', () async {
    final got = <TelemetryErrorNotice>[];
    final sub = ingest.notices.listen(got.add);
    final s1 = (await ingest.openTaskRun(appTask, command: 'flutter run'))!;
    s1.add('{"level":"info","msg":"ok"}\n');
    s1.add('Error: boom\n    at f (/ws/shop/app/lib/a.js:1:1)\n');
    s1.add('Error: boom\n    at f (/ws/shop/app/lib/a.js:1:1)\n');
    await s1.close(exitCode: 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(got, isNotEmpty);
    final all = got.expand((n) => n.fingerprints).toSet();
    expect(all, hasLength(1));
    expect(got.first.workspaceId, 'ws-mono');
    expect(got.first.project, 'app');
    expect(got.first.runId, s1.runId);
  });

  test(
    'dedup: mesmo fingerprint por stdout e por evento direto conta uma vez',
    () async {
      final s1 = (await ingest.openTaskRun(appTask, command: 'flutter run'))!;
      s1.add('Error: same\n    at f (/ws/shop/app/lib/a.js:1:1)\n');
      // simula o VM Service entregando o mesmo erro logo depois
      final store = await registry.forWorkspace('ws-mono');
      final parsed = (await store.append(const []));
      expect(parsed, isEmpty);
      final err = TelemetryError(
        type: 'Error',
        message: 'same',
        frames: const [
          TelemetryFrame(raw: '', file: 'lib/a.js', line: 1, inProject: true),
        ],
      );
      (s1 as dynamic).addEvents([
        TelemetryEvent(
          runId: s1.runId,
          ts: DateTime.now(),
          stream: TelemetryStream.vm,
          severity: TelemetrySeverity.error,
          body: 'same',
          error: err,
        ),
      ]);
      await s1.close(exitCode: 1);
      final c = (await store.cases(const TelemetryQuery())).single;
      expect(c.count, 1);
    },
  );
}
