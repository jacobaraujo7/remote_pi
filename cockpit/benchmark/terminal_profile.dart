// ignore_for_file: invalid_use_of_visible_for_testing_member
// Run: flutter run --profile -d windows -t benchmark/terminal_profile.dart
// Prints one terminal_profile JSON line after 30 seconds. No app bootstrap,
// saved profile, PTY, or installed user data is accessed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/terminal/pty_output_scheduler.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_harness_monitor.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Benchmark());
}

final bool _renderGate = Platform.environment['BENCH_RENDER_GATE'] != 'false';
final bool _scanThrottle =
    Platform.environment['BENCH_SCAN_THROTTLE'] != 'false';
final bool _hiddenFrames =
    Platform.environment['BENCH_HIDDEN_FRAMES'] == 'true';
final bool _visibleOutput =
    Platform.environment['BENCH_VISIBLE_OUTPUT'] != 'false';
final int _switchMs = _positiveMilliseconds('BENCH_SWITCH_MS', 500);
final int _outputMs = _positiveMilliseconds('BENCH_OUTPUT_MS', 50);
final int _durationMs = _positiveMilliseconds('BENCH_DURATION_MS', 30000);

int _positiveMilliseconds(String key, int fallback) {
  final value = int.tryParse(Platform.environment[key] ?? '');
  return value != null && value > 0 ? value : fallback;
}

class _Benchmark extends StatefulWidget {
  const _Benchmark();
  @override
  State<_Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<_Benchmark> {
  static const count = 10;
  final terminals = List.generate(count, (_) => GhosttyTerminalController());
  final focusNodes = List.generate(count, (_) => FocusNode());
  final frames = <int>[];
  final builds = <int>[];
  final rasters = <int>[];
  final switches = <int>[];
  final clock = Stopwatch()..start();
  late final PtyOutputScheduler scheduler;
  late final List<PtyOutputCoalescer> sources;
  late final _SyntheticProcessTreeProvider processProvider;
  late final TerminalHarnessMonitor monitor;
  Timer? outputTimer;
  Timer? switchTimer;
  Timer? finishTimer;
  int selected = 0;
  int sequence = 0;
  int maxPending = 0;
  int maxReady = 0;
  int generated = 0;
  int parsed = 0;
  int hiddenParsed = 0;
  int acknowledgements = 0;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    scheduler = PtyOutputScheduler(scheduleHiddenFrames: _hiddenFrames);
    processProvider = _SyntheticProcessTreeProvider();
    monitor = TerminalHarnessMonitor(
      provider: processProvider,
      pollInterval: const Duration(days: 1),
      idlePollInterval: const Duration(days: 1),
      activityPollInterval: _scanThrottle
          ? const Duration(seconds: 1)
          : Duration.zero,
      urgentPollInterval: _scanThrottle
          ? const Duration(milliseconds: 150)
          : Duration.zero,
      pendingPollDelay: _scanThrottle
          ? const Duration(milliseconds: 40)
          : Duration.zero,
    );
    for (var index = 0; index < count; index++) {
      monitor.registerSession(
        sessionId: 'agent-$index',
        rootPid: () => 1000 + index,
        onHarnessChanged: (_) {},
      );
    }
    sources = List.generate(
      count,
      (index) => PtyOutputCoalescer(
        scheduler: scheduler,
        onFlush: (chunk) {
          terminals[index].write(chunk);
          monitor.requestPoll(sessionId: 'agent-$index');
          parsed += chunk.length;
          if (index != selected) hiddenParsed += chunk.length;
        },
        onAcknowledge: () => acknowledgements++,
      )..visible = index == selected,
    );
    SchedulerBinding.instance.addTimingsCallback(recordFrames);
    outputTimer = Timer.periodic(
      Duration(milliseconds: _outputMs),
      (_) => emitOutput(),
    );
    switchTimer = Timer.periodic(
      Duration(milliseconds: _switchMs),
      (_) => switchTab(),
    );
    finishTimer = Timer(
      Duration(milliseconds: _durationMs),
      () => unawaited(finish()),
    );
  }

  void recordFrames(List<FrameTiming> timings) {
    for (final timing in timings) {
      frames.add(timing.totalSpan.inMicroseconds);
      builds.add(timing.buildDuration.inMicroseconds);
      rasters.add(timing.rasterDuration.inMicroseconds);
    }
  }

