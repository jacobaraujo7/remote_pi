import 'package:cockpit/app/cockpit/domain/entities/workspace_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual order survives mode changes and restoration', () {
    final order = ['second', 'first'];
    final state = const WorkspacePresentation()
        .copyWith(boxOrder: order)
        .copyWith(mode: WorkspaceViewMode.graph);
    order.clear();
    expect(WorkspacePresentation.fromJson(state.toJson()).boxOrder, [
      'second',
      'first',
    ]);
    expect(
      WorkspacePresentation.fromJson({
        'boxOrder': ['a', 3, 'a', '', 'b'],
      }).boxOrder,
      ['a', 'b'],
    );
    expect(WorkspacePresentation.fromJson(null).boxOrder, isEmpty);
  });
  test('legacy workspace starts in terminals with collapsed inspector', () {
    final state = WorkspacePresentation.fromJson(null);
    expect(state.mode, WorkspaceViewMode.terminals);
    expect(state.inspectorOpen, isFalse);
    expect(state.boxesPreviewFraction, .60);
    expect(state.graphPreviewFraction, .35);
  });
  test('each mode retains its independent preview height', () {
    var state = const WorkspacePresentation().copyWith(
      mode: WorkspaceViewMode.boxes,
    );
    state = state.copyWith(
      selectedBoxId: 'stable-box',
      previewFraction: .70,
      inspectorOpen: true,
    );
    state = state
        .copyWith(mode: WorkspaceViewMode.graph)
        .copyWith(previewFraction: .45);
    final restored = WorkspacePresentation.fromJson(state.toJson());
    expect(restored.selectedBoxId, 'stable-box');
    expect(restored.boxesPreviewFraction, .70);
    expect(restored.graphPreviewFraction, .45);
    expect(restored.mode, WorkspaceViewMode.graph);
    expect(restored.inspectorOpen, isTrue);
  });
  test('unknown mode and invalid dimensions have safe defaults', () {
    final state = WorkspacePresentation.fromJson({
      'mode': 'future-mode',
      'inspectorWidth': double.nan,
      'boxesPreviewFraction': 9,
      'graphPreviewFraction': -1,
    });
    expect(state.mode, WorkspaceViewMode.terminals);
    expect(state.inspectorWidth, 340);
    expect(state.boxesPreviewFraction, .80);
    expect(state.graphPreviewFraction, .20);
  });
}
