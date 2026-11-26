import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_presentation.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_restore_state.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> snapshot() => {
  'ownershipVersion': 2,
  'document': OrchestrationDocument(
    boxes: [
      const OrchestrationBox(
        box: GraphBox(
          id: 'box',
          title: 'API',
          role: '',
          harness: '',
          model: '',
          position: Offset.zero,
        ),
      ),
    ],
  ).encode(),
  'bindings': {'box': 'owned'},
  'sessions': {
    'owned': {
      'type': 'terminal',
      'cwd': '/worktree/src',
      'harness': 'codex',
      'claude_sid': 'local-conversation',
      'transcriptPath': '/owned/conversation.jsonl',
      'engine': 'ghostty',
    },
  },
  'multiplexer': {
    'tree': {
      'k': 'leaf',
      'id': 'app-pane-1',
      'tabs': ['owned'],
      'active': 'owned',
    },
    'focusedPaneId': 'app-pane-1',
    'keyboardTabId': 'owned',
  },
  'presentation': {
    'mode': 'graph',
    'selectedBoxId': 'box',
    'graphTerminalFraction': .42,
  },
};
OrchestrationRestoreState decode(Map<String, dynamic> raw) =>
    OrchestrationRestoreState.parse(
      raw,
      instanceId: 'app',
      projectId: 'worktree',
    );

void main() {
  test(
    'validates local resume metadata and separate presentation before spawning',
    () {
      final restored = decode(snapshot());
      expect(restored.bindings, {'box': 'owned'});
      expect(restored.sessions['owned']!['claude_sid'], 'local-conversation');
      expect(
        restored.sessions['owned']!['transcriptPath'],
        '/owned/conversation.jsonl',
      );
      expect(restored.presentation.mode, OrchestrationViewMode.graph);
      expect(restored.presentation.graphTerminalFraction, .42);
      expect(
        restored.document!.encode(),
        isNot(contains('local-conversation')),
      );
      expect(restored.document!.encode(), isNot(contains('owned')));
    },
  );
  test(
    'portable files and old global bindings cannot become local process descriptors',
    () {
      expect(
        () => decode({'version': 1, 'boxes': [], 'links': []}),
        throwsFormatException,
      );
      final old = snapshot()..remove('ownershipVersion');
      expect(() => decode(old), throwsFormatException);
    },
  );
  test(
    'rejects an outside binding, outside tree tab and nonterminal child',
    () {
      final binding = snapshot()..['bindings'] = {'box': 'outside'};
      expect(() => decode(binding), throwsFormatException);
      final tree = snapshot();
      (tree['multiplexer'] as Map)['tree'] = {
        'k': 'leaf',
        'id': 'p',
        'tabs': ['outside'],
        'active': 'outside',
      };
      expect(() => decode(tree), throwsFormatException);
      final editor = snapshot()
        ..['sessions'] = {
          'owned': {'type': 'viewer'},
        };
      expect(() => decode(editor), throwsFormatException);
    },
  );
  test(
    'rejects orphaned and duplicate native bindings before any side effect',
    () {
      final orphan = snapshot()..['bindings'] = <String, String>{};
      expect(() => decode(orphan), throwsFormatException);
      final duplicate = snapshot();
      duplicate['document'] = OrchestrationDocument(
        boxes: [
          for (final id in ['box', 'second'])
            OrchestrationBox(
              box: GraphBox(
                id: id,
                title: id,
                role: '',
                harness: '',
                model: '',
                position: Offset.zero,
              ),
            ),
        ],
      ).encode();
      duplicate['bindings'] = {'box': 'owned', 'second': 'owned'};
      expect(() => decode(duplicate), throwsFormatException);
    },
  );
  test(
    'keeps externally removed live definitions pending across app restart',
    () {
      final raw = snapshot();
      raw['pendingRemovals'] = raw['document'];
      raw['document'] = const OrchestrationDocument().encode();
      final restored = decode(raw);
      expect(restored.document!.boxes, isEmpty);
      expect(restored.pendingRemovals!.boxes.single.box.id, 'box');
      expect(restored.bindings['box'], 'owned');
    },
  );
  test(
    'valid empty document remains empty and cannot acquire a saved process',
    () {
      final raw = snapshot()
        ..['document'] = const OrchestrationDocument().encode()
        ..['bindings'] = <String, String>{}
        ..['sessions'] = <String, dynamic>{}
        ..['multiplexer'] = <String, dynamic>{};
      expect(decode(raw).sessions, isEmpty);
      raw['dirty'] = true;
      raw.remove('document');
      expect(() => decode(raw), throwsFormatException);
    },
  );
}
