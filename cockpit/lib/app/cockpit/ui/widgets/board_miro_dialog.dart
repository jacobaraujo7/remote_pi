import 'package:flutter/material.dart';
import 'package:cockpit/i18n/strings.g.dart';
import '../../domain/services/board_miro.dart';

Future<BoardMiro?> miroConnection(BuildContext context) async {
  var board = '', token = '';
  final tr = context.t.cockpit.gallery.board;
  return showDialog<BoardMiro>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Miro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Board ID'),
              onChanged: (v) => update(() => board = v),
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Access token'),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (v) => update(() => token = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr.discard),
          ),
          TextButton(
            onPressed: board.trim().isEmpty || token.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, BoardMiro(token.trim(), board)),
            child: Text(tr.apply),
          ),
        ],
      ),
    ),
  );
}
