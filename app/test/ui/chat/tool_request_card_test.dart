import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _bashTool = ToolEvent(
  id: 'tc1',
  toolCallId: 'tc1',
  tool: 'Bash',
  args: {'command': 'ls -la'},
);

const _editToolWithHunk = ToolEvent(
  id: 'tc2',
  toolCallId: 'tc4',
  tool: 'edit',
  args: {
    'path': 'app/test/ui/chat/tool_request_card_test.dart',
    'hunks': [
      {
        'lines': [
          {'kind': 'context', 'oldLine': 16, 'newLine': 16, 'text': 'args: {'},
          {'kind': 'remove', 'oldLine': 17, 'text': "  tool: 'Edit',"},
          {'kind': 'add', 'newLine': 17, 'text': "  tool: 'edit',"},
          {'kind': 'context', 'oldLine': 18, 'newLine': 18, 'text': '},'},
        ],
      },
    ],
  },
);

void main() {
  group('Subagent workflows', () {
    testWidgets('renders live scripted workflow child inventory', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'script',
        toolCallId: 'script',
        tool: 'subagent',
        args: {'workflow': './review.js'},
        details: {
          'mode': 'workflow',
          'results': [
            {
              'index': 0,
              'workflowKey': 'scan',
              'agent': 'scout',
              'exitCode': 0,
              'finalOutput': 'Scout report',
            },
          ],
          'workflowChildren': {
            'version': 1,
            'workflowState': 'running',
            'children': [
              {'childId': 'scan', 'state': 'completed'},
              {'childId': 'review', 'agent': 'reviewer', 'state': 'running'},
            ],
          },
        },
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('scout · completed'), findsOneWidget);
      expect(find.text('reviewer · running'), findsOneWidget);
      await tester.tap(find.text('Child output'));
      await tester.pumpAndSettle();
      expect(find.text('Scout report'), findsOneWidget);
    });

    testWidgets('names finished live children when inventory omits agent', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'inventory',
        toolCallId: 'inventory',
        tool: 'subagent',
        args: {'workflow': './review.js'},
        details: {
          'workflowChildren': {
            'children': [
              {'childId': 'scout', 'state': 'completed'},
              {'childId': 'reviewer', 'agent': 'reviewer', 'state': 'running'},
            ],
          },
        },
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('scout · completed'), findsOneWidget);
      expect(find.text('reviewer · running'), findsOneWidget);
    });

    testWidgets('keeps script results with repeated child-local indexes', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'script-done',
        toolCallId: 'script-done',
        tool: 'subagent',
        args: {'workflow': './review.js'},
        status: ToolEventStatus.completed,
        details: {
          'results': [
            {
              'index': 0,
              'workflowKey': 'scan',
              'agent': 'scout',
              'exitCode': 0,
              'finalOutput': 'Scout report',
            },
            {
              'index': 0,
              'workflowKey': 'review',
              'agent': 'reviewer',
              'exitCode': 0,
              'finalOutput': 'Review report',
            },
          ],
          'workflowChildren': {
            'children': [
              {'childId': 'scan', 'agent': 'scout', 'state': 'completed'},
              {'childId': 'review', 'agent': 'reviewer', 'state': 'completed'},
            ],
          },
        },
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('scout · completed'), findsOneWidget);
      expect(find.text('reviewer · completed'), findsOneWidget);
      expect(find.text('Child output'), findsNWidgets(2));
    });

    testWidgets('renders queued chain steps and live child activity', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'workflow',
        toolCallId: 'workflow',
        tool: 'subagent',
        args: {
          'chain': [
            {'agent': 'scout', 'task': 'Find files'},
            {'agent': 'reviewer', 'task': 'Review code'},
          ],
        },
        details: {
          'mode': 'chain',
          'progress': [
            {
              'index': 0,
              'agent': 'scout',
              'status': 'running',
              'currentTool': 'read',
              'recentOutput': ['Inspecting files'],
            },
          ],
        },
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('Chain workflow'), findsOneWidget);
      expect(find.text('scout · running'), findsOneWidget);
      expect(find.text('reviewer · pending'), findsOneWidget);
      expect(find.text('Tool: read'), findsOneWidget);
      expect(find.text('Inspecting files'), findsOneWidget);
      expect(find.text('RUNNING'), findsOneWidget);
    });

    testWidgets('shows child failure and expandable final output', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'workflow',
        toolCallId: 'workflow',
        tool: 'subagent',
        args: {'workflow': 'review'},
        status: ToolEventStatus.completed,
        result: 'Workflow summary',
        details: {
          'mode': 'workflow',
          'results': [
            {
              'index': 4,
              'agent': 'reviewer',
              'exitCode': 1,
              'error': 'Review failed',
              'finalOutput': 'Child report',
            },
          ],
        },
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('Workflow: review'), findsOneWidget);
      expect(find.text('reviewer · failed'), findsOneWidget);
      expect(find.text('Review failed'), findsOneWidget);
      await tester.tap(find.text('Child output'));
      await tester.pumpAndSettle();
      expect(find.text('Child report'), findsOneWidget);
      await tester.tap(find.text('Workflow output'));
      await tester.pumpAndSettle();
      expect(find.text('Workflow summary'), findsOneWidget);
    });

    testWidgets('background snapshots show nested states on narrow screens', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'run',
        toolCallId: 'run',
        tool: 'subagent',
        args: {'workflow': 'parallel-review'},
        details: {
          'runs': [
            {
              'id': 'r1',
              'label': 'Review',
              'state': 'running',
              'children': [
                {'id': 'r2', 'agent': 'reviewer', 'state': 'complete'},
                {'id': 'r3', 'agent': 'scout', 'state': 'paused'},
              ],
            },
          ],
        },
      );
      await tester.pumpWidget(
        _wrap(
          const Center(
            child: SizedBox(width: 280, child: ToolRequestCard(tool: tool)),
          ),
        ),
      );
      expect(find.text('Review · running'), findsOneWidget);
      expect(find.text('reviewer · complete'), findsOneWidget);
      expect(find.text('scout · paused'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('older text-only subagent results remain visible', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'old',
        toolCallId: 'old',
        tool: 'subagent',
        args: {'agent': 'worker', 'task': 'Do work'},
        status: ToolEventStatus.completed,
        result: 'Legacy report',
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('worker · unknown'), findsOneWidget);
      await tester.tap(find.text('Workflow output'));
      await tester.pumpAndSettle();
      expect(find.text('Legacy report'), findsOneWidget);
    });

    testWidgets('reads older child messages without exposing thinking', (
      tester,
    ) async {
      const tool = ToolEvent(
        id: 'legacy-child',
        toolCallId: 'legacy-child',
        tool: 'subagent',
        args: {},
        status: ToolEventStatus.completed,
        details: {
          'results': [
            {
              'index': 0,
              'agent': 'worker',
              'exitCode': 0,
              'execution': {'status': 'completed'},
              'progress': {'status': 'running'},
              'messages': [
                {
                  'role': 'assistant',
                  'content': [
                    {'type': 'thinking', 'thinking': 'Private reasoning'},
                    {'type': 'text', 'text': 'Legacy child report'},
                  ],
                },
              ],
            },
          ],
        },
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: tool)));
      expect(find.text('worker · completed'), findsOneWidget);
      await tester.tap(find.text('Child output'));
      await tester.pumpAndSettle();
      expect(find.text('Legacy child report'), findsOneWidget);
      expect(find.text('Private reasoning'), findsNothing);
    });
  });

  group('ToolRequestCard (informational)', () {
    testWidgets('shows tool name and command', (tester) async {
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: _bashTool)));
      expect(find.text('BASH'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
    });

    testWidgets('edit renders rich hunks with context lines', (tester) async {
      await tester.pumpWidget(
        _wrap(const ToolRequestCard(tool: _editToolWithHunk)),
      );

      expect(
        find.textContaining('   16 args: {', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining("-  17   tool: 'Edit',", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining("+  17   tool: 'edit',", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('   18 },', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('pending state shows RUNNING and no Allow/Deny buttons', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: _bashTool)));
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
      expect(find.text('Deny'), findsNothing);
      expect(find.textContaining('s'), findsAny); // no '60s' countdown
      expect(find.textContaining('60s'), findsNothing);
    });

    testWidgets('completed state shows DONE', (tester) async {
      const done = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
        status: ToolEventStatus.completed,
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: done)));
      expect(find.text('DONE'), findsOneWidget);
      expect(find.textContaining('Done'), findsAny);
    });

    testWidgets('denied state shows DENIED label', (tester) async {
      const denied = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
        status: ToolEventStatus.denied,
        error: 'user denied',
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: denied)));
      expect(find.text('DENIED'), findsOneWidget);
    });

    testWidgets('allowed state shows RUNNING (still in flight)', (
      tester,
    ) async {
      const allowed = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
        status: ToolEventStatus.allowed,
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: allowed)));
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
    });

    // Plan/32 — the card is colored by status: running blue, done green,
    // failed red. We assert the outcome line's color (the same _statusColor
    // drives the border / icon / tool name).
    Color? outcomeColor(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style?.color;

    testWidgets('completed → green "✓ Done"', (tester) async {
      const done = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
        status: ToolEventStatus.completed,
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: done)));
      expect(outcomeColor(tester, '✓ Done'), AppColors.dark.success);
    });

    testWidgets('failed → red "✗ {error}" + FAILED label', (tester) async {
      const failed = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'exit 1'},
        status: ToolEventStatus.failed,
        error: 'command failed: exit 1',
      );
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: failed)));
      expect(find.text('FAILED'), findsOneWidget);
      expect(
        outcomeColor(tester, '✗ command failed: exit 1'),
        AppColors.dark.error,
      );
    });

    testWidgets('running → blue "⏳ Running…"', (tester) async {
      // pending defaults
      await tester.pumpWidget(_wrap(const ToolRequestCard(tool: _bashTool)));
      expect(outcomeColor(tester, '⏳ Running…'), AppColors.dark.accent);
    });
  });
}
