import 'package:path/path.dart' as paths;
import 'package:flutter/foundation.dart';
import '../../../core/domain/result.dart';
import '../../../core/utils/path_utils.dart';
import '../../domain/entities/orchestration_presentation.dart';
import '../services/orchestration_controller.dart';
import '../viewmodels/orchestration_context.dart';
import '../viewmodels/orchestration_multiplexer.dart';
import 'pane_item.dart';
import 'orchestration_file_presentation.dart';
import 'terminal_session.dart';

/// The single outer tab owns an independent terminal registry and graph context.
class OrchestrationSession extends PaneItem {
  OrchestrationSession({
    required this.id,
    required this.projectId,
    required this.path,
    this.remoteFileSystem = false,
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
      onRevealTerminals: showTerminals,
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

  /// Captured origin; local tree events must not retarget a remote homonym.
  final bool remoteFileSystem;
  String path;
  final OrchestrationController controller;
  final OrchestrationMultiplexer<TerminalSession> terminals;
  late final OrchestrationContext context;
  final Future<Result<String, String>> Function(String tabId)? onCloseTerminal;
  final VoidCallback? onFocus;
  final Future<void> Function()? onBeforeDispose;
  final Listenable? windowActivityChanges;
  final Future<Result<OrchestrationFilePresentation, String>> Function(
    TerminalSession terminal,
    String path, {
    int? line,
  })?
  onOpenFile;
  OrchestrationFilePresentation? filePresentation;
  bool fileVisible = false;
  bool _presentationActive = false;
  bool presentationVisible = false;
  int _fileOpenGeneration = 0;

  void setPresentationActive(bool value, {bool visible = true}) {
    presentationVisible = visible;
    _presentationActive = value;
    if (!_disposed) terminals.setActive(value && !fileVisible);
  }

  void showFile() {
    if (_disposed || closing || filePresentation == null) return;
    fileVisible = true;
    terminals.releaseKeyboard();
    terminals.setActive(false);
    notifyListeners();
  }

  void showTerminals() {
    if (_disposed || closing || !fileVisible) return;
    fileVisible = false;
    terminals.setActive(_presentationActive);
    notifyListeners();
  }

  bool closeFile({bool discard = false, bool focus = true}) {
    if (_disposed || closing) return false;
    final previous = filePresentation;
    if (previous == null) return true;
    if (previous.dirty && !discard) return false;
    _fileOpenGeneration++;
    filePresentation = null;
    fileVisible = false;
    terminals.setActive(_presentationActive);
    if (focus && terminals.contains(previous.terminalId)) {
      context.focusTerminalTab(previous.terminalId);
    }
    notifyListeners();
    return true;
  }

  Future<Result<String, String>> openFile(
    String terminalId,
    String path, {
    int? line,
  }) async {
    final terminal = terminals.session(terminalId);
    final open = onOpenFile;
    if (_disposed ||
        closing ||
        terminal == null ||
        terminal.hasExited ||
        open == null) {
      return const Failure('Originating terminal is unavailable');
    }
    final generation = ++_fileOpenGeneration;
    try {
      final result = await open(terminal, path, line: line);
      if (_disposed ||
          closing ||
          generation != _fileOpenGeneration ||
          !identical(terminals.session(terminalId), terminal) ||
          terminal.hasExited) {
        return const Failure('Originating terminal is unavailable');
      }
      if (result case Failure(:final error)) {
        controller.reportError(error);
        return Failure(error);
      }
      final next =
          (result as Success<OrchestrationFilePresentation, String>).value;
      final current = filePresentation;
      if (current?.path == next.path && current?.terminalId == terminalId) {
        if (line != null) current?.viewer?.reveal(line, select: false);
      } else {
        if (current?.dirty == true) {
          const error =
              'Save or discard the current document before opening another file';
          controller.reportError(error);
          return const Failure(error);
        }
        filePresentation = next;
      }
      showFile();
      return Success(next.path);
    } on Object catch (error) {
      if (!_disposed && !closing && generation == _fileOpenGeneration) {
        controller.reportError(error);
      }
      return Failure(error.toString());
    }
  }

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

  /// Follow local file-tree changes without borrowing another host's path.
  bool retargetLocalFilesystem(String from, String to) {
    if (_disposed || closing || remoteFileSystem || !isUnderPath(path, from)) {
      return false;
    }
    retarget(path == from ? to : '$to${path.substring(from.length)}');
    return true;
  }

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
    if (filePresentation?.dirty == true) {
      return const Failure(
        'Save or discard the owned document before closing this app',
      );
    }
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
