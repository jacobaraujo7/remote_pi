import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_runtime_variable.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/cockpit/domain/services/http_script_session.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Aba de baixo da view `.http`.
enum HttpResponsePane { response, headers, tests }

enum HttpResponseFormat { json, html, xml, javascript, raw, hex, base64 }

enum HttpRequestRunStatus { idle, loading, success, error }

class HttpRequestOutcome {
  HttpRequestRunStatus status = HttpRequestRunStatus.idle;
  HttpRequestRunStatus? statusBeforeLoading;
  HttpResponseResult? result;
  HttpRequestError? error;
  String? scriptError;
  List<String> logs = const [];
  List<HttpScriptTest> tests = const [];
  Map<String, String> requestVariables = const {};
  final Map<HttpResponseFormat, Set<int>> responseFolds = {};
}

/// Estado de VISUALIZAÇÃO de uma tab `.http` que precisa sobreviver ao
/// re-mount do widget (mover a tab de pane destrói o `State` — mesma razão do
/// [DbTabViewState] no `DatabaseViewModel`). Mutável; o widget lê/escreve
/// direto.
class HttpTabState extends ChangeNotifier {
  final Map<String, Map<String, HttpRuntimeVariable>> _runtimeVariables = {};

  Map<String, HttpRuntimeVariable> runtimeVariablesFor(String? environment) =>
      Map.unmodifiable(_runtimeVariables[environment ?? ''] ?? const {});

  Map<String, String> runtimeValuesFor(String? environment) => {
    for (final entry in runtimeVariablesFor(environment).entries)
      entry.key: entry.value.value,
  };

  void setRuntimeVariable(
    String? environment,
    String name,
    HttpRuntimeVariable value,
  ) {
    if (value.validationError != null) return;
    _runtimeVariables.putIfAbsent(environment ?? '', () => {})[name] = value;
    notifyListeners();
  }

  void clearRuntimeVariable(String? environment, String name) {
    if (_runtimeVariables[environment ?? '']?.remove(name) != null) {
      notifyListeners();
    }
  }

  List<HttpRequestOutcome> outcomes = [];
  final Set<int> foldedStarts = {};
  List<HttpRequestSpec> _requests = [];
  final List<({HttpRequestSpec request, HttpRequestOutcome outcome})>
  _detached = [];
  int selectedRequest = 0;
  bool isRunning = false;
  String? _source;
  int _sourceGeneration = 0;
  double split = 0.5;
  HttpResponsePane pane = HttpResponsePane.response;
  HttpResponseFormat? format;

  HttpRequestOutcome? get selectedOutcome =>
      selectedRequest >= 0 && selectedRequest < outcomes.length
      ? outcomes[selectedRequest]
      : null;

  void clearSelectedResponse() {
    if (isRunning ||
        selectedRequest < 0 ||
        selectedRequest >= outcomes.length) {
      return;
    }
    outcomes[selectedRequest] = HttpRequestOutcome();
    pane = HttpResponsePane.response;
    notifyListeners();
  }

  /// Mantém o último resultado de cada seção enquanto o arquivo é editado.
  /// Uma linha de request temporariamente inválida não descarta a resposta.
  void syncSource(String source, int requestCount) {
    if (_source == source && outcomes.length == requestCount) return;
    if (_source != null && _source != source) foldedStarts.clear();
    _source = source;
    _sourceGeneration++;
    final next = HttpDocument.parse(source).requests;
    if (next.isEmpty) {
      for (final outcome in outcomes) {
        if (outcome.status == HttpRequestRunStatus.loading) {
          outcome.status =
              outcome.statusBeforeLoading ?? HttpRequestRunStatus.idle;
          outcome.statusBeforeLoading = null;
        }
      }
      notifyListeners();
      return;
    }

    final previous = <({HttpRequestSpec request, HttpRequestOutcome outcome})>[
      for (var i = 0; i < _requests.length && i < outcomes.length; i++)
        (request: _requests[i], outcome: outcomes[i]),
      ..._detached,
    ];
    final assigned = List<HttpRequestOutcome?>.filled(next.length, null);
    final matchedRequest = List<HttpRequestSpec?>.filled(next.length, null);
    final used = <int>{};

    void match(bool Function(HttpRequestSpec, HttpRequestSpec) matches) {
      for (var i = 0; i < next.length; i++) {
        if (assigned[i] != null) continue;
        for (var j = 0; j < previous.length; j++) {
          if (used.contains(j) || !matches(previous[j].request, next[i])) {
            continue;
          }
          assigned[i] = previous[j].outcome;
          matchedRequest[i] = previous[j].request;
          used.add(j);
          break;
        }
      }
    }

    // Primeiro identidades fortes, depois o índice para uma URL ainda em edição.
    match(
      (old, current) =>
          old.method == current.method &&
          old.url == current.url &&
          old.name == current.name,
    );
    match(
      (old, current) => old.method == current.method && old.url == current.url,
    );
    match(
      (old, current) =>
          old.name.isNotEmpty &&
          old.name == current.name &&
          old.method == current.method,
    );
    for (var i = 0; i < next.length; i++) {
      if (assigned[i] != null || i >= _requests.length || used.contains(i)) {
        continue;
      }
      assigned[i] = previous[i].outcome;
      matchedRequest[i] = previous[i].request;
      used.add(i);
    }

    final selectedOutcomeBefore = selectedOutcome;
    for (final item in previous) {
      if (item.outcome.status == HttpRequestRunStatus.loading) {
        item.outcome.status =
            item.outcome.statusBeforeLoading ?? HttpRequestRunStatus.idle;
        item.outcome.statusBeforeLoading = null;
      }
    }
    _detached
      ..clear()
      ..addAll([
        for (var i = 0; i < previous.length; i++)
          if (!used.contains(i) &&
              previous[i].outcome.status != HttpRequestRunStatus.idle)
            previous[i],
      ]);
    outcomes = [
      for (final outcome in assigned) outcome ?? HttpRequestOutcome(),
    ];
    for (var i = 0; i < next.length; i++) {
      final before = matchedRequest[i];
      if (before != null &&
          (before.preScript != next[i].preScript ||
              before.postScript != next[i].postScript)) {
        outcomes[i].requestVariables = const {};
      }
    }
    _requests = next;
    for (final outcome in outcomes) {
      if (outcome.status == HttpRequestRunStatus.loading) {
        outcome.status =
            outcome.statusBeforeLoading ?? HttpRequestRunStatus.idle;
        outcome.statusBeforeLoading = null;
      }
    }
    final selectedIndex = outcomes.indexWhere(
      (outcome) => identical(outcome, selectedOutcomeBefore),
    );
    selectedRequest = selectedIndex >= 0
        ? selectedIndex
        : selectedRequest.clamp(0, next.length - 1);
    notifyListeners();
  }

