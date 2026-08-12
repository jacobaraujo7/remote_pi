import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/domain/services/scm_baseline_cache.dart';
import 'package:cockpit/app/cockpit/domain/services/scm_line_decoration_calculator.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';

/// Coordena baseline Git + debounce do buffer → [FileViewerSession.scmDecorations].
///
/// Publicação assíncrona só ocorre quando sessão, path, identidade do baseline
/// e buffer revision ainda são os da solicitação.
class ScmLineDecorationCoordinator {
  ScmLineDecorationCoordinator({
    required this.session,
    required this.cache,
    required this.calculator,
    required this.resolveGitRoot,
    this.debounce = const Duration(milliseconds: 120),
  });

  final FileViewerSession session;
  final ScmBaselineCache cache;
  final ScmLineDecorationCalculator calculator;
  final String? Function(String absPath) resolveGitRoot;
  final Duration debounce;

  CodeEditingController? _controller;
  Timer? _debounce;
  int _bufferRevision = 0;
  String? _baselineContent;
  String? _baselineHead;
  bool _disposed = false;
  bool _loadingBaseline = false;

  /// Liga o controller do editor e inicia o ciclo (baseline + cálculo).
  void attachController(CodeEditingController controller) {
    if (_disposed) return;
    if (identical(_controller, controller)) return;
    _detachControllerOnly();
    _controller = controller;
    controller.addListener(_onBufferChanged);
    _clearPublished();
    unawaited(_reloadBaselineAndSchedule());
  }

  /// Troca de path (preview reuse / retarget) — limpa e recarrega.
  void onSessionPathChanged() {
    if (_disposed) return;
    _debounce?.cancel();
    _bufferRevision++;
    _baselineContent = null;
    _baselineHead = null;
    _clearPublished();
    if (_controller != null) {
      unawaited(_reloadBaselineAndSchedule());
    }
  }

  /// Revisão Git mudou — invalida baseline da root e recalcula.
  void onGitRevisionChanged() {
    if (_disposed) return;
    final root = resolveGitRoot(session.path);
    if (root != null) cache.invalidateRepo(root);
    _baselineContent = null;
    _baselineHead = null;
    _bufferRevision++;
    unawaited(_reloadBaselineAndSchedule());
  }

  /// Buffer adotou conteúdo externo (watcher).
  void onExternalContentAdopted() {
    if (_disposed || _controller == null) return;
    _scheduleCalculate();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    _detachControllerOnly();
    _clearPublished();
  }

  void _detachControllerOnly() {
    _controller?.removeListener(_onBufferChanged);
    _controller = null;
  }

  void _onBufferChanged() => _scheduleCalculate();

  void _clearPublished() {
    session.setScmDecorations(ScmLineDecorations.empty);
  }

  Future<void> _reloadBaselineAndSchedule() async {
    if (_disposed) return;
    if (session.scratch) {
      _baselineContent = null;
      _baselineHead = null;
      _clearPublished();
      return;
    }

    final path = session.path;
    final root = resolveGitRoot(path);
    if (root == null) {
      _baselineContent = null;
      _baselineHead = null;
      _clearPublished();
      return;
    }

    _loadingBaseline = true;
    final requestPath = path;
    final baseline = await cache.baselineFor(root, path);
    _loadingBaseline = false;
    if (_disposed || session.path != requestPath) return;

    if (baseline == null) {
      _baselineContent = null;
      _baselineHead = null;
      _clearPublished();
      return;
    }

    _baselineContent = baseline.content;
    _baselineHead = baseline.headIdentity;
    _scheduleCalculate(immediate: true);
  }

  void _scheduleCalculate({bool immediate = false}) {
    if (_disposed || _controller == null) return;
    _debounce?.cancel();
    final revision = ++_bufferRevision;
    if (immediate) {
      unawaited(_calculate(revision));
      return;
    }
    _debounce = Timer(debounce, () => unawaited(_calculate(revision)));
  }

  Future<void> _calculate(int revision) async {
    if (_disposed) return;
    final controller = _controller;
    final baseline = _baselineContent;
    final head = _baselineHead;
    final path = session.path;
    if (controller == null || baseline == null || head == null) {
      if (!_loadingBaseline) _clearPublished();
      return;
    }

    final current = controller.text;
    final sessionId = session.id;
    final calc = calculator;

    // Cede o frame atual e calcula fora do caminho síncrono de pintura.
    final result = await Future<ScmLineDecorations>(() {
      return calc.calculate(baseline: baseline, current: current);
    });

    if (_disposed) return;
    if (session.id != sessionId) return;
    if (session.path != path) return;
    if (_baselineHead != head) return;
    if (revision != _bufferRevision) return;

    session.setScmDecorations(result);
  }
}
