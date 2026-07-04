import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_tree_panel.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('FileTreePanel selection', () {
    testWidgets(
      'clicking on a file triggers onSelectFile and onTapFile callbacks',
      (tester) async {
        String? selectedFile;
        String? tappedFile;

        await tester.pumpWidget(
          ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: FileTreePanel(
                rootPath: '/workspace',
                revision: 1,
                listChildren: (path) async {
                  if (path == '/workspace') {
                    return const [
                      FileNode(
                        name: 'file1.txt',
                        path: '/workspace/file1.txt',
                        isDirectory: false,
                      ),
                    ];
                  }
                  return const [];
                },
                gitStatusOf: (path) => null,
                onOpenFile: (path) {},
                onTapFile: (path) {
                  tappedFile = path;
                },
                onSelectFile: (path) {
                  selectedFile = path;
                },
                onOpenDiff: (path) {},
                isGitRepo: false,
                changedPaths: const [],
                onOpenWith: (path) {},
                onCreateInFolder: (sub, terminal) {},
                onCreate: (parentDir, name, isFolder) async =>
                    const Success(null),
                onRename: (path, newName) async => const Success(null),
                onDelete: (path) async => const Success(null),
              ),
            ),
          ),
        );

        // Wait for lazy-loading to complete and rebuild
        await tester.pumpAndSettle();

        // Find the file node in the tree
        final fileFinder = find.text('file1.txt');
        expect(fileFinder, findsOneWidget);

        // Click on the file
        await tester.tap(fileFinder);
        await tester.pumpAndSettle();

        // Verify that callbacks were invoked with the correct file path
        expect(selectedFile, '/workspace/file1.txt');
        expect(tappedFile, '/workspace/file1.txt');
      },
    );
  });
}
