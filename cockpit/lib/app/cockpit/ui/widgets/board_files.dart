import 'dart:io';
import 'board_miro_dialog.dart';
import 'board_export.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cockpit/i18n/strings.g.dart';
import '../../domain/entities/board_document.dart';
import '../../domain/services/board_interchange.dart';
import '../../domain/services/board_editor.dart';
import '../../domain/services/board_svg.dart';

class BoardFiles extends StatelessWidget {
  const BoardFiles({
    super.key,
    required this.document,
    required this.selection,
    required this.apply,
    required this.onError,
  });
  final BoardDocument document;
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
      if (action.startsWith('miro/')) {
        final miro = await miroConnection(context);
        if (miro == null || !context.mounted) return;
        try {
          if (action == 'miro/export') {
            final omitted = document.items.values
                .where(
                  (i) =>
                      i.kind == BoardKind.stroke || i.kind == BoardKind.mermaid,
                )
                .map((i) => i.kind.name)
                .toSet();
            if (await confirm(
              context,
              'Miro · ${tr.exportWarning}\n${omitted.join(', ')}',
            )) {
              await miro.publish(document);
            }
          } else {
            final incoming = await miro.read();
            if (!context.mounted ||
                !await confirm(
                  context,
                  'Miro · ${tr.importWarning}\n${incoming.skipped.join(', ')}',
                )) {
              return;
            }
            await append(incoming.board);
          }
        } finally {
          miro.close();
        }
        return;
      }
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
        fileName: 'diagram.$format',
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
          'svg' => boardSvg(document, selected: selected),
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

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.gallery.board;
    return PopupMenuButton<String>(
      tooltip: tr.fileActions,
      icon: const Icon(Icons.import_export),
      onSelected: (v) => run(context, v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'import',
          child: Text(
            '${tr.openFile} · Board / Markdown / XML / draw.io / Excalidraw',
          ),
        ),
        for (final format in [
          'png',
          'pdf',
          'html',
          'xml',
          'md',
          'svg',
          'drawio',
          'excalidraw',
          'mmd',
        ])
          PopupMenuItem(
            value: format,
            child: Text('${tr.exportFile} · $format'),
          ),
        PopupMenuItem(
          value: 'miro/import',
          child: Text('${tr.openFile} · Miro'),
        ),
        PopupMenuItem(
          value: 'miro/export',
          child: Text('${tr.exportFile} · Miro'),
        ),
        if (selection.isNotEmpty)
          for (final format in ['png', 'pdf', 'html', 'svg'])
            PopupMenuItem(
              value: '$format/selected',
              child: Text('${tr.select} · $format'),
            ),
      ],
    );
  }
}
