import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Publishes editable-box geometry and its root transform for text input.
typedef TextInputGeometryChanged =
    void Function({
      required Size editableSize,
      required Matrix4 transform,
      required Rect caretRect,
      required Rect composingRect,
    });

/// Flutter text input connection for terminal editing.
///
/// The terminal has no editable text buffer, so this client keeps a sentinel
/// editing value only to give platform IMEs an anchor for composing ranges.
/// It turns platform edits into terminal events: committed text, newlines,
/// deletions, and visible preedit text.
///
/// The sentinel never becomes terminal content. Delta edits are translated
/// relative to it, then the platform value is reset after each commit. Some
/// platforms report Enter through both an action and a delta; the short-lived
/// dedupe counters ensure one terminal newline while leaving later input
/// untouched.
@internal
final class TextInputSession with DeltaTextInputClient {
  static const _newlineActionDedupeWindow = Duration(milliseconds: 100);
  static const _sentinel = TextEditingValue(
    selection: .collapsed(offset: 1),
    text: ' ',
  );
  static final _newlinePattern = RegExp(r'\r\n|[\n\r]');
  static final _onlyNewlinesPattern = RegExp(r'^(?:\r\n|[\n\r])+$');

  _CommittedCompositionEdit _committedCompositionEdit = .none;
  TextInputConnection? _connection;
  var _hadVisiblePreeditText = false;
  Brightness _keyboardAppearance = .dark;
  var _newlineActionsToSuppress = 0;
  Timer? _newlineActionDedupeTimer;
  var _newlineDeltasToSuppress = 0;
  var _reopenScheduled = false;
  VoidCallback? _onNewline;
  ValueChanged<int>? _onDelete;
  ValueChanged<String>? _onPreeditChanged;
  ValueChanged<String>? _onTextCommitted;
  TextEditingValue _value = _sentinel;
  int? _viewId;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue get currentTextEditingValue => _value;

  /// Whether the platform owns a composing range, even when no visible
  /// preedit text should be rendered.
  bool get hasActiveComposition => _value.hasTerminalComposingRange;

  /// Whether this client owns the platform text input connection.
  ///
  /// Text input accepts one client at a time. Another client can replace this
  /// connection without invoking [connectionClosed], so non-nullness alone
  /// does not prove ownership.
  bool get isAttached => _connection?.attached ?? false;

  set keyboardAppearance(Brightness value) {
    if (_keyboardAppearance == value) return;
    _keyboardAppearance = value;
    final connection = _connection;
    if (connection != null && connection.attached) {
      connection.updateConfig(_configuration);
    }
  }

  set onDelete(ValueChanged<int>? callback) => _onDelete = callback;

  set onNewline(VoidCallback? callback) => _onNewline = callback;

  set onPreeditChanged(ValueChanged<String>? callback) {
    _onPreeditChanged = callback;
  }

  set onTextCommitted(ValueChanged<String>? callback) {
    _onTextCommitted = callback;
  }

  /// Replaces an active connection because platform text input is view-bound.
  set viewId(int value) {
    if (_viewId == value) return;
    final wasAttached = _connection != null;
    if (wasAttached) _closeConnection();
    _viewId = value;
    if (wasAttached) _openConnection();
  }

  TextInputConfiguration get _configuration {
    final viewId = _viewId;
    if (viewId == null) {
      throw StateError(
        'Text input requires an owning Flutter view before attachment.',
      );
    }
    return TextInputConfiguration(
      viewId: viewId,
      autocorrect: false,
      inputType: .multiline,
      inputAction: .newline,
      smartDashesType: .disabled,
      smartQuotesType: .disabled,
      enableDeltaModel: true,
      enableSuggestions: false,
      enableInlinePrediction: false,
      enableInteractiveSelection: false,
      enableIMEPersonalizedLearning: false,
      keyboardAppearance: _keyboardAppearance,
    );
  }

  @override
  void connectionClosed() {
    _connection = null;
    _resetInputState();
  }

  /// Lets one plain desktop Backspace/Delete reach the platform IME after a
  /// candidate commit, while arming suppression for the matching edit delta.
  bool consumeCommittedCompositionEdit() {
    if (_committedCompositionEdit != .pending) return false;
    _committedCompositionEdit = .suppressNextDeletionDelta;
    return true;
  }

