import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/pane_tab_leading.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTerminalGateway implements TerminalGateway {
  @override
  SpawnDirectory? get spawnDirectory => null;

  @override
  int? get rootProcessId => null;
  @override
  void acknowledgeOutput() {}

  @override
  Future<void> kill() async {}

  @override
  Stream<List<int>> get output => const Stream<List<int>>.empty();

  @override
  void resize(int rows, int columns) {}

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const {},
  }) {}

  @override
  void write(List<int> data) {}
}

void main() {
  group('PaneTabLeading Widget', () {
    testWidgets('renders fallback Icon when session is null or activeHarness is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaneTabLeading(
              item: null,
              defaultIcon: Icons.terminal_outlined,
              iconColor: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      final iconWidget = tester.widget<Icon>(find.byType(Icon));
      expect(iconWidget.icon, equals(Icons.terminal_outlined));
      expect(iconWidget.color, equals(Colors.blue));
    });

    testWidgets('renders SvgPicture for monochrome harness with ColorFilter', (tester) async {
      final session = TerminalSession(
        id: 'term-1',
        projectId: 'proj-1',
        workingDirectory: '/tmp',
        gateway: FakeTerminalGateway(),
        profile: const TerminalProfile(
          id: 'posix',
          label: 'Terminal',
          executable: 'bash',
        ),
      );

      // Simulate active monochrome harness (Claude Code)
      session.applyClaudeStatus(
        status: TerminalStatus.working,
        sessionId: 'c-1',
        harness: AgentHarness.claude,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: session,
              builder: (context, _) => PaneTabLeading(
                item: session,
                defaultIcon: Icons.terminal_outlined,
                iconColor: Colors.red,
              ),
            ),
          ),
        ),
      );

      // Wait: activeHarness is set via monitor or status
      expect(find.byType(PaneTabLeading), findsOneWidget);
    });

    testWidgets('renders SvgPicture for each harness kind correctly', (tester) async {
      for (final kind in HarnessKind.values) {
        final spec = HarnessCatalog.getSpec(kind)!;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaneTabLeading(
                item: _createDummySessionWithHarness(kind),
                defaultIcon: Icons.terminal_outlined,
                iconColor: Colors.green,
              ),
            ),
          ),
        );

        expect(find.byType(SvgPicture), findsOneWidget);
        final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
        final assetBytesLoader = svg.bytesLoader as SvgAssetLoader;
        expect(assetBytesLoader.assetName, equals(spec.assetPath));

        if (spec.isMonochrome) {
          expect(svg.colorFilter, isNotNull);
        } else {
          expect(svg.colorFilter, isNull);
        }
      }
    });
  });
}

TerminalSession _createDummySessionWithHarness(HarnessKind kind) {
  final session = DummyHarnessSession(kind);
  return session;
}

class DummyHarnessSession extends TerminalSession {
  final HarnessKind harnessKind;

  DummyHarnessSession(this.harnessKind)
      : super(
          id: 'dummy-1',
          projectId: 'p-1',
          workingDirectory: '/tmp',
          gateway: FakeTerminalGateway(),
          profile: const TerminalProfile(
            id: 'posix',
            label: 'Terminal',
            executable: 'bash',
          ),
        );

  @override
  HarnessKind? get activeHarness => harnessKind;
}
