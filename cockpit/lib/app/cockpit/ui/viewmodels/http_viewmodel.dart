import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Aba de baixo da view `.http`.
enum HttpResponsePane { body, headers, raw }

enum HttpRequestRunStatus { idle, loading, success, error }

class HttpRequestOutcome {
  HttpRequestRunStatus status = HttpRequestRunStatus.idle;
  HttpResponseResult? result;
  HttpRequestError? error;
}

/// Estado de VISUALIZAÇÃO de uma tab `.http` que precisa sobreviver ao
/// re-mount do widget (mover a tab de pane destrói o `State` — mesma razão do
/// [DbTabViewState] no `DatabaseViewModel`). Mutável; o widget lê/escreve
/// direto.
class HttpTabState extends ChangeNotifier {
  List<HttpRequestOutcome> outcomes = [];
  int selectedRequest = 0;
  bool isRunning = false;
  String? _source;
  int _sourceGeneration = 0;
  double split = 0.5;
  HttpResponsePane pane = HttpResponsePane.body;

  /// Corpo JSON mostrado cru em vez de indentado.
  bool rawBody = false;

  HttpRequestOutcome? get selectedOutcome =>
      selectedRequest >= 0 && selectedRequest < outcomes.length
      ? outcomes[selectedRequest]
      : null;

  /// Resultados só pertencem ao texto de onde vieram; editar o arquivo
  /// invalida a associação entre índices e seções.
  void syncSource(String source, int requestCount) {
    if (_source == source && outcomes.length == requestCount) return;
    _source = source;
    _sourceGeneration++;
    outcomes = List.generate(requestCount, (_) => HttpRequestOutcome());
    selectedRequest = selectedRequest.clamp(
      0,
      requestCount > 0 ? requestCount - 1 : 0,
    );
    notifyListeners();
  }

  /// Executa em série. Um erro não impede as seções seguintes de rodar.
  Future<void> runRequests(
    HttpRequestRunner runner,
    List<HttpRequestSpec> requests, {
    required String baseDir,
    int? onlyIndex,
  }) async {
    if (isRunning || requests.length != outcomes.length) return;
    isRunning = true;
    notifyListeners();
    final generation = _sourceGeneration;
    try {
      if (onlyIndex == null) {
        outcomes = List.generate(requests.length, (_) => HttpRequestOutcome());
        notifyListeners();
      }
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
        outcome
          ..status = HttpRequestRunStatus.loading
          ..result = null
          ..error = null;
        notifyListeners();
        try {
          final sent = await runner.send(requests[index], baseDir: baseDir);
          if (generation != _sourceGeneration) break;
          switch (sent) {
            case Success(:final value):
              outcome.result = value;
              outcome.status = value.statusCode >= 400
                  ? HttpRequestRunStatus.error
                  : HttpRequestRunStatus.success;
            case Failure(:final error):
              outcome.error = error;
              outcome.status = HttpRequestRunStatus.error;
          }
        } catch (error) {
          if (generation != _sourceGeneration) break;
          outcome.error = HttpRequestError(
            HttpRequestErrorKind.connectionFailed,
            detail: '$error',
          );
          outcome.status = HttpRequestRunStatus.error;
        }
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
  static const _maxTabStates = 24;

  /// Side-car por tab (chave = session id), com cap LRU barato: tab fechada
  /// some do mapa quando ele gira.
  HttpTabState tabStateFor(String sessionId) {
    final existing = _tabStates.remove(sessionId);
    if (existing != null) {
      _tabStates[sessionId] = existing; // re-insere no fim
      return existing;
    }
    final fresh = HttpTabState();
    _tabStates[sessionId] = fresh;
    if (_tabStates.length > _maxTabStates) {
      _tabStates.remove(_tabStates.keys.first);
    }
    return fresh;
  }
}
