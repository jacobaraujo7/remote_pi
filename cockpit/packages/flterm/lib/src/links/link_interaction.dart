import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' show Offset;
import 'package:libghostty/libghostty.dart' show Mods, Position, Terminal;

import '../foundation.dart';
import 'activation_policy.dart';
import 'link_resolver.dart';
import 'link_settings.dart';
import 'link_snapshot.dart';

/// Immutable inputs needed to resolve links for one terminal viewport.
@internal
@immutable
final class LinkContext {
  final int cols;
  final int rows;
  final String? cwd;
  final Terminal terminal;

  const LinkContext({
    required this.cols,
    required this.cwd,
    required this.rows,
    required this.terminal,
  });

  @override
  int get hashCode => Object.hash(cols, cwd, rows, identityHashCode(terminal));

  bool get hasViewport => rows > 0 && cols > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkContext &&
          cols == other.cols &&
          cwd == other.cwd &&
          rows == other.rows &&
          identical(terminal, other.terminal);
}

/// Owns link detection, render snapshots, and pointer activation for one view.
///
/// Detection is lazy and cached until terminal content, viewport context, or
/// matching settings change. Pointer state stays here so presses and releases
/// resolve against the same detected link. Hover-only style changes invalidate
/// renderer snapshots without rebuilding link matches; content or matching
/// changes invalidate both caches and any in-flight activation candidate.
@internal
final class LinkInteraction extends ChangeNotifier {
  final LinkResolver _resolver;

  LinkContext? _context;
  CellRange? _highlighted;
  var _idleStyle = const HyperlinkStyle();
  LinkSnapshot? _idleSnapshot;
  CellMetrics? _lastHoverMetrics;
  Mods? _lastHoverMods;
  var _hoverDirty = false;
  Position? _lastHoverCell;
  Offset? _lastHoverPosition;
  _LinkPressCandidate? _pressCandidate;
  var _settings = const LinkSettings();
  LinkSnapshot? _snapshot;

  LinkInteraction({LinkResolver? resolver})
    : _resolver = resolver ?? LinkResolver();

  CellRange? get highlighted {
    _refreshHoverIfNeeded();
    return _highlighted;
  }

  /// Clears hover and press state without invalidating detected links.
  void cancel() {
    final changed = _highlighted != null || _pressCandidate != null;
    _clearInteraction();
    if (changed) notifyListeners();
  }

  void cancelHover() {
    final previous = _highlighted;
    _lastHoverPosition = null;
    _lastHoverMetrics = null;
    _lastHoverMods = null;
    _clearHoverHit();
    if (previous != _highlighted) notifyListeners();
  }

