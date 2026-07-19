import 'dart:math' as math;
import 'dart:ui';

/// Procedurally paints **Block Elements** (`U+2580–U+259F`) and **Box Drawing**
/// (`U+2500–U+257F`) glyphs, filling the cell exactly so they tile seamlessly
/// across cells — exactly what native terminals (iTerm2, kitty, Ghostty, …) do.
///
/// Drawing these from the font (via `drawParagraph`) leaves hairline gaps
/// between cells: the font glyph is painted at its natural size, not stretched
/// to the cell box, so stacked half-blocks (`▀▄█`) used for pixel-art (e.g. the
/// Claude Code mascot) come out striped, and box borders don't connect.
///
/// Returns `true` if [codepoint] was handled (caller must then skip the font
/// glyph); `false` for anything not covered here (it falls back to the font, so
/// there is never a regression — only the gap-prone glyphs are intercepted).
bool paintBuiltinGlyph(
  Canvas canvas,
  Offset offset,
  Size cell,
  int codepoint,
  Color color,
) {
  if (codepoint >= 0x2580 && codepoint <= 0x259F) {
    _paintBlockElement(canvas, offset, cell, codepoint, color);
    return true;
  }
  final arms = _boxArms[codepoint];
  if (arms != null) {
    _paintBoxDrawing(
      canvas,
      offset,
      cell,
      arms,
      color,
      _rounded.contains(codepoint),
    );
    return true;
  }
  return false;
}

/// Draws [r] but extends its right/bottom edge by 1px **when that edge sits on
/// the cell boundary**, so same-colored fills in adjacent cells overlap instead
/// of leaving a sub-pixel seam. Cell origin/size are fractional, so abutting
/// rects can otherwise miss a column/row of pixels — which both shows the
/// background through (vertical seam) and thins the overall ink (looks paler).
/// Mirrors the `width + 1` trick the cell-background painter already uses.
void _edgeFill(Canvas canvas, Rect r, Offset o, Size cell, Paint paint) {
  final touchesRight = (r.right - (o.dx + cell.width)).abs() < 0.5;
  final touchesBottom = (r.bottom - (o.dy + cell.height)).abs() < 0.5;
  canvas.drawRect(
    Rect.fromLTRB(
      r.left,
      r.top,
      touchesRight ? r.right + 1.0 : r.right,
      touchesBottom ? r.bottom + 1.0 : r.bottom,
    ),
    paint,
  );
}

// ===========================================================================
// Block Elements — U+2580..U+259F
// ===========================================================================

void _paintBlockElement(
  Canvas canvas,
  Offset o,
  Size cell,
  int cp,
  Color color,
) {
  final w = cell.width;
  final h = cell.height;
  final paint = Paint()..isAntiAlias = false;

  // Shade blocks ░▒▓ — fill the whole cell with reduced opacity.
  if (cp >= 0x2591 && cp <= 0x2593) {
    const opacities = [0.25, 0.5, 0.75];
    paint.color = color.withValues(alpha: color.a * opacities[cp - 0x2591]);
    _edgeFill(canvas, o & cell, o, cell, paint);
    return;
  }

  // Quadrants ▖▗▘▙▚▛▜▝▞▟ — up to four w/2 × h/2 sub-cells.
  if (cp >= 0x2596 && cp <= 0x259F) {
    paint.color = color;
    final q = _quadrants[cp - 0x2596];
    final mx = o.dx + w / 2;
    final my = o.dy + h / 2;
    if (q & _ul != 0) {
      _edgeFill(
        canvas,
        Rect.fromLTWH(o.dx, o.dy, w / 2, h / 2),
        o,
        cell,
        paint,
      );
    }
    if (q & _ur != 0) {
      _edgeFill(canvas, Rect.fromLTWH(mx, o.dy, w / 2, h / 2), o, cell, paint);
    }
    if (q & _ll != 0) {
      _edgeFill(canvas, Rect.fromLTWH(o.dx, my, w / 2, h / 2), o, cell, paint);
    }
    if (q & _lr != 0) {
      _edgeFill(canvas, Rect.fromLTWH(mx, my, w / 2, h / 2), o, cell, paint);
    }
    return;
  }

  paint.color = color;
  final Rect r;
  switch (cp) {
    case 0x2580: // ▀ upper half
      r = Rect.fromLTWH(o.dx, o.dy, w, h / 2);
    case 0x2588: // █ full block
      r = o & cell;
    case 0x2590: // ▐ right half
      r = Rect.fromLTWH(o.dx + w / 2, o.dy, w / 2, h);
    case 0x2594: // ▔ upper one eighth
      r = Rect.fromLTWH(o.dx, o.dy, w, h / 8);
    case 0x2595: // ▕ right one eighth
      r = Rect.fromLTWH(o.dx + w * 7 / 8, o.dy, w / 8, h);
    case >= 0x2581 && <= 0x2587: // ▁▂▃▄▅▆▇ lower 1/8..7/8
      final eighths = cp - 0x2580;
      final hh = h * eighths / 8;
      r = Rect.fromLTWH(o.dx, o.dy + h - hh, w, hh);
    case >= 0x2589 && <= 0x258F: // ▉▊▋▌▍▎▏ left 7/8..1/8
      final eighths = 8 - (cp - 0x2588);
      r = Rect.fromLTWH(o.dx, o.dy, w * eighths / 8, h);
    default:
      return;
  }
  _edgeFill(canvas, r, o, cell, paint);
}

