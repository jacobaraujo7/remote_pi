enum WorkspaceViewMode { terminals, boxes, graph }

/// Presentation preferences are independent of the saved terminal pane tree.
class WorkspacePresentation {
  const WorkspacePresentation({
    this.mode = WorkspaceViewMode.terminals,
    this.selectedBoxId,
    this.inspectorOpen = false,
    this.inspectorWidth = 340,
    this.boxesPreviewFraction = .60,
    this.graphPreviewFraction = .35,
  });
  final WorkspaceViewMode mode;
  final String? selectedBoxId;
  final bool inspectorOpen;
  final double inspectorWidth;
  final double boxesPreviewFraction;
  final double graphPreviewFraction;
  double get previewFraction => mode == WorkspaceViewMode.boxes
      ? boxesPreviewFraction
      : graphPreviewFraction;

  WorkspacePresentation copyWith({
    WorkspaceViewMode? mode,
    String? selectedBoxId,
    bool? inspectorOpen,
    double? inspectorWidth,
    double? previewFraction,
  }) => WorkspacePresentation(
    mode: mode ?? this.mode,
    selectedBoxId: selectedBoxId ?? this.selectedBoxId,
    inspectorOpen: inspectorOpen ?? this.inspectorOpen,
    inspectorWidth: inspectorWidth ?? this.inspectorWidth,
    boxesPreviewFraction: (mode ?? this.mode) == WorkspaceViewMode.boxes
        ? previewFraction ?? boxesPreviewFraction
        : boxesPreviewFraction,
    graphPreviewFraction: (mode ?? this.mode) == WorkspaceViewMode.graph
        ? previewFraction ?? graphPreviewFraction
        : graphPreviewFraction,
  );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'selectedBoxId': selectedBoxId,
    'inspectorOpen': inspectorOpen,
    'inspectorWidth': inspectorWidth,
    'boxesPreviewFraction': boxesPreviewFraction,
    'graphPreviewFraction': graphPreviewFraction,
  };
  factory WorkspacePresentation.fromJson(Object? raw) {
    if (raw is! Map) return const WorkspacePresentation();
    double number(String key, double fallback, double min, double max) {
      final value = raw[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    return WorkspacePresentation(
      mode:
          WorkspaceViewMode.values
              .where((m) => m.name == raw['mode'])
              .firstOrNull ??
          WorkspaceViewMode.terminals,
      selectedBoxId: raw['selectedBoxId'] is String
          ? raw['selectedBoxId'] as String
          : null,
      inspectorOpen: raw['inspectorOpen'] == true,
      inspectorWidth: number('inspectorWidth', 340, 280, 460),
      boxesPreviewFraction: number('boxesPreviewFraction', .60, .20, .80),
      graphPreviewFraction: number('graphPreviewFraction', .35, .20, .80),
    );
  }
}
