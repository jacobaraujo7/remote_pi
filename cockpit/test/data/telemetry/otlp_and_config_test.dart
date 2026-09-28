import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/telemetry/otlp_receiver.dart';
import 'package:cockpit/app/cockpit/data/telemetry/telemetry_workspace_config.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sink implements OtlpSink {
  final got = <String, List<TelemetryEvent>>{};

  @override
  void addEvents(String runId, List<TelemetryEvent> events) =>
      got.putIfAbsent(runId, () => []).addAll(events);

  @override
  List<String> projectRootsOf(String runId) => const ['/ws/backend'];

  @override
  String? runFor({String? runId, String? serviceName}) {
    if (runId == 'r_1') return 'r_1';
    if (serviceName == 'api') return 'r_api';
    return null;
  }
}

Future<int> post(String endpoint, String path, Object body) async {
  final c = HttpClient();
  final req = await c.postUrl(Uri.parse('$endpoint$path'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  await res.drain<void>();
  c.close();
  return res.statusCode;
}

Map<String, Object?> kv(String k, Object v) => {
  'key': k,
  'value': v is int ? {'intValue': '$v'} : {'stringValue': '$v'},
};

void main() {
  group('OTLP receiver', () {
    late OtlpReceiver rx;
    late _Sink sink;

    setUp(() async {
      sink = _Sink();
      rx = OtlpReceiver(sink);
      await rx.start();
      expect(rx.endpoint, startsWith('http://127.0.0.1:'));
    });
    tearDown(() => rx.stop());

    test('logs: roteia por cockpit.run, mapeia severidade e exceção', () async {
      final code = await post(rx.endpoint, '/v1/logs', {
        'resourceLogs': [
          {
            'resource': {
              'attributes': [
                kv('cockpit.run', 'r_1'),
                kv('service.name', 'api'),
              ],
            },
            'scopeLogs': [
              {
                'logRecords': [
                  {
                    'timeUnixNano': '1758632475810000000',
                    'severityNumber': 17,
                    'body': {'stringValue': 'db connect failed'},
                    'traceId': 'abc',
                    'attributes': [
                      kv('exception.type', 'Error'),
                      kv(
                        'exception.message',
                        'connect ECONNREFUSED 127.0.0.1:5432',
                      ),
                      kv(
                        'exception.stacktrace',
                        'Error: connect ECONNREFUSED\n    at pool.connect (/ws/backend/src/db.ts:12:9)',
                      ),
                      kv('code', 'ECONNREFUSED'),
                    ],
                  },
                  {
                    'severityNumber': 9,
                    'body': {'stringValue': 'listening'},
                    'attributes': [kv('port', 3000)],
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(code, 200);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final evs = sink.got['r_1']!;
      expect(evs, hasLength(2));
      final err = evs.first;
      expect(err.severity, TelemetrySeverity.error);
      expect(err.stream, TelemetryStream.otlp);
      expect(err.error!.projectFrame!.location, 'src/db.ts:12');
      expect(err.attrs['code'], 'ECONNREFUSED');
      expect(err.attrs['service'], 'api');
      expect(err.fingerprint, isNotNull);
      expect(err.traceId, 'abc');
      expect(err.ts.millisecondsSinceEpoch, 1758632475810);
      expect(evs.last.severity, TelemetrySeverity.info);
      expect(evs.last.attrs['port'], 3000);
    });

    test(
      'traces: span com status erro vira caso; sem run conhecido é descartado',
      () async {
        await post(rx.endpoint, '/v1/traces', {
          'resourceSpans': [
            {
              'resource': {
                'attributes': [kv('service.name', 'api')],
              },
              'scopeSpans': [
                {
                  'spans': [
                    {
                      'traceId': 't1',
                      'spanId': 's1',
                      'name': 'POST /orders',
                      'startTimeUnixNano': '1000000000',
                      'endTimeUnixNano': '1812000000',
                      'status': {'code': 2, 'message': 'boom'},
                      'attributes': [kv('http.response.status_code', 500)],
                    },
                  ],
                },
              ],
            },
            {
              'resource': {
                'attributes': [kv('service.name', 'unknown-svc')],
              },
              'scopeSpans': [
                {
                  'spans': [
                    {
                      'name': 'x',
                      'startTimeUnixNano': '1',
                      'endTimeUnixNano': '2',
                    },
                  ],
                },
              ],
            },
          ],
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(sink.got.keys, ['r_api']);
        final e = sink.got['r_api']!.single;
        expect(e.error!.type, 'HTTP 500');
        expect(e.body, 'POST /orders 500 812ms');
        expect(e.attrs['duration_ms'], 812);
        expect(e.traceId, 't1');
      },
    );

    test('método/tipo errados não derrubam o servidor', () async {
      final c = HttpClient();
      final r1 = await (await c.getUrl(
        Uri.parse('${rx.endpoint}/v1/logs'),
      )).close();
      await r1.drain<void>();
      expect(r1.statusCode, 405);
      final req = await c.postUrl(Uri.parse('${rx.endpoint}/v1/logs'));
      req.headers.contentType = ContentType('application', 'x-protobuf');
      req.add([1, 2, 3]);
      final r2 = await req.close();
      await r2.drain<void>();
      expect(r2.statusCode, 415);
      c.close();
    });
  });

  group('telemetry.json', () {
    test('parse com comentários, proxy e regexes inválidas ignoradas', () {
      final cfg = TelemetryWorkspaceConfig.parse('''
{
  // prefixos extras
  "unwrap": ["^api-1\\\\s*\\\\| ", "[invalid"],
  "ignore": ["DeprecationWarning: punycode"],
  "projectFrames": ["packages/"],
  "proxy": { "listen": 3100, "upstream": "http://127.0.0.1:3000" }
}
''');
      expect(cfg.unwrap, hasLength(1));
      expect(
        cfg.ignore.single.hasMatch('DeprecationWarning: punycode is old'),
        isTrue,
      );
      expect(cfg.projectFrames, ['packages/']);
      expect(cfg.proxy!.listen, 3100);
      expect(cfg.proxy!.upstream.port, 3000);
    });

    test('ausente ou inválido = vazio', () {
      expect(TelemetryWorkspaceConfig.load('/nope/never').proxy, isNull);
      expect(TelemetryWorkspaceConfig.parse('not json').unwrap, isEmpty);
      expect(
        TelemetryWorkspaceConfig.parse('{"proxy":{"listen":"x"}}').proxy,
        isNull,
      );
    });
  });
}