const _ul = 1, _ur = 2, _ll = 4, _lr = 8;

/// Quadrant masks for U+2596..U+259F, in order.
const _quadrants = <int>[
  _ll, // ▖
  _lr, // ▗
  _ul, // ▘
  _ul | _ll | _lr, // ▙
  _ul | _lr, // ▚
  _ul | _ur | _ll, // ▛
  _ul | _ur | _lr, // ▜
  _ur, // ▝
  _ur | _ll, // ▞
  _ur | _ll | _lr, // ▟
];

// ===========================================================================
// Box Drawing — U+2500..U+257F (lines, corners, junctions, half-lines)
// ===========================================================================
//
// Each glyph is encoded as four 2-bit arms (0 none, 1 light, 2 heavy) packed as
// up | right<<2 | down<<4 | left<<6. Double-line, dashed and diagonal variants
// are intentionally omitted (they fall back to the font).

int _arm(int u, int r, int d, int l) => u | (r << 2) | (d << 4) | (l << 6);

final Map<int, int> _boxArms = {
  0x2500: _arm(0, 1, 0, 1), // ─
  0x2501: _arm(0, 2, 0, 2), // ━
  0x2502: _arm(1, 0, 1, 0), // │
  0x2503: _arm(2, 0, 2, 0), // ┃
  0x250C: _arm(0, 1, 1, 0), // ┌
  0x250D: _arm(0, 2, 1, 0), // ┍
  0x250E: _arm(0, 1, 2, 0), // ┎
  0x250F: _arm(0, 2, 2, 0), // ┏
  0x2510: _arm(0, 0, 1, 1), // ┐
  0x2511: _arm(0, 0, 1, 2), // ┑
  0x2512: _arm(0, 0, 2, 1), // ┒
  0x2513: _arm(0, 0, 2, 2), // ┓
  0x2514: _arm(1, 1, 0, 0), // └
  0x2515: _arm(1, 2, 0, 0), // ┕
  0x2516: _arm(2, 1, 0, 0), // ┖
  0x2517: _arm(2, 2, 0, 0), // ┗
  0x2518: _arm(1, 0, 0, 1), // ┘
  0x2519: _arm(1, 0, 0, 2), // ┙
  0x251A: _arm(2, 0, 0, 1), // ┚
  0x251B: _arm(2, 0, 0, 2), // ┛
  0x251C: _arm(1, 1, 1, 0), // ├
  0x251D: _arm(1, 2, 1, 0), // ┝
  0x251E: _arm(2, 1, 1, 0), // ┞
  0x251F: _arm(1, 1, 2, 0), // ┟
  0x2520: _arm(2, 1, 2, 0), // ┠
  0x2521: _arm(2, 2, 1, 0), // ┡
  0x2522: _arm(1, 2, 2, 0), // ┢
  0x2523: _arm(2, 2, 2, 0), // ┣
  0x2524: _arm(1, 0, 1, 1), // ┤
  0x2525: _arm(1, 0, 1, 2), // ┥
  0x2526: _arm(2, 0, 1, 1), // ┦
  0x2527: _arm(1, 0, 2, 1), // ┧
  0x2528: _arm(2, 0, 2, 1), // ┨
  0x2529: _arm(2, 0, 1, 2), // ┩
  0x252A: _arm(1, 0, 2, 2), // ┪
  0x252B: _arm(2, 0, 2, 2), // ┫
  0x252C: _arm(0, 1, 1, 1), // ┬
  0x252D: _arm(0, 1, 1, 2), // ┭
  0x252E: _arm(0, 2, 1, 1), // ┮
  0x252F: _arm(0, 2, 1, 2), // ┯
  0x2530: _arm(0, 1, 2, 1), // ┰
  0x2531: _arm(0, 1, 2, 2), // ┱
  0x2532: _arm(0, 2, 2, 1), // ┲
  0x2533: _arm(0, 2, 2, 2), // ┳
  0x2534: _arm(1, 1, 0, 1), // ┴
  0x2535: _arm(1, 1, 0, 2), // ┵
  0x2536: _arm(1, 2, 0, 1), // ┶
  0x2537: _arm(1, 2, 0, 2), // ┷
  0x2538: _arm(2, 1, 0, 1), // ┸
  0x2539: _arm(2, 1, 0, 2), // ┹
  0x253A: _arm(2, 2, 0, 1), // ┺
  0x253B: _arm(2, 2, 0, 2), // ┻
  0x253C: _arm(1, 1, 1, 1), // ┼
  0x253D: _arm(1, 1, 1, 2), // ┽
  0x253E: _arm(1, 2, 1, 1), // ┾
  0x253F: _arm(1, 2, 1, 2), // ┿
  0x2540: _arm(2, 1, 1, 1), // ╀
  0x2541: _arm(1, 1, 2, 1), // ╁
  0x2542: _arm(2, 1, 2, 1), // ╂
  0x2543: _arm(2, 1, 1, 2), // ╃
  0x2544: _arm(2, 2, 1, 1), // ╄
  0x2545: _arm(1, 1, 2, 2), // ╅
  0x2546: _arm(1, 2, 2, 1), // ╆
  0x2547: _arm(2, 2, 1, 2), // ╇
  0x2548: _arm(1, 2, 2, 2), // ╈
  0x2549: _arm(2, 1, 2, 2), // ╉
  0x254A: _arm(2, 2, 2, 1), // ╊
  0x254B: _arm(2, 2, 2, 2), // ╋
  // Half lines
  0x2574: _arm(0, 0, 0, 1), // ╴
  0x2575: _arm(1, 0, 0, 0), // ╵
  0x2576: _arm(0, 1, 0, 0), // ╶
  0x2577: _arm(0, 0, 1, 0), // ╷
  0x2578: _arm(0, 0, 0, 2), // ╸
  0x2579: _arm(2, 0, 0, 0), // ╹
  0x257A: _arm(0, 2, 0, 0), // ╺
  0x257B: _arm(0, 0, 2, 0), // ╻
  0x257C: _arm(0, 2, 0, 1), // ╼
  0x257D: _arm(1, 0, 2, 0), // ╽
  0x257E: _arm(0, 1, 0, 2), // ╾
  0x257F: _arm(2, 0, 1, 0), // ╿
  // Rounded (light) corners — see [_rounded]
  0x256D: _arm(0, 1, 1, 0), // ╭
  0x256E: _arm(0, 0, 1, 1), // ╮
  0x256F: _arm(1, 0, 0, 1), // ╯
  0x2570: _arm(1, 1, 0, 0), // ╰
};

