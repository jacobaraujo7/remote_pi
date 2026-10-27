enum OrchestrationViewMode { boxes, graph }

/// Local presentation of the dockable app; never controls terminal geometry.
class OrchestrationPresentation {
  const OrchestrationPresentation({
    this.mode = OrchestrationViewMode.boxes,
    this.selectedBoxId,
    this.boxOrder = const [],
    this.inspectorOpen = false,
    this.inspectorWidth = 340,
  });
  final OrchestrationViewMode mode;
  final String? selectedBoxId;
  final List<String> boxOrder;
  final bool inspectorOpen;
  final double inspectorWidth;
  OrchestrationPresentation copyWith({
    OrchestrationViewMode? mode,
    String? selectedBoxId,
    List<String>? boxOrder,
    bool? inspectorOpen,
    double? inspectorWidth,
  }) => OrchestrationPresentation(
    mode: mode ?? this.mode,
    selectedBoxId: selectedBoxId ?? this.selectedBoxId,
    boxOrder: boxOrder == null ? this.boxOrder : List.unmodifiable(boxOrder),
    inspectorOpen: inspectorOpen ?? this.inspectorOpen,
    inspectorWidth: inspectorWidth ?? this.inspectorWidth,
  );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'selectedBoxId': selectedBoxId,
    'boxOrder': boxOrder,
    'inspectorOpen': inspectorOpen,
    'inspectorWidth': inspectorWidth,
  };
  factory OrchestrationPresentation.fromJson(Object? raw) {
    if (raw is! Map) return const OrchestrationPresentation();
    final width = raw['inspectorWidth'];
    return OrchestrationPresentation(
      mode: raw['mode'] == 'graph'
          ? OrchestrationViewMode.graph
          : OrchestrationViewMode.boxes,
      selectedBoxId: raw['selectedBoxId'] is String
          ? raw['selectedBoxId']
          : null,
      boxOrder: raw['boxOrder'] is List
          ? List.unmodifiable(
              (raw['boxOrder'] as List).whereType<String>().toSet(),
            )
          : const [],
      inspectorOpen: raw['inspectorOpen'] == true,
      inspectorWidth: width is num && width.isFinite
          ? width.toDouble().clamp(280, 520)
          : 340,
    );
  }
}
