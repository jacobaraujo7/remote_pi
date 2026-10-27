enum OrchestrationViewMode { boxes, graph }

/// Local presentation of one dockable document; never changes the outer dock.
class OrchestrationPresentation {
  const OrchestrationPresentation({
    this.mode = OrchestrationViewMode.boxes,
    this.selectedBoxId,
    this.boxOrder = const [],
    this.inspectorOpen = false,
    this.inspectorWidth = 340,
    this.boxesTerminalFraction = .6,
    this.graphTerminalFraction = .35,
  });
  final OrchestrationViewMode mode;
  final String? selectedBoxId;
  final List<String> boxOrder;
  final bool inspectorOpen;
  final double inspectorWidth;
  final double boxesTerminalFraction;
  final double graphTerminalFraction;
  double get terminalFraction => mode == OrchestrationViewMode.boxes
      ? boxesTerminalFraction
      : graphTerminalFraction;
  OrchestrationPresentation copyWith({
    OrchestrationViewMode? mode,
    String? selectedBoxId,
    List<String>? boxOrder,
    bool? inspectorOpen,
    double? inspectorWidth,
    double? boxesTerminalFraction,
    double? graphTerminalFraction,
  }) => OrchestrationPresentation(
    mode: mode ?? this.mode,
    selectedBoxId: selectedBoxId ?? this.selectedBoxId,
    boxOrder: boxOrder == null ? this.boxOrder : List.unmodifiable(boxOrder),
    inspectorOpen: inspectorOpen ?? this.inspectorOpen,
    inspectorWidth: inspectorWidth ?? this.inspectorWidth,
    boxesTerminalFraction: boxesTerminalFraction ?? this.boxesTerminalFraction,
    graphTerminalFraction: graphTerminalFraction ?? this.graphTerminalFraction,
  );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'selectedBoxId': selectedBoxId,
    'boxOrder': boxOrder,
    'inspectorOpen': inspectorOpen,
    'inspectorWidth': inspectorWidth,
    'boxesTerminalFraction': boxesTerminalFraction,
    'graphTerminalFraction': graphTerminalFraction,
  };
  factory OrchestrationPresentation.fromJson(Object? raw) {
    if (raw is! Map) return const OrchestrationPresentation();
    final width = raw['inspectorWidth'];
    double fraction(String key, double fallback) {
      final value = raw[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(.15, .85)
          : fallback;
    }

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
      boxesTerminalFraction: fraction('boxesTerminalFraction', .6),
      graphTerminalFraction: fraction('graphTerminalFraction', .35),
      inspectorWidth: width is num && width.isFinite
          ? width.toDouble().clamp(280, 520)
          : 340,
    );
  }
}
