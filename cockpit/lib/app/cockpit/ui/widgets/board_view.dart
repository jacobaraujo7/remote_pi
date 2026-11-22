import 'board_painter.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:flutter/gestures.dart'
    show kDoubleTapTimeout, kDoubleTapSlop, kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import '../../domain/entities/board_document.dart';
import '../../domain/services/board_svg.dart' show boardRoute;
import '../../domain/entities/file_view.dart';
import '../../domain/services/board_editor.dart';
import '../session/file_viewer_session.dart';

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.session, required this.onSave});
  final FileViewerSession session;
  final Future<bool> Function(String) onSave;
  @override
  State<BoardView> createState() => _BoardState();
}

class _BoardState extends State<BoardView> {
  final viewport = GlobalKey();
  final transform = TransformationController();
  Rect sceneExtent = const Rect.fromLTWH(0, 0, 6000, 6000);
  Offset get sceneOrigin => -sceneExtent.topLeft;

  void includeGeometry(Iterable<BoardItem> items) {
    var extent = sceneExtent;
    for (final item in items) {
      if (item.kind != BoardKind.arrow) {
        extent = extent.expandToInclude(
          Rect.fromLTWH(item.x, item.y, item.width, item.height),
        );
      }
    }
    if (extent == sceneExtent) return;
    final delta = sceneExtent.topLeft - extent.topLeft;
    sceneExtent = extent;
    if (delta == Offset.zero) return;
    final matrix = transform.value.clone();
    final previous = matrix.getTranslation();
    final scale = matrix.getMaxScaleOnAxis();
    transform.value = matrix
      ..setTranslationRaw(
        previous.x - delta.dx * scale,
        previous.y - delta.dy * scale,
        previous.z,
      );
  }

  final label = TextEditingController();
  final history = <BoardEdit>[];
  BoardDocument? doc;
  BoardDocument? savedDocument;
  final selection = <String>{};

  BoardItem? dragItem;
  final dragOffset = ValueNotifier(Offset.zero);
  BoardItem? editing;
  Rect? lastEditorBounds;
  Duration? lastTap;
  Offset? lastTapPosition;
  String? lastTapId;
  bool editable(BoardItem? item) =>
      item != null &&
      item.kind != BoardKind.stroke &&
      item.kind != BoardKind.mermaid;

  Rect editorBounds(BoardItem item, {List<Offset>? path}) {
    final points = path ?? (item.kind == BoardKind.arrow ? route(item) : null);
    final mid = points == null
        ? center(item)
        : Offset.lerp(points[1], points[2], .5)!;
    return Rect.fromCenter(
      center: mid,
      width: item.kind == BoardKind.arrow ? 140 : math.max(64, item.width),
      height: math.max(36, math.min(100, item.height)),
    );
  }

