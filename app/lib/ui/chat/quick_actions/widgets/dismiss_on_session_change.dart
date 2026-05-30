import 'package:app/routing/adaptive.dart';
import 'package:flutter/material.dart';

/// Tablet split-view fix: the Quick Actions sheet is a modal route on the
/// detail-pane navigator. Switching the selected session (master list) swaps
/// the chat *under* the sheet, leaving it orphaned over a different chat. This
/// wrapper closes the sheet (and any sub-picker pushed above it) the moment the
/// active [SessionSelection] changes.
class DismissOnSessionChange extends StatefulWidget {
  const DismissOnSessionChange({
    super.key,
    required this.selection,
    required this.child,
  });

  final SessionSelection selection;
  final Widget child;

  @override
  State<DismissOnSessionChange> createState() => _DismissOnSessionChangeState();
}

class _DismissOnSessionChangeState extends State<DismissOnSessionChange> {
  ({String epk, String roomId})? _initial;

  @override
  void initState() {
    super.initState();
    _initial = _key(widget.selection.current);
    widget.selection.addListener(_onChange);
  }

  static ({String epk, String roomId})? _key(
    ({String epk, String roomId, String title})? c,
  ) => c == null ? null : (epk: c.epk, roomId: c.roomId);

  void _onChange() {
    if (!mounted) return;
    if (_key(widget.selection.current) == _initial) return;
    // Pop this sheet + any sub-picker (both PopupRoutes) back to the chat.
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