  CellRange? handleHover({
    required Offset localPosition,
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    final previous = _highlighted;
    _lastHoverPosition = localPosition;
    _lastHoverMetrics = metrics;
    _lastHoverMods = virtualMods;
    final next = _hoverAt(
      localPosition,
      metrics: metrics,
      virtualMods: virtualMods,
    );
    _hoverDirty = false;
    if (previous != next) notifyListeners();
    return next;
  }

  bool handlePress({
    required Offset localPosition,
    required CellMetrics metrics,
    required PointerDeviceKind pointerKind,
    required Mods virtualMods,
  }) {
    _pressCandidate = null;
    if (!_canActivate(pointerKind, virtualMods)) return false;

    final cell = metrics.cellAt(localPosition);
    final link = _linkAt(cell);
    if (link == null) return false;

    _pressCandidate = _LinkPressCandidate(cell, link);
    return true;
  }

  /// Whether a mouse press at [localPosition] belongs to a link rather than
  /// to terminal mouse tracking.
  ///
  /// True only when an explicit activation modifier is configured and held
  /// (Cmd/Ctrl by default) over a link. Without this, an application that
  /// enables mouse reporting (Claude Code, vim, htop) receives the press: the
  /// link highlights on hover but a click never opens it. Plain clicks
  /// ([ActivationModifier.none]) keep going to the application.
  bool claimsModifiedPress({
    required Offset localPosition,
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    if (_settings.modifier == .none) return false;
    if (!_canActivate(.mouse, virtualMods)) return false;
    return _linkAt(metrics.cellAt(localPosition)) != null;
  }

  ActivatedLink? handleRelease({
    required Offset localPosition,
    required CellMetrics metrics,
  }) {
    final candidate = _pressCandidate;
    _pressCandidate = null;
    if (candidate == null) return null;

    final cell = metrics.cellAt(localPosition);
    return cell == candidate.cell ? candidate.link : null;
  }

  void invalidateContent() {
    _idleSnapshot = null;
    _snapshot = null;
    _cancelPress();
    _lastHoverCell = null;
    if (_lastHoverPosition == null ||
        _lastHoverMetrics == null ||
        _lastHoverMods == null) {
      _clearHoverHit();
      _hoverDirty = false;
    } else {
      _hoverDirty = true;
    }
  }

  CellRange? refreshHover({
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    final position = _lastHoverPosition;
    if (position == null) return _highlighted;
    _lastHoverMetrics = metrics;
    _lastHoverMods = virtualMods;
    final previous = _highlighted;
    final next = _hoverAt(position, metrics: metrics, virtualMods: virtualMods);
    _hoverDirty = false;
    if (previous != next) notifyListeners();
    return next;
  }

  /// Returns the current renderer snapshot, rebuilding it when needed.
  LinkSnapshot snapshot() {
    _refreshHoverIfNeeded();
    final cached = _snapshot;
    if (cached != null) return cached;

    final context = _context;
    final snapshot = context == null || !context.hasViewport
        ? LinkSnapshot.empty
        : _buildSnapshot(context);
    _snapshot = snapshot;
    return snapshot;
  }

  void update({
    required LinkContext context,
    required LinkSettings settings,
    required HyperlinkStyle idleStyle,
  }) {
    final previousSettings = _settings;
    final contextChanged = _context != context;
    final matchSettingsChanged = !_sameMatchSettings(
      previousSettings,
      settings,
    );
    final gestureSettingsChanged = !_sameGestureSettings(
      previousSettings,
      settings,
    );
    final idleStyleChanged = _idleStyle != idleStyle;

    _context = context;
    _settings = settings;
    _idleStyle = idleStyle;

    if (contextChanged || matchSettingsChanged) {
      _idleSnapshot = null;
      _snapshot = null;
      _clearInteraction();
      return;
    }

    if (idleStyleChanged) {
      _idleSnapshot = null;
      _snapshot = null;
    }
    if (gestureSettingsChanged) {
      _clearInteraction();
    }
  }

  LinkSnapshot _buildSnapshot(LinkContext context) {
    if (_settings.types.isEmpty) return .empty;
    if (_needsIdleSnapshot()) {
      return _idleSnapshotFor(context).withHighlighted(_highlighted);
    }
    final range = _highlighted;
    return range == null ? .empty : .highlighted(range);
  }

  bool _canActivate(PointerDeviceKind pointerKind, Mods virtualMods) {
    return canActivateLink(
      settings: _settings,
      virtualMods: virtualMods,
      pointerKind: pointerKind,
    );
  }

  void _cancelPress() => _pressCandidate = null;

  void _clearHoverHit() {
    _lastHoverCell = null;
    if (_highlighted == null) return;
    _highlighted = null;
    _snapshot = null;
  }

  void _clearInteraction() {
    _cancelPress();
    _lastHoverPosition = null;
    _lastHoverMetrics = null;
    _lastHoverMods = null;
    _hoverDirty = false;
    _clearHoverHit();
  }

  bool _hasIdleVisualEffect() {
    return _idleStyle.underline != .none ||
        _idleStyle.underlineColor != null ||
        _idleStyle.textColor != null;
  }

  CellRange? _hoverAt(
    Offset localPosition, {
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    if (!_canActivate(.mouse, virtualMods)) {
      _clearHoverHit();
      return null;
    }

    final cell = metrics.cellAt(localPosition);
    if (cell == _lastHoverCell) return _highlighted;

    final link = _linkAt(cell);
    _lastHoverCell = cell;
    final nextRange = link?.range;
    if (nextRange == _highlighted) return _highlighted;

    _highlighted = nextRange;
    _snapshot = null;
    return _highlighted;
  }

  LinkSnapshot _idleSnapshotFor(LinkContext context) {
    final cached = _idleSnapshot;
    if (cached != null) return cached;

    final snapshot = _resolver.buildSnapshot(
      context.terminal,
      _settings,
      rows: context.rows,
      cols: context.cols,
    );
    _idleSnapshot = snapshot;
    return snapshot;
  }

  ActivatedLink? _linkAt(Position cell) {
    final context = _context;
    if (context == null || !context.hasViewport) return null;
    if (cell.row < 0 ||
        cell.row >= context.rows ||
        cell.col < 0 ||
        cell.col >= context.cols) {
      return null;
    }
    return _resolver.linkAt(
      context.terminal,
      cell,
      _settings,
      rows: context.rows,
      cols: context.cols,
      cwd: context.cwd,
    );
  }

  bool _needsIdleSnapshot() {
    if (!_hasIdleVisualEffect()) return false;
    final Set<LinkType> types = _settings.types;
    if (types.contains(LinkType.osc8) || types.contains(LinkType.text)) {
      return true;
    }
    if (!types.contains(LinkType.custom)) return false;
    return _settings.rules.any((rule) => rule.highlightMode == .always);
  }

  void _refreshHoverIfNeeded() {
    if (!_hoverDirty) return;
    final position = _lastHoverPosition;
    final metrics = _lastHoverMetrics;
    final virtualMods = _lastHoverMods;
    if (position == null || metrics == null || virtualMods == null) {
      _hoverDirty = false;
      _clearHoverHit();
      return;
    }
    _hoverAt(position, metrics: metrics, virtualMods: virtualMods);
    _hoverDirty = false;
  }

  bool _sameGestureSettings(LinkSettings a, LinkSettings b) {
    return a.modifier == b.modifier &&
        (a.onActivate != null) == (b.onActivate != null);
  }

  bool _sameMatchSettings(LinkSettings a, LinkSettings b) {
    return setEquals(a.types, b.types) && listEquals(a.rules, b.rules);
  }
}

final class _LinkPressCandidate {
  final Position cell;
  final ActivatedLink link;

  const _LinkPressCandidate(this.cell, this.link);
}
