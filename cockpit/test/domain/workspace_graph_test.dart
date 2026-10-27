import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moving a box preserves its identity and link endpoints', () {
    const planner = GraphBox(
      id: 'box-planner',
      title: 'Planner',
      role: 'Plan the work',
      harness: 'claude',
      model: 'sonnet',
      position: Offset(10, 20),
      tabId: 't1',
    );
    const backend = GraphBox(
      id: 'box-backend',
      title: 'Backend',
      role: 'Implement API',
      harness: 'codex',
      model: 'gpt',
      position: Offset(300, 40),
      tabId: 't2',
    );
    final link = GraphLink(from: planner.id, to: backend.id);

    final moved = planner.copyWith(position: const Offset(500, 700));
    expect(moved.id, planner.id);
    expect(moved.tabId, planner.tabId);
    expect(moved.position, const Offset(500, 700));
    expect(link.from, moved.id);
    expect(link.to, backend.id);
  });

  test('saved boxes and links round trip without changing relationships', () {
    const box = GraphBox(
      id: 'box-1',
      title: 'QA',
      role: 'Review changes',
      harness: 'pi',
      model: 'openai/gpt',
      position: Offset(125.5, 42),
    );
    const link = GraphLink(from: 'box-1', to: 'box-2');
    final restored = GraphBox.fromJson(box.toJson());
    final restoredLink = GraphLink.fromJson(link.toJson());
    expect(restored?.position, box.position);
    expect(restored?.role, box.role);
    expect(restoredLink?.from, box.id);
    expect(restoredLink?.to, 'box-2');
  });

  test('temporary subagents are deduplicated and removed with their owner', () {
    final registry = GraphSubagentRegistry();
    final first = GraphSubagent(
      projectId: 'workspace',
      ownerTabId: 'terminal-1',
      agentId: 'agent-1',
      agentType: 'Explore',
      harness: 'claude',
      startedAt: DateTime.utc(2026, 1, 1),
    );
    final second = GraphSubagent(
      projectId: 'workspace',
      ownerTabId: 'terminal-1',
      agentId: 'agent-2',
      agentType: 'Plan',
      harness: 'claude',
      startedAt: DateTime.utc(2026, 1, 1),
    );
    expect(registry.start(first), isTrue);
    expect(registry.start(first), isFalse);
    expect(registry.start(second), isTrue);
    expect(registry.forProject('workspace'), hasLength(2));
    expect(
      registry.stop('terminal-1', 'agent-1', DateTime.utc(2026, 1, 2)),
      isTrue,
    );
    expect(registry.forProject('workspace').single.agentId, 'agent-2');
    expect(registry.clearOwner('terminal-1'), isTrue);
    expect(registry.forProject('workspace'), isEmpty);
  });

  test('late start after stop does not resurrect a temporary box', () {
    final registry = GraphSubagentRegistry();
    final start = DateTime.utc(2026, 1, 1, 12);
    expect(
      registry.stop(
        'terminal-1',
        'agent-1',
        start.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    GraphSubagent child(DateTime at) => GraphSubagent(
      projectId: 'workspace',
      ownerTabId: 'terminal-1',
      agentId: 'agent-1',
      agentType: 'Explore',
      harness: 'claude',
      startedAt: at,
    );
    expect(registry.start(child(start)), isFalse);
    expect(registry.forProject('workspace'), isEmpty);
    expect(
      registry.start(child(start.add(const Duration(seconds: 2)))),
      isTrue,
    );
  });
}
