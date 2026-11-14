import 'board_painter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout, kDoubleTapSlop;
import 'package:flutter/services.dart';
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
  final label = TextEditingController();
  final history = <BoardEdit>[];
  BoardDocument? doc;
  final selection = <String>{};
  BoardDocument get display => doc!;

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

  Rect editorBounds(BoardItem item) {
    final mid = item.kind == BoardKind.arrow
        ? Offset.lerp(route(item)[1], route(item)[2], .5)!
        : center(item);
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
      .15,
      5.0,
    );
    final offset = middle - scene * scale;
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
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
    for (final i in display.items.values.toList().reversed) {
      if (i.id == from || !connectable(i) || !doc!.items.containsKey(i.id)) {
        continue;
      }
      if (!Rect.fromLTWH(
        i.x,
        i.y,
        i.width,
        i.height,
      ).inflate(4 / transform.value.getMaxScaleOnAxis()).contains(p)) {
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
      previewConnection(anchor!, e.localPosition);
      return;
    }
    if (tool != 'select') return;
    final id = handleAt(e.localPosition) ?? targetAt(e.localPosition, null);
    final next = connectable(doc!.items[id]) ? id : null;
    if (next != hovered) setState(() => hovered = next);
  }

  Future<void> finishConnection(String from, Offset p) async {
    final to = targetAt(p, from);
    setState(() {
      anchor = null;
      connectionStart = null;
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
      setState(() => anchor = null);
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
    if (saving || content == source) return;
    setState(() {
      source = content;
      if (pointer == null) {
        dragItem = null;
        start = null;
        ink.clear();
      }
      try {
        doc = content == null ? null : BoardDocument.parse(content);
        error = null;
      } on FormatException catch (e) {
        doc = null;
        error = e.message;
      }
      if (doc?.items.containsKey(editing?.id) != true) editing = null;
      if (doc?.items.containsKey(selected) != true) select(null);
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
        final next = request.edit.apply(BoardDocument.parse(base)).encode();
        final ok = await widget.onSave(next);
        if (request.done.isCompleted) return;
        if (!ok) throw StateError(tr.saveError);
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

  Iterable<BoardItem> get visible sync* {
    yield* display.items.values;
  }

  Offset center(BoardItem i) => Offset(i.x + i.width / 2, i.y + i.height / 2);
  List<Offset> route(BoardItem edge) {
    final a = display.items[edge.from] ?? doc!.items[edge.from]!,
        b = display.items[edge.to] ?? doc!.items[edge.to]!;
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
    for (final i in visible.toList().reversed) {
      if (i.kind != BoardKind.arrow &&
          Rect.fromLTWH(i.x, i.y, i.width, i.height).contains(p)) {
        return i.id;
      }
    }
    for (final e in visible.where((i) => i.kind == BoardKind.arrow)) {
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
      setState(() => anchor = id);
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
      if (editorBounds(doc!.items[editing!.id]!).contains(e.localPosition)) {
        return;
      }
      finishLabel();
    }
    canvasFocus.requestFocus();
    pointer = e.pointer;
    start = e.localPosition;
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
    final p = e.localPosition;
    final delta = p - start!;
    if (!moved && delta.distance * transform.value.getMaxScaleOnAxis() < 3) {
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
    final origin = start!, p = e.localPosition;
    final from = connectionStart;
    final points = ink.points;
    final dragged = dragItem;
    BoardItem? item = dragged?.edited(
      x: dragged.x + p.dx - origin.dx,
      y: dragged.y + p.dy - origin.dy,
    );
    cancel();
    if (from != null) {
      if (!moved && anchor == null) {
        setState(() => anchor = from);
        previewConnection(from, p);
      } else {
        await finishConnection(from, p);
      }
      return;
    }
    if (tool == 'pencil') {
      final stroke = [...points, p];
      final bounds = stroke.fold(
        Rect.fromPoints(origin, origin),
        (r, p) => r.expandToInclude(Rect.fromPoints(p, p)),
      );
      item = BoardItem(
        BoardDocument.newId(),
        BoardKind.stroke,
        bounds.left,
        bounds.top,
        color: drawingColor,
        width: math.max(1, bounds.width),
        height: math.max(1, bounds.height),
        points: [
          for (final p in stroke) (x: p.dx - bounds.left, y: p.dy - bounds.top),
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
    final objects = doc == null ? <BoardItem>[] : visible.toList();
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
            size: const Size(6000, 6000),
            painter: BoardPainter(
              positioned,
              route,
              {...selection},
              colors.text,
              colors.bg,
              colors.accent,
              context.typo.body,
            ),
          ),
          for (final i in positioned)
            if (i.kind == BoardKind.mermaid && i.thumbnail != null)
              Positioned(
                left: i.x + 2,
                top: i.y + 2,
                width: i.width - 4,
                height: i.height - 4,
                child: IgnorePointer(child: _Thumbnail(source: i.thumbnail!)),
              ),
        ],
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
            ink.clear();
            canvasFocus.requestFocus();
            tool = t.key;
            anchor = null;
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
                        child: InteractiveViewer(
                          key: viewport,
                          transformationController: transform,
                          constrained: false,
                          alignment: Alignment.topLeft,
                          minScale: .15,
                          maxScale: 5,
                          panEnabled: navigating,
                          child: Listener(
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
                                  RepaintBoundary(
                                    child: layer(
                                      moving.isEmpty
                                          ? objects
                                          : objects
                                                .where(
                                                  (i) =>
                                                      !movingIds.contains(i.id),
                                                )
                                                .toList(),
                                      Offset.zero,
                                    ),
                                  ),
                                  if (handleItem != null &&
                                      connectable(handleItem) &&
                                      editing == null &&
                                      tool == 'select' &&
                                      !navigating &&
                                      dragItem == null &&
                                      anchor == null)
                                    Positioned(
                                      left: handleCenter(handleItem).dx - 7,
                                      top: handleCenter(handleItem).dy - 7,
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
                                          child: ValueListenableBuilder<Offset>(
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
                                      rect: editorBounds(edited),
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
                                            onTapOutside: (_) => finishLabel(),
                                            onSubmitted: (_) => finishLabel(),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tool == 'arrow' || anchor != null
                          ? (anchor == null ? tr.arrowStart : tr.arrowEnd)
                          : doc?.items.isEmpty == true
                          ? tr.emptyBoard
                          : tools[tool]?.$2 ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.label.copyWith(color: colors.text2),
                    ),
                  ),
                  PopupMenuButton<String>(
                    constraints: const BoxConstraints(
                      minWidth: 200,
                      maxWidth: 320,
                    ),
                    enabled:
                        tool != 'select' || current?.kind != BoardKind.mermaid,
                    tooltip: tr.diagramColor,
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
                            Container(width: 8, height: 12, color: swatch(rgb)),
                        ],
                      ),
                    ),
                    itemBuilder: (_) => [
                      for (final entry in swatches.entries)
                        CheckedPopupMenuItem(
                          value: entry.key,
                          checked: (targetColor ?? '') == entry.key,
                          child: Row(
                            children: [
                              Icon(
                                entry.key.isEmpty
                                    ? Icons.tonality
                                    : Icons.circle,
                                size: 16,
                                color: entry.key.isEmpty
                                    ? colors.text2
                                    : swatch(entry.key),
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: Text(entry.value)),
                            ],
                          ),
                        ),
                    ],
                    onSelected: (value) {
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
                  ),
                  if (editable(current))
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(tr.label),
                      onPressed: () => editLabel(current),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GesturePreview extends ChangeNotifier {
  List<Offset> points = [];
  Path path = Path();
  void begin(Offset p) {
    points = [p];
    path = Path()..moveTo(p.dx, p.dy);
  }

  void add(Offset p) {
    points.add(p);
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
  _PreviewPainter(this.preview, this.color) : super(repaint: preview);
  final _GesturePreview preview;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
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
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      color != old.color || preview != old.preview;
}

class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.source});
  final String source;
  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  late MemoryImage image = MemoryImage(base64Decode(widget.source));
  @override
  void didUpdateWidget(_Thumbnail old) {
    super.didUpdateWidget(old);
    if (widget.source != old.source) {
      image = MemoryImage(base64Decode(widget.source));
    }
  }

  @override
  Widget build(BuildContext context) =>
      Image(image: image, gaplessPlayback: true);
}
