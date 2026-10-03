import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueGetter, ValueSetter, VoidCallback;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:libghostty/libghostty.dart' show TerminalCompressionResult;
import 'package:meta/meta.dart' show internal;

/// Schedules bounded scrollback compression after terminal activity becomes
/// quiet.
///
/// Compression becomes pending when the activity token changes or [schedule]
/// explicitly requests it. Pending work waits 250 milliseconds without new
/// activity, then runs one bounded step at Flutter's idle priority. Incremental
/// results yield for 1 millisecond before scheduling another idle step so
/// parsing and frames retain priority. The quiet period restarts after every
/// activity report while compression remains pending.
///
/// Flutter idle tasks cannot be canceled. A generation token and a fresh
/// activity read therefore guard every queued step against newer terminal
/// work, cancellation, unsupported targets, and disposal.
@internal
final class CompressionScheduler {
  /// Gives terminal parsing and frame production a quiet window before
  /// compression starts.
  static const _idleDelay = Duration(milliseconds: 250);

  /// Lets the UI isolate handle pending input and frames between compression
  /// steps.
  static const _continuationDelay = Duration(milliseconds: 1);

  final ValueGetter<int> _readActivity;
  final ValueSetter<VoidCallback> _scheduleIdle;
  final ValueGetter<TerminalCompressionResult> _compress;

  Timer? _timer;
  int _activity;
  int _generation;
  bool _disposed;
  bool _unsupported;
  bool _compressionPending;

  /// Uses `readActivity` to invalidate stale work and invokes `compress` only
  /// from scheduled idle tasks.
  ///
  /// When [scheduleIdle] is omitted, bounded steps run through Flutter's task
  /// scheduler at idle priority.
  CompressionScheduler({
    required this._compress,
    required ValueGetter<int> readActivity,
    ValueSetter<VoidCallback>? scheduleIdle,
  }) : _readActivity = readActivity,
       _scheduleIdle = scheduleIdle ?? _scheduleAtIdle,
       _activity = readActivity(),
       _generation = 0,
       _compressionPending = false,
       _unsupported = false,
       _disposed = false;

  bool get _canSchedule => !_unsupported && !_disposed;

  /// Cancels pending compression and invalidates any queued idle step.
  ///
  /// Later terminal activity may schedule compression again.
  void cancel() {
    if (_disposed) return;
    _cancelPending();
  }

  /// Permanently stops scheduling and invalidates pending work.
  ///
  /// Repeated calls are safe. Other public methods become no-ops afterward.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelPending();
  }

  /// Updates scheduling after terminal or viewport activity.
  ///
  /// A changed activity token schedules compression. An unchanged token
  /// postpones pending compression but does not schedule it.
  void notifyActivity() {
    if (!_canSchedule) return;

    final activity = _readActivity();
    if (activity == _activity && !_compressionPending) return;
    _activity = activity;
    _restart(_idleDelay);
  }

  /// Schedules compression after the quiet period regardless of the activity
  /// token.
  ///
  /// Compression proceeds in bounded idle steps until complete. Unlike
  /// [notifyActivity], this method schedules work when the token is unchanged.
  void schedule() {
    if (!_canSchedule) return;
    _activity = _readActivity();
    _restart(_idleDelay);
  }

  void _cancelPending() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _compressionPending = false;
  }

  void _restart(Duration delay) {
    _cancelPending();
    _compressionPending = true;
    final generation = _generation;
    _timer = Timer(delay, () {
      _timer = null;
      // Flutter idle tasks cannot be canceled. A weak reference keeps a task
      // deferred by animations from retaining its controller.
      final scheduler = WeakReference(this);
      _scheduleIdle(() => scheduler.target?._step(generation));
    });
  }

  void _step(int generation) {
    if (generation != _generation || !_canSchedule) return;

    final activity = _readActivity();
    if (activity != _activity) {
      _activity = activity;
      _restart(_idleDelay);
      return;
    }

    switch (_compress()) {
      case .pending:
        _restart(_continuationDelay);
      case .unsupported:
        _unsupported = true;
        _cancelPending();
      case .complete:
        _compressionPending = false;
        return;
    }
  }

  static void _scheduleAtIdle(VoidCallback callback) {
    unawaited(
      SchedulerBinding.instance.scheduleTask(
        callback,
        .idle,
        debugLabel: 'Terminal scrollback compression',
      ),
    );
  }
}
