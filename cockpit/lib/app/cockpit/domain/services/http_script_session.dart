import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:quickjs_engine/quickjs_engine.dart';

class HttpScriptTest {
  const HttpScriptTest(this.name, this.passed, this.message);
  final String name;
  final bool passed;
  final String? message;
}

class HttpScriptExecution {
  const HttpScriptExecution({
    this.response,
    this.transportError,
    this.scriptError,
    this.logs = const [],
    this.tests = const [],
  });

  final HttpResponseResult? response;
  final HttpRequestError? transportError;
  final String? scriptError;
  final List<String> logs;
  final List<HttpScriptTest> tests;
  bool get failed =>
      transportError != null ||
      scriptError != null ||
      response?.statusCode != null && response!.statusCode >= 400 ||
      tests.any((test) => !test.passed);
}

/// Estado de `client.global` durante a vida do app. Compartilhado pela aba e
/// pela CLI; nenhuma variável é gravada em disco.
class HttpScriptSession {
  static final HttpScriptSession shared = HttpScriptSession();
  final Map<String, String> _globals = {};

  Future<HttpScriptExecution> run(
    HttpRequestRunner transport,
    HttpDocument document,
    HttpRequestSpec request, {
    required String baseDir,
    Map<String, String> environment = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final vars = <String, String>{};
    final logs = <String>[];
    final tests = <HttpScriptTest>[];

    if (request.preScript != null) {
      final pre = await _execute(request.preScript!, _globals, vars);
      _globals.addAll(pre.globals);
      vars.addAll(pre.variables);
      logs.addAll(pre.logs);
      tests.addAll(pre.tests);
      if (pre.error != null) {
        return HttpScriptExecution(
          scriptError: 'Pre-request: ${pre.error}',
          logs: logs,
          tests: tests,
        );
      }
    }

    final resolved = document.resolveRequest(
      request,
      environment: environment,
      globals: _globals,
      requestVariables: vars,
    );
    final sent = await transport.send(
      resolved,
      baseDir: baseDir,
      timeout: timeout,
    );
    switch (sent) {
      case Failure(:final error):
        return HttpScriptExecution(
          transportError: error,
          logs: logs,
          tests: tests,
        );
      case Success(:final value):
        if (request.postScript != null) {
          Object? body = value.bodyText;
          try {
            body = jsonDecode(value.bodyText);
          } on FormatException {
            // Corpo textual permanece uma string.
          }
          final post = await _execute(
            request.postScript!,
            _globals,
            vars,
            response: {
              'body': body,
              'status': value.statusCode,
              'headers': {
                for (final h in value.headers) h.name.toLowerCase(): h.value,
              },
            },
          );
          _globals.addAll(post.globals);
          logs.addAll(post.logs);
          tests.addAll(post.tests);
          return HttpScriptExecution(
            response: value,
            scriptError: post.error == null
                ? null
                : 'Post-request: ${post.error}',
            logs: logs,
            tests: tests,
          );
        }
        return HttpScriptExecution(response: value, logs: logs, tests: tests);
    }
  }
}

typedef _ScriptResult = ({
  Map<String, String> globals,
  Map<String, String> variables,
  List<String> logs,
  List<HttpScriptTest> tests,
  String? error,
});

Future<_ScriptResult> _execute(
  String script,
  Map<String, String> globals,
  Map<String, String> variables, {
  Map<String, Object?>? response,
}) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_scriptWorker, [
    port.sendPort,
    script,
    globals,
    variables,
    response,
  ]);
  try {
    final raw = await port.first.timeout(const Duration(seconds: 2));
    final data = Map<String, dynamic>.from(raw as Map);
    return (
      globals: Map<String, String>.from(data['globals'] as Map? ?? {}),
      variables: Map<String, String>.from(data['variables'] as Map? ?? {}),
      logs: List<String>.from(data['logs'] as List? ?? []),
      tests: [
        for (final item in data['tests'] as List? ?? [])
          HttpScriptTest(
            '${(item as Map)['name']}',
            item['passed'] == true,
            item['message']?.toString(),
          ),
      ],
      error: data['error']?.toString(),
    );
  } on TimeoutException {
    return (
      globals: globals,
      variables: variables,
      logs: <String>[],
      tests: <HttpScriptTest>[],
      error: 'Script exceeded the 2 second time limit',
    );
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _scriptWorker(List<dynamic> args) {
  final send = args[0] as SendPort;
  final script = args[1] as String;
  final globals = args[2] as Map<String, String>;
  final variables = args[3] as Map<String, String>;
  final response = args[4] as Map<String, Object?>?;
  final js = QuickJsRuntime2(
    memoryLimit: 64 * 1024 * 1024,
    stackSize: 512 * 1024,
  );
  try {
    final setup =
        '''
      globalThis.__state = {
        globals: ${jsonEncode(globals)}, variables: ${jsonEncode(variables)},
        logs: [], tests: [], response: ${jsonEncode(response)}
      };
      const __value = value => typeof value === 'string' ? value :
        (value === undefined ? 'undefined' : JSON.stringify(value));
      globalThis.request = {variables: {
        set: (name, value) => { __state.variables[String(name)] = __value(value); },
        get: name => __state.variables[String(name)]
      }};
      globalThis.client = {
        global: {
          set: (name, value) => { __state.globals[String(name)] = __value(value); },
          get: name => __state.globals[String(name)]
        },
        test: (name, fn) => { __state.tests.push({name: String(name), fn}); },
        assert: (condition, message) => {
          if (!condition) throw new Error(message || 'Assertion failed');
        },
        log: (...values) => __state.logs.push(values.map(__value).join(' '))
      };
      globalThis.console = {log: (...values) => client.log(...values)};
      if (__state.response !== null) {
        globalThis.response = {
          body: __state.response.body, status: __state.response.status,
          headers: {valueOf: name => __state.response.headers[String(name).toLowerCase()]}
        };
      }
    ''';
    final setupResult = js.evaluate(setup);
    if (setupResult.isError) throw StateError(setupResult.stringResult);
    final runResult = js.evaluate(script, sourceUrl: 'request.http');
    final error = runResult.isError ? runResult.stringResult : null;
    final snapshot = js.evaluate('''
      const __results = __state.tests.map(test => {
        try { test.fn(); return {name: test.name, passed: true}; }
        catch (error) { return {name: test.name, passed: false, message: String(error)}; }
      });
      JSON.stringify({globals: __state.globals, variables: __state.variables,
        logs: __state.logs, tests: __results});
    ''');
    if (snapshot.isError) throw StateError(snapshot.stringResult);
    final data = jsonDecode(snapshot.stringResult) as Map<String, dynamic>;
    send.send({...data, 'error': error});
  } catch (error) {
    send.send({
      'globals': globals,
      'variables': variables,
      'logs': <String>[],
      'tests': <Object>[],
      'error': '$error',
    });
  } finally {
    js.dispose();
  }
}
