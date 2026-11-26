import 'package:cockpit/app/cockpit/ui/services/layout_scrollback_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps ordinary terminal and task history from older layouts', () {
    expect(
      layoutScrollbackKeys([
        {
          'sessions': {
            'shell': {'type': 'terminal'},
            'task-view': {'type': 'task_output', 'taskId': 'run'},
            'editor': {'type': 'viewer'},
          },
        },
      ]),
      {'shell', 'run'},
    );
  });

  test('keeps independent child histories in every saved orchestration', () {
    expect(
      layoutScrollbackKeys([
        {
          'sessions': {
            'outside': {'type': 'terminal'},
            'app-a': {
              'type': 'orchestration',
              'ownershipVersion': 2,
              'sessions': {
                'owned-a': {'type': 'terminal'},
                'owned-a-split': {'type': 'terminal'},
              },
            },
            'app-b': {
              'type': 'orchestration',
              'ownershipVersion': 2,
              'sessions': {
                'owned-b': {'type': 'terminal'},
              },
            },
          },
        },
        {
          'sessions': {
            'other-worktree': {'type': 'terminal'},
          },
        },
      ]),
      {'outside', 'owned-a', 'owned-a-split', 'owned-b', 'other-worktree'},
    );
  });

  test('retains recoverable histories with an unsupported app version', () {
    expect(
      layoutScrollbackKeys([
        {
          'sessions': {
            'future-app': {
              'type': 'orchestration',
              'ownershipVersion': 99,
              'sessions': {
                'recoverable': {'type': 'terminal'},
              },
            },
          },
        },
      ]),
      {'recoverable'},
    );
  });

  test('ignores malformed values and unrelated nested documents', () {
    expect(
      layoutScrollbackKeys([
        null,
        {},
        {'sessions': []},
        {
          'sessions': {
            'bad': null,
            'task': {'type': 'task_output', 'taskId': 8},
            'document': {
              'type': 'viewer',
              'sessions': {
                'not-runtime': {'type': 'terminal'},
              },
            },
            'app': {
              'type': 'orchestration',
              'sessions': {
                7: {'type': 'terminal'},
                'bad-child': [],
                'editor': {'type': 'viewer'},
                'nested-app': {
                  'type': 'orchestration',
                  'sessions': {
                    'invalid-grandchild': {'type': 'terminal'},
                  },
                },
              },
            },
          },
        },
      ]),
      isEmpty,
    );
  });
}
