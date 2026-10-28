import 'package:path/path.dart' as paths;
import 'package:flutter/foundation.dart';
import '../../../core/domain/result.dart';
import '../../domain/entities/orchestration_presentation.dart';
import '../services/orchestration_controller.dart';
import '../viewmodels/orchestration_context.dart';
import '../viewmodels/orchestration_multiplexer.dart';
import 'pane_item.dart';
import 'terminal_session.dart';

/// The single outer tab owns an independent terminal registry and graph context.
class OrchestrationSession extends PaneItem {
  OrchestrationSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.controller,
    this.onCloseTerminal,
    this.onFocus,
    this.onOpenFile,
    this.onBeforeDispose,
    this.windowActivityChanges,
    bool Function()? windowActive,
    OrchestrationBoxAction? onOpenShell,
    OrchestrationBoxAction? onStartCli,
    OrchestrationBoxAction? onHandoff,
    OrchestrationBoxAction? onSuggestRole,
    bool Function()? remoteDisconnected,
    VoidCallback? onPersist,
    Future<Set<String>> Function(TerminalSession)? readAliases,
    OrchestrationPresentation presentation = const OrchestrationPresentation(),
  }) : terminals = OrchestrationMultiplexer(
         instanceId: id,
         projectId: projectId,
         windowActive: windowActive,
       ) {
    context = OrchestrationContext(
      instanceId: id,
      projectId: projectId,
      controller: controller,
      terminals: terminals,
      title: () => paths.basename(path),
      remoteDisconnected: remoteDisconnected,
      presentation: presentation,
      onOpenShell: onOpenShell,
      onStartCli: onStartCli,
      onHandoff: onHandoff,
      onSuggestRole: onSuggestRole,
      onPersist: onPersist,
      readAliases: readAliases,
    );
    windowActivityChanges?.addListener(_onWindowActivity);
  }

  void _onWindowActivity() {
    if (!_disposed && !closing) terminals.refreshReadEligibility();
  }

  @override
  final String id;
  @override
  final String projectId;
  String path;
  final OrchestrationController controller;
  final OrchestrationMultiplexer<TerminalSession> terminals;
  late final OrchestrationContext context;
  final Future<Result<String, String>> Function(String tabId)? onCloseTerminal;
  final VoidCallback? onFocus;
  final Future<void> Function()? onBeforeDispose;
  final Listenable? windowActivityChanges;
  final void Function(TerminalSession terminal, String path, {int? line})?
  onOpenFile;
  final Set<String> closingTerminals = {};
  // Retain the original local snapshot until all saved sessions/layout are
  // restored. An invalid file or disconnected host must not erase recovery data.
  Map<String, dynamic>? pendingRestoration;
  Map<String, dynamic>? ownershipMigration;
  bool closing = false;
  bool _disposed = false;
  bool get disposed => _disposed;
  @override
  String get title => paths.basename(path);
  @override
  String get workingDirectory => paths.dirname(path);

  void retarget(String nextPath) {
    path = nextPath;
    context.documentRenamed();
    notifyListeners();
  }

  /// Shared by the inner X, keyboard/menu close and deferred CLI close.
  Future<Result<String, String>> closeTerminal(String tabId) async {
    if (_disposed || closing || !terminals.contains(tabId)) {
      return const Failure('Terminal is no longer available in this app');
    }
    final close = onCloseTerminal;
    if (close == null) return const Failure('Terminal close is unavailable');
    try {
      final result = await close(tabId);
      if (result case Failure(:final error) when !_disposed) {
        controller.reportError(error);
      }
      return result;
    } on Object catch (error) {
      if (!_disposed) controller.reportError(error);
      return Failure(error.toString());
    }
  }

  /// Called only after the user confirms closing this app. Stop processes
  /// before removing the outer tab; a failed kill leaves the app recoverable.
  Future<Result<String, String>> prepareClose() async {
    if (_disposed) return Success(id);
    if (closing) return const Failure('Orchestration is already closing');
    closing = true;
    try {
      await controller.settle();
      if (controller.dirty) await controller.load();
      if (controller.dirty) {
        throw StateError(controller.error ?? 'Unsaved document');
      }
      for (final terminal in terminals.sessions.values.toList()) {
        await terminal.stopProcess();
      }
      return Success(id);
    } catch (e) {
      closing = false;
      controller.reportError(e);
      return Failure(e.toString());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    closing = true;
    windowActivityChanges?.removeListener(_onWindowActivity);
    context.dispose();
    // Capture local layout synchronously, before the global VM clears its
    // registry during shutdown; queue persistence before awaiting teardown.
    final localSave = Future<void>.sync(() => onBeforeDispose?.call());
    controller.dispose();
    final children = terminals.sessions.values.toList();
    try {
      // Start teardown immediately; retain metadata in the registry until all
      // synchronous shutdown snapshots have been captured by the parent VM.
      await Future.wait<void>([
        localSave,
        for (final child in children) child.dispose(),
      ]);
    } finally {
      terminals.dispose();
      super.dispose();
    }
  }
}
