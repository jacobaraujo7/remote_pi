import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/actions/tab_actions.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _NoopGateway implements TerminalGateway {
  @override
  SpawnDirectory? get spawnDirectory => null;

  @override
  int? get rootProcessId => null;

  @override
  int? get wslProcessId => null;

  final _out = StreamController<List<int>>();

  @override
  Stream<List<int>> get output => _out.stream;

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {}

  @override
  void write(List<int> data) {}

  @override
  void resize(int rows, int columns) {}

  @override
  void acknowledgeOutput() {}

  @override
  Future<void> kill() async {
    await _out.close();
  }
}

class _FakeSettingsStore implements SettingsStore {
  const _FakeSettingsStore();

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

/// O X do titulo e o ⌘W passam pela MESMA regra ([requestCloseTab]): um
/// caminho que esquecesse o dialogo descartaria trabalho em silencio.
void main() {
  FileViewerSession session({required bool dirty}) {
    final s = FileViewerSession(
      id: 'v1',
      projectId: 'p1',
      path: '/repo/a.dart',
      view: const FileViewText('x'),
    );
    if (dirty) s.setDirty(true);
    return s;
  }

  TerminalSession terminalSession() {
    return TerminalSession(
      id: 't1',
      projectId: 'p1',
      workingDirectory: '/tmp',
      gateway: _NoopGateway(),
      profile: const TerminalProfile(
        id: 'login-shell',
        label: 'sh',
        executable: '/bin/sh',
      ),
    );
  }

  /// Monta a arvore e devolve um contexto vivo abaixo do TranslationProvider.
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('aba limpa fecha direto, sem perguntar', (tester) async {
    final ctx = await pump(tester);
    var closed = 0;

    final ok = await requestCloseTab(
      ctx,
      session(dirty: false),
      () => closed++,
    );
    await tester.pumpAndSettle();

    expect(ok, isTrue);
    expect(closed, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('aba suja pergunta e so fecha com a resposta', (tester) async {
    final ctx = await pump(tester);
    var closed = 0;

    final pending = requestCloseTab(ctx, session(dirty: true), () => closed++);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(closed, 0, reason: 'nao pode fechar antes da resposta');

    // "Descartar" fecha sem salvar.
    await tester.tap(find.text(ctx.t.cockpit.confirmDialog.dontSave));
    await tester.pumpAndSettle();

    expect(await pending, isTrue);
    expect(closed, 1);
  });

  testWidgets('cancelar mantem a aba aberta', (tester) async {
    final ctx = await pump(tester);
    var closed = 0;

    final pending = requestCloseTab(ctx, session(dirty: true), () => closed++);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ctx.t.common.cancel));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    expect(closed, 0);
  });

  testWidgets('terminal pergunta antes de fechar quando confirmCloseTerminal e true', (tester) async {
    final ctx = await pump(tester);
    final controller = SettingsController(const _FakeSettingsStore());
    var closed = 0;

    final pending = requestCloseTab(
      ctx,
      terminalSession(),
      () => closed++,
      settingsController: controller,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(closed, 0, reason: 'nao pode fechar antes da confirmacao');

    await tester.tap(find.text(ctx.t.cockpit.confirmDialog.close));
    await tester.pumpAndSettle();

    expect(await pending, isTrue);
    expect(closed, 1);
  });

  testWidgets('cancelar dialogo do terminal mantem aba aberta', (tester) async {
    final ctx = await pump(tester);
    final controller = SettingsController(const _FakeSettingsStore());
    var closed = 0;

    final pending = requestCloseTab(
      ctx,
      terminalSession(),
      () => closed++,
      settingsController: controller,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(ctx.t.common.cancel));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    expect(closed, 0);
  });

  testWidgets('marcar nao perguntar novamente desativa confirmCloseTerminal', (tester) async {
    final ctx = await pump(tester);
    final controller = SettingsController(const _FakeSettingsStore());
    var closed = 0;

    final pending = requestCloseTab(
      ctx,
      terminalSession(),
      () => closed++,
      settingsController: controller,
    );
    await tester.pumpAndSettle();

    // Clica no checkbox "Nao perguntar novamente"
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Confirma o fechamento
    await tester.tap(find.text(ctx.t.cockpit.confirmDialog.close));
    await tester.pumpAndSettle();

    expect(await pending, isTrue);
    expect(closed, 1);
    expect(controller.settings.confirmCloseTerminal, isFalse);

    // Segundo fechamento agora fecha direto sem abrir modal
    var closedAgain = 0;
    final ok = await requestCloseTab(
      ctx,
      terminalSession(),
      () => closedAgain++,
      settingsController: controller,
    );
    await tester.pumpAndSettle();

    expect(ok, isTrue);
    expect(closedAgain, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('terminalOwnerShortcuts mapeia atalhos de novo terminal e fechar aba', () {
    var newTerminalCalls = 0;
    var closeTabCalls = 0;

    final shortcuts = terminalOwnerShortcuts(
      onNewTerminal: () => newTerminalCalls++,
      onCloseTab: () => closeTabCalls++,
    );

    // Ctrl+T e Cmd+T disparam onNewTerminal
    shortcuts[const SingleActivator(LogicalKeyboardKey.keyT, control: true)]?.call();
    expect(newTerminalCalls, 1);

    shortcuts[const SingleActivator(LogicalKeyboardKey.keyT, meta: true)]?.call();
    expect(newTerminalCalls, 2);

    // Ctrl+W, Cmd+W, Ctrl+Shift+W e Cmd+Shift+W disparam onCloseTab
    shortcuts[const SingleActivator(LogicalKeyboardKey.keyW, control: true)]?.call();
    expect(closeTabCalls, 1);

    shortcuts[const SingleActivator(LogicalKeyboardKey.keyW, meta: true)]?.call();
    expect(closeTabCalls, 2);

    shortcuts[const SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true)]?.call();
    expect(closeTabCalls, 3);

    shortcuts[const SingleActivator(LogicalKeyboardKey.keyW, meta: true, shift: true)]?.call();
    expect(closeTabCalls, 4);
  });
}
