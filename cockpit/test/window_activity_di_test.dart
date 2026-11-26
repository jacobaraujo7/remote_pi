import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context));
}

void main() {
  testWidgets(
    'feature instance resolves into route-scoped GitController with identity',
    (tester) async {
      final activity = WindowActivityController();
      WindowActivityController? controllerActivity;
      final feature = createModule(
        path: '/',
        register: (c) => c
          ..addInstance<GitStatusReader>(_FakeGitStatusReader())
          ..addInstance<GitCommandRunner>(_FakeGitCommandRunner())
          ..route(
            '/',
            provide: (s) => s
              ..addChangeNotifier<GitController>((
                GitStatusReader reader,
                GitCommandRunner runner,
              ) {
                controllerActivity = activity;
                return GitController(reader, runner, activity);
              }),
            child: (context, state) => Builder(
              builder: (context) {
                final git = context.watch<GitController>();
                return Text(
                  'git:${git.revision};same:${identical(controllerActivity, activity)}',
                );
              },
            ),
          ),
      );
      final app = createModule(register: (c) => c.module(feature));

      await tester.pumpWidget(
        ModularApp(
          module: app,
          provide: (services) => services
              .addChangeNotifier<WindowActivityController>(() => activity),
          child: const _Root(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('git:0;same:true'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeGitStatusReader implements GitStatusReader {
  @override
  Future<GitInfo?> read(String path) async => null;
}

class _FakeGitCommandRunner implements GitCommandRunner {
  Never _unused() => throw UnimplementedError();

  @override
  GitMergeOutcome mergeIntoParent(
    String parentPath,
    String worktreePath,
    String worktreeBranch,
  ) => _unused();

  @override
  GitRun run(String repoPath, List<String> args) => _unused();

  @override
  GitRun syncPullPush(String repoPath) => _unused();
  @override
  GitRun clone(String url, String targetPath) => _unused();
}
