import 'dart:async';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';

/// Plan/28 Wave C — drives the Quick Actions bottom sheet and its
/// Model sub-picker. Holds the last-resolved "current" pair (model /
/// thinking level) so the picker can highlight without waiting for
/// another round-trip.
///
/// Plan/28 Wave D — also hydrates the current thinking / model name
/// from [IActionsRepository.activeRoomMetaStream] so the bottom sheet
/// reflects the Pi's real state on first open (instead of starting
/// `null`). External model changes (other paired apps or the TUI's
/// `/model`) come in through the same stream.
///
/// Errors raised by [IActionsRepository] are forwarded to [errors] so
/// the page can surface them as SnackBars. State stays usable after a
/// failure — the next tap retries.
class QuickActionsViewModel extends ViewModel<QuickActionsState> {
  final IActionsRepository _repo;
  /// Optional so test harnesses can construct the VM without the app's
  /// Preferences instance. `null` → the sheet omits the per-room
  /// "Hide tool calls" row instead of crashing on a missing provider.
  final Preferences? _prefs;
  final _errorController = StreamController<String>.broadcast();
  StreamSubscription<ActiveRoomMeta>? _metaSub;
  bool _disposed = false;

  QuickActionsViewModel(this._repo, [this._prefs])
    : super(const QuickActionsIdle()) {
    // Plan/28 Wave D — seed from the repo's current snapshot before
    // anything is shown so the first build already has the right
    // highlight (instead of a flash of "null" while the stream
    // delivers its first event).
    _adoptMeta(_repo.activeRoomMeta);
    _metaSub = _repo.activeRoomMetaStream.listen(_adoptMeta);
  }

  /// Snackbar feed: one string per failure. The page listens with a
  /// `StreamSubscription` so a failed action can show a toast without
  /// blocking the sheet itself.
  Stream<String> get errors => _errorController.stream;

  ThinkingLevel? get currentThinking => state.currentThinking;
  WireModel? get currentModel => state.currentModel;
  String? get currentModelName => state.currentModelName;

  // ---------------------------------------------------------------------------
  // Per-room tool-calls toggle
  // ---------------------------------------------------------------------------

  /// The [Preferences] this VM was built with (may be `null` in tests).
  /// The sheet listens to it directly for reactive rebuilds.
  Preferences? get preferences => _prefs;

  /// Whether the ACTIVE room's (peer, room) pair hides tool rows.
  /// No record → `false` (default). `false` when the VM has no
  /// [Preferences] or the active room is unknown.
  bool get hideToolCalls {
    final meta = _repo.activeRoomMeta;
    final epk = meta.peerEpk;
    if (_prefs == null || epk == null) return false;
    return _prefs.hideToolCallsFor(epk, meta.roomId);
  }

