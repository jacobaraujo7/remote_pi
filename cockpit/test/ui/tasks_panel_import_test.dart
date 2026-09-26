import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/task_discovery_impl.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/tasks_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/tasks_panel.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../tasks/tasks_workspace_import_test.dart'
    show IdleTaskRunner, taskConfig;

class _Root extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const settings = AppSettings(interfaceFont: 'Ahem', codeFont: 'Ahem');
    final tokens = buildTokens(brightness: Brightness.dark, settings: settings);
    return CockpitTheme(
      colors: tokens.colors,
      typo: tokens.typo,
      syntax: tokens.syntax,
      terminal: tokens.terminal,
      child: ShadcnApp.router(
        theme: buildTheme(brightness: Brightness.dark, settings: settings),
        routerConfig: ModularApp.routerConfigOf(context),
      ),
    );
  }
}

void main() {
  for (final keyboard in [false, true]) {
    testWidgets('imports using ${keyboard ? 'keyboard' : 'mouse'} link', (
      tester,
    ) async {
      late Directory temp;
      late TasksViewModel vm;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('tasks-panel-import-');
        final source = File('${temp.path}/source/.cockpit/tasks.json');
        await source.parent.create(recursive: true);
        await source.writeAsString(taskConfig);
        await Directory('${temp.path}/worktree').create();
        vm = TasksViewModel(TaskDiscoveryImpl(const []), IdleTaskRunner());
        await vm.loadFor(
          '${temp.path}/worktree',
          sourceWorkspaceCwd: '${temp.path}/source',
        );
      });
      final feature = createModule(
        path: '/',
        register: (c) => c.route(
          '/',
          child: (_, _) => Scaffold(
            child: SizedBox(
              width: 320,
              child: TasksPanel(
                cwd: '${temp.path}/worktree',
                sourceWorkspaceCwd: '${temp.path}/source',
                listHeight: 200,
                onResizeDelta: (_) {},
                onResizeEnd: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        TranslationProvider(
          child: ModularApp(
            module: createModule(register: (c) => c.module(feature)),
            provide: (s) => s.addChangeNotifier<TasksViewModel>(() => vm),
            child: _Root(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinkButton), findsOneWidget);
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(LinkButton),
          matching: find.byType(Text),
        ),
      );
      expect(text.style?.decoration, TextDecoration.underline);

      await tester.runAsync(() async {
        final imported = Completer<void>();
        void onLoaded() {
          if (vm.tasks.isNotEmpty && !imported.isCompleted) imported.complete();
        }

        vm.addListener(onLoaded);
        if (keyboard) {
          // Traverse the header refresh action before reaching the import link.
          for (var i = 0; i < 5; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            final focus = FocusManager.instance.primaryFocus?.context;
            if (focus != null &&
                focus.findAncestorWidgetOfExactType<LinkButton>() != null) {
              break;
            }
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.byType(LinkButton));
        }
        await imported.future.timeout(const Duration(seconds: 5));
        vm.removeListener(onLoaded);
      });
      await tester.pumpAndSettle();
      expect(vm.tasks.single.label, 'API');
      expect(find.byType(LinkButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => temp.delete(recursive: true));
    });
  }
}
