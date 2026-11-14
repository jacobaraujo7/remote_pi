import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/ui/widgets/board_files.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _SavePicker extends FilePicker {
  _SavePicker(this.directory);
  final Directory directory;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    expect(type, FileType.custom);
    expect(fileName, 'order.${allowedExtensions!.single}');
    return '${directory.path}/$fileName';
  }
}

void main() {
  Future<void> tick(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> mount(
    WidgetTester tester,
    Brightness brightness,
    Set<String> selected,
  ) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          popoverHandler: const AppPopoverOverlayHandler(),
          theme: buildTheme(
            brightness: brightness,
          ).copyWith(platform: () => TargetPlatform.windows),
          home: Scaffold(
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                SizedBox(
                  width: 280,
                  height: 320,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: BoardFiles(
                      documentPath: 'workspace/order.board',
                      document: BoardDocument([
                        const BoardItem('a', BoardKind.process, 10, 10),
                      ]),
                      selection: selected,
                      apply: (_) async {},
                      onError: (error) => fail(error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'narrow panel offers export scope before formats and selection by keyboard',
    (tester) async {
      await mount(tester, Brightness.dark, {'a'});
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tick(tester);
      expect(find.text('Export entire document'), findsOneWidget);
      expect(find.text('PNG'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tick(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tick(tester);
      expect(find.text('PNG'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('HTML'), findsOneWidget);
      expect(find.text('SVG'), findsOneWidget);
      expect(find.text('XML'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tick(tester);
      expect(find.text('PNG'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tick(tester);
      expect(find.text('Export entire document'), findsOneWidget);
    },
  );

  testWidgets(
    'light theme exposes document formats and disables empty selection',
    (tester) async {
      await mount(tester, Brightness.light, {});
      await tester.tap(find.byTooltip('Import or export'));
      await tick(tester);
      expect(
        tester
            .widget<MenuButton>(
              find.widgetWithText(MenuButton, 'Export selection'),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Export entire document'));
      await tick(tester);
      expect(find.text('XML'), findsOneWidget);
      expect(find.text('Markdown (.md)'), findsOneWidget);
    },
  );

  testWidgets(
    'export menu saves the chosen local format using the board name',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('canvas-export-');
      addTearDown(() => directory.deleteSync(recursive: true));
      FilePicker.platform = _SavePicker(directory);
      await mount(tester, Brightness.dark, {'a'});
      for (final format in [
        'PNG',
        'PDF',
        'XML',
        'HTML',
        'SVG',
        'Markdown (.md)',
        'draw.io',
        'Excalidraw',
        'Mermaid (.mmd)',
      ]) {
        await tester.tap(find.text('Export'));
        await tick(tester);
        await tester.tap(find.text('Export entire document'));
        await tick(tester);
        await tester.ensureVisible(find.text(format));
        await tester.tap(find.text(format));
        await tick(tester);
        if ([
          'XML',
          'draw.io',
          'Excalidraw',
          'Mermaid (.mmd)',
        ].contains(format)) {
          await tester.tap(find.text('Apply'));
          await tick(tester);
        }
        final extension = switch (format) {
          'Markdown (.md)' => 'md',
          'draw.io' => 'drawio',
          'Mermaid (.mmd)' => 'mmd',
          _ => format.toLowerCase(),
        };
        final file = File('${directory.path}/order.$extension');
        for (var frame = 0; frame < 150; frame++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (file.existsSync() && file.lengthSync() > 0) break;
        }
        await tick(tester);
        expect(file.existsSync(), isTrue, reason: format);
        expect(file.lengthSync(), greaterThan(0), reason: format);
      }
    },
  );
}
