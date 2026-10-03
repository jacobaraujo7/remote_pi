import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show Selection;
import 'package:material_ui/material_ui.dart'
    show Theme, materialTextSelectionHandleControls;
import 'package:meta/meta.dart';

import '../foundation/cell_metrics.dart';
import 'selection_cupertino_handle_controls.dart';
import 'selection_handle_geometry.dart';
import 'selection_handle_target.dart';
import 'selection_session.dart';

@internal
final class SelectionHandleLayer extends StatelessWidget {
  final Selection selection;
  final CellMetrics metrics;
  final void Function(SelectionEndpoint) onDragCancel;
  final void Function(SelectionEndpoint, DragEndDetails) onDragEnd;
  final void Function(SelectionEndpoint, DragUpdateDetails) onDragUpdate;
  final void Function(SelectionHandleLayout, DragStartDetails) onDragStart;

  const SelectionHandleLayer({
    super.key,
    required this.metrics,
    required this.selection,
    required this.onDragEnd,
    required this.onDragStart,
    required this.onDragCancel,
    required this.onDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final controls = switch (Theme.of(context).platform) {
      .android => materialTextSelectionHandleControls,
      .iOS => selectionCupertinoHandleControls,
      _ => null,
    };
    if (controls == null) return const SizedBox.expand();
    final layout = SelectionHandleGeometry.layout(selection, metrics);
    return Stack(
      clipBehavior: .none,
      children: [
        if (layout.start case final start?)
          _target(start, controls, layout.end),
        if (layout.end case final end?) _target(end, controls, layout.start),
      ],
    );
  }

  SelectionHandleTarget _target(
    SelectionHandleLayout layout,
    TextSelectionControls controls,
    SelectionHandleLayout? peer,
  ) {
    return SelectionHandleTarget(
      layout: layout,
      controls: controls,
      peerAnchor: peer?.anchor,
      lineHeight: metrics.cellHeight,
      onDragCancel: () => onDragCancel(layout.endpoint),
      onDragStart: (details) => onDragStart(layout, details),
      onDragEnd: (details) => onDragEnd(layout.endpoint, details),
      onDragUpdate: (details) => onDragUpdate(layout.endpoint, details),
    );
  }
}
