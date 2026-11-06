import 'dart:async';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/http_viewmodel.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubRunner implements HttpRequestRunner {
  @override
  Future<Result<HttpResponseResult, HttpRequestError>> send(
    HttpRequestSpec spec, {
    required String baseDir,
    Duration timeout = const Duration(seconds: 30),
    bool followRedirects = true,
  }) async => Failure(const HttpRequestError(HttpRequestErrorKind.noRequest));
}

HttpResponseResult _result(String body, {String type = 'application/json'}) =>
    HttpResponseResult(
      statusCode: 200,
      reasonPhrase: 'OK',
      headers: [(name: 'content-type', value: type)],
      bodyBytes: Uint8List.fromList(body.codeUnits),
      elapsed: const Duration(milliseconds: 12),
      requestLabel: 'GET /x',
    );

class _ControlledRunner implements HttpRequestRunner {
  final sent = <HttpRequestSpec>[];
  final pending = <Completer<Result<HttpResponseResult, HttpRequestError>>>[];

  @override
  Future<Result<HttpResponseResult, HttpRequestError>> send(
    HttpRequestSpec spec, {
    required String baseDir,
    Duration timeout = const Duration(seconds: 30),
    bool followRedirects = true,
  }) {
    sent.add(spec);
    final completer = Completer<Result<HttpResponseResult, HttpRequestError>>();
    pending.add(completer);
    return completer.future;
  }

  void succeed(int index, {int status = 200}) => pending[index].complete(
    Success(
      HttpResponseResult(
        statusCode: status,
        reasonPhrase: 'OK',
        headers: const [],
        bodyBytes: Uint8List(0),
        elapsed: const Duration(milliseconds: 1),
        requestLabel: sent[index].label,
      ),
    ),
  );

  void fail(int index) => pending[index].complete(
    const Failure(HttpRequestError(HttpRequestErrorKind.timeout)),
  );
}

