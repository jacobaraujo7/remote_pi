import 'dart:convert';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/cockpit/domain/entities/terminal_owner.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
// Run: flutter test tool/design/render_workspace_layouts_test.dart
// These are component renders with fictional data, not desktop screenshots.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_presentation.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/orchestration_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/stable_pane_host.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/ui/widgets/adaptive_terminal_pane.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import '../../test/support/attachment_terminal_gateway.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

class _PreviewSettings extends SettingsController {
  _PreviewSettings() : super(_Settings());
  @override
  AppSettings get settings => _settings;
}

class _VM extends ChangeNotifier implements CockpitViewModel {
  _VM(this.presentation) {
    for (final box in graphBoxes) {
      final tab = TerminalSession(
        id: box.tabId!,
        owner: const TerminalOwner.orchestration('app'),
        projectId: 'demo',
        workingDirectory: '/workspace/demo',
        gateway: AttachmentTerminalGateway(),
        profile: const TerminalProfile(
          id: 'shell',
          label: 'Shell',
          executable: 'sh',
        ),
      );
      tab.terminal.write(
        'Terminal de demonstração: ${box.title}\r\n/workspace/demo > \r\n',
      );
      tabs[tab.id] = tab;
    }
  }
  final tabs = <String, TerminalSession>{};
  String? openedBox;
  void simulateWorkspaceTraffic() => notifyListeners();
  @override
  void openBoxInTerminals(String boxId) {
    openedBox = boxId;
  }

  @override
  OrchestrationPresentation presentation;
  @override
  String? get selectedProjectId {
    projectReads++;
    return 'demo';
  }