  void emitOutput() {
    final line =
        '\u001b[36magent ${sequence++}\u001b[0m '
        '${List.filled(8, 'working on a synthetic task ').join()}\r\n';
    for (var index = 0; index < sources.length; index++) {
      if (!_visibleOutput && index == selected) continue;
      final source = sources[index];
      source.add(line);
      generated += line.length;
    }
    if (scheduler.pendingChars > maxPending) {
      maxPending = scheduler.pendingChars;
    }
    if (scheduler.readySources > maxReady) {
      maxReady = scheduler.readySources;
    }
  }

  void switchTab() {
    final start = clock.elapsedMicroseconds;
    setState(() {
      sources[selected].visible = false;
      selected = (selected + 1) % count;
      sources[selected].visible = true;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      switches.add(clock.elapsedMicroseconds - start);
    });
  }

  Future<void> finish() async {
    if (finished) return;
    finished = true;
    outputTimer?.cancel();
    switchTimer?.cancel();
    await Future.wait(sources.map((source) => source.drained));
    monitor.dispose();
    await SchedulerBinding.instance.endOfFrame;
    frames.sort();
    builds.sort();
    rasters.sort();
    switches.sort();
    final result = jsonEncode({
      'benchmark': 'synthetic_terminal_profile',
      'renderGate': _renderGate,
      'scanThrottle': _scanThrottle,
      'hiddenFrames': _hiddenFrames,
      'visibleOutput': _visibleOutput,
      'switchMs': _switchMs,
      'outputMs': _outputMs,
      'terminals': count,
      'durationMs': clock.elapsedMilliseconds,
      'frameCount': frames.length,
      'jankFrames': frames.where((us) => us > 16667).length,
      'frameP95Us': percentile(frames),
      'frameMaxUs': frames.isEmpty ? null : frames.last,
      'buildP95Us': percentile(builds),
      'buildOverBudget': builds.where((us) => us > 16667).length,
      'rasterP95Us': percentile(rasters),
      'rasterOverBudget': rasters.where((us) => us > 16667).length,
      'tabSwitchCount': switches.length,
      'tabSwitchP95Us': percentile(switches),
      'tabSwitchMaxUs': switches.isEmpty ? null : switches.last,
      'ptyMaxPendingChars': maxPending,
      'ptyPendingCharsAtEnd': scheduler.pendingChars,
      'ptyMaxReadySources': maxReady,
      'generatedChars': generated,
      'parsedChars': parsed,
      'hiddenParsedChars': hiddenParsed,
      'acknowledgements': acknowledgements,
      'rssBytes': ProcessInfo.currentRss,
      'syntheticProcessScans': processProvider.calls,
    });
    stdout.writeln('terminal_profile $result');
    final resultFile = Platform.environment['BENCH_RESULT_FILE'];
    if (resultFile != null && resultFile.isNotEmpty) {
      await File(resultFile).writeAsString(result);
    } else {
      await stdout.flush();
    }
    exit(0);
  }

  int? percentile(List<int> sorted) =>
      sorted.isEmpty ? null : sorted[((sorted.length - 1) * 0.95).round()];

  @override
  void dispose() {
    outputTimer?.cancel();
    switchTimer?.cancel();
    finishTimer?.cancel();
    monitor.dispose();
    SchedulerBinding.instance.removeTimingsCallback(recordFrames);
    for (final source in sources) {
      source.dispose();
    }
    for (final node in focusNodes) {
      node.dispose();
    }
    for (final terminal in terminals) {
      terminal.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xff18181b),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Center(
              child: Text(
                'Synthetic terminal benchmark ${selected + 1}/$count',
                style: const TextStyle(color: Color(0xffffffff)),
              ),
            ),
          ),
          Expanded(
            child: ghost.TerminalScope(
              child: Stack(
                children: [
                  for (var i = 0; i < count; i++)
                    Offstage(
                      offstage: i != selected,
                      child: TickerMode(
                        enabled: i == selected,
                        child: ghost.TerminalView(
                          key: GlobalObjectKey(terminals[i].controller),
                          controller: terminals[i].controller,
                          presentationActive: !_renderGate || i == selected,
                          focusNode: focusNodes[i],
                          showKeyboard: false,
                          padding: EdgeInsets.zero,
                          scrollPhysics: const ClampingScrollPhysics(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SyntheticProcessTreeProvider implements ProcessTreeProvider {
  int calls = 0;

  @override
  Future<List<ProcessSnapshot>> getProcessSnapshots({
    required List<int> rootPids,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const [];
  }
}
