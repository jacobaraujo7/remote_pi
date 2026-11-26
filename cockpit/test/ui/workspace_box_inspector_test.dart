import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_box_inspector.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_box_list.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const _box = GraphBox(
  id: 'box',
  title: 'Shell',
  role: '',
  harness: '',
  model: '',
  position: Offset.zero,
);

class _InspectorVM implements CockpitViewModel {
  int saved = 0;
  int started = 0;
  String? name;
  String? role;
  @override
  List<GraphBox> get graphBoxes => [_box];
  @override
  List<GraphLink> get graphLinks => [];
  @override
  bool get selectedRemoteDisconnected => false;
  @override
  TerminalSession? session(String id) => null;
  @override
  Result<String, String> configureGraphBox({
    required String boxId,
    String? title,
    required String role,
    required String harness,
    required String model,
  }) {
    saved++;
    name = title;
    this.role = role;
    return Success(boxId);
  }

  @override
  Result<String, String> relaunchGraphBox(String id, {String? workspaceId}) {
    started++;
    return Success(id);
  }

  @override
  Future<Result<String, String>> openBoxShell(
    String id, {
    String? workspaceId,
  }) async {
    started++;
    return Success(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 400.0]) {
    testWidgets(
      'agent role is a preview until explicitly accepted and saved / $width px',
      (tester) async {
        final vm = _InspectorVM();
        var asked = 0;
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          TranslationProvider(
            child: ShadcnApp(
              theme: buildTheme(brightness: Brightness.dark),
              home: Scaffold(
                child: WorkspaceBoxInspector(
                  vm: vm,
                  box: _box,
                  entry: const WorkspaceBoxEntry(
                    box: _box,
                    status: WorkspaceBoxStatus.idle,
                    tool: 'Codex',
                  ),
                  onClose: () {},
                  onSuggestRole: () async {
                    asked++;
                    return const Success('Revisar contratos da API');
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final roleField = find.byType(TextField).at(1);
        final roleHelp = find.text(t.orchestration.roleMissing);
        final askButton = find.ancestor(
          of: find.text(t.orchestration.askRole),
          matching: find.byType(OutlineButton),
        );
        expect(
          tester.getRect(roleHelp).top,
          greaterThan(tester.getRect(roleField).bottom),
        );
        expect(
          tester.getRect(askButton).top,
          greaterThan(tester.getRect(roleHelp).bottom),
        );
        await tester.ensureVisible(find.text(t.orchestration.askRole));
        await tester.tap(find.text(t.orchestration.askRole));
        await tester.pumpAndSettle();
        expect(asked, 1);
        expect(vm.saved, 0);
        expect(vm.started, 0);
        expect(find.text('Revisar contratos da API'), findsOneWidget);
        final acceptButton = find.ancestor(
          of: find.text(t.orchestration.useSuggestion),
          matching: find.byType(OutlineButton),
        );
        expect(
          tester.getRect(acceptButton).top,
          greaterThan(
            tester.getRect(find.text('Revisar contratos da API')).bottom,
          ),
        );
        await tester.ensureVisible(find.text(t.orchestration.useSuggestion));
        await tester.tap(find.text(t.orchestration.useSuggestion));
        await tester.pumpAndSettle();
        expect(vm.saved, 0);
        await tester.ensureVisible(find.text(t.workspaceView.save));
        await tester.tap(find.text(t.workspaceView.save));
        await tester.pumpAndSettle();
        expect(vm.saved, 1);
        expect(vm.role, 'Revisar contratos da API');
        expect(vm.started, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'inspector saves optional context without starting a tool / $brightness',
      (tester) async {
        final vm = _InspectorVM();
        var closed = 0;
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          TranslationProvider(
            child: ShadcnApp(
              theme: buildTheme(brightness: brightness),
              home: Scaffold(
                child: WorkspaceBoxInspector(
                  vm: vm,
                  box: _box,
                  entry: const WorkspaceBoxEntry(
                    box: _box,
                    status: WorkspaceBoxStatus.closed,
                    tool: '',
                  ),
                  onClose: () => closed++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'New name');
        await tester.ensureVisible(find.text(t.workspaceView.save));
        await tester.tap(find.text(t.workspaceView.save));
        await tester.pumpAndSettle();
        expect(vm.saved, 1);
        expect(vm.name, 'New name');
        expect(vm.role, '');
        expect(vm.started, 0);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(TextField).first);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, 1);
      },
    );
  }
}
