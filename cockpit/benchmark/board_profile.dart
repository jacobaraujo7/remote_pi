import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart' as m;
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_view.dart';

typedef ProfileView =
    w.Widget Function({
      w.Key? key,
      required FileViewerSession session,
      required Future<bool> Function(String) onSave,
      required Future<void> Function() onReload,
    });

Future<void> main() => runBoardProfile();

Future<void> runBoardProfile({ProfileView? baseline}) async {
  w.WidgetsFlutterBinding.ensureInitialized();
  final output = File(
    Platform.environment['BOARD_PROFILE_RESULT'] ?? 'build/board-profile.tsv',
  );
  await output.parent.create(recursive: true);
  try {
    final suite = Platform.environment['BOARD_PROFILE_SUITE'];
    if (suite == 'interactions' || suite == 'opening' || suite == 'pane') {
      await measureInteractions(
        output,
        baseline,
        scenarios: suite == 'interactions'
            ? _Scenario.values
            : const [_Scenario.firstPaint],
        separateHost: suite == 'pane',
      );
    } else {
      await measure(output, baseline);
    }
  } catch (error, stack) {
    await File('${output.path}.error').writeAsString('$error\n$stack');
    exit(1);
  }
  exit(0);
}

Future<void> measure(File output, ProfileView? baseline) async {
  final report = <String>[
    'version\tcount\trun\tframes\tbuildP95ms\trasterP95ms\tover16.67ms\toverDisplayBudget\tdisplayHz',
  ];
  for (final count in [32, 240, 960]) {
    for (var run = 1; run <= 3; run++) {
      final variants = {
        'baseline': ?baseline,
        'current': BoardView.new,
      }.entries.toList();
      for (final variant in run.isEven ? variants.reversed : variants) {
        final session = FileViewerSession(
          id: 'perf',
          projectId: 'test',
          path: 'perf.board',
          view: FileViewText(
            BoardDocument([
              for (var i = 0; i < count; i++)
                BoardItem(
                  'n$i',
                  BoardKind.process,
                  (i % 20) * 150.0,
                  (i ~/ 20) * 85.0,
                  label: 'Etapa de aprovação $i',
                ),
              for (var i = 1; i < count; i++)
                BoardItem(
                  'e$i',
                  BoardKind.arrow,
                  0,
                  0,
                  from: 'n${i - 1}',
                  to: 'n$i',
                ),
              BoardItem(
                'ink',
                BoardKind.stroke,
                12,
                250,
                width: 900,
                height: 50,
                points: [
                  for (var n = 0; n < 3000; n++)
                    (x: n * 0.3, y: (n % 50).toDouble()),
                ],
              ),
              const BoardItem(
                'diagram',
                BoardKind.mermaid,
                150,
                300,
                label: 'flowchart LR\n A-->B',
                thumbnail:
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8CKuQAAAAASUVORK5CYII=',
              ),
            ]).encode(),
          ),
        );
        final key = w.GlobalKey();
        var saves = 0;
        Future<bool> save(String s) async {
          saves++;
          await Future<void>.delayed(const Duration(milliseconds: 120));
          session.adoptDisk(FileViewText(s));
          return true;
        }

        w.runApp(
          TranslationProvider(
            child: ShadcnApp(
              theme: buildTheme(brightness: Brightness.dark),
              home: Scaffold(
                child: Row(
                  children: [
                    Expanded(
                      child: variant.value(
                        key: key,
                        session: session,
                        onSave: save,
                        onReload: () async {},
                      ),
                    ),
                    const SizedBox(width: 160, child: Text('Adjacent pane')),
                  ],
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        w.Element? viewer;
        void visit(w.Element e) {
          if (e.widget is w.InteractiveViewer) {
            viewer = e;
          } else {
            e.visitChildren(visit);
          }
        }

        visit(key.currentContext! as w.Element);
        final box = viewer!.renderObject as w.RenderBox;
        final start = box.localToGlobal(const Offset(50, 32));
        final binding = GestureBinding.instance;
        final id = count + run;
        binding.handlePointerEvent(
          PointerDownEvent(
            pointer: id,
            kind: ui.PointerDeviceKind.mouse,
            position: start,
            buttons: 1,
          ),
        );
        final times = <ui.FrameTiming>[];
        void record(List<ui.FrameTiming> v) => times.addAll(v);
        SchedulerBinding.instance.addTimingsCallback(record);
        final gestureFrames = <int>{};
        for (var i = 0; i < 180; i++) {
          final offset = Offset((i % 95).toDouble(), (i % 35).toDouble());
          binding.handlePointerEvent(
            PointerMoveEvent(
              pointer: id,
              kind: ui.PointerDeviceKind.mouse,
              position: start + offset,
              buttons: 1,
            ),
          );
          SchedulerBinding.instance.scheduleFrame();
          await SchedulerBinding.instance.endOfFrame;
          if (i >= 20) {
            gestureFrames.add(
              ui.PlatformDispatcher.instance.frameData.frameNumber,
            );
          }
        }
        binding.handlePointerEvent(
          PointerUpEvent(
            pointer: id,
            kind: ui.PointerDeviceKind.mouse,
            position: start + const Offset(84, 4),
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        SchedulerBinding.instance.removeTimingsCallback(record);
        final moved = BoardDocument.parse(
          (session.view as FileViewText).text,
        ).items['n0']!;
        if (saves != 1 ||
            (moved.x - 84).abs() > .01 ||
            (moved.y - 4).abs() > .01) {
          throw StateError(
            'Drag failed for ${variant.key} $count/$run: saves=$saves, position=(${moved.x}, ${moved.y})',
          );
        }
        final data = times
            .where((t) => gestureFrames.contains(t.frameNumber))
            .toList();
        if (data.length < 145 || data.length > 160) {
          throw StateError('Incomplete FrameTiming batch: ${data.length}');
        }
        double p95(Duration Function(ui.FrameTiming t) get) {
          final values = data.map((t) => get(t).inMicroseconds / 1000).toList()
            ..sort();
          return values[(.95 * (values.length - 1)).round()];
        }

        final over = data
            .where(
              (t) =>
                  t.buildDuration.inMicroseconds > 16667 ||
                  t.rasterDuration.inMicroseconds > 16667,
            )
            .length;
        final hz =
            ui.PlatformDispatcher.instance.views.first.display.refreshRate;
        final displayBudget = 1e6 / hz;
        final overDisplay = data
            .where(
              (frame) =>
                  frame.buildDuration.inMicroseconds > displayBudget ||
                  frame.rasterDuration.inMicroseconds > displayBudget,
            )
            .length;
        report.add(
          '${variant.key}\t$count\t$run\t${data.length}\t${p95((t) => t.buildDuration)}\t${p95((t) => t.rasterDuration)}\t$over\t$overDisplay\t$hz',
        );
        output.writeAsStringSync(report.join('\n'));
        w.runApp(const w.SizedBox.shrink());
        await SchedulerBinding.instance.endOfFrame;
        session.dispose();
      }
    }
  }
}

/// An offline 640 × 320 architecture thumbnail with paths, labels and shapes.
Future<String> architectureThumbnail() async {
  final recorder = ui.PictureRecorder();
  final c = ui.Canvas(recorder);
  final paint = ui.Paint();
  c.drawColor(const Color(0xfff3f5f7), ui.BlendMode.src);
  final nodes = [
    (const Offset(32, 106), 'Gateway'),
    (const Offset(240, 48), 'Orders API'),
    (const Offset(448, 48), 'PostgreSQL'),
    (const Offset(240, 180), 'Queue'),
    (const Offset(448, 180), 'Worker'),
  ];
  for (final pair in [(0, 1), (0, 3), (1, 2), (3, 4), (1, 4)]) {
    final from = nodes[pair.$1].$1 + const Offset(140, 28);
    final to = nodes[pair.$2].$1 + const Offset(0, 28);
    final mid = (from.dx + to.dx) / 2;
    final path = ui.Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(mid, from.dy)
      ..lineTo(mid, to.dy)
      ..lineTo(to.dx, to.dy);
    c.drawPath(
      path,
      paint
        ..color = const Color(0xff476780)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
  for (final (at, title) in nodes) {
    c.drawRRect(
      ui.RRect.fromRectAndRadius(
        at & const Size(140, 56),
        const Radius.circular(10),
      ),
      paint
        ..style = ui.PaintingStyle.fill
        ..color = const Color(0xff2d5674),
    );
    final text =
        (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 18))
              ..pushStyle(
                ui.TextStyle(color: const Color(0xffffffff), fontSize: 18),
              )
              ..addText(title))
            .build()
          ..layout(const ui.ParagraphConstraints(width: 130));
    c.drawParagraph(text, at + const Offset(10, 16));
    text.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 320);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

enum _Scenario { firstPaint, ink, zoom, group }

w.Element? findElement(
  w.Element parent,
  bool Function(w.Widget widget) matches,
) {
  if (matches(parent.widget)) return parent;
  w.Element? result;
  parent.visitChildren((element) {
    result ??= findElement(element, matches);
  });
  return result;
}

BoardDocument interactionScene(int count, String thumbnail) => BoardDocument([
  for (var i = 0; i < count; i++)
    BoardItem(
      'n$i',
      BoardKind.process,
      (i % 20) * 150.0,
      (i ~/ 20) * 85.0,
      label: 'Etapa de aprovação $i',
      group: i < 8 ? 'architecture' : null,
    ),
  for (var i = 1; i < count; i++)
    BoardItem('e$i', BoardKind.arrow, 0, 0, from: 'n${i - 1}', to: 'n$i'),
  BoardItem(
    'architecture',
    BoardKind.mermaid,
    150,
    180,
    width: 320,
    height: 160,
    group: 'architecture',
    thumbnail: thumbnail,
    label:
        'flowchart LR\n Gateway-->Orders\n Orders-->PostgreSQL\n Gateway-->Queue\n Queue-->Worker\n Orders-->Worker',
  ),
]);

Offset inkOffset(int sample) => sample == 0
    ? const Offset(1, 0)
    : Offset(
        4 + ((sample % 600) - 300).abs().toDouble(),
        90 + 70 * math.sin(sample * .025),
      );

/// Measure the targeted board interactions separately from the historical drag
/// suite. A real file in the scratch directory validates persist/reopen.
Future<void> measureInteractions(
  File output,
  ProfileView? baseline, {
  required List<_Scenario> scenarios,
  required bool separateHost,
}) async {
  final rows = <String>[
    'version\tscenario\tcount\trun\tframes\tbuildP95ms\trasterP95ms\tover16.67ms\toverDisplayBudget\tdisplayHz\treadyMs\tsaves\tgestureMs\tframeIntervalP95ms'
        '${separateHost ? '\thostBuildMs\thostRasterMs' : ''}',
  ];
  final scratch = await output.parent.createTemp('board-profile-');
  final thumbnail = await architectureThumbnail();
  final host = w.ValueNotifier<w.Widget>(const w.SizedBox.shrink());
  w.runApp(
    w.ValueListenableBuilder<w.Widget>(
      valueListenable: host,
      builder: (_, widget, _) => widget,
    ),
  );
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 500));
  try {
    for (var run = 1; run <= 3; run++) {
      for (final scenario in (run.isEven ? scenarios.reversed : scenarios)) {
        final views = {
          'before': ?baseline,
          'current': BoardView.new,
        }.entries.toList();
        for (final version in run.isEven ? views.reversed : views) {
          const count = 960;
          final original = interactionScene(count, thumbnail);
          final path = File(
            '${scratch.path}/${version.key}-${scenario.name}-$run.board',
          );
          await path.writeAsString(original.encode(), flush: true);
          final session = FileViewerSession(
            id: 'scene',
            projectId: 'benchmark',
            path: path.path,
            view: FileViewText(await path.readAsString()),
          );
          final key = w.GlobalKey();
          final scheduler = SchedulerBinding.instance;
          final dispatcher = ui.PlatformDispatcher.instance;
          final times = <ui.FrameTiming>[];
          final ids = <int>{};
          var saves = 0;
          var readyMs = 0.0;
          var gestureMs = 0.0;
          final intervals = <double>[];
          final pane = w.ValueNotifier<w.Widget>(const w.SizedBox.shrink());
          int? hostFrame;
          void record(List<ui.FrameTiming> batch) => times.addAll(batch);
          scheduler.addTimingsCallback(record);
          try {
            final clock = Stopwatch()..start();
            final editor = version.value(
              key: key,
              session: session,
              onReload: () async {},
              onSave: (source) async {
                saves++;
                await Future<void>.delayed(const Duration(milliseconds: 120));
                await path.writeAsString(source, flush: true);
                session.adoptDisk(FileViewText(await path.readAsString()));
                return true;
              },
            );
            host.value = TranslationProvider(
              child: ShadcnApp(
                theme: buildTheme(brightness: Brightness.dark),
                home: Scaffold(
                  child: Row(
                    children: [
                      Expanded(
                        child: separateHost
                            ? w.ValueListenableBuilder<w.Widget>(
                                valueListenable: pane,
                                builder: (_, child, _) => child,
                              )
                            : editor,
                      ),
                      const SizedBox(width: 160, child: Text('Adjacent pane')),
                    ],
                  ),
                ),
              ),
            );
            await scheduler.endOfFrame;
            if (separateHost) {
              hostFrame = dispatcher.frameData.frameNumber;
              await Future<void>.delayed(const Duration(milliseconds: 500));
              clock.reset();
              pane.value = editor;
              await scheduler.endOfFrame;
            }
            final root = key.currentContext! as w.Element;
            final first = dispatcher.frameData.frameNumber;
            final viewer = findElement(root, (w) => w is m.InteractiveViewer)!;
            final camera = (viewer.widget as m.InteractiveViewer)
                .transformationController!;
            final box = viewer.renderObject as w.RenderBox;
            final start = box.localToGlobal(const Offset(50, 32));
            final deadline = DateTime.now().add(const Duration(seconds: 10));
            while (findElement(
                  root,
                  (w) => w is m.RawImage && w.image != null,
                ) ==
                null) {
              if (DateTime.now().isAfter(deadline)) {
                throw StateError('Thumbnail did not decode');
              }
              scheduler.scheduleFrame();
              await scheduler.endOfFrame;
            }
            readyMs = clock.elapsedMicroseconds / 1000;
            if (scenario == _Scenario.firstPaint) {
              ids.add(first);
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              final isZoom = scenario == _Scenario.zoom;
              if (scenario == _Scenario.ink) {
                final pencil = findElement(
                  root,
                  (widget) =>
                      widget is m.IconButton &&
                      widget.tooltip == root.t.cockpit.gallery.board.pencil,
                );
                (pencil!.widget as m.IconButton).onPressed!();
                await scheduler.endOfFrame;
              }
              final id = 10 + run * 4 + scenario.index;
              final input = GestureBinding.instance;
              if (!isZoom) {
                input.handlePointerEvent(
                  PointerDownEvent(
                    pointer: id,
                    kind: ui.PointerDeviceKind.mouse,
                    position: start,
                    buttons: 1,
                  ),
                );
              }
              var last = start;
              final zoomStart = camera.value.clone();
              var maxScale = camera.value.getMaxScaleOnAxis();
              final gestureClock = Stopwatch()..start();
              var previousMicros = 0;
              for (var frame = 0; frame < 180; frame++) {
                if (isZoom) {
                  input.handlePointerEvent(
                    PointerScrollEvent(
                      kind: ui.PointerDeviceKind.mouse,
                      position: start + const Offset(150, 60),
                      scrollDelta: Offset(0, frame % 20 < 10 ? -10 : 10),
                    ),
                  );
                } else {
                  final samples = scenario == _Scenario.ink ? 16 : 1;
                  for (var j = 0; j < samples; j++) {
                    final i = (frame * samples + j);
                    last = scenario == _Scenario.ink
                        ? start + inkOffset(i)
                        : start +
                              Offset(
                                (frame % 95).toDouble(),
                                (frame % 35).toDouble(),
                              );
                    input.handlePointerEvent(
                      PointerMoveEvent(
                        pointer: id,
                        kind: ui.PointerDeviceKind.mouse,
                        position: last,
                        buttons: 1,
                      ),
                    );
                  }
                }
                scheduler.scheduleFrame();
                await scheduler.endOfFrame;
                final nowMicros = gestureClock.elapsedMicroseconds;
                if (frame >= 20) {
                  ids.add(dispatcher.frameData.frameNumber);
                  intervals.add((nowMicros - previousMicros) / 1000);
                }
                previousMicros = nowMicros;
                maxScale = math.max(maxScale, camera.value.getMaxScaleOnAxis());
              }
              gestureMs = gestureClock.elapsedMicroseconds / 1000;
              if (isZoom) {
                if (maxScale < 1.4 ||
                    (camera.value.getMaxScaleOnAxis() -
                                zoomStart.getMaxScaleOnAxis())
                            .abs() >
                        .01) {
                  throw StateError(
                    'Zoom did not oscillate: peak=$maxScale, final=${camera.value.getMaxScaleOnAxis()}',
                  );
                }
              } else {
                input.handlePointerEvent(
                  PointerUpEvent(
                    pointer: id,
                    position: last,
                    kind: ui.PointerDeviceKind.mouse,
                  ),
                );
              }
            }
            await Future<void>.delayed(const Duration(seconds: 2));
            final source = await path.readAsString();
            if ((session.view as FileViewText).text != source ||
                session.dirty) {
              throw StateError('Disk and visible session differ');
            }
            final saved = BoardDocument.parse(source);
            switch (scenario) {
              case _Scenario.firstPaint:
              case _Scenario.zoom:
                if (saves != 0 || source != original.encode()) {
                  throw StateError('Read-only interaction changed document');
                }
              case _Scenario.ink:
                final strokes = saved.items.values.where(
                  (i) => i.kind == BoardKind.stroke,
                );
                if (saves != 1 ||
                    strokes.length != 1 ||
                    strokes.single.points.length != 2881 ||
                    saved.items.length != original.items.length + 1) {
                  throw StateError(
                    'Ink failed: saves=$saves, points=${strokes.firstOrNull?.points.length}',
                  );
                }
                final stroke = strokes.single;
                for (var i = 0; i < stroke.points.length; i++) {
                  final expected =
                      const Offset(50, 32) +
                      (i == 0 ? Offset.zero : inkOffset(i - 1));
                  final point = stroke.points[i];
                  if ((Offset(point.x + stroke.x, point.y + stroke.y) -
                              expected)
                          .distance >
                      .01) {
                    throw StateError('Ink sample $i differs after reopening');
                  }
                }
              case _Scenario.group:
                if (saves != 1 || saved.items.length != original.items.length) {
                  throw StateError('Invalid group save');
                }
                for (final item in original.items.values) {
                  final moved = saved.items[item.id]!;
                  final expected = item.group == 'architecture'
                      ? item.edited(x: item.x + 84, y: item.y + 4)
                      : item;
                  if (jsonEncode(moved.toJson()) !=
                      jsonEncode(expected.toJson())) {
                    throw StateError('Group changed ${item.id} incorrectly');
                  }
                }
            }
            final data = times
                .where((t) => ids.contains(t.frameNumber))
                .toList();
            if (data.length != ids.length ||
                ids.length != (scenario == _Scenario.firstPaint ? 1 : 160)) {
              throw StateError('Missing frames: ${data.length}/${ids.length}');
            }
            double p95(Duration Function(ui.FrameTiming) f) {
              final sorted =
                  data.map((t) => f(t).inMicroseconds / 1000).toList()..sort();
              return sorted[((sorted.length - 1) * .95).round()];
            }

            final hz = dispatcher.views.first.display.refreshRate;
            int over(double budget) => data
                .where(
                  (t) =>
                      math.max(
                        t.buildDuration.inMicroseconds,
                        t.rasterDuration.inMicroseconds,
                      ) >
                      budget,
                )
                .length;
            intervals.sort();
            final shell = hostFrame == null
                ? null
                : times.singleWhere((frame) => frame.frameNumber == hostFrame);
            rows.add(
              [
                version.key,
                scenario.name,
                count,
                run,
                data.length,
                p95((t) => t.buildDuration),
                p95((t) => t.rasterDuration),
                over(16667),
                over(1e6 / hz),
                hz,
                readyMs,
                saves,
                gestureMs,
                intervals.isEmpty
                    ? 0
                    : intervals[((intervals.length - 1) * .95).round()],
                if (shell != null) ...[
                  shell.buildDuration.inMicroseconds / 1000,
                  shell.rasterDuration.inMicroseconds / 1000,
                ],
              ].join('\t'),
            );
            await output.writeAsString(rows.join('\n'), flush: true);
          } finally {
            scheduler.removeTimingsCallback(record);
            host.value = const w.SizedBox.shrink();
            await scheduler.endOfFrame;
            session.dispose();
            pane.dispose();
            m.PaintingBinding.instance.imageCache.clear();
            m.PaintingBinding.instance.imageCache.clearLiveImages();
          }
        }
      }
    }
  } finally {
    await scratch.delete(recursive: true);
  }
}