void main() {
  test('estado da resposta sobrevive a re-mount e reabertura do arquivo', () {
    final vm = HttpViewModel(_StubRunner());
    final a = vm.tabStateFor(
      'tab-a',
      projectId: 'project',
      path: '/api/login.http',
    );
    a.split = 0.3;
    expect(identical(vm.tabStateFor('tab-a'), a), isTrue);
    expect(vm.tabStateFor('tab-a').split, 0.3);
    expect(identical(vm.tabStateFor('tab-b'), a), isFalse);
    expect(
      identical(
        vm.tabStateFor(
          'reopened',
          projectId: 'project',
          path: '/api/login.http',
        ),
        a,
      ),
      isTrue,
    );
  });

  group('HttpResponseResult', () {
    test('JSON válido vira corpo indentado', () {
      expect(_result('{"a":1}').prettyJson, '{\n  "a": 1\n}');
    });

    test('Content-Type mentindo cai no texto cru', () {
      expect(_result('not json').prettyJson, isNull);
      expect(_result('not json').bodyText, 'not json');
    });

    test('toJson manda json decodificado quando dá, senão body', () {
      expect(_result('{"a":1}').toJson()['json'], {'a': 1});
      final plain = _result('hello', type: 'text/plain').toJson();
      expect(plain['body'], 'hello');
      expect(plain.containsKey('json'), isFalse);
      expect(plain['status'], 200);
      expect(plain['elapsedMs'], 12);
    });

    test('headerValue é case-insensitive', () {
      expect(_result('{}').headerValue('Content-Type'), 'application/json');
      expect(_result('{}').isJson, isTrue);
    });
  });

  const source =
      '### first\nGET https://example.com/1\n'
      '###\nGET https://example.com/2\n'
      '### third\nGET https://example.com/3\n';
  final requests = HttpDocument.parse(source).requests;

  test(
    'Run percorre as seções em ordem, selecionando loading e resultado',
    () async {
      final state = HttpTabState()..syncSource(source, requests.length);
      final runner = _ControlledRunner();
      final events = <(int, List<HttpRequestRunStatus>)>[];
      void changed() => events.add((
        state.selectedRequest,
        state.outcomes.map((e) => e.status).toList(),
      ));
      state.addListener(changed);

      final run = state.runRequests(runner, requests, baseDir: '/api');
      expect(runner.sent.map((e) => e.url), ['https://example.com/1']);
      expect(events.last.$1, 0);
      expect(events.last.$2, [
        HttpRequestRunStatus.loading,
        HttpRequestRunStatus.idle,
        HttpRequestRunStatus.idle,
      ]);

      runner.succeed(0);
      await Future<void>.delayed(Duration.zero);
      expect(runner.sent.map((e) => e.url), [
        'https://example.com/1',
        'https://example.com/2',
      ]);
      expect(events.last.$1, 1);
      expect(events.last.$2[0], HttpRequestRunStatus.success);
      expect(events.last.$2[1], HttpRequestRunStatus.loading);

      runner.fail(1);
      await Future<void>.delayed(Duration.zero);
      expect(runner.sent.length, 3);
      expect(events.last.$1, 2);
      expect(events.last.$2[1], HttpRequestRunStatus.error);
      expect(events.last.$2[2], HttpRequestRunStatus.loading);

      runner.succeed(2, status: 404);
      await run;
      expect(state.outcomes.map((e) => e.status), [
        HttpRequestRunStatus.success,
        HttpRequestRunStatus.error,
        HttpRequestRunStatus.error,
      ]);
      expect(state.outcomes[2].result?.statusCode, 404);
    },
  );

  test('Run individual preserva os outros resultados', () async {
    final state = HttpTabState()..syncSource(source, requests.length);
    final runner = _ControlledRunner();
    final first = state.runRequests(
      runner,
      requests,
      baseDir: '/api',
      onlyIndex: 0,
    );
    runner.succeed(0);
    await first;

    final second = state.runRequests(
      runner,
      requests,
      baseDir: '/api',
      onlyIndex: 2,
    );
    expect(state.selectedRequest, 2);
    expect(state.outcomes[0].status, HttpRequestRunStatus.success);
    expect(state.outcomes[1].status, HttpRequestRunStatus.idle);
    runner.fail(1);
    await second;
    expect(state.outcomes[0].status, HttpRequestRunStatus.success);
    expect(state.outcomes[2].status, HttpRequestRunStatus.error);
  });

  test('limpar resposta zera apenas o resultado selecionado', () {
    final state = HttpTabState()..syncSource(source, requests.length);
    state.outcomes[0]
      ..status = HttpRequestRunStatus.success
      ..result = _result('{"ok":true}');
    state.outcomes[1]
      ..status = HttpRequestRunStatus.error
      ..error = const HttpRequestError(HttpRequestErrorKind.timeout);
    state.selectedRequest = 1;
    state.pane = HttpResponsePane.tests;

    state.clearSelectedResponse();

    expect(state.outcomes[0].status, HttpRequestRunStatus.success);
    expect(state.outcomes[0].result, isNotNull);
    expect(state.outcomes[1].status, HttpRequestRunStatus.idle);
    expect(state.outcomes[1].error, isNull);
    expect(state.pane, HttpResponsePane.response);
  });

  test('editar o documento mantém as respostas anteriores', () async {
    final state = HttpTabState()..syncSource(source, requests.length);
    final runner = _ControlledRunner();
    final run = state.runRequests(
      runner,
      requests,
      baseDir: '/api',
      onlyIndex: 0,
    );
    runner.succeed(0);
    await run;
    final response = state.outcomes[0].result;

    state.syncSource('$source\n# changed', requests.length);
    expect(state.outcomes[0].result, same(response));
    expect(state.outcomes[0].status, HttpRequestRunStatus.success);

    state.syncSource(
      source.replaceFirst('example.com/1', 'example.com/edited'),
      requests.length,
    );
    expect(state.outcomes[0].result, same(response));

    state.syncSource('### first\nGET \n', 0);
    expect(state.selectedOutcome?.result, same(response));
    state.syncSource(source, requests.length);
    expect(state.outcomes[0].result, same(response));
  });

  test('inserir uma seção mantém as respostas das seções existentes', () {
    final state = HttpTabState()..syncSource(source, requests.length);
    final response = _result('{"ok":true}');
    state.outcomes[1]
      ..result = response
      ..status = HttpRequestRunStatus.success;
    state.selectedRequest = 1;
    final inserted = '### new\nGET https://example.com/new\n$source';

    state.syncSource(inserted, 4);

    expect(state.outcomes[0].status, HttpRequestRunStatus.idle);
    expect(state.outcomes[2].result, same(response));
    expect(state.selectedRequest, 2);
  });

  test('remover e restaurar uma seção recupera sua última resposta', () {
    final state = HttpTabState()..syncSource(source, requests.length);
    final response = _result('previous');
    state.outcomes[1]
      ..result = response
      ..status = HttpRequestRunStatus.success;
    final removed = source.replaceFirst('###\nGET https://example.com/2\n', '');
    state.syncSource(removed, 2);
    state.syncSource(source, 3);
    expect(state.outcomes[1].result, same(response));
  });

  test('editar durante nova execução preserva a resposta anterior', () async {
    final state = HttpTabState()..syncSource(source, requests.length);
    final response = _result('previous');
    state.outcomes[0]
      ..result = response
      ..status = HttpRequestRunStatus.success;
    final runner = _ControlledRunner();
    final run = state.runRequests(
      runner,
      requests,
      baseDir: '/api',
      onlyIndex: 0,
    );
    expect(state.outcomes[0].status, HttpRequestRunStatus.loading);
    expect(state.outcomes[0].result, same(response));

    state.syncSource('$source\n# edit', requests.length);
    expect(state.outcomes[0].status, HttpRequestRunStatus.success);
    expect(state.outcomes[0].result, same(response));
    runner.succeed(0);
    await run;
    expect(state.outcomes[0].result, same(response));
  });
}
