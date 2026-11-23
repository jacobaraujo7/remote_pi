import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_cache.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_tree_panel.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  setUp(() => DotnetSolutionCache.instance.clear());
  tearDown(() => DotnetSolutionCache.instance.clear());

  testWidgets('hides the solution toggle when the workspace has no solution', (
    tester,
  ) async {
    await _pump(
      tester,
      root: '/plain',
      listChildren: (_) async => const [
        FileNode(
          name: 'readme.txt',
          path: '/plain/readme.txt',
          isDirectory: false,
        ),
      ],
    );
    expect(find.byKey(const ValueKey('solution-mode-toggle')), findsNothing);
    expect(find.text('readme.txt'), findsOneWidget);
  });

  testWidgets('loads the solution once and keeps the file tree usable', (
    tester,
  ) async {
    var loads = 0;
    await _pump(
      tester,
      root: '/dotnet',
      listChildren: (path) async {
        if (path == '/dotnet') {
          return const [
            FileNode(
              name: 'app.sln',
              path: '/dotnet/app.sln',
              isDirectory: false,
            ),
            FileNode(
              name: 'readme.txt',
              path: '/dotnet/readme.txt',
              isDirectory: false,
            ),
          ];
        }
        return const [];
      },
      load: (path) async {
        loads++;
        return _snapshot;
      },
    );

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Api'), findsOneWidget);
    expect(loads, 1);

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('readme.txt'), findsOneWidget);
    expect(loads, 1);

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Api'), findsOneWidget);
    expect(loads, 1);
  });

  testWidgets('a failed solution load leaves the file tree usable', (
    tester,
  ) async {
    await _pump(
      tester,
      root: '/broken',
      listChildren: (path) async {
        if (path == '/broken') {
          return const [
            FileNode(
              name: 'app.sln',
              path: '/broken/app.sln',
              isDirectory: false,
            ),
            FileNode(
              name: 'readme.txt',
              path: '/broken/readme.txt',
              isDirectory: false,
            ),
          ];
        }
        return const [];
      },
      load: (_) async => null,
    );

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('solution-load-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('readme.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('solution-load-error')), findsNothing);
  });

  testWidgets('opening a solution item keeps the solution view', (
    tester,
  ) async {
    var revealGen = 0;
    String? revealPath;
    String? selectedPath;
    late StateSetter rebuild;

    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return FileTreePanel(
                  rootPath: '/dotnet',
                  revision: 1,
                  selectedPath: selectedPath,
                  revealPath: revealPath,
                  revealGen: revealGen,
                  listChildren: (path) async {
                    if (path == '/dotnet') {
                      return const [
                        FileNode(
                          name: 'app.sln',
                          path: '/dotnet/app.sln',
                          isDirectory: false,
                        ),
                        FileNode(
                          name: 'readme.txt',
                          path: '/dotnet/readme.txt',
                          isDirectory: false,
                        ),
                      ];
                    }
                    return const [];
                  },
                  loadDotnetSolution: (_) async => _snapshot,
                  gitStatusOf: (_) => null,
                  onTapFile: (path) {
                    rebuild(() {
                      selectedPath = path;
                      revealPath = path;
                      revealGen++;
                    });
                  },
                  onOpenFile: (path) {
                    rebuild(() {
                      selectedPath = path;
                      revealPath = path;
                      revealGen++;
                    });
                  },
                  onOpenDiff: (_) {},
                  isGitRepo: false,
                  changedPaths: const [],
                  onOpenWith: (_) {},
                  onCreateInFolder: (_, {command}) {},
                  onCreate: (_, _, _) async => const Success(null),
                  onRename: (_, _) async => const Success(null),
                  onDelete: (_) async => const Success(null),
                  onMove: (_, _) async => const Success(null),
                  onCopy: (_) {},
                  onCut: (_) {},
                  onPaste: (_) async => const Success(null),
                  canPaste: false,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Program.cs'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);

    await tester.tap(find.text('Program.cs'));
    await tester.pumpAndSettle();

    expect(selectedPath, '/dotnet/Program.cs');
    expect(revealGen, 1);
    expect(find.text('Program.cs'), findsOneWidget);
    expect(find.text('Api'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);
  });

  testWidgets('an expanded project lists folders before files', (tester) async {
    await _pump(
      tester,
      root: '/dotnet',
      listChildren: (path) async {
        if (path == '/dotnet') {
          return const [
            FileNode(
              name: 'app.sln',
              path: '/dotnet/app.sln',
              isDirectory: false,
            ),
          ];
        }
        if (path == '/dotnet/Api') {
          return const [
            FileNode(
              name: 'zeta.cs',
              path: '/dotnet/Api/zeta.cs',
              isDirectory: false,
            ),
            FileNode(
              name: 'Config',
              path: '/dotnet/Api/Config',
              isDirectory: true,
            ),
            FileNode(
              name: 'Program.cs',
              path: '/dotnet/Api/Program.cs',
              isDirectory: false,
            ),
            FileNode(
              name: 'Factories',
              path: '/dotnet/Api/Factories',
              isDirectory: true,
            ),
            FileNode(name: 'bin', path: '/dotnet/Api/bin', isDirectory: true),
          ];
        }
        return const [];
      },
      load: (_) async => _orderedProject,
    );

    await tester.tap(find.byKey(const ValueKey('solution-mode-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Api'));
    await tester.pumpAndSettle();

    expect(find.text('Dependencies'), findsNothing);
    expect(find.text('bin'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Config')).dy,
      lessThan(_top(tester, 'Factories')),
    );
    expect(
      tester.getTopLeft(find.text('Factories')).dy,
      lessThan(_top(tester, 'Program.cs')),
    );
    expect(
      tester.getTopLeft(find.text('Program.cs')).dy,
      lessThan(_top(tester, 'zeta.cs')),
    );
  });
}

double _top(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label)).dy;

Future<void> _pump(
  WidgetTester tester, {
  required String root,
  required Future<List<FileNode>> Function(String path) listChildren,
  Future<DotnetSolutionSnapshot?> Function(String path)? load,
}) async {
  LocaleSettings.setLocale(AppLocale.en);
  await tester.pumpWidget(
    TranslationProvider(
      child: ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Scaffold(
          child: FileTreePanel(
            rootPath: root,
            revision: 1,
            listChildren: listChildren,
            loadDotnetSolution: load,
            gitStatusOf: (_) => null,
            onOpenFile: (_) {},
            onOpenDiff: (_) {},
            isGitRepo: false,
            changedPaths: const [],
            onOpenWith: (_) {},
            onCreateInFolder: (_, {command}) {},
            onCreate: (_, _, _) async => const Success(null),
            onRename: (_, _) async => const Success(null),
            onDelete: (_) async => const Success(null),
            onMove: (_, _) async => const Success(null),
            onCopy: (_) {},
            onCut: (_) {},
            onPaste: (_) async => const Success(null),
            canPaste: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _orderedProject = DotnetSolutionSnapshot(
  path: '/dotnet/app.sln',
  name: 'Demo',
  fingerprint: 'fp',
  projectPaths: const [],
  root: DotnetNode(
    id: 'sln:/dotnet/app.sln',
    kind: DotnetNodeKind.solution,
    name: 'Demo',
    projectCount: 1,
    children: [
      DotnetNode(
        id: 'proj:/dotnet/Api/Api.csproj',
        kind: DotnetNodeKind.project,
        name: 'Api',
        path: '/dotnet/Api/Api.csproj',
        directory: '/dotnet/Api',
      ),
    ],
  ),
);

final _snapshot = DotnetSolutionSnapshot(
  path: '/dotnet/app.sln',
  name: 'Demo',
  fingerprint: 'fp',
  projectPaths: const [],
  root: DotnetNode(
    id: 'sln:/dotnet/app.sln',
    kind: DotnetNodeKind.solution,
    name: 'Demo',
    projectCount: 1,
    children: [
      DotnetNode(
        id: 'proj:/dotnet/Api/Api.csproj',
        kind: DotnetNodeKind.project,
        name: 'Api',
        path: '/dotnet/Api/Api.csproj',
        directory: '/dotnet/Api',
      ),
      DotnetNode(
        id: 'file:/dotnet/Program.cs',
        kind: DotnetNodeKind.file,
        name: 'Program.cs',
        path: '/dotnet/Program.cs',
      ),
    ],
  ),
);