  void zoomBy(double factor) {
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final middle = box.size.center(Offset.zero);
    final scene = transform.toScene(middle);
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      .001,
      5.0,
    );
    positionCamera(middle, scene, scale);
  }

  void positionCamera(Offset middle, Offset scene, double scale) {
    final offset = middle - scene * scale;
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
  }

  Rect itemBounds(BoardItem item) {
    if (item.kind != BoardKind.arrow) {
      return Rect.fromLTWH(item.x, item.y, item.width, item.height);
    }
    final path = route(item);
    final bounds = Rect.fromPoints(path.first, path.last).inflate(9);
    return item.label.isEmpty
        ? bounds
        : bounds.expandToInclude(editorBounds(item, path: path));
  }

  void revealItem(BoardItem item) {
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final visible = Rect.fromPoints(
      transform.toScene(Offset.zero),
      transform.toScene(box.size.bottomRight(Offset.zero)),
    );
    final bounds = itemBounds(item).shift(sceneOrigin);
    if (visible.contains(bounds.topLeft) &&
        visible.contains(bounds.bottomRight)) {
      return;
    }
    positionCamera(
      box.size.center(Offset.zero),
      bounds.center,
      transform.value.getMaxScaleOnAxis(),
    );
  }

  void fitItems(Iterable<BoardItem> items) {
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || items.isEmpty) return;
    final bounds = items.map(itemBounds).reduce((a, b) => a.expandToInclude(b));
    final scale = math
        .min(
          (box.size.width - 32) / math.max(1, bounds.width),
          (box.size.height - 32) / math.max(1, bounds.height),
        )
        .clamp(.001, 5.0);
    positionCamera(
      box.size.center(Offset.zero),
      bounds.center + sceneOrigin,
      scale,
    );
    canvasFocus.requestFocus();
  }

  void editLabel(BoardItem? item) {
    if (item == null || !editable(item)) return;
    setState(() {
      select(item.id);
      editing = item;
      lastEditorBounds = editorBounds(item);
      label.selection = TextSelection(
        baseOffset: 0,
        extentOffset: label.text.length,
      );
    });
    labelFocus.requestFocus();
  }

  bool finishLabel({bool discard = false}) {
    final original = editing;
    if (original == null) return true;
    final value = label.text;
    final current = doc?.items[original.id];
    final changed =
        !discard && value != original.label && value != current?.label;
    if (changed && current?.label != original.label) {
      return false;
    }
    setState(() => editing = null);
    if (changed && current != null) {
      unawaited(commit(BoardEdit.replace(doc!, current.edited(label: value))));
    }
    syncDirty();
    canvasFocus.requestFocus();
    return true;
  }

  Offset? start;
  String? source, selected, anchor, error;
  String tool = 'select';
  String? drawingColor;
  static Color swatch(String rgb) =>
      Color(0xff000000 | int.parse(rgb.substring(1), radix: 16));
  bool saving = false, advanced = false;
  final ink = _GesturePreview();
  final labelFocus = FocusNode();
  final canvasFocus = FocusNode();
  final pending = <({BoardEdit edit, Completer<bool> done, bool undo})>[];
  int? pointer;
  String? hovered, connectionStart;
  Offset? connectionPointer;
  bool spacePan = false;
  bool get navigating => spacePan || tool == 'pan';
  bool connectable(BoardItem? i) =>
      i != null && i.kind != BoardKind.arrow && i.kind != BoardKind.stroke;
  Offset handleCenter(BoardItem i) =>
      Offset(i.x + i.width + 6, i.y + i.height / 2);

  String? handleAt(Offset p) {
    if (tool != 'select' || navigating || editing != null) return null;
    final item = doc?.items[hovered] ?? doc?.items[selected];
    if (item != null &&
        connectable(item) &&
        (handleCenter(item) - p).distance <= 9) {
      return item.id;
    }
    return null;
  }

  String? targetAt(Offset p, String? from) {
    String? container;
    final tolerance = 4 / transform.value.getMaxScaleOnAxis();
    for (final i in doc!.paintOrder.reversed) {
      if (i.id == from || !connectable(i)) {
        continue;
      }
      if (!Rect.fromLTWH(
        i.x,
        i.y,
        i.width,
        i.height,
      ).inflate(tolerance).contains(p)) {
        continue;
      }
      if (i.kind != BoardKind.container && i.kind != BoardKind.lane) {
        return i.id;
      }
      container ??= i.id;
    }
    return container;
  }

  void previewConnection(String from, Offset p) {
    connectionPointer = p;
    keyboardTarget = null;
    final a = doc?.items[from];
    if (a == null) {
      ink.clear();
      return;
    }
    final b = doc?.items[targetAt(p, from)];
    previewTarget(a, b, p);
  }

  void previewTarget(BoardItem a, BoardItem? b, Offset p) {
    ink.connector(
      boardRouteOffsets(
        boardRoute(
          math.Rectangle(a.x, a.y, a.width, a.height),
          b == null
              ? math.Rectangle(p.dx, p.dy, 0, 0)
              : math.Rectangle(b.x, b.y, b.width, b.height),
        ),
      ),
      b == null ? null : Rect.fromLTWH(b.x, b.y, b.width, b.height),
      b?.kind == BoardKind.decision,
    );
  }

  void hover(PointerHoverEvent e) {
    if (editing != null || navigating || pointer != null || doc == null) return;
    if (anchor != null) {
      previewConnection(anchor!, (e.localPosition - sceneOrigin));
      return;
    }
    if (tool != 'select') return;
    final id =
        handleAt((e.localPosition - sceneOrigin)) ??
        targetAt((e.localPosition - sceneOrigin), null);
    final next = connectable(doc!.items[id]) ? id : null;
    if (next != hovered) setState(() => hovered = next);
  }

  Future<void> finishConnection(String from, Offset p) async {
    final to = targetAt(p, from);
    await connectItems(from, to);
  }

  Future<void> connectItems(String from, String? to) async {
    setState(() {
      anchor = null;
      connectionStart = null;
      keyboardTarget = null;
    });
    ink.clear();
    if (from == to ||
        !connectable(doc?.items[from]) ||
        !connectable(doc?.items[to])) {
      return;
    }
    final edge = BoardItem(
      BoardDocument.newId(),
      BoardKind.arrow,
      0,
      0,
      from: from,
      to: to,
      color: drawingColor,
    );
    await commit(BoardEdit.replace(doc!, edge));
  }

  String? keyboardTarget;

  bool traverseItems({required bool backwards}) {
    final all = doc?.items.values;
    if (all == null || all.isEmpty) return false;
    final from = anchor;
    final candidates = all
        .where((item) => from == null || (item.id != from && connectable(item)))
        .toList();
    if (candidates.isEmpty) return false;
    final id = from == null ? selected : keyboardTarget;
    final currentIndex = candidates.indexWhere((item) => item.id == id);
    final index = currentIndex < 0
        ? (backwards ? candidates.length - 1 : 0)
        : currentIndex + (backwards ? -1 : 1);
    // Let Flutter traverse out of the canvas at either boundary.
    if (from == null && (index < 0 || index >= candidates.length)) return false;
    final item = candidates[index % candidates.length];
    if (from == null) {
      setState(() => select(item.id));
    } else {
      final origin = doc!.items[from];
      if (origin == null) return false;
      connectionPointer = null;
      setState(() => keyboardTarget = item.id);
      previewTarget(origin, item, center(item));
    }
    revealItem(item);
    return true;
  }

  String itemDescription(BoardItem item) {
    final tr = context.t.cockpit.gallery.board;
    final kind = switch (item.kind) {
      BoardKind.process => tr.process,
      BoardKind.decision => tr.decision,
      BoardKind.text => tr.text,
      BoardKind.note => tr.note,
      BoardKind.stroke => tr.pencil,
      BoardKind.service => tr.service,
      BoardKind.lane => tr.lane,
      BoardKind.container => tr.container,
      BoardKind.arrow => tr.arrow,
      BoardKind.mermaid => 'Mermaid',
    };
    final title = item.label.trim().split('\n').first;
    final name = title.isEmpty ? kind : '$kind · $title';
    if (item.kind != BoardKind.arrow) return name;
    final from = doc?.items[item.from], to = doc?.items[item.to];
    if (from == null || to == null) return name;
    return '$name · ${tr.connectorEndpoints(from: itemDescription(from), to: itemDescription(to))}';
  }

  CustomPainterSemantics itemSemantics(BoardItem item) {
    return CustomPainterSemantics(
      key: ValueKey(item.id),
      rect:
          (item.kind == BoardKind.arrow
                  ? editorBounds(item)
                  : Rect.fromLTWH(item.x, item.y, item.width, item.height))
              .shift(sceneOrigin),
      properties: SemanticsProperties(
        textDirection: Directionality.of(context),
        label: itemDescription(item),
        button: true,
        selected: selection.contains(item.id),
        focused:
            canvasFocus.hasPrimaryFocus &&
            item.id == (keyboardTarget ?? selected),
        onTap: () {
          if (anchor != null && anchor != item.id && connectable(item)) {
            unawaited(connectItems(anchor!, item.id));
          } else {
            setState(() => select(item.id));
            canvasFocus.requestFocus();
            revealItem(item);
          }
        },
        onLongPress: editable(item) ? () => editLabel(item) : null,
      ),
    );
  }

  void beginKeyboardConnection(BoardItem? item) {
    if (!connectable(item) ||
        !doc!.items.values.any(
          (other) => other.id != item!.id && connectable(other),
        )) {
      return;
    }
    setState(() {
      anchor = item!.id;
      keyboardTarget = null;
    });
    traverseItems(backwards: false);
  }

  KeyEventResult canvasKey(FocusNode node, KeyEvent event) {
    if (editing != null || !node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final down = event is! KeyUpEvent;
      if (spacePan != down) {
        if (down) cancel();
        setState(() => spacePan = down);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        event is KeyDownEvent) {
      cancel();
      setState(() {
        anchor = null;
        keyboardTarget = null;
        if (tool == 'moveHere') tool = 'select';
      });
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent || doc == null || navigating) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab &&
        traverseItems(backwards: keyboard.isShiftPressed)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter &&
        anchor != null &&
        keyboardTarget != null) {
      unawaited(connectItems(anchor!, keyboardTarget));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC &&
        event is KeyDownEvent &&
        anchor == null) {
      beginKeyboardConnection(doc!.items[selected]);
      return KeyEventResult.handled;
    }
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (delta != null && selected != null && anchor == null) {
      final step = delta * (keyboard.isShiftPressed ? 10 : 1);
      unawaited(
        changeSelection(
          (item, _) => item.edited(x: item.x + step.dx, y: item.y + step.dy),
        ),
      );
      final moved = doc!.items[selected];
      if (moved != null) revealItem(moved);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool moved = false;
  bool get placing => BoardKind.values.any((k) => k.name == tool);

  @override
  void initState() {
    super.initState();
    widget.session.saveDraft = saveDraft;
    widget.session.addListener(refresh);
    refresh();
  }

  @override
  void didUpdateWidget(BoardView old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(refresh);
      releaseDraft(old.session);
      widget.session.saveDraft = saveDraft;
      widget.session.addListener(refresh);
      editing = null;
      source = null;
      history.clear();
      refresh();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(refresh);
    releaseDraft(widget.session);
    dragOffset.dispose();
    ink.dispose();
    labelFocus.dispose();
    canvasFocus.dispose();
    transform.dispose();
    label.dispose();
    super.dispose();
  }

  void releaseDraft(FileViewerSession session) {
    if (session.saveDraft == saveDraft) session.saveDraft = null;
    for (final request in pending) {
      request.done.complete(false);
    }
    pending.clear();
    saving = false;
  }

  void syncDirty() => widget.session.setDirty(
    pending.isNotEmpty || (editing != null && editing!.label != label.text),
  );

  Future<bool> saveDraft() async {
    if (!finishLabel()) return false;
    while (pending.isNotEmpty) {
      if (!await pending.last.done.future) return false;
    }
    return true;
  }

  void refresh() {
    final content = switch (widget.session.view) {
      FileViewText(:final text) => text,
      FileViewMarkdown(:final text) => text,
      _ => null,
    };
    if (saving || (content == source && identical(doc, savedDocument))) return;
    final previousSource = source;
    setState(() {
      source = content;
      if (pointer == null) {
        dragItem = null;
        start = null;
        if (anchor == null) ink.clear();
      }
      try {
        if (content == null) {
          savedDocument = null;
        } else if (savedDocument == null || content != previousSource) {
          savedDocument = BoardDocument.parse(content);
        }
        doc = savedDocument;
        if (doc != null) includeGeometry(doc!.items.values);
        error = null;
      } on FormatException catch (e) {
        savedDocument = null;
        doc = null;
        error = e.message;
      }
      final currentEditor = doc?.items[editing?.id];
      if (currentEditor != null) {
        lastEditorBounds = editorBounds(currentEditor);
      } else if (editing != null && editing!.label == label.text) {
        editing = null;
      }
      selection.removeWhere((id) => doc?.items.containsKey(id) != true);
      if (doc?.items.containsKey(selected) != true) {
        selected = null;
        selection.clear();
        if (editing == null) label.clear();
      }
      final from = connectionStart ?? anchor;
      if (from != null) {
        final origin = doc?.items[from];
        if (origin == null || !connectable(origin)) {
          pointer = null;
          start = null;
          anchor = null;
          connectionStart = null;
          keyboardTarget = null;
          connectionPointer = null;
          ink.clear();
        } else if (keyboardTarget != null) {
          final target = doc?.items[keyboardTarget];
          if (target != null && connectable(target)) {
            previewTarget(origin, target, center(target));
          } else {
            keyboardTarget = null;
            ink.clear();
          }
        } else if (connectionPointer case final position?) {
          previewConnection(from, position);
        }
      }
    });
  }

  void select(String? id) {
    selected = id;
    selection.clear();
    if (id != null) {
      selection.add(id);
      final g = doc?.items[id]?.group;
      if (g != null) {
        selection.addAll(
          doc!.items.values.where((e) => e.group == g).map((e) => e.id),
        );
      }
    }
    label.text = doc?.items[id]?.label ?? '';
  }

  Future<void> commit(BoardEdit edit, {bool undo = false}) async {
    if (doc == null) return;
    final done = Completer<bool>();
    try {
      final next = edit.apply(doc!);
      setState(() {
        doc = next;
        includeGeometry(edit.after.values.whereType<BoardItem>());
        error = null;
        pending.add((edit: edit, done: done, undo: undo));
      });
      if (!saving) unawaited(flush());
      syncDirty();
      await done.future;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> flush() async {
    saving = true;
    final tr = context.t.cockpit.gallery.board;
    final session = widget.session;
    try {
      while (mounted && session == widget.session && pending.isNotEmpty) {
        final request = pending.first;
        final view = session.view;
        final base = switch (view) {
          FileViewText(:final text) || FileViewMarkdown(:final text) => text,
          _ => throw StateError(tr.saveError),
        };
        final baseDocument = base == source && savedDocument != null
            ? savedDocument!
            : BoardDocument.parse(base);
        final updated = request.edit.apply(baseDocument);
        final next = updated.encode();
        final ok = await widget.onSave(next);
        if (request.done.isCompleted) return;
        if (!ok) throw StateError(tr.saveError);
        source = next;
        savedDocument = updated;
        pending.removeAt(0);
        request.done.complete(true);
        if (request.undo) {
          history.removeLast();
        } else {
          history.add(request.edit.inverse);
        }
      }
    } catch (e) {
      if (!mounted || session != widget.session) return;
      for (final request in pending) {
        request.done.complete(false);
      }
      pending.clear();
      saving = false;
      syncDirty();
      source = null;
      refresh();
      setState(() {
        error = e.toString();
      });
      return;
    } finally {
      if (mounted && widget.session == session) saving = false;
    }
    if (mounted) {
      syncDirty();
      refresh();
      setState(() {});
    }
  }

  Offset center(BoardItem i) => Offset(i.x + i.width / 2, i.y + i.height / 2);
  List<Offset> route(BoardItem edge) {
    final a = doc!.items[edge.from]!, b = doc!.items[edge.to]!;
    final delta = dragItem == null ? Offset.zero : dragOffset.value;
    math.Rectangle<double> bounds(BoardItem item) {
      final offset = selection.contains(item.id) ? delta : Offset.zero;
      return math.Rectangle(
        item.x + offset.dx,
        item.y + offset.dy,
        item.width,
        item.height,
      );
    }

    return boardRouteOffsets(boardRoute(bounds(a), bounds(b)));
  }

  String? hit(Offset p) {
    for (final item in doc!.paintOrder.reversed) {
      if (item.kind == BoardKind.arrow) {
        final points = route(item);
        if (item.label.isNotEmpty &&
            editorBounds(item, path: points).contains(p)) {
          return item.id;
        }
        for (var i = 1; i < points.length; i++) {
          if (Rect.fromPoints(
            points[i - 1],
            points[i],
          ).inflate(6 + (item.strokeWidth ?? 0) / 2).contains(p)) {
            return item.id;
          }
        }
      } else if (item.kind == BoardKind.stroke) {
        final radius = 5 + (item.strokeWidth ?? 1.5) / 2;
        if (!itemBounds(item).inflate(radius).contains(p)) continue;
        Offset? previous;
        for (final sample in item.points) {
          final end = Offset(item.x + sample.x, item.y + sample.y);
          final start = previous ?? end;
          final segment = end - start;
          final relative = p - start;
          final t = segment.distanceSquared == 0
              ? 0.0
              : ((relative.dx * segment.dx + relative.dy * segment.dy) /
                        segment.distanceSquared)
                    .clamp(0.0, 1.0);
          if ((p - (start + segment * t)).distance <= radius) return item.id;
          previous = end;
        }
      } else if (Rect.fromLTWH(
        item.x,
        item.y,
        item.width,
        item.height,
      ).contains(p)) {
        return item.id;
      }
    }
    return null;
  }

  Future<void> tap(Offset p, {Rect? bounds}) async {
    if (doc == null) return;
    if (tool == 'moveHere') {
      setState(() => tool = 'select');
      final chosen = doc!.items.values.where(
        (item) => selection.contains(item.id) && item.kind != BoardKind.arrow,
      );
      if (chosen.isEmpty) return;
      final center = chosen
          .map(itemBounds)
          .reduce((a, b) => a.expandToInclude(b))
          .center;
      final offset = p - center;
      await changeSelection(
        (item, _) => item.edited(x: item.x + offset.dx, y: item.y + offset.dy),
      );
      return;
    }
    final id = hit(p);
    if (id != null && !doc!.items.containsKey(id)) return;
    if (tool == 'select') {
      setState(() {
        if (HardwareKeyboard.instance.isShiftPressed && id != null) {
          if (!selection.add(id)) selection.remove(id);
          selected = selection.lastOrNull;
          label.text = doc!.items[selected]?.label ?? '';
        } else {
          select(id);
        }
      });
      return;
    }
    if (tool == 'arrow') {
      if (!connectable(doc!.items[id])) return;
      setState(() {
        keyboardTarget = null;
        anchor = id;
      });
      return;
    }
    if (tool == 'pan' || tool == 'pencil') return;
    final kind = BoardKind.values.byName(tool);
    final wide = kind == BoardKind.lane || kind == BoardKind.container;
    final item = BoardItem(
      BoardDocument.newId(),
      kind,
      bounds?.left ?? p.dx,
      bounds?.top ?? p.dy,
      color: drawingColor,
      label: kind == BoardKind.text ? context.t.cockpit.gallery.board.text : '',
      width: bounds == null ? (wide ? 350 : 136) : math.max(24, bounds.width),
      height: bounds == null ? (wide ? 180 : 64) : math.max(24, bounds.height),
    );
    unawaited(commit(BoardEdit.replace(doc!, item)));
    if (mounted && doc!.items.containsKey(item.id)) {
      setState(() {
        tool = 'select';
        select(item.id);
        if (kind == BoardKind.text || kind == BoardKind.note) {
          editLabel(item);
        }
      });
    }
  }

  Map<String, String> get swatches {
    final tr = context.t.cockpit.gallery.board;
    return {
      '': tr.themeColor,
      '#6EA8FE': tr.blue,
      '#64CBA7': tr.green,
      '#F4C363': tr.amber,
      '#FA8983': tr.red,
      '#B29AF4': tr.violet,
      '#5CCBDC': tr.cyan,
    };
  }

  void keyboardMenu() {
    final item = doc?.items[selected];
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (item == null || box == null) return;
    revealItem(item);
    final point = MatrixUtils.transformPoint(
      transform.value,
      itemBounds(item).center + sceneOrigin,
    );
    unawaited(objectMenu(item.id, box.localToGlobal(point)));
  }

  Future<void> objectMenu(String id, Offset position) async {
    final original = doc!;
    final session = widget.session;
    if (!selection.contains(id)) setState(() => select(id));
    final ids = selection.toSet();
    final items = [for (final key in ids) original.items[key]!];
    final shapes = items.where((i) => i.kind != BoardKind.arrow).toList();
    final colored = items.where((i) => i.kind != BoardKind.mermaid).toList();
    final lines = colored.where((i) => i.kind != BoardKind.text).toList();
    final groups = shapes.map((i) => i.group).whereType<String>().toSet();
    final order = original.paintOrder;
    final tr = context.t.cockpit.gallery.board;
    final action = await showAppMenu<String>(
      context,
      globalPosition: position,
      items: [
        if (items.length == 1 && editable(items.single))
          AppMenuItem(
            value: 'text',
            label: tr.editObjectText,
            icon: Icons.edit_outlined,
          ),
        if (colored.isNotEmpty)
          AppMenuItem(
            value: 'color',
            label: tr.diagramColor,
            icon: Icons.palette_outlined,
          ),
        if (lines.isNotEmpty)
          AppMenuItem(
            value: 'width',
            label: lines.length == items.length
                ? tr.strokeWidth
                : tr.selectedLineWidth,
            icon: Icons.line_weight,
          ),
        AppMenuItem(
          value: 'front',
          label: tr.bringFront,
          icon: Icons.flip_to_front,
          enabled: !order.reversed
              .take(ids.length)
              .every((i) => ids.contains(i.id)),
        ),
        AppMenuItem(
          value: 'back',
          label: tr.sendBack,
          icon: Icons.flip_to_back,
          enabled: !order.take(ids.length).every((i) => ids.contains(i.id)),
        ),
        if (shapes.length > 1)
          AppMenuItem(
            value: 'group',
            label: tr.group,
            icon: Icons.group_work_outlined,
            enabled: groups.length != 1 || shapes.any((i) => i.group == null),
          ),
        if (groups.isNotEmpty)
          AppMenuItem(
            value: 'ungroup',
            label: tr.ungroup,
            icon: Icons.grid_off,
          ),
        const AppMenuItem<String>.divider(),
        AppMenuItem(
          value: 'delete',
          label: tr.delete,
          danger: true,
          icon: Icons.delete_outline,
        ),
      ],
    );
    if (!mounted || widget.session != session) return;
    String? value;
    if (action == 'color' || action == 'width') {
      final options = action == 'color'
          ? swatches
          : {
              '': tr.themeColor,
              for (final w in [1, 2, 4, 8]) '$w': '$w',
            };
      value = await showAppMenu<String>(
        context,
        globalPosition: position,
        items: [
          for (final entry in options.entries)
            AppMenuItem(
              value: entry.key,
              label: entry.value,
              selected: action == 'color'
                  ? colored.every((i) => (i.color ?? '') == entry.key)
                  : lines.every(
                      (i) => i.strokeWidth == double.tryParse(entry.key),
                    ),
              leading: action == 'color' && entry.key.isNotEmpty
                  ? Icon(Icons.circle, size: 16, color: swatch(entry.key))
                  : null,
            ),
        ],
      );
    }
    if (!mounted || widget.session != session) return;
    canvasFocus.requestFocus();
    if (action == null ||
        ((action == 'color' || action == 'width') && value == null)) {
      return;
    }
    final latest = doc;
    if (latest == null || latest.id != original.id) return;
    bool dependsOn(BoardItem i) =>
        ids.contains(i.id) ||
        ((action == 'group' || action == 'ungroup') &&
            groups.contains(i.group)) ||
        (action == 'delete' && (ids.contains(i.from) || ids.contains(i.to)));
    final captured = original.items.values.where(dependsOn).toList();
    if (latest.items.values.where(dependsOn).length != captured.length ||
        captured.any((i) => latest.items[i.id]?.sameContent(i) != true)) {
      setState(() => error = tr.menuChanged);
      return;
    }
    Future<void> change(
      Iterable<BoardItem> targets,
      BoardItem Function(BoardItem) update,
    ) async {
      final after = {for (final i in targets) i.id: update(i)}
        ..removeWhere((id, next) => latest.items[id]!.sameContent(next));
      if (after.isNotEmpty) {
        await commit(
          BoardEdit({for (final id in after.keys) id: latest.items[id]}, after),
        );
      }
    }

    switch (action) {
      case 'text':
        editLabel(latest.items[id]);
      case 'color':
        await change(
          colored,
          (i) => i.edited(color: value, clearColor: value!.isEmpty),
        );
      case 'width':
        await change(
          lines,
          (i) => i.edited(
            strokeWidth: double.tryParse(value!),
            clearStrokeWidth: value.isEmpty,
          ),
        );
      case 'front' || 'back':
        await commit(BoardEdit.reorder(latest, ids, front: action == 'front'));
      case 'group':
        final group = BoardDocument.newId();
        await change(shapes, (i) => i.edited(group: group));
      case 'ungroup':
        await change(
          captured.where((i) => groups.contains(i.group)),
          (i) => i.edited(ungroup: true),
        );
      case 'delete':
        await commit(BoardEdit.removeMany(latest, ids));
    }
  }

  void begin(PointerDownEvent e) {
    if (e.buttons == kSecondaryMouseButton) {
      if (doc == null || pointer != null || spacePan) return;
      final position = e.localPosition - sceneOrigin;
      if (editing != null) {
        if (lastEditorBounds?.contains(position) == true || !finishLabel()) {
          return;
        }
      }
      final id = hit(position);
      if (id != null) unawaited(objectMenu(id, e.position));
      return;
    }
    if (pointer != null && e.pointer != pointer) {
      cancel();
      return;
    }
    if (e.buttons != 1 || navigating) return;
    if (editing != null) {
      if (editorBounds(
        doc!.items[editing!.id]!,
      ).contains((e.localPosition - sceneOrigin))) {
        return;
      }
      if (!finishLabel()) return;
    }
    canvasFocus.requestFocus();
    pointer = e.pointer;
    start = (e.localPosition - sceneOrigin);
    moved = false;
    connectionPointer = null;
    connectionStart =
        anchor ??
        handleAt(start!) ??
        (tool == 'arrow' && connectable(doc!.items[hit(start!)])
            ? hit(start!)
            : null);
    if (tool == 'pencil') ink.begin(start!);
  }

  void move(PointerMoveEvent e) {
    if (pointer != e.pointer || start == null) return;
    final p = (e.localPosition - sceneOrigin);
    final delta = p - start!;
    if (tool != 'pencil' &&
        !moved &&
        delta.distance * transform.value.getMaxScaleOnAxis() < 3) {
      return;
    }
    moved = true;
    lastTapId = null;
    if (connectionStart != null) {
      previewConnection(connectionStart!, p);
    } else if (tool == 'pencil') {
      ink.add(p);
    } else if (tool == 'arrow') {
      return;
    } else if (placing) {
      ink.box(Rect.fromPoints(start!, p), tool == 'decision');
    } else if (tool == 'select') {
      final id = dragItem?.id ?? hit(start!);
      final origin = doc?.items[id];
      if (origin == null || origin.kind == BoardKind.arrow) return;
      if (dragItem == null) {
        setState(() {
          if (!selection.contains(id)) select(id);
          dragItem = origin;
        });
      }
      dragOffset.value = delta;
    }
  }

  void cancel() {
    pointer = null;
    connectionStart = null;
    connectionPointer = null;
    start = null;
    ink.clear();
    if (dragItem != null) {
      setState(() => dragItem = null);
      dragOffset.value = Offset.zero;
    }
  }

  Future<void> end(PointerUpEvent e) async {
    if (pointer != e.pointer || start == null) return;
    final origin = start!, p = (e.localPosition - sceneOrigin);
    final from = connectionStart;
    final points = ink.points;
    if (tool == 'pencil' && points.last != p) ink.add(p);
    final strokeBounds = ink.bounds;
    final dragged = dragItem;
    cancel();
    if (from != null) {
      if (!moved && anchor == null) {
        setState(() {
          keyboardTarget = null;
          anchor = from;
        });
        previewConnection(from, p);
      } else {
        await finishConnection(from, p);
      }
      return;
    }
    BoardItem? item;
    if (tool == 'pencil') {
      item = BoardItem(
        BoardDocument.newId(),
        BoardKind.stroke,
        strokeBounds.left,
        strokeBounds.top,
        color: drawingColor,
        width: math.max(1, strokeBounds.width),
        height: math.max(1, strokeBounds.height),
        points: [
          for (final p in points)
            (x: p.dx - strokeBounds.left, y: p.dy - strokeBounds.top),
        ],
      );
    } else if (!moved) {
      final id = hit(p);
      if (tool == 'select' &&
          !HardwareKeyboard.instance.isShiftPressed &&
          id != null &&
          lastTapId == id &&
          lastTap != null &&
          e.timeStamp - lastTap! <= kDoubleTapTimeout &&
          (e.position - lastTapPosition!).distance <= kDoubleTapSlop &&
          editable(doc?.items[id])) {
        lastTapId = null;
        editLabel(doc!.items[id]);
        return;
      }
      lastTapId = tool == 'select' ? id : null;
      lastTap = e.timeStamp;
      lastTapPosition = e.position;
      await tap(p);
      return;
    } else if (placing) {
      await tap(origin, bounds: Rect.fromPoints(origin, p));
      return;
    }
    final current = doc?.items[dragged?.id];
    if (current != null && current.kind != BoardKind.arrow) {
      final delta = p - origin;
      BoardItem translate(BoardItem shape) =>
          shape.edited(x: shape.x + delta.dx, y: shape.y + delta.dy);
      if (selection.length > 1) {
        await changeSelection((shape, _) => translate(shape));
      } else {
        await commit(BoardEdit.replace(doc!, translate(current)));
      }
    } else if (item != null && doc != null) {
      await commit(BoardEdit.replace(doc!, item));
    }
  }

  Future<void> changeSelection(
    BoardItem Function(BoardItem, int) change,
  ) async {
    final chosen =
        doc!.items.values
            .where((i) => selection.contains(i.id) && i.kind != BoardKind.arrow)
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
    if (chosen.isEmpty) return;
    await commit(
      BoardEdit(
        {for (final i in chosen) i.id: i},
        {for (final (index, i) in chosen.indexed) i.id: change(i, index)},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.gallery.board, colors = context.colors;
    final tools = {
      'select': (Icons.near_me, tr.select),
      'pan': (Icons.pan_tool, tr.pan),
      'pencil': (Icons.edit, tr.pencil),
      'text': (Icons.title, tr.text),
      'note': (Icons.sticky_note_2_outlined, tr.note),
      'process': (Icons.crop_square, tr.process),
      'decision': (Icons.crop_square, tr.decision),
      'arrow': (Icons.arrow_right_alt, tr.arrow),
      if (advanced) ...{
        'lane': (Icons.view_agenda, tr.lane),
        'container': (Icons.dashboard_outlined, tr.container),
        'service': (Icons.dns_outlined, tr.service),
      },
    };
    final current = doc?.items[selected];
    final objects = doc?.paintOrder ?? const <BoardItem>[];
    final selectedShapes = advanced
        ? selection
              .map((id) => doc?.items[id])
              .whereType<BoardItem>()
              .where((item) => item.kind != BoardKind.arrow)
              .toList()
        : const <BoardItem>[];
    final moving = dragItem == null
        ? <BoardItem>[]
        : objects
              .where(
                (i) => i.kind == BoardKind.arrow
                    ? selection.contains(i.from) || selection.contains(i.to)
                    : selection.contains(i.id),
              )
              .toList();
    final movingIds = moving.map((i) => i.id).toSet();
    Widget layer(List<BoardItem> items, Offset delta) {
      final positioned = delta == Offset.zero
          ? items
          : [
              for (final i in items)
                if (i.kind == BoardKind.arrow)
                  i
                else
                  i.edited(x: i.x + delta.dx, y: i.y + delta.dy),
            ];
      final layers = <Widget>[];
      var batch = <BoardItem>[];
      void flush() {
        final items = batch;
        batch = [];
        if (items.isEmpty) return;
        layers.add(
          CustomPaint(
            foregroundPainter: _BoardSemantics(
              () => [for (final item in items) itemSemantics(item)],
            ),
            size: sceneExtent.size,
            painter: BoardPainter(
              items,
              route,
              {...selection},
              colors.text,
              colors.bg,
              colors.accent,
              context.typo.body,
              origin: sceneOrigin,
            ),
          ),
        );
      }

      // Connectors sit behind shapes. Insert each decoded image immediately
      // after its frame so later objects can cover the diagram.
      for (final item in positioned) {
        batch.add(item);
        if (item.kind != BoardKind.mermaid || item.thumbnail == null) continue;
        flush();
        layers.add(
          Positioned(
            left: sceneOrigin.dx + item.x + 2,
            top: sceneOrigin.dy + item.y + 2,
            width: math.max(0, item.width - 4),
            height: math.max(0, item.height - 4),
            child: IgnorePointer(
              child: Image.memory(item.thumbnailBytes!, gaplessPlayback: true),
            ),
          ),
        );
      }
      flush();
      return SizedBox.fromSize(
        size: sceneExtent.size,
        child: Stack(children: layers),
      );
    }

    Rect? paintedArea;
    List<Widget> sceneLayers = [];
    List<Widget> visibleLayers(Rect viewportBounds) {
      final previous = paintedArea;
      if (previous != null &&
          previous.contains(viewportBounds.topLeft) &&
          previous.contains(viewportBounds.bottomRight)) {
        return sceneLayers;
      }
      // Keep a margin so small camera movements reuse the existing display list.
      final area = viewportBounds.inflate(
        math.max(viewportBounds.width, viewportBounds.height) * .25 + 8,
      );
      paintedArea = area;
      sceneLayers = [];
      var batch = <BoardItem>[];
      var batchMoves = false;
      void flush() {
        if (batch.isEmpty) return;
        final items = batch;
        batch = [];
        sceneLayers.add(
          RepaintBoundary(
            child: batchMoves
                ? ValueListenableBuilder<Offset>(
                    valueListenable: dragOffset,
                    builder: (_, delta, _) => layer(items, delta),
                  )
                : layer(items, Offset.zero),
          ),
        );
      }

      // Preserve document order while repainting only moving runs per frame.
      for (final item in objects) {
        final moves = movingIds.contains(item.id);
        if (!moves && !itemBounds(item).inflate(8).overlaps(area)) continue;
        if (moves != batchMoves) flush();
        batchMoves = moves;
        batch.add(item);
      }
      flush();
      if (sceneLayers.isEmpty) {
        sceneLayers.add(SizedBox.fromSize(size: sceneExtent.size));
      }
      return sceneLayers;
    }

    final currentEditor = doc?.items[editing?.id];
    final editBounds = currentEditor != null
        ? editorBounds(currentEditor)
        : editing == null
        ? null
        : lastEditorBounds;
    final handleItem = doc?.items[hovered] ?? current;
    final targetColor = tool == 'select' && current != null
        ? current.color
        : drawingColor;
    final palette = <Widget>[
      for (final t in tools.entries)
        IconButton(
          tooltip: t.value.$2,
          iconSize: 19,
          isSelected: tool == t.key,
          style: tool == t.key
              ? IconButton.styleFrom(
                  backgroundColor: colors.accent.withValues(alpha: .16),
                )
              : null,
          color: tool == t.key ? colors.accent : colors.text2,
          icon: t.key == 'decision'
              ? Transform.rotate(angle: math.pi / 4, child: Icon(t.value.$1))
              : Icon(t.value.$1),
          onPressed: () => setState(() {
            cancel();
            canvasFocus.requestFocus();
            tool = t.key;
            anchor = null;
            keyboardTarget = null;
          }),
        ),
      IconButton(
        tooltip: tr.advanced,
        isSelected: advanced,
        icon: const Icon(Icons.more_horiz),
        onPressed: () => setState(() => advanced = !advanced),
      ),
      if (selectedShapes.length > 1) ...[
        IconButton(
          tooltip: tr.group,
          icon: const Icon(Icons.group_work_outlined),
          onPressed: () {
            final g = BoardDocument.newId();
            changeSelection((i, _) => i.edited(group: g));
          },
        ),
        IconButton(
          tooltip: tr.ungroup,
          icon: const Icon(Icons.grid_off),
          onPressed: () => changeSelection((i, _) => i.edited(ungroup: true)),
        ),
        IconButton(
          tooltip: tr.align,
          icon: const Icon(Icons.align_vertical_top),
          onPressed: () {
            canvasFocus.requestFocus();
            final y = selectedShapes.map((i) => i.y).reduce(math.min);
            changeSelection((i, _) => i.edited(y: y));
          },
        ),
        if (selectedShapes.length > 2)
          IconButton(
            tooltip: tr.distribute,
            icon: const Icon(Icons.horizontal_distribute),
            onPressed: () {
              final xs = selectedShapes.map((i) => i.x).toList()..sort();
              changeSelection(
                (i, n) => i.edited(
                  x: xs.first + n * (xs.last - xs.first) / (xs.length - 1),
                ),
              );
            },
          ),
      ],
    ];
    return Material(
      color: colors.bg,
      child: Column(
        children: [
          Container(
            color: colors.panel,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.title.copyWith(color: colors.text),
                  ),
                ),
              ],
            ),
          ),
          if (error != null) SelectableText(error!),
          if (doc != null &&
              editing != null &&
              editing!.label != currentEditor?.label)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: label,
              builder: (_, draft, _) {
                if (editing == null ||
                    draft.text == editing!.label ||
                    draft.text == currentEditor?.label) {
                  return const SizedBox.shrink();
                }
                return Semantics(
                  liveRegion: true,
                  child: Text(
                    currentEditor == null ? tr.objectDeleted : tr.labelChanged,
                  ),
                );
              },
            ),
          if (widget.session.loading) const LinearProgressIndicator(),
          if (doc != null)
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    decoration: BoxDecoration(
                      color: colors.panel,
                      border: Border(right: BorderSide(color: colors.border)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 5,
                      ),
                      child: Column(children: palette),
                    ),
                  ),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: editing != null
                          ? {}
                          : {
                              const SingleActivator(
                                LogicalKeyboardKey.f10,
                                shift: true,
                              ): keyboardMenu,
                              const SingleActivator(
                                LogicalKeyboardKey.contextMenu,
                              ): keyboardMenu,
                              const SingleActivator(
                                LogicalKeyboardKey.f2,
                              ): () =>
                                  editLabel(current),
                              const SingleActivator(
                                LogicalKeyboardKey.enter,
                              ): () =>
                                  editLabel(current),
                              const SingleActivator(
                                LogicalKeyboardKey.keyZ,
                                control: true,
                              ): () {
                                if (!saving && history.isNotEmpty) {
                                  commit(history.last, undo: true);
                                }
                              },
                              const SingleActivator(
                                LogicalKeyboardKey.delete,
                              ): () {
                                if (current != null) {
                                  commit(
                                    BoardEdit.removeMany(
                                      doc!,
                                      selection.toSet(),
                                    ),
                                  );
                                }
                              },
                            },
                      child: Focus(
                        autofocus: true,
                        focusNode: canvasFocus,
                        onKeyEvent: canvasKey,
                        onFocusChange: (focused) {
                          if (!focused && spacePan) {
                            setState(() => spacePan = false);
                          }
                        },
                        child: InteractiveViewer.builder(
                          key: viewport,
                          transformationController: transform,
                          alignment: Alignment.topLeft,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          minScale: .001,
                          maxScale: 5,
                          panEnabled: navigating,
                          builder: (context, quad) {
                            final viewportBounds = Rect.fromPoints(
                              Offset(quad.point0.x, quad.point0.y),
                              Offset(quad.point2.x, quad.point2.y),
                            ).shift(-sceneOrigin);
                            return Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: begin,
                              onPointerMove: move,
                              onPointerUp: end,
                              onPointerCancel: (e) {
                                if (pointer == e.pointer) cancel();
                              },
                              child: MouseRegion(
                                onHover: hover,
                                onExit: (_) {
                                  if (mounted &&
                                      hovered != null &&
                                      pointer == null) {
                                    setState(() => hovered = null);
                                  }
                                },
                                cursor: navigating
                                    ? SystemMouseCursors.grab
                                    : tool == 'select'
                                    ? SystemMouseCursors.basic
                                    : SystemMouseCursors.precise,
                                child: Stack(
                                  children: [
                                    ...visibleLayers(viewportBounds),
                                    if (handleItem != null &&
                                        connectable(handleItem) &&
                                        editing == null &&
                                        tool == 'select' &&
                                        !navigating &&
                                        dragItem == null &&
                                        anchor == null)
                                      Positioned(
                                        left:
                                            sceneOrigin.dx +
                                            handleCenter(handleItem).dx -
                                            7,
                                        top:
                                            sceneOrigin.dy +
                                            handleCenter(handleItem).dy -
                                            7,
                                        child: IgnorePointer(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: colors.panel,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: colors.accent,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.add,
                                              size: 13,
                                              color: colors.accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: RepaintBoundary(
                                          child: CustomPaint(
                                            painter: _PreviewPainter(
                                              ink,
                                              sceneOrigin,
                                              tool == 'pencil' &&
                                                      drawingColor != null
                                                  ? swatch(drawingColor!)
                                                  : colors.accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (editBounds != null)
                                      Positioned.fromRect(
                                        rect: editBounds.shift(sceneOrigin),
                                        child: Material(
                                          color: colors.bg,
                                          child: CallbackShortcuts(
                                            bindings: {
                                              const SingleActivator(
                                                LogicalKeyboardKey.escape,
                                              ): () =>
                                                  finishLabel(discard: true),
                                            },
                                            child: TextField(
                                              controller: label,
                                              onChanged: (_) => syncDirty(),
                                              focusNode: labelFocus,
                                              style: context.typo.body.copyWith(
                                                color: colors.text,
                                              ),
                                              textAlign: TextAlign.center,
                                              textAlignVertical:
                                                  TextAlignVertical.center,
                                              expands: true,
                                              minLines: null,
                                              maxLines: null,
                                              textInputAction:
                                                  TextInputAction.done,
                                              decoration: InputDecoration(
                                                hintText: tr.label,
                                                isDense: true,
                                                border:
                                                    const OutlineInputBorder(),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 3,
                                                    ),
                                              ),
                                              onTapOutside: (_) =>
                                                  finishLabel(),
                                              onSubmitted: (_) => finishLabel(),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final status = Semantics(
                liveRegion: true,
                child: Text(
                  anchor != null &&
                          keyboardTarget != null &&
                          doc?.items[keyboardTarget] != null
                      ? tr.keyboardTarget(
                          target: itemDescription(doc!.items[keyboardTarget]!),
                        )
                      : tool == 'moveHere'
                      ? tr.moveDestination
                      : tool == 'arrow' || anchor != null
                      ? (anchor == null ? tr.arrowStart : tr.arrowEnd)
                      : doc?.items.isEmpty == true
                      ? tr.emptyBoard
                      : tool == 'select'
                      ? tr.keyboardHelp
                      : tools[tool]?.$2 ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              );
              final controls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (buttonContext) => Tooltip(
                      message: tr.diagramColor,
                      child: TextButton(
                        onPressed:
                            tool == 'select' &&
                                current?.kind == BoardKind.mermaid
                            ? null
                            : () async {
                                final value = await showAppMenu<String?>(
                                  buttonContext,
                                  items: [
                                    for (final entry in swatches.entries)
                                      AppMenuItem(
                                        value: entry.key,
                                        label: entry.value,
                                        selected:
                                            (targetColor ?? '') == entry.key,
                                        leading: Icon(
                                          entry.key.isEmpty
                                              ? Icons.tonality
                                              : Icons.circle,
                                          size: 16,
                                          color: entry.key.isEmpty
                                              ? colors.text2
                                              : swatch(entry.key),
                                        ),
                                      ),
                                  ],
                                );
                                if (!mounted) return;
                                canvasFocus.requestFocus();
                                if (value == null) return;
                                final color = value.isEmpty ? null : value;
                                if (tool == 'select' && current != null) {
                                  final items = doc!.items.values.where(
                                    (i) =>
                                        selection.contains(i.id) &&
                                        i.kind != BoardKind.mermaid &&
                                        i.color != color,
                                  );
                                  if (items.isNotEmpty) {
                                    commit(
                                      BoardEdit(
                                        {for (final i in items) i.id: i},
                                        {
                                          for (final i in items)
                                            i.id: i.edited(
                                              color: color,
                                              clearColor: color == null,
                                            ),
                                        },
                                      ),
                                    );
                                  }
                                } else {
                                  setState(() => drawingColor = color);
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.palette_outlined,
                                size: 18,
                                color: colors.text2,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                tr.diagramColor,
                                style: context.typo.label.copyWith(
                                  color: colors.text,
                                ),
                              ),
                              const SizedBox(width: 5),
                              for (final rgb
                                  in targetColor == null
                                      ? swatches.keys.skip(1).take(3)
                                      : [targetColor])
                                Container(
                                  width: 8,
                                  height: 12,
                                  color: swatch(rgb),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (editable(current))
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(tr.label),
                      onPressed: () => editLabel(current),
                    ),
                  if (selection.any(
                    (id) => doc?.items[id]?.kind != BoardKind.arrow,
                  ))
                    IconButton(
                      tooltip: tr.moveHere,
                      isSelected: tool == 'moveHere',
                      icon: const Icon(Icons.open_with, size: 17),
                      onPressed: () {
                        canvasFocus.requestFocus();
                        ink.clear();
                        setState(() {
                          tool = tool == 'moveHere' ? 'select' : 'moveHere';
                          anchor = null;
                          keyboardTarget = null;
                        });
                      },
                    ),
                  IconButton(
                    tooltip: tr.fitDocument,
                    iconSize: 17,
                    icon: const Icon(Icons.fit_screen),
                    onPressed: objects.isEmpty ? null : () => fitItems(objects),
                  ),
                  IconButton(
                    tooltip: tr.fitSelection,
                    iconSize: 17,
                    icon: const Icon(Icons.center_focus_strong),
                    onPressed: selection.isEmpty
                        ? null
                        : () => fitItems(
                            objects.where((i) => selection.contains(i.id)),
                          ),
                  ),
                  IconButton(
                    tooltip: context.t.core.menu.zoomOut,
                    iconSize: 17,
                    icon: const Icon(Icons.remove),
                    onPressed: () => zoomBy(1 / 1.2),
                  ),
                  ValueListenableBuilder<Matrix4>(
                    valueListenable: transform,
                    builder: (_, matrix, _) => TextButton(
                      onPressed: () => zoomBy(1 / matrix.getMaxScaleOnAxis()),
                      child: Text(
                        '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.t.core.menu.zoomIn,
                    iconSize: 17,
                    icon: const Icon(Icons.add),
                    onPressed: () => zoomBy(1.2),
                  ),
                ],
              );
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          status,
                          SizedBox(
                            height: 38,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: controls,
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        height: 38,
                        child: Row(
                          children: [
                            Expanded(child: status),
                            controls,
                          ],
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BoardSemantics extends CustomPainter {
  _BoardSemantics(this.nodes);
  final List<CustomPainterSemantics> Function() nodes;
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (_) => nodes();
  @override
  bool shouldRebuildSemantics(_BoardSemantics old) => true;
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_BoardSemantics old) => false;
}

class _GesturePreview extends ChangeNotifier {
  List<Offset> points = [];
  Rect bounds = Rect.zero;
  Path path = Path();
  void begin(Offset p) {
    points = [p];
    bounds = Rect.fromPoints(p, p);
    path = Path()..moveTo(p.dx, p.dy);
    notifyListeners();
  }

  void add(Offset p) {
    if (points.last == p) return;
    points.add(p);
    bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
    path.lineTo(p.dx, p.dy);
    notifyListeners();
  }

  Offset? snap;
  Rect? target;
  bool diamond = false;
  void connector(List<Offset> points, Rect? bounds, bool decision) {
    path = Path()..addPolygon(points, false);
    snap = bounds == null ? null : points.last;
    target = bounds;
    diamond = decision;
    notifyListeners();
  }

  void box(Rect rect, bool diamond) {
    path = Path();
    if (diamond) {
      path.addPolygon([
        rect.topCenter,
        rect.centerRight,
        rect.bottomCenter,
        rect.centerLeft,
      ], true);
    } else {
      path.addRect(rect);
    }
    notifyListeners();
  }

  void clear() {
    points = [];
    path = Path();
    snap = null;
    target = null;
    notifyListeners();
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.preview, this.origin, this.color)
    : super(repaint: preview);
  final _GesturePreview preview;
  final Offset origin;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final r = preview.target;
    if (r != null) {
      final outline = Path();
      if (preview.diamond) {
        outline.addPolygon([
          r.topCenter,
          r.centerRight,
          r.bottomCenter,
          r.centerLeft,
        ], true);
      } else {
        outline.addRect(r);
      }
      canvas.drawPath(outline, Paint()..color = color.withValues(alpha: .2));
      canvas.drawPath(
        outline,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(preview.snap!, 5, Paint()..color = color);
    }
    if (preview.points.length == 1 && r == null) {
      canvas.drawCircle(preview.points.first, 1, Paint()..color = color);
    }
    canvas.drawPath(
      preview.path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      origin != old.origin || color != old.color || preview != old.preview;
}
