import 'package:cockpit/app/core/domain/result.dart';

/// Why detaching a workspace into its own window failed. No sentence here: the
/// UI translates it (see `workspace_window_error_message.dart`).
enum WorkspaceWindowErrorKind {
  /// Platform without workspace windows (mobile).
  unsupported,

  /// The new window's state could not be prepared (disk, permissions).
  seedFailed,

  /// The new window's process did not start.
  launchFailed,
}

class WorkspaceWindowError implements Exception {
  const WorkspaceWindowError(this.kind, {this.detail});

  final WorkspaceWindowErrorKind kind;

  /// Raw OS text, interpolated into the translated sentence.
  final String? detail;

  @override
  String toString() =>
      'WorkspaceWindowError(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// A window's position/size, in logical screen pixels.
typedef WindowBounds = ({double x, double y, double width, double height});

/// Detached workspace windows.
///
/// Each detached window is **another Cockpit process**, running on an isolated
/// profile (`COCKPIT_ISOLATED_ROOT`) and pinned to a single workspace. The
/// isolated profile gives it its own JSON state, status socket, internal CLI
/// and sidecar, so the two processes never write the same file nor compete for
/// the same socket.
///
/// Workspace ownership: while the detached window is alive, **only it**
/// activates that workspace (and its worktrees). The main window keeps the
/// item in the rail, marked as open in another window. When the detached
/// window closes, the layout it saved is handed back to the main window's
/// state and the workspace is released ([closed]).
abstract interface class WorkspaceWindowService {
  /// Workspace hosted by THIS process, or `null` in the main window.
  String? get hostedWorkspaceId;

  /// `true` when this platform can open workspace windows.
  bool get isSupported;

  /// Workspaces (roots) currently hosted by another window.
  Set<String> get openWorkspaceIds;

  /// Emits the id of the workspace whose window closed, after its layout has
  /// already been handed back to the main window's store.
  Stream<String> get closed;

  /// Reconciles windows left by a previous session (hands back the layout of
  /// the ones that already closed) and starts watching the live ones. Must run
  /// before the main window loads the layouts.
  Future<void> start();

  /// Opens [workspaceId] in a new window. The caller has already shut down the
  /// workspace's runtime in this window and persisted its layout. [near] are
  /// the source window's bounds: the new one cascades from them instead of
  /// opening exactly on top.
  Future<Result<void, WorkspaceWindowError>> open(
    String workspaceId, {
    WindowBounds? near,
  });

  /// Brings to the front the window hosting [workspaceId]. `false` when it did
  /// not answer.
  Future<bool> focus(String workspaceId);

  Future<void> dispose();
}
