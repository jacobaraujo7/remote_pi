import 'dart:ui';

import 'package:flutter/painting.dart';

import '../kitty_image_cache.dart';
import '../kitty_placement_cache.dart';
import '../paint_state.dart';

/// Paints one ordered Kitty graphics placement list.
///
/// The caller chooses where the list belongs in the surrounding paint order;
/// this painter only clips and draws the snapshots it receives.
class KittyGraphicsPainter {
  final Paint _paint;
  final PaintState _state;
  final KittyImageCache _cache;
  final List<KittyPlacementSnapshot> _snapshots;

  KittyGraphicsPainter({
    required this._cache,
    required this._state,
    required this._snapshots,
  }) : _paint = Paint()..filterQuality = .low;

  void paint(Canvas canvas) {
    if (_snapshots.isEmpty) return;
    final width = _state.cols * _state.metrics.cellWidth;
    final height = _state.rows * _state.metrics.cellHeight;
    if (width <= 0 || height <= 0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, width, height));
    for (final snap in _snapshots) {
      final cached = _cache.lookupById(snap.imageId);
      if (cached is! KittyImageReady ||
          cached.generation != snap.imageGeneration) {
        continue;
      }

      canvas.drawImageRect(cached.image, snap.src, snap.dst, _paint);
    }
    canvas.restore();
  }
}
