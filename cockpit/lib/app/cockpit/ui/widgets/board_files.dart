import 'dart:io';
import 'board_export.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import '../../domain/entities/board_document.dart';
import '../../domain/services/board_interchange.dart';
import '../../domain/services/board_editor.dart';

class BoardFiles extends StatelessWidget {
  const BoardFiles({
    super.key,
    required this.document,
    required this.documentPath,
    required this.selection,
    required this.apply,
    required this.onError,
  });
  final BoardDocument document;
  final String documentPath;
  final Set<String> selection;
  final Future<void> Function(BoardEdit) apply;
  final ValueChanged<String> onError;

  Future<void> append(BoardDocument source) async {
    final ids = {for (final id in source.items.keys) id: BoardDocument.newId()};
    final groups = {
      for (final g
          in source.items.values
              .map((i) => i.group)
              .whereType<String>()
              .toSet())
        g: BoardDocument.newId(),
    };
    final items = {
      for (final item in source.items.values)
        ids[item.id]!: BoardItem.read({
          ...item.toJson(),
          'id': ids[item.id],
          if (item.group != null) 'group': groups[item.group],
          if (item.from != null) 'from': ids[item.from],
          if (item.to != null) 'to': ids[item.to],
        }),
    };
    await apply(BoardEdit({for (final id in items.keys) id: null}, items));
  }

  Future<void> run(BuildContext context, String action) async {
    try {
      final tr = context.t.cockpit.gallery.board;
      if (action == 'import') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['drawio', 'xml', 'excalidraw', 'board', 'md'],
        );
        final path = result?.files.single.path;
        if (path == null) return;
        final raw = await File(path).readAsString();
        final source = switch (path.toLowerCase().split('.').last) {
          'drawio' || 'xml' => BoardInterchange.readDrawio(raw),
          'excalidraw' => BoardInterchange.readExcalidraw(raw),
          _ => BoardDocument.parse(raw),
        };

        final native =
            path.toLowerCase().endsWith('.md') ||
            path.toLowerCase().endsWith('.board');
        if (!context.mounted ||
            !await confirm(
              context,
              native ? tr.appendBoard : tr.importWarning,
            )) {
          return;
        }
        await append(source);
        return;
      }
      final format = action.split('/').first;
      if (['xml', 'drawio', 'mmd', 'excalidraw'].contains(format) &&
          !await confirm(context, tr.exportWarning)) {
        return;
      }
      final path = await FilePicker.platform.saveFile(
        fileName: '${p.basenameWithoutExtension(documentPath)}.$format',
        type: FileType.custom,
        allowedExtensions: [format],
      );
      if (path == null) return;
      final file = File(path);
      final selected = action.endsWith('/selected') ? selection : null;
      if (format == 'png' || format == 'pdf') {
        final bytes = format == 'pdf'
            ? await boardPdf(document, selected: selected)
            : await boardPng(document, selected: selected);
        await file.writeAsBytes(bytes);
      } else {
        final text = switch (format) {
          'svg' => boardSvgExport(document, selected: selected),
          'html' => boardHtml(document, selected: selected),
          'md' => document.encode(),
          'mmd' => BoardInterchange.mermaid(document),
          'xml' || 'drawio' => BoardInterchange.drawio(document),
          'excalidraw' => BoardInterchange.excalidraw(document),
          _ => throw FormatException('Unknown format: $format'),
        };
        await file.writeAsString(text);
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<bool> confirm(BuildContext context, String message) async {
    final tr = context.t.cockpit.gallery.board;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr.discard),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr.apply),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> openMenu(BuildContext context) async {
    final tr = context.t.cockpit.gallery.board;
    final scope = await showAppMenu<String?>(
      context,
      items: [
        AppMenuItem(
          value: 'document',
          label: tr.exportDocument,
          icon: Icons.description_outlined,
        ),
        AppMenuItem(
          value: 'selection',
          label: tr.exportSelection,
          icon: Icons.select_all,
          enabled: selection.isNotEmpty,
        ),
        const AppMenuItem<String>.divider(),
        AppMenuItem(
          value: 'import',
          label: tr.openFile,
          icon: Icons.file_open_outlined,
        ),
      ],
    );
    if (scope == null || !context.mounted) return;
    if (scope == 'document' || scope == 'selection') {
      final selected = scope == 'selection';
      final format = await showAppMenu<String?>(
        context,
        items: [
          for (final format in [
            'png',
            'pdf',
            'html',
            'svg',
            if (!selected) ...['xml', 'md', 'drawio', 'excalidraw', 'mmd'],
          ])
            AppMenuItem(
              value: format,
              label: switch (format) {
                'md' => 'Markdown (.md)',
                'drawio' => 'draw.io',
                'excalidraw' => 'Excalidraw',
                'mmd' => 'Mermaid (.mmd)',
                _ => format.toUpperCase(),
              },
            ),
        ],
      );
      if (format != null && context.mounted) {
        await run(context, selected ? '$format/selected' : format);
      }
    } else {
      await run(context, scope);
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.t.cockpit.gallery.board.fileActions,
    child: TextButton.icon(
      icon: const Icon(Icons.import_export, size: 18),
      label: Text(context.t.cockpit.gallery.board.exportFile),
      onPressed: () => openMenu(context),
    ),
  );
}
