import 'dart:async';

import 'package:cockpit/app/core/domain/contracts/automation_gateway.dart';
import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/exceptions/automation_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

class AutomationController extends ChangeNotifier {
  AutomationController(this._gateway);

  final AutomationGateway _gateway;
  List<AutomationHarness> _harnesses = const <AutomationHarness>[];
  bool _initialized = false;
  bool _discovering = false;
  bool _generating = false;
  AutomationError? _error;

  List<AutomationHarness> get harnesses => _harnesses;
  bool get initialized => _initialized;
  bool get discovering => _discovering;
  bool get generating => _generating;

  /// Última falha, **sem texto** — a UI traduz com `automationErrorMessage`.
  AutomationError? get error => _error;

  AutomationHarness? harnessFor(HarnessKind? id) {
    if (id == null) return null;
    for (final harness in _harnesses) {
      if (harness.id == id) return harness;
    }
    return null;
  }

  /// Descobre harnesses na primeira necessidade (Settings ou geração).
  Future<void> ensureInitialized() async {
    if (_initialized || _discovering) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_discovering) return;
    _discovering = true;
    _error = null;
    notifyListeners();
    try {
      _harnesses = await _gateway.discover();
    } catch (error) {
      _error = AutomationError(AutomationErrorKind.process, cause: error);
      debugPrint('[automation] discovery failed: $error');
    } finally {
      _initialized = true;
      _discovering = false;
      notifyListeners();
    }
  }

  /// Limpa um modelId que sumiu da lista descoberta e avisa o usuário.
  /// Retorna o aviso tipado (a UI traduz), ou `null` se nada mudou.
  AutomationError? reconcileStaleModel({
    required HarnessKind? harnessId,
    required String? modelId,
    required void Function() clearToCliDefault,
  }) {
    if (harnessId == null) return null;
    final trimmed = modelId?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final harness = harnessFor(harnessId);
    if (harness == null || harness.models.isEmpty) return null;
    if (harness.models.any((model) => model.id == trimmed)) return null;
    clearToCliDefault();
    final warning = AutomationError(
      AutomationErrorKind.unavailable,
      harness: harness.label,
      model: trimmed,
    );
    _error = warning;
    notifyListeners();
    return warning;
  }

  Future<Result<GeneratedCommitMessage, AutomationError>> generate({
    required AutomationSelection selection,
    required AutomationRequest request,
  }) async {
    if (_generating) {
      return const Failure(AutomationError(AutomationErrorKind.busy));
    }
    await ensureInitialized();
    final harness = harnessFor(selection.harnessId);
    if (harness == null) {
      return Failure(
        AutomationError(
          AutomationErrorKind.unavailable,
          harness: selection.harnessId.label,
        ),
      );
    }
    final modelId = selection.modelId?.trim();
    if (modelId != null &&
        modelId.isNotEmpty &&
        harness.models.isNotEmpty &&
        !harness.models.any((model) => model.id == modelId)) {
      return Failure(
        AutomationError(
          AutomationErrorKind.unavailable,
          harness: harness.label,
          model: modelId,
        ),
      );
    }
    // Sem escolha explícita, cai no padrão do harness — `auto` quando ele
    // roteia sozinho, senão o modelo que o próprio CLI já usa.
    final effective = modelId == null || modelId.isEmpty
        ? selection.withModel(harness.defaultModelId)
        : selection;
    _generating = true;
    _error = null;
    notifyListeners();
    try {
      return Success(
        await _gateway.generate(selection: effective, request: request),
      );
    } on AutomationError catch (error) {
      _error = error;
      return Failure(error);
    } catch (error) {
      final failure = AutomationError(
        AutomationErrorKind.process,
        cause: error,
      );
      _error = failure;
      debugPrint('[automation] generation failed: $error');
      return Failure(failure);
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  Future<void> cancelGeneration() => _gateway.cancel();

  @override
  void dispose() {
    unawaited(_gateway.close());
    super.dispose();
  }
}