  /// Executa em série. Um erro não impede as seções seguintes de rodar.
  Future<void> runRequests(
    HttpRequestRunner runner,
    List<HttpRequestSpec> requests, {
    required String baseDir,
    int? onlyIndex,
    HttpDocument? document,
    Map<String, String> environment = const {},
    Map<String, String> overrides = const {},
  }) async {
    if (isRunning || requests.length != outcomes.length) return;
    isRunning = true;
    notifyListeners();
    final generation = _sourceGeneration;
    try {
      final indexes = onlyIndex == null
          ? Iterable<int>.generate(requests.length)
          : <int>[onlyIndex];
      for (final index in indexes) {
        if (generation != _sourceGeneration ||
            index < 0 ||
            index >= outcomes.length) {
          break;
        }
        final outcome = outcomes[index];
        selectedRequest = index;
        outcome.statusBeforeLoading = outcome.status;
        outcome
          ..status = HttpRequestRunStatus.loading
          ..error = null
          ..scriptError = null
          ..logs = const []
          ..tests = const [];
        notifyListeners();
        try {
          if (document != null) {
            final execution = await HttpScriptSession.shared.run(
              runner,
              document,
              requests[index],
              baseDir: baseDir,
              environment: environment,
              overrides: overrides,
            );
            if (generation != _sourceGeneration) break;
            outcome.responseFolds.clear();
            outcome
              ..result = execution.response
              ..error = execution.transportError
              ..scriptError = execution.scriptError
              ..logs = execution.logs
              ..tests = execution.tests
              ..requestVariables = execution.variables
              ..status = execution.failed
                  ? HttpRequestRunStatus.error
                  : HttpRequestRunStatus.success
              ..statusBeforeLoading = null;
            notifyListeners();
            continue;
          }
          final sent = await runner.send(requests[index], baseDir: baseDir);
          if (generation != _sourceGeneration) break;
          outcome.responseFolds.clear();
          switch (sent) {
            case Success(:final value):
              outcome.result = value;
              outcome.status = value.statusCode >= 400
                  ? HttpRequestRunStatus.error
                  : HttpRequestRunStatus.success;
            case Failure(:final error):
              outcome.result = null;
              outcome.error = error;
              outcome.status = HttpRequestRunStatus.error;
          }
        } catch (error) {
          if (generation != _sourceGeneration) break;
          outcome.result = null;
          outcome.error = HttpRequestError(
            HttpRequestErrorKind.connectionFailed,
            detail: '$error',
          );
          outcome.status = HttpRequestRunStatus.error;
        }
        outcome.statusBeforeLoading = null;
        notifyListeners();
      }
    } finally {
      isRunning = false;
      notifyListeners();
    }
  }
}

/// Estado das tabs `.http` + o motor de execução compartilhado com a CLI
/// (`cockpit http run`). Page-scoped, provido no `cockpit_module` — espelha o
/// papel do `DatabaseViewModel` para o `.dbq`.
class HttpViewModel extends ChangeNotifier {
  HttpViewModel(this.runner);

  /// Motor compartilhado tab/CLI.
  final HttpRequestRunner runner;

  final _tabStates = <String, HttpTabState>{};
  final _statesByPath = <String, HttpTabState>{};

  /// O estado de arquivos reais é indexado também pelo caminho: fechar e
  /// reabrir a aba não perde a resposta durante a vida do Cockpit.
  HttpTabState tabStateFor(
    String sessionId, {
    String? projectId,
    String? path,
  }) {
    final key = projectId == null || path == null
        ? null
        : '$projectId\u0000$path';
    final state =
        _tabStates[sessionId] ??
        (key == null ? null : _statesByPath[key]) ??
        HttpTabState();
    _tabStates[sessionId] = state;
    if (key != null) _statesByPath[key] = state;
    return state;
  }
}
