import 'dart:convert';
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

class _VM extends ChangeNotifier implements CockpitViewModel {
  _VM(this.presentation) {
    for (final box in graphBoxes) {
      final tab = TerminalSession(
        id: box.tabId!,
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
  @override
  void openBoxInTerminals(String boxId) {
    openedBox = boxId;
  }

  @override
  OrchestrationPresentation presentation;
  @override
  String? get selectedProjectId => 'demo';
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
      await controller.load();
      expect(controller.error, isNull);
      final app = OrchestrationSession(
        id: 'app',
        projectId: 'demo',
        path: '/workspace/demo/agents.orchestration',
        controller: controller,
      );
      final key = GlobalKey();
      final focus = FocusNode();
      Widget overview() => OrchestrationView(
        session: app,
        vm: vm,
        active: true,
        processMetrics: _Metrics(),
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
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark, settings: _settings),
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
                                  terminal: vm.tabs['api']!.terminal,
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
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Novo terminal'), findsOneWidget);
      // App mode switching changes only its own pane; no second terminal view.
      expect(
        find.byType(AdaptiveTerminalPane),
        entry.$4 < 800 ? findsNothing : findsOneWidget,
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
        await tester.tap(find.text('Design'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(vm.presentation.selectedBoxId, 'design');
        expect(vm.openedBox, 'design');

        final terminalElement = tester.element(
          find.byType(AdaptiveTerminalPane),
        );
        await tester.tap(find.text('Grafo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(vm.presentation.mode, OrchestrationViewMode.graph);
        expect(
          tester.element(find.byType(AdaptiveTerminalPane)),
          same(terminalElement),
        );
        await tester.tap(find.text('Boxes'));
        await tester.pump();
        expect(
          tester.element(find.byType(AdaptiveTerminalPane)),
          same(terminalElement),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      app.dispose();
      focus.dispose();
      await tester.runAsync(() async {
        for (final tab in vm.tabs.values) {
          tab.dispose();
        }
        await Future<void>.delayed(Duration.zero);
      });
      vm.dispose();
    });
  }
}