const Set<int> _rounded = {0x256D, 0x256E, 0x256F, 0x2570};

double _lineWidth(Size cell, bool heavy) {
  final base = (cell.width / 8).clamp(1.0, 3.0);
  final w = heavy ? base * 2 : base;
  return w.roundToDouble().clamp(1.0, double.infinity);
}

void _paintBoxDrawing(
  Canvas canvas,
  Offset o,
  Size cell,
  int arms,
  Color color,
  bool rounded,
) {
  final w = cell.width;
  final h = cell.height;
  final cx = o.dx + w / 2;
  final cy = o.dy + h / 2;
  final light = _lineWidth(cell, false);
  final heavy = _lineWidth(cell, true);
  final paint = Paint()
    ..color = color
    ..isAntiAlias = false;

  final u = arms & 0x3;
  final r = (arms >> 2) & 0x3;
  final d = (arms >> 4) & 0x3;
  final l = (arms >> 6) & 0x3;

  double tw(int arm) => arm == 2 ? heavy : light;

  if (rounded) {
    _paintRoundedCorner(canvas, o, cell, cx, cy, u, r, d, l, light, paint);
    return;
  }

  // Solid center square sized to the thickest arm, so junctions never gap.
  var maxT = 0.0;
  for (final arm in [u, r, d, l]) {
    if (arm != 0) maxT = math.max(maxT, tw(arm));
  }
  if (maxT > 0) {
    canvas.drawRect(
      Rect.fromLTRB(cx - maxT / 2, cy - maxT / 2, cx + maxT / 2, cy + maxT / 2),
      paint,
    );
  }

  if (u != 0) {
    final t = tw(u);
    _edgeFill(
      canvas,
      Rect.fromLTRB(cx - t / 2, o.dy, cx + t / 2, cy),
      o,
      cell,
      paint,
    );
  }
  if (d != 0) {
    final t = tw(d);
    _edgeFill(
      canvas,
      Rect.fromLTRB(cx - t / 2, cy, cx + t / 2, o.dy + h),
      o,
      cell,
      paint,
    );
  }
  if (l != 0) {
    final t = tw(l);
    _edgeFill(
      canvas,
      Rect.fromLTRB(o.dx, cy - t / 2, cx, cy + t / 2),
      o,
      cell,
      paint,
    );
  }
  if (r != 0) {
    final t = tw(r);
    _edgeFill(
      canvas,
      Rect.fromLTRB(cx, cy - t / 2, o.dx + w, cy + t / 2),
      o,
      cell,
      paint,
    );
  }
}

