import 'board_painter.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout, kDoubleTapSlop;
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import '../../domain/entities/board_document.dart';
import '../../domain/entities/file_view.dart';
import '../../domain/services/board_editor.dart';
import '../session/file_viewer_session.dart';
import 'board_mermaid.dart';
import 'board_files.dart';

class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.session,
    required this.onSave,
    required this.onReload,
  });
  final FileViewerSession session;
  final Future<bool> Function(String) onSave;
  final Future<void> Function() onReload;
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
    final changed = !discard && value != original.label;
    if (changed && current?.label != original.label) {
      setState(() => error = context.t.cockpit.gallery.board.saveError);
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
    final a = doc?.items[from];
    if (a == null) {
      ink.clear();
      return;
    }
    final b = doc?.items[targetAt(p, from)];
    previewTarget(a, b, p);
  }

  void previewTarget(BoardItem a, BoardItem? b, Offset p) {
    final q = b == null ? p : center(b);
    final sign = center(a).dx <= q.dx ? 1 : -1;
    final left = center(a) + Offset(sign * a.width / 2, 0);
    ink.connector(
      left,
      b == null ? p : q - Offset(sign * b.width / 2, 0),
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
    if (to == null || !doc!.items.containsKey(from)) return;
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
        ink.clear();
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
      if (doc?.items.containsKey(editing?.id) != true) editing = null;
      if (doc?.items.containsKey(selected) != true) select(null);
      if (doc?.items.containsKey(anchor) != true) {
        anchor = null;
        keyboardTarget = null;
      } else if (doc?.items.containsKey(keyboardTarget) != true) {
        keyboardTarget = null;
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
    final p = center(a) + (selection.contains(a.id) ? delta : Offset.zero);
    final q = center(b) + (selection.contains(b.id) ? delta : Offset.zero);
    final sign = p.dx <= q.dx ? 1 : -1;
    final left = p + Offset(sign * a.width / 2, 0),
        right = q - Offset(sign * b.width / 2, 0);
    final mid = (left.dx + right.dx) / 2;
    return [left, Offset(mid, left.dy), Offset(mid, right.dy), right];
  }

  String? hit(Offset p) {
    for (final i in doc!.paintOrder.reversed) {
      if (i.kind != BoardKind.arrow &&
          Rect.fromLTWH(i.x, i.y, i.width, i.height).contains(p)) {
        return i.id;
      }
    }
    for (final e in doc!.items.values.where((i) => i.kind == BoardKind.arrow)) {
      final pts = route(e);
      for (var i = 1; i < pts.length; i++) {
        if (Rect.fromPoints(pts[i - 1], pts[i]).inflate(6).contains(p)) {
          return e.id;
        }
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

  void begin(PointerDownEvent e) {
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
      finishLabel();
    }
    canvasFocus.requestFocus();
    pointer = e.pointer;
    start = (e.localPosition - sceneOrigin);
    moved = false;
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
    BoardItem? item = dragged?.edited(
      x: dragged.x + p.dx - origin.dx,
      y: dragged.y + p.dy - origin.dy,
    );
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
    if (item == null) return;
    final old = doc!.items[item.id];
    if (old != null && selection.length > 1) {
      final dx = item.x - old.x, dy = item.y - old.y;
      await changeSelection((e, index) => e.edited(x: e.x + dx, y: e.y + dy));
    } else {
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
      return Stack(
        children: [
          CustomPaint(
            foregroundPainter: _BoardSemantics(
              () => [for (final item in positioned) itemSemantics(item)],
            ),
            size: sceneExtent.size,
            painter: BoardPainter(
              positioned,
              route,
              {...selection},
              colors.text,
              colors.bg,
              colors.accent,
              context.typo.body,
              origin: sceneOrigin,
            ),
          ),
          for (final i in positioned)
            if (i.kind == BoardKind.mermaid && i.thumbnail != null)
              Positioned(
                left: sceneOrigin.dx + i.x + 2,
                top: sceneOrigin.dy + i.y + 2,
                width: i.width - 4,
                height: i.height - 4,
                child: IgnorePointer(
                  child: Image.memory(i.thumbnailBytes!, gaplessPlayback: true),
                ),
              ),
        ],
      );
    }

    Rect? paintedArea;
    Widget? stationaryLayer;
    Widget stationary(Rect viewportBounds) {
      final previous = paintedArea;
      if (previous != null &&
          previous.contains(viewportBounds.topLeft) &&
          previous.contains(viewportBounds.bottomRight)) {
        return stationaryLayer!;
      }
      // Keep a margin so small camera movements reuse the existing display list.
      final area = viewportBounds.inflate(
        math.max(viewportBounds.width, viewportBounds.height) * .25 + 8,
      );
      paintedArea = area;
      return stationaryLayer = RepaintBoundary(
        child: layer([
          for (final item in objects)
            if (!movingIds.contains(item.id) &&
                itemBounds(item).inflate(8).overlaps(area))
              item,
        ], Offset.zero),
      );
    }

    final edited = doc?.items[editing?.id];
    final handleItem = doc?.items[hovered] ?? current;
    final swatches = {
      '': tr.themeColor,
      '#6EA8FE': tr.blue,
      '#64CBA7': tr.green,
      '#F4C363': tr.amber,
      '#FA8983': tr.red,
      '#B29AF4': tr.violet,
      '#5CCBDC': tr.cyan,
    };
    final targetColor = tool == 'select' && current != null
        ? current.color
        : drawingColor;
    final palette = <Widget>[
      for (final t in tools.entries)
        IconButton(
          tooltip: t.value.$2,
          iconSize: 19,
          isSelected: tool == t.key,
          style: IconButton.styleFrom(
            backgroundColor: tool == t.key
                ? colors.accent.withValues(alpha: .16)
                : null,
          ),
          icon: Transform.rotate(
            angle: t.key == 'decision' ? math.pi / 4 : 0,
            child: Icon(
              t.value.$1,
              color: tool == t.key ? colors.accent : colors.text2,
            ),
          ),
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
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        if (advanced && selection.length > 1) ...[
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
                            onPressed: () => changeSelection(
                              (i, _) => i.edited(ungroup: true),
                            ),
                          ),
                          IconButton(
                            tooltip: tr.align,
                            icon: const Icon(Icons.align_vertical_top),
                            onPressed: () {
                              final y = doc!.items.values
                                  .where((i) => selection.contains(i.id))
                                  .map((i) => i.y)
                                  .reduce(math.min);
                              changeSelection((i, _) => i.edited(y: y));
                            },
                          ),
                          if (selection.length > 2)
                            IconButton(
                              tooltip: tr.distribute,
                              icon: const Icon(Icons.horizontal_distribute),
                              onPressed: () {
                                final xs =
                                    doc!.items.values
                                        .where(
                                          (i) =>
                                              selection.contains(i.id) &&
                                              i.kind != BoardKind.arrow,
                                        )
                                        .map((i) => i.x)
                                        .toList()
                                      ..sort();
                                if (xs.length > 2) {
                                  changeSelection(
                                    (i, n) => i.edited(
                                      x:
                                          xs.first +
                                          n *
                                              (xs.last - xs.first) /
                                              (xs.length - 1),
                                    ),
                                  );
                                }
                              },
                            ),
                        ],
                        IconButton(
                          tooltip: tr.undo,
                          icon: const Icon(Icons.undo),
                          onPressed: saving || history.isEmpty
                              ? null
                              : () => commit(history.last, undo: true),
                        ),
                        IconButton(
                          tooltip: tr.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: saving || current == null
                              ? null
                              : () =>
                                    commit(BoardEdit.remove(doc!, current.id)),
                        ),
                        IconButton(
                          tooltip: tr.reload,
                          icon: const Icon(Icons.refresh),
                          onPressed: saving ? null : widget.onReload,
                        ),
                        if (doc != null)
                          BoardFiles(
                            document: doc!,
                            documentPath: widget.session.path,
                            selection: Set.of(selection),
                            apply: commit,
                            onError: (e) {
                              if (mounted) setState(() => error = e);
                            },
                          ),
                        TextButton(
                          onPressed: saving || doc == null
                              ? null
                              : () async {
                                  final text = await editMermaid(
                                    context,
                                    current?.kind == BoardKind.mermaid
                                        ? current!.label
                                        : null,
                                  );
                                  if (text == null || !mounted || doc == null) {
                                    return;
                                  }
                                  final item =
                                      current?.kind == BoardKind.mermaid
                                      ? current!.edited(
                                          label: text.source,
                                          thumbnail: text.thumbnail,
                                        )
                                      : BoardItem(
                                          BoardDocument.newId(),
                                          BoardKind.mermaid,
                                          80,
                                          80,
                                          label: text.source,
                                          thumbnail: text.thumbnail,
                                          width: 240,
                                          height: 110,
                                        );
                                  await commit(BoardEdit.replace(doc!, item));
                                },
                          child: const Text('Mermaid'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (error != null) SelectableText(error!),
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
                                  commit(BoardEdit.remove(doc!, current.id));
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
                                    stationary(viewportBounds),
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
                                    if (moving.isNotEmpty)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: RepaintBoundary(
                                            child:
                                                ValueListenableBuilder<Offset>(
                                                  valueListenable: dragOffset,
                                                  builder: (_, delta, _) =>
                                                      layer(moving, delta),
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
                                    if (edited != null)
                                      Positioned.fromRect(
                                        rect: editorBounds(
                                          edited,
                                        ).shift(sceneOrigin),
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
  void connector(Offset a, Offset b, Rect? bounds, bool decision) {
    final mid = (a.dx + b.dx) / 2;
    path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(mid, a.dy)
      ..lineTo(mid, b.dy)
      ..lineTo(b.dx, b.dy);
    snap = bounds == null ? null : b;
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