  int projectReads = 0;
  @override
  String get selectedDisplayTitle => 'Workspace de demonstração';
  @override
  bool get selectedRemoteDisconnected => false;
  @override
  List<GraphBox> get graphBoxes => const [
    GraphBox(
      id: 'backend',
      title: 'Backend',
      role: 'Implementar a API',
      harness: 'codex',
      model: '',
      position: Offset(30, 190),
      tabId: 'api',
    ),
    GraphBox(
      id: 'design',
      title: 'Design',
      role: 'Refinar a interface',
      harness: '',
      model: '',
      position: Offset(290, 350),
      tabId: 'ui',
    ),
    GraphBox(
      id: 'review',
      title: 'Review',
      role: 'Revisar a entrega',
      harness: 'claude',
      model: '',
      position: Offset(550, 190),
      tabId: 'qa',
    ),
  ];
  @override
  List<GraphLink> get graphLinks => const [
    GraphLink(from: 'backend', to: 'review'),
  ];
  @override
  List<GraphObservedLink> get graphTraffic => [];
  @override
  List<GraphUnresolvedPeer> get graphUnresolvedPeers => [];
  @override
  List<GraphSubagent> get graphSubagents => [];
  @override
  Iterable<TerminalSession> get allSessions => tabs.values;
  @override
  TerminalSession? session(String id) => tabs[id];
  @override
  GraphBox? get selectedWorkspaceBox =>
      graphBoxes.where((b) => b.id == presentation.selectedBoxId).firstOrNull ??
      graphBoxes.first;
  @override
  void setWorkspaceView(OrchestrationViewMode mode) =>
      updatePresentation(presentation.copyWith(mode: mode));
  @override
  void selectWorkspaceBox(String id, {bool configure = false}) =>
      updatePresentation(
        presentation.copyWith(
          selectedBoxId: id,
          inspectorOpen: configure ? true : null,
        ),
      );
  @override
  void updatePresentation(OrchestrationPresentation value) {
    presentation = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metrics implements ProcessMetricsProvider {
  @override
  Future<ProcessMetricsSnapshot> read(int pid) async => ProcessMetricsSnapshot(
    pid: pid,
    cpuPercent: null,
    rssBytes: null,
    collectedAt: DateTime.now(),
    source: 'fixture',
  );
}

const _settings = AppSettings(
  interfaceFont: 'Preview UI',
  codeFont: 'Preview Mono',
  terminalFont: 'Preview Mono',
);
Future<void> _loadFonts() async {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  );
  final packages = (config['packages'] as List).cast<Map>();
  String root(String name) => Uri.parse(
    packages.firstWhere((p) => p['name'] == name)['rootUri'] as String,
  ).toFilePath();
  final shadcn = root('shadcn_flutter');
  final font = File(
    '$shadcn/lib/fonts/Geist-Regular.otf',
  ).readAsBytesSync().buffer.asByteData();
  for (final family in ['Preview UI', 'Preview Mono']) {
    await (FontLoader(family)..addFont(Future.value(font))).load();
  }
  final flutterRoot = Directory(root('flutter')).parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync().buffer.asByteData();
  await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  for (final entry in [
    ('boxes-dock', OrchestrationViewMode.boxes, false, 1440.0),
    ('graph-dock', OrchestrationViewMode.graph, false, 1440.0),
    ('inspector-dock', OrchestrationViewMode.boxes, true, 1600.0),
    ('narrow-inspector', OrchestrationViewMode.boxes, true, 540.0),
    ('narrow-graph', OrchestrationViewMode.graph, false, 540.0),
  ]) {
    testWidgets('dockable orchestration ${entry.$1}', (tester) async {
      tester.view.physicalSize = Size(entry.$4, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await LocaleSettings.setLocale(AppLocale.ptBr);
      final vm = _VM(
        OrchestrationPresentation(
          mode: entry.$2,
          inspectorOpen: entry.$3,
          selectedBoxId: 'backend',
          boxOrder: const ['backend', 'design', 'review'],
        ),
      );
      final document = OrchestrationDocument(
        boxes: [for (final b in vm.graphBoxes) OrchestrationBox(box: b)],
        links: vm.graphLinks,
      );
      final controller = OrchestrationController(
        read: () async => document.encode(),
        write: (_) async {},
        createShell: (_) async => throw StateError('must reuse fixture shells'),
        closeTerminal: (_) async {},
        terminals: () => [
          for (final tab in vm.tabs.values)
            OrchestrationTerminal(tab.id, tab.displayTitle, '.'),
        ],
        newBoxId: () => throw StateError('unexpected discovery'),
        bindings: {for (final box in vm.graphBoxes) box.id: box.tabId!},
      );
      final app = OrchestrationSession(
        id: 'app',
        projectId: 'demo',
        path: '/workspace/demo/agents.orchestration',
        controller: controller,
        presentation: vm.presentation,
      );
      for (final tab in vm.tabs.values) {
        app.terminals.attach(tab, focus: false);
      }
      await controller.load();
      app.context.openBoxInTerminals('backend');
      expect(controller.error, isNull);
      final external = createTerminalController(TerminalEngine.xterm);
      external.write('Terminal externo ao orquestrador\r\n/workspace/demo > ');
      final key = GlobalKey();
      final focus = FocusNode();
      final overviewActive = ValueNotifier(true);
      var sourceEdits = 0;
      Widget overview() => ValueListenableBuilder<bool>(
        valueListenable: overviewActive,
        builder: (_, active, _) => OrchestrationView(
          session: app,
          active: active,
          focused: active,
          processMetrics: _Metrics(),
          onEditSource: () => sourceEdits++,
        ),
      );
      Widget dockHeader(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            color: const Color(0xff202027),
            child: Text(label),
          ),
          Expanded(child: child),
        ],
      );
      await tester.pumpWidget(
        ModularApp(
          module: createModule(register: (_) {}),
          provide: (scope) => scope
            ..addChangeNotifier<SettingsController>(() => _PreviewSettings()),
          child: TranslationProvider(
            child: ShadcnApp(
              theme: buildTheme(
                brightness: Brightness.dark,
                settings: _settings,
              ),
              builder: (context, child) {
                final tokens = buildTokens(
                  brightness: Brightness.dark,
                  settings: _settings,
                );
                return CockpitTheme(
                  colors: tokens.colors,
                  typo: tokens.typo,
                  syntax: tokens.syntax,
                  terminal: tokens.terminal,
                  child: child!,
                );
              },
              home: Scaffold(
                child: RepaintBoundary(
                  key: key,
                  child: entry.$4 < 800
                      ? overview()
                      : StablePaneHost(
                          tree: const SplitPane(
                            id: 'split',
                            dir: SplitDir.vertical,
                            frac: .64,
                            a: LeafPane(
                              id: 'orchestration',
                              tabs: ['app'],
                              active: 'app',
                            ),
                            b: LeafPane(
                              id: 'terminals',
                              tabs: ['api', 'ui', 'qa'],
                              active: 'api',
                            ),
                          ),
                          onResize: (_, _) {},
                          paneBuilder: (pane, visible) =>
                              pane.id == 'orchestration'
                              ? dockHeader('Agent Orchestration  ×', overview())
                              : dockHeader(
                                  'Backend  ×     Design     Review     +',
                                  AdaptiveTerminalPane(
                                    terminal: external,
                                    focusNode: focus,
                                    active: true,
                                    textStyle: const xterm.TerminalStyle(
                                      fontFamily: 'Preview Mono',
                                    ),
                                    theme: xterm.TerminalThemes.defaultTheme,
                                    onKeyEvent: (_) => KeyEventResult.ignored,
                                  ),
                                ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Novo terminal'), findsOneWidget);
      await tester.tap(find.text('Abrir como JSON'));
      await tester.pump();
      expect(sourceEdits, 1);
      expect(app.terminals.sessions.length, 3);
      // One selected owned terminal plus the independent external terminal.
      expect(
        find.byType(AdaptiveTerminalPane),
        entry.$4 < 800 ? findsOneWidget : findsNWidgets(2),
      );
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = Directory('review/agent-orchestration');
        out.createSync(recursive: true);
        File(
          '${out.path}/${entry.$1}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      if (entry.$1 == 'boxes-dock') {
        await tester.tap(find.text('Design').first);
        await tester.pump(const Duration(milliseconds: 350));
        expect(app.context.presentation.selectedBoxId, 'design');
        expect(app.terminals.keyboardTabId, 'ui');

        final terminalElement = tester.element(
          find.descendant(
            of: find.byKey(const ValueKey(('app', 'ui'))),
            matching: find.byType(AdaptiveTerminalPane),
          ),
        );
        await tester.tap(find.text('Grafo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(app.context.presentation.mode, OrchestrationViewMode.graph);
        expect(
          tester.element(
            find.descendant(
              of: find.byKey(const ValueKey(('app', 'ui'))),
              matching: find.byType(AdaptiveTerminalPane),
            ),
          ),
          same(terminalElement),
        );
        await tester.tap(find.text('Boxes'));
        await tester.pump();
        expect(
          tester.element(
            find.descendant(
              of: find.byKey(const ValueKey(('app', 'ui'))),
              matching: find.byType(AdaptiveTerminalPane),
            ),
          ),
          same(terminalElement),
        );
        expect(tester.takeException(), isNull);
      }
      // Hidden app tabs keep their state but must not rebuild on workspace
      // traffic or run graph telemetry timers. Native sessions stay mounted.
      final overviewState = tester.state(find.byType(OrchestrationView));
      overviewActive.value = false;
      await tester.pump();
      expect(tester.state(find.byType(OrchestrationView)), same(overviewState));
      final beforeTraffic = vm.projectReads;
      vm.simulateWorkspaceTraffic();
      vm.tabs.values.first.markUnseen();
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      expect(vm.projectReads, beforeTraffic);
      overviewActive.value = true;
      await tester.pump();
      expect(
        vm.projectReads,
        beforeTraffic,
      ); // no global project lookup even on reactivation

      expect(tester.state(find.byType(OrchestrationView)), same(overviewState));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      overviewActive.dispose();
      focus.dispose();
      external.dispose();
      await tester.runAsync(() async {
        await app.dispose();
      });
      vm.dispose();
    });
  }
}