/// Light rounded corner: two straight arms up to a quarter-circle that smooths
/// the bend. The straight parts still reach the cell edges, so they connect to
/// neighbouring box glyphs.
void _paintRoundedCorner(
  Canvas canvas,
  Offset o,
  Size cell,
  double cx,
  double cy,
  int u,
  int r,
  int d,
  int l,
  double t,
  Paint paint,
) {
  final w = cell.width;
  final h = cell.height;
  final radius = math.min(w, h) / 2;
  final stroke = Paint()
    ..color = paint.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = t
    ..isAntiAlias = true;

  // Straight arm rectangles from the cell edge to the arc tangent point.
  if (u != 0) {
    canvas.drawRect(
      Rect.fromLTRB(cx - t / 2, o.dy, cx + t / 2, cy - radius),
      paint,
    );
  }
  if (d != 0) {
    canvas.drawRect(
      Rect.fromLTRB(cx - t / 2, cy + radius, cx + t / 2, o.dy + h),
      paint,
    );
  }
  if (l != 0) {
    canvas.drawRect(
      Rect.fromLTRB(o.dx, cy - t / 2, cx - radius, cy + t / 2),
      paint,
    );
  }
  if (r != 0) {
    canvas.drawRect(
      Rect.fromLTRB(cx + radius, cy - t / 2, o.dx + w, cy + t / 2),
      paint,
    );
  }

  // Quarter-circle joining the two present arms. Center is diagonally opposite
  // the bend; the swept quarter faces the corner.
  final Offset center;
  final double startAngle;
  if (d != 0 && r != 0) {
    center = Offset(cx + radius, cy + radius); // ╭
    startAngle = math.pi;
  } else if (d != 0 && l != 0) {
    center = Offset(cx - radius, cy + radius); // ╮
    startAngle = -math.pi / 2;
  } else if (u != 0 && l != 0) {
    center = Offset(cx - radius, cy - radius); // ╯
    startAngle = 0;
  } else {
    center = Offset(cx + radius, cy - radius); // ╰ (u && r)
    startAngle = math.pi / 2;
  }
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: radius),
    startAngle,
    math.pi / 2,
    false,
    stroke,
  );
}
