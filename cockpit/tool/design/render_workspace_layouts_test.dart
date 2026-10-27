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
import 'package:cockpit/app/cockpit/domain/entities/workspace_presentation.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_experience.dart';
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
  @override
  WorkspacePresentation presentation;
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
      position: Offset(60, 110),
      tabId: 'api',
    ),
    GraphBox(
      id: 'design',
      title: 'Design',
      role: 'Refinar a interface',
      harness: '',
      model: '',
      position: Offset(360, 230),
      tabId: 'ui',
    ),
    GraphBox(
      id: 'review',
      title: 'Review',
      role: 'Revisar a entrega',
      harness: 'claude',
      model: '',
      position: Offset(660, 110),
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
  GraphBox? get selectedWorkspaceBox => graphBoxes.first;
  @override
  String? previewTabFor(String projectId) => 'api';
  @override
  void updatePresentation(WorkspacePresentation value) {
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
    ('boxes', WorkspaceViewMode.boxes, false, 1440.0),
    ('graph', WorkspaceViewMode.graph, false, 1440.0),
    ('inspector', WorkspaceViewMode.boxes, true, 1440.0),
  ]) {
    testWidgets('render ${entry.$1}', (tester) async {
      tester.view.physicalSize = Size(entry.$4, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await LocaleSettings.setLocale(AppLocale.ptBr);
      final vm = _VM(
        WorkspacePresentation(
          mode: entry.$2,
          inspectorOpen: entry.$3,
          selectedBoxId: 'backend',
          boxOrder: const ['backend', 'design', 'review'],
        ),
      );
      final key = GlobalKey();
      final focus = FocusNode();
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
                child: WorkspaceExperience(
                  vm: vm,
                  processMetrics: _Metrics(),
                  terminals: Builder(
                    builder: (context) => ColoredBox(
                      color: context.colors.panel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Backend · Prévia do terminal',
                              style: context.typo.label,
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: AdaptiveTerminalPane(
                                terminal: vm.tabs['api']!.terminal,
                                active: true,
                                focusNode: focus,
                                textStyle: const xterm.TerminalStyle(
                                  fontFamily: 'Preview Mono',
                                ),
                                theme: xterm.TerminalThemes.defaultTheme,
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
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 1);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('review/workspace-layouts/${entry.$1}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        for (final tab in vm.tabs.values) {
          await tab.dispose();
        }
      });
      focus.dispose();
      vm.dispose();
    });
  }
}
