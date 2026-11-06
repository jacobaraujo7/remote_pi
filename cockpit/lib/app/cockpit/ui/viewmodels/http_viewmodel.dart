import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/http_request_error.dart';
import 'package:flutter/foundation.dart';

/// Aba de baixo da view `.http`.
enum HttpResponsePane { body, headers, raw }

/// Estado de VISUALIZAÇÃO de uma tab `.http` que precisa sobreviver ao
/// re-mount do widget (mover a tab de pane destrói o `State` — mesma razão do
/// [DbTabViewState] no `DatabaseViewModel`). Mutável; o widget lê/escreve
/// direto.
class HttpTabState {
  HttpResponseResult? result;
  HttpRequestError? error;
  double split = 0.5;
  HttpResponsePane pane = HttpResponsePane.body;

  /// Corpo JSON mostrado cru em vez de indentado.
  bool rawBody = false;
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
