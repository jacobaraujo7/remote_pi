import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../domain/entities/board_document.dart';
import '../../domain/services/board_svg.dart' show BoardRoute;

List<Offset> boardRouteOffsets(BoardRoute route) {
  final a = Offset(route.start.x, route.start.y);
  final b = Offset(route.end.x, route.end.y);
  final mid = (a + b) / 2;
  return route.vertical
      ? [a, Offset(a.dx, mid.dy), Offset(b.dx, mid.dy), b]
      : [a, Offset(mid.dx, a.dy), Offset(mid.dx, b.dy), b];
}

Color boardColor(String rgb) =>
    Color(0xff000000 | int.parse(rgb.substring(1), radix: 16));

class BoardPainter extends CustomPainter {
  BoardPainter(
    this.items,
    this.route,
    this.selected,
    this.ink,
    this.bg,
    this.accent,
    this.labelStyle, {
    this.origin = Offset.zero,
    this.thumbnails = const {},
  });
  final Offset origin;
  final Map<BoardItem, ui.Image> thumbnails;
  final List<BoardItem> items;
  final List<Offset> Function(BoardItem) route;
  final Set<String> selected;
  final Color ink, bg, accent;
  final TextStyle labelStyle;
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.translate(origin.dx, origin.dy);
    void line(List<Offset> pts, Paint paint) {
      if (pts.isEmpty) return;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path, paint);
    }

    for (final i in items) {
      final tint = i.color == null ? null : boardColor(i.color!);
      final fill =
          tint ??
          (i.kind == BoardKind.note
              ? Color.alphaBlend(accent.withValues(alpha: .18), bg)
              : bg);
      final labelInk = tint == null
          ? ink
          : i.usesInkColor
          ? tint
          : boardColor(i.contrastInk);
      final paint = Paint()
        ..color = i.usesInkColor && tint != null
            ? tint
            : selected.contains(i.id)
            ? accent
            : ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected.contains(i.id) ? 2.5 : 1.5;
      var rect = Rect.fromLTWH(i.x, i.y, i.width, i.height);
      if (i.kind == BoardKind.arrow) {
        final pts = route(i);
        line(pts, paint);
        final end = pts.last, dir = (end - pts[2]).direction;
        for (final a in [-.48, .48]) {
          c.drawLine(end, end - Offset.fromDirection(dir + a, 9), paint);
        }
        rect = Rect.fromCenter(
          center: Offset.lerp(pts[1], pts[2], .5)!,
          width: 120,
          height: 34,
        );
      } else if (i.kind == BoardKind.stroke) {
        if (i.width <= 1 && i.height <= 1) {
          c.drawCircle(Offset(i.x, i.y), 1, Paint()..color = paint.color);
        } else {
          line([for (final p in i.points) Offset(i.x + p.x, i.y + p.y)], paint);
        }
        continue;
      } else if (i.kind != BoardKind.text) {
        final path = Path();
        if (i.kind == BoardKind.decision) {
          path.addPolygon([
            rect.topCenter,
            rect.centerRight,
            rect.bottomCenter,
            rect.centerLeft,
          ], true);
        } else {
          path.addRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          );
        }
        c.drawPath(path, Paint()..color = fill);
        c.drawPath(path, paint);
      }
      if (i.kind == BoardKind.text && selected.contains(i.id)) {
        c.drawRect(rect, paint);
      }
      if (i.kind == BoardKind.mermaid && i.thumbnail != null) {
        final image = thumbnails[i];
        if (image != null) {
          paintImage(canvas: c, rect: rect, image: image, fit: BoxFit.contain);
        }
        continue;
      }
      if (i.label.isEmpty) continue;
      final text = TextPainter(
        text: TextSpan(
          text: i.kind == BoardKind.mermaid
              ? 'Mermaid\n${i.label.split('\n').first}'
              : i.label,
          style: labelStyle.copyWith(color: labelInk),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, rect.width - 4));
      final origin = rect.center - Offset(text.width / 2, text.height / 2);
      if (i.kind == BoardKind.arrow) {
        final caption = (origin & text.size).inflate(3);
        var captionBg = bg;
        if (tint != null) {
          final foreground = tint.computeLuminance();
          final background = bg.computeLuminance();
          final contrast =
              (math.max(foreground, background) + .05) /
              (math.min(foreground, background) + .05);
          if (contrast < 4.5) captionBg = boardColor(i.contrastInk);
        }
        c.drawRRect(
          RRect.fromRectAndRadius(caption, const Radius.circular(3)),
          Paint()..color = captionBg,
        );
      }
      text.paint(c, origin);
      text.dispose();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(BoardPainter old) => true;
}
