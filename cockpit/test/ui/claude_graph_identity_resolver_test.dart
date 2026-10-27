import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/ui/services/claude_graph_identity_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recovers only the current session from a historical ListAgents result',
    () async {
      final dir = await Directory.systemTemp.createTemp('graph-identity-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}session.jsonl');
      await file.writeAsString(
        [
          jsonEncode({
            'message': {
              'content': [
                {'type': 'tool_use', 'name': 'ListAgents', 'id': 'tool-1'},
              ],
            },
          }),
          jsonEncode({
            'message': {
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 'tool-1',
                  'content':
                      'This session is massivo-42 [active]\nOther sessions: massivo-99',
                },
              ],
            },
          }),
          jsonEncode({
            'message': {
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 'unrelated',
                  'content': 'This session is forged-1 [active]',
                },
              ],
            },
          }),
          'not json',
        ].join('\n'),
      );

      final aliases = await const ClaudeGraphIdentityResolver().readAliases(
        file.path,
      );
      expect(aliases, {'massivo-42'});
    },
  );
}
