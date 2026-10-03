import 'package:meta/meta.dart';

/// A validated, immutable measurement of the terminal surface.
///
/// Logical values describe the Flutter view. Physical values describe the
/// surface supplied to the terminal engine and the mouse encoder. Construction
/// rejects non-finite, empty, or protocol-unrepresentable measurements; callers
/// can therefore commit every non-null instance without repeating validation.
@immutable
@internal
final class SurfaceGeometry {
  /// Maximum grid dimension representable by the native terminal geometry.
  static const _maxGridDimension = 0xffff;

  /// Maximum physical dimension representable by mouse-coordinate encoding.
  static const _maxMouseDimension = 0xffffffff;

  final int cols;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final double paddingLeft;
  final double paddingRight;
  final double paddingTop;
  final double paddingBottom;
  final double devicePixelRatio;
  final int cellWidthPx;
  final int cellHeightPx;
  final int paddingLeftPx;
  final int paddingRightPx;
  final int paddingTopPx;
  final int paddingBottomPx;
  final int screenWidth;
  final int screenHeight;

  const SurfaceGeometry._({
    required this.cols,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
    required this.paddingLeft,
    required this.paddingRight,
    required this.paddingTop,
    required this.paddingBottom,
    required this.devicePixelRatio,
    required this.cellWidthPx,
    required this.cellHeightPx,
    required this.paddingLeftPx,
    required this.paddingRightPx,
    required this.paddingTopPx,
    required this.paddingBottomPx,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  int get hashCode => Object.hash(
    cols,
    rows,
    cellWidth,
    cellHeight,
    paddingLeft,
    paddingRight,
    paddingTop,
    paddingBottom,
    devicePixelRatio,
  );

  @override
  bool operator ==(Object other) {
    return other is SurfaceGeometry &&
        other.cols == cols &&
        other.rows == rows &&
        other.cellWidth == cellWidth &&
        other.cellHeight == cellHeight &&
        other.paddingLeft == paddingLeft &&
        other.paddingRight == paddingRight &&
        other.paddingTop == paddingTop &&
        other.paddingBottom == paddingBottom &&
        other.devicePixelRatio == devicePixelRatio;
  }

  /// Creates validated geometry from [measurement].
  ///
  /// Returns `null` when a logical value is invalid, a cell rounds to zero
  /// physical pixels, or a derived physical value exceeds its C ABI field.
  static SurfaceGeometry? tryFrom(SurfaceMeasurement measurement) {
    if (measurement.cols <= 0 ||
        measurement.cols > _maxGridDimension ||
        measurement.rows <= 0 ||
        measurement.rows > _maxGridDimension ||
        !_isPositive(measurement.cellWidth) ||
        !_isPositive(measurement.cellHeight) ||
        !_isNonNegative(measurement.paddingLeft) ||
        !_isNonNegative(measurement.paddingRight) ||
        !_isNonNegative(measurement.paddingTop) ||
        !_isNonNegative(measurement.paddingBottom) ||
        !_isPositive(measurement.devicePixelRatio)) {
      return null;
    }

    final dpr = measurement.devicePixelRatio;
    final cellWidthPx = _physicalPixels(
      measurement.cellWidth,
      dpr,
      nonZero: true,
    );
    final cellHeightPx = _physicalPixels(
      measurement.cellHeight,
      dpr,
      nonZero: true,
    );
    final paddingLeftPx = _physicalPixels(measurement.paddingLeft, dpr);
    final paddingRightPx = _physicalPixels(measurement.paddingRight, dpr);
    final paddingTopPx = _physicalPixels(measurement.paddingTop, dpr);
    final paddingBottomPx = _physicalPixels(measurement.paddingBottom, dpr);
    if (cellWidthPx == null ||
        cellHeightPx == null ||
        paddingLeftPx == null ||
        paddingRightPx == null ||
        paddingTopPx == null ||
        paddingBottomPx == null) {
      return null;
    }

    final screenWidth =
        measurement.cols * cellWidthPx + paddingLeftPx + paddingRightPx;
    final screenHeight =
        measurement.rows * cellHeightPx + paddingTopPx + paddingBottomPx;
    if (screenWidth > _maxMouseDimension || screenHeight > _maxMouseDimension) {
      return null;
    }

    return SurfaceGeometry._(
      cols: measurement.cols,
      rows: measurement.rows,
      cellWidth: measurement.cellWidth,
      cellHeight: measurement.cellHeight,
      paddingLeft: measurement.paddingLeft,
      paddingRight: measurement.paddingRight,
      paddingTop: measurement.paddingTop,
      paddingBottom: measurement.paddingBottom,
      devicePixelRatio: measurement.devicePixelRatio,
      cellWidthPx: cellWidthPx,
      cellHeightPx: cellHeightPx,
      paddingLeftPx: paddingLeftPx,
      paddingRightPx: paddingRightPx,
      paddingTopPx: paddingTopPx,
      paddingBottomPx: paddingBottomPx,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );
  }

  static bool _isNonNegative(double value) => value.isFinite && value >= 0;

  static bool _isPositive(double value) => value.isFinite && value > 0;

  static int? _physicalPixels(
    double logicalPixels,
    double devicePixelRatio, {
    bool nonZero = false,
  }) {
    final physicalPixels = logicalPixels * devicePixelRatio;
    if (!physicalPixels.isFinite || physicalPixels > _maxMouseDimension) {
      return null;
    }
    final pixels = physicalPixels.round();
    return nonZero && pixels == 0 ? null : pixels;
  }
}

/// A complete terminal surface measurement in logical pixels.
///
/// The renderer produces this value; the controller validates and commits it
/// before input and selection consume the resulting [SurfaceGeometry]. One
/// value contains the grid, cell metrics, surface padding, and device scale so
/// no consumer can observe a partially updated measurement.
@internal
@immutable
final class SurfaceMeasurement {
  /// Number of measured terminal columns.
  final int cols;

  /// Number of measured terminal rows.
  final int rows;

  /// Logical width of one terminal cell.
  final double cellWidth;

  /// Logical height of one terminal cell.
  final double cellHeight;

  /// Logical padding before the grid's horizontal origin.
  final double paddingLeft;

  /// Logical padding after the grid's horizontal extent.
  final double paddingRight;

  /// Logical padding before the grid's vertical origin.
  final double paddingTop;

  /// Logical padding after the grid's vertical extent.
  final double paddingBottom;

  /// Number of physical pixels represented by one logical pixel.
  final double devicePixelRatio;

  const SurfaceMeasurement({
    required this.cols,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
    required this.paddingLeft,
    required this.paddingRight,
    required this.paddingTop,
    required this.paddingBottom,
    required this.devicePixelRatio,
  });

  @override
  int get hashCode => Object.hash(
    cols,
    rows,
    cellWidth,
    cellHeight,
    paddingLeft,
    paddingRight,
    paddingTop,
    paddingBottom,
    devicePixelRatio,
  );

  @override
  bool operator ==(Object other) {
    return other is SurfaceMeasurement &&
        other.cols == cols &&
        other.rows == rows &&
        other.cellWidth == cellWidth &&
        other.cellHeight == cellHeight &&
        other.paddingLeft == paddingLeft &&
        other.paddingRight == paddingRight &&
        other.paddingTop == paddingTop &&
        other.paddingBottom == paddingBottom &&
        other.devicePixelRatio == devicePixelRatio;
  }
}