  /// Persist the toggle for the ACTIVE room. No-op without a
  /// [Preferences] or a resolvable (peer, room) pair.
  Future<void> setHideToolCalls(bool value) async {
    final meta = _repo.activeRoomMeta;
    final epk = meta.peerEpk;
    if (_prefs == null || epk == null) return;
    await _prefs.setHideToolCallsFor(epk, meta.roomId, value);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> compact() async {
    await _runVoid(ActionName.sessionCompact, _repo.compact);
  }

  Future<void> newSession() async {
    await _runVoid(ActionName.sessionNew, _repo.newSession);
  }

  Future<void> setModel(WireModel model) async {
    // Optimistic highlight — flip the current model immediately so the
    // picker row reflects the tap before the round-trip resolves.
    final previous = state.currentModel;
    final previousName = state.currentModelName;
    _emitIfAlive(QuickActionsBusy(
      action: ActionName.modelSet,
      currentModel: model,
      currentModelName: model.name,
      currentThinking: state.currentThinking,
    ));
    try {
      await _repo.setModel(model.provider, model.id);
      _emitIfAlive(QuickActionsIdle(
        currentModel: model,
        currentModelName: model.name,
        currentThinking: state.currentThinking,
      ));
    } on ActionFailure catch (e) {
      // Revert optimistic highlight on failure.
      _emitIfAlive(QuickActionsIdle(
        currentModel: previous,
        currentModelName: previousName,
        currentThinking: state.currentThinking,
      ));
      _errorController.add(e.message);
      rethrow;
    }
  }

  Future<void> setThinking(ThinkingLevel level) async {
    final previous = state.currentThinking;
    _emitIfAlive(QuickActionsBusy(
      action: ActionName.thinkingSet,
      currentThinking: level,
      currentModel: state.currentModel,
      currentModelName: state.currentModelName,
    ));
    try {
      await _repo.setThinking(level);
      _emitIfAlive(QuickActionsIdle(
        currentThinking: level,
        currentModel: state.currentModel,
        currentModelName: state.currentModelName,
      ));
    } on ActionFailure catch (e) {
      _emitIfAlive(QuickActionsIdle(
        currentThinking: previous,
        currentModel: state.currentModel,
        currentModelName: state.currentModelName,
      ));
      _errorController.add(e.message);
      rethrow;
    }
  }

  /// Hits the Pi (or returns the cached catalogue) for the model
  /// picker. Throws [ActionFailure] on disconnect / timeout — the
  /// picker widget catches and renders an error placeholder.
  Future<ModelsCatalogue> loadModels({bool forceRefresh = false}) async {
    try {
      final catalogue = await _repo.listModels(forceRefresh: forceRefresh);
      // Adopt the Pi's "current" answer; only overwrite when present so
      // a stale cache entry (current=null) doesn't clobber a value we
      // already learned via setModel.
      if (catalogue.current != null) {
        _emitIfAlive(QuickActionsIdle(
          currentModel: catalogue.current,
          currentModelName: catalogue.current?.name ?? state.currentModelName,
          currentThinking: state.currentThinking,
        ));
      }
      return catalogue;
    } on ActionFailure catch (e) {
      _errorController.add(e.message);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------

  /// Plan/28 Wave D — react to a room-meta snapshot. Adopts the
  /// thinking level (always — the relay is the source of truth) and
  /// the model name (when present). Leaves the structured
  /// [currentModel] alone because the meta only carries a display
  /// name, not the full [WireModel]; the picker can call
  /// [loadModels] when it needs the structured record.
  void _adoptMeta(ActiveRoomMeta meta) {
    if (_disposed) return;
    final cur = state;
    // Compose the next state preserving the busy-action flag so an
    // in-flight call doesn't lose its spinner mid-update.
    final nextThinking = meta.thinking ?? cur.currentThinking;
    final nextModelName = meta.model ?? cur.currentModelName;
    // If the meta's model differs from the structured `currentModel`
    // name (external switch), drop the structured model so the picker
    // re-fetches on next open.
    WireModel? nextModel = cur.currentModel;
    if (meta.model != null &&
        cur.currentModel != null &&
        cur.currentModel!.name != meta.model) {
      nextModel = null;
    }

    QuickActionsState next;
    if (cur is QuickActionsBusy) {
      next = QuickActionsBusy(
        action: cur.action,
        currentThinking: nextThinking,
        currentModel: nextModel,
        currentModelName: nextModelName,
      );
    } else {
      next = QuickActionsIdle(
        currentThinking: nextThinking,
        currentModel: nextModel,
        currentModelName: nextModelName,
      );
    }
    if (next == cur) return;
    emit(next);
  }

  Future<void> _runVoid(
    ActionName action,
    Future<void> Function() body,
  ) async {
    _emitIfAlive(QuickActionsBusy(
      action: action,
      currentThinking: state.currentThinking,
      currentModel: state.currentModel,
      currentModelName: state.currentModelName,
    ));
    try {
      await body();
      _emitIfAlive(QuickActionsIdle(
        currentThinking: state.currentThinking,
        currentModel: state.currentModel,
        currentModelName: state.currentModelName,
      ));
    } on ActionFailure catch (e) {
      _emitIfAlive(QuickActionsIdle(
        currentThinking: state.currentThinking,
        currentModel: state.currentModel,
        currentModelName: state.currentModelName,
      ));
      _errorController.add(e.message);
      rethrow;
    }
  }

  void _emitIfAlive(QuickActionsState next) {
    if (_disposed) return;
    emit(next);
  }

  @override
  void dispose() {
    _disposed = true;
    _metaSub?.cancel();
    _errorController.close();
    super.dispose();
  }
}
