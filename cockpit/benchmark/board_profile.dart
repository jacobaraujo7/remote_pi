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
    await measure(output, baseline);
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