  void detach() => _closeConnection();

  @override
  void didChangeInputControl(TextInputControl? _, TextInputControl? _) {}

  void ensureAttached({Brightness? keyboardAppearance}) {
    if (keyboardAppearance != null) _keyboardAppearance = keyboardAppearance;
    final connection = _connection;
    if (connection == null) return _openConnection();
    if (!connection.attached) {
      _closeConnection();
      return _openConnection();
    }
    connection.updateConfig(_configuration);
  }

  void hide() => _closeConnection();

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  bool onFocusReceived() => false;

  @override
  void performAction(TextInputAction action) {
    if (action != .newline) return;
    if (_newlineActionsToSuppress > 0) {
      _newlineActionsToSuppress--;
      _finishNewlineDedupeIfIdle();
      return;
    }
    _onNewline?.call();
    _newlineDeltasToSuppress++;
    _armNewlineActionDedupeTimer();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void removeTextPlaceholder() {}

  void show() {
    ensureAttached();
    _connection?.show();
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void showToolbar() {}

  @override
  void updateEditingValue(TextEditingValue value) {
    final expireSuppressionAfterUpdate =
        _committedCompositionEdit == .suppressNextDeletionDelta;
    _value = value;
    _processEditingValue(value);
    if (expireSuppressionAfterUpdate &&
        _committedCompositionEdit == .suppressNextDeletionDelta) {
      _clearCommittedCompositionEdit();
    }
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    final expireSuppressionAfterBatch =
        _committedCompositionEdit == .suppressNextDeletionDelta;
    var fromCompositionInBatch = _hadVisiblePreeditText || hasActiveComposition;
    for (final delta in deltas) {
      final TextEditingValue next;
      try {
        next = delta.apply(_value);
      } on Object {
        // Some platforms (notably iOS) keep their own marked-text buffer and
        // ignore the sentinel we push via setEditingState after each commit.
        // A later delta then references offsets past our sentinel value, so
        // applying it throws. Left uncaught, that kills the text-input channel
        // and freezes all further typing (e.g. after composing an accent).
        // Resync the platform back to the sentinel and drop this batch instead.
        _recoverFromDesync(delta);
        return;
      }
      _value = next;
      _processDelta(delta, fromCompositionInBatch: fromCompositionInBatch);
      fromCompositionInBatch = fromCompositionInBatch || _hadVisiblePreeditText;
    }
    if (expireSuppressionAfterBatch &&
        _committedCompositionEdit == .suppressNextDeletionDelta) {
      _clearCommittedCompositionEdit();
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  /// Anchors native composing and candidate UI to the terminal cursor cell.
  void updateGeometry({
    required Size editableSize,
    required Matrix4 transform,
    required Rect caretRect,
    required Rect composingRect,
  }) {
    final connection = _connection;
    if (connection == null || !connection.attached) return;
    connection
      ..setEditableSizeAndTransform(editableSize, transform)
      ..setCaretRect(caretRect)
      ..setComposingRect(composingRect);
  }

  void _armNewlineActionDedupeTimer() {
    _newlineActionDedupeTimer?.cancel();
    _newlineActionDedupeTimer = Timer(
      _newlineActionDedupeWindow,
      _clearNewlineActionSuppression,
    );
  }

  void _clearCommittedCompositionEdit() {
    _committedCompositionEdit = .none;
  }

  void _clearNewlineActionSuppression() {
    _newlineActionDedupeTimer?.cancel();
    _newlineActionDedupeTimer = null;
    _newlineActionsToSuppress = 0;
    _newlineDeltasToSuppress = 0;
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
    _resetInputState();
  }

  void _commitEndedCompositionFromValue() {
    final committed = _value.terminalCommittedText;
    if (committed.isEmpty) {
      _clearCommittedCompositionEdit();
      return;
    }
    _commitInputText(committed, fromComposition: true);
  }

  void _commitInputText(String text, {required bool fromComposition}) {
    _commitText(text);
    _committedCompositionEdit =
        text.isNotEmpty && (fromComposition || text.isImeLikeCommit)
        ? .pending
        : .none;
    _resetBuffer();
  }

  void _commitNewlines(int count) {
    final suppressed = count < _newlineDeltasToSuppress
        ? count
        : _newlineDeltasToSuppress;
    _newlineDeltasToSuppress -= suppressed;
    final emitted = count - suppressed;
    for (var i = 0; i < emitted; i++) {
      _onNewline?.call();
    }
    _newlineActionsToSuppress += emitted;
    if (_newlineActionsToSuppress > 0 || _newlineDeltasToSuppress > 0) {
      _armNewlineActionDedupeTimer();
    } else {
      _finishNewlineDedupeIfIdle();
    }
  }

  void _commitText(String text) {
    if (_onlyNewlinesPattern.hasMatch(text)) {
      _commitNewlines(_newlinePattern.allMatches(text).length);
      return;
    }

    _clearNewlineActionSuppression();

    var offset = 0;
    for (final match in _newlinePattern.allMatches(text)) {
      final chunk = text.substring(offset, match.start);
      if (chunk.isNotEmpty) _onTextCommitted?.call(chunk);
      _onNewline?.call();
      offset = match.end;
    }

    final tail = text.substring(offset);
    if (tail.isNotEmpty) _onTextCommitted?.call(tail);
  }

  void _finishNewlineDedupeIfIdle() {
    if (_newlineActionsToSuppress == 0 && _newlineDeltasToSuppress == 0) {
      _clearNewlineActionSuppression();
    }
  }

  void _openConnection() {
    final connection = TextInput.attach(this, _configuration);
    _connection = connection;
    _value = _sentinel;
    connection.setEditingState(_value);
  }

  void _processDelta(
    TextEditingDelta delta, {
    required bool fromCompositionInBatch,
  }) {
    final preeditText = _value.terminalComposingText;
    final hasActiveComposition = _value.hasTerminalComposingRange;
    final hasVisiblePreeditText = preeditText.isNotEmpty;
    var committedFromDelta = false;
    final String? committedText = switch (delta) {
      TextEditingDeltaInsertion(:final textInserted)
          when !hasActiveComposition =>
        textInserted,
      TextEditingDeltaReplacement(:final replacementText)
          when !hasActiveComposition =>
        replacementText,
      _ => null,
    };

    if (committedText != null) {
      _commitInputText(committedText, fromComposition: fromCompositionInBatch);
      committedFromDelta = true;
    } else if (delta is TextEditingDeltaDeletion &&
        !hasActiveComposition &&
        !_hadVisiblePreeditText) {
      // After an IME candidate commit, desktop IMEs may report the first
      // plain delete through both the raw key path and the text-input delta
      // path. The controller forwards that key to the platform once, and this
      // client drops only the matching deletion delta.
      if (_committedCompositionEdit == .suppressNextDeletionDelta) {
        _clearCommittedCompositionEdit();
        _resetBuffer();
        return;
      }
      final count = delta.deletedRange.end - delta.deletedRange.start;
      _clearNewlineActionSuppression();
      _onDelete?.call(count);
      _clearCommittedCompositionEdit();
      _resetBuffer();
    }

    if (hasVisiblePreeditText) {
      _clearCommittedCompositionEdit();
      _onPreeditChanged?.call(preeditText);
    } else if (_hadVisiblePreeditText) {
      if (!committedFromDelta) _commitEndedCompositionFromValue();
      _onPreeditChanged?.call('');
    }

    _hadVisiblePreeditText = hasVisiblePreeditText;
  }

  void _processEditingValue(TextEditingValue value) {
    final preeditText = value.terminalComposingText;
    if (preeditText.isNotEmpty) {
      _clearCommittedCompositionEdit();
      _onPreeditChanged?.call(preeditText);
      _hadVisiblePreeditText = true;
      return;
    }

    final hadVisiblePreeditText = _hadVisiblePreeditText;
    if (hadVisiblePreeditText) _commitEndedCompositionFromValue();
    if (hadVisiblePreeditText) _onPreeditChanged?.call('');
    _hadVisiblePreeditText = false;
    if (hadVisiblePreeditText) return;

    final committed = value.terminalCommittedText;
    if (committed.isNotEmpty) {
      _commitInputText(committed, fromComposition: false);
    }
  }

  void _resetBuffer() {
    _value = _sentinel;
    final connection = _connection;
    if (connection != null && connection.attached) {
      connection.setEditingState(_value);
    }
  }

  /// Resynchronizes after [failedDelta] could not be applied to the sentinel.
  ///
  /// Clears any composition/newline bookkeeping and forces the platform back to
  /// the sentinel so subsequent input maps to a known state again, keeping the
  /// text-input channel alive instead of letting the failure freeze typing.
  ///
  /// A plain [setEditingState] is not enough on iOS: it keeps its own
  /// marked-text buffer and ignores the sentinel we push, so every following
  /// delta stays anchored to that buffer and re-desyncs, dropping input
  /// indefinitely (e.g. after composing a dead-key accent with a physical
  /// keyboard). The connection has to be reopened so iOS discards the marked
  /// text and re-anchors on a fresh sentinel, but reopening synchronously here
  /// lands mid-delivery and does not re-engage key input until the view is
  /// refocused, so it is deferred past this callback (see [_scheduleReopen]).
  ///
  /// The failing delta usually carries the composed character iOS was trying to
  /// commit (a dead-key accent), so it is salvaged and committed before the
  /// batch is dropped; otherwise the accent would be lost with the batch.
  void _recoverFromDesync(TextEditingDelta failedDelta) {
    _clearNewlineActionSuppression();
    _clearCommittedCompositionEdit();
    final hadVisiblePreeditText = _hadVisiblePreeditText;
    _hadVisiblePreeditText = false;
    if (hadVisiblePreeditText) _onPreeditChanged?.call('');

    final salvaged = switch (failedDelta) {
      TextEditingDeltaInsertion(:final textInserted) => textInserted,
      TextEditingDeltaReplacement(:final replacementText) => replacementText,
      _ => '',
    };
    if (salvaged.isNotEmpty) _commitText(salvaged);

    _value = _sentinel;
    if (_connection != null && _connection!.attached) {
      _scheduleReopen();
    } else {
      _resetBuffer();
    }
  }

  /// Reopens the text-input connection after the current frame.
  ///
  /// Closing/reopening while a delta batch is still being delivered leaves iOS
  /// with an open channel that stops handing over keys until the view is
  /// refocused. A microtask still runs inside the same platform turn, so the
  /// reopen is deferred to the next post-frame callback: that lets iOS fully
  /// settle its marked-text state first, and the fresh connection then receives
  /// subsequent keys and is re-shown so key delivery resumes without a manual
  /// refocus.
  void _scheduleReopen() {
    if (_reopenScheduled) return;
    _reopenScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reopenScheduled = false;
      final connection = _connection;
      if (connection == null || !connection.attached) return;
      _closeConnection();
      _openConnection();
      _connection?.show();
    });
  }

  void _resetInputState() {
    final hadVisiblePreeditText =
        _hadVisiblePreeditText || _value.terminalComposingText.isNotEmpty;
    _value = _sentinel;
    _clearNewlineActionSuppression();
    _clearCommittedCompositionEdit();
    _hadVisiblePreeditText = false;
    if (hadVisiblePreeditText) _onPreeditChanged?.call('');
  }
}

enum _CommittedCompositionEdit { none, pending, suppressNextDeletionDelta }

/// Extracts terminal-owned text from Flutter's sentinel editing value.
extension _EditingValue on TextEditingValue {
  bool get hasTerminalComposingRange {
    final composing = this.composing;
    return composing.isValid &&
        !composing.isCollapsed &&
        composing.start >= 0 &&
        composing.end <= text.length;
  }

  String get terminalCommittedText =>
      _withoutTerminalInputSentinel(0, text.length);

  String get terminalComposingText {
    if (!hasTerminalComposingRange) return '';
    final composing = this.composing;
    return _withoutTerminalInputSentinel(composing.start, composing.end);
  }

  String _withoutTerminalInputSentinel(int start, int end) {
    var contentStart = start;
    if (start == 0 &&
        end > 0 &&
        text.startsWith(TextInputSession._sentinel.text)) {
      contentStart = TextInputSession._sentinel.text.length;
    }
    if (contentStart >= end) return '';
    return text.substring(contentStart, end);
  }
}

extension _InputString on String {
  bool get isImeLikeCommit => codeUnits.any((codeUnit) => codeUnit > 0x7f);
}
