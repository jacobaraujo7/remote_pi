import 'package:app/domain/session_state.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Displays pi-subagents' public tool details without depending on the package.
class SubagentWorkflow extends StatelessWidget {
  final ToolEvent tool;

  const SubagentWorkflow({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final args = tool.args is Map ? tool.args as Map : const {};
    final details = tool.details ?? const {};
    final workflow = args['workflow'];
    final mode = _text(details['mode']);
    final title = workflow is String
        ? 'Workflow: $workflow'
        : mode.isNotEmpty
        ? '${mode[0].toUpperCase()}${mode.substring(1)} workflow'
        : 'Subagent workflow';
    final children = _children(args, details);
    final output = tool.result;
    final waiting =
        tool.status == ToolEventStatus.pending ||
        tool.status == ToolEventStatus.allowed;
    final omitted = details['omitted'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.typo.mono),
        if (details['background'] == true || details['asyncId'] is String)
          Text(
            'Background run — tool completion is not workflow completion.',
            style: context.typo.mono.copyWith(color: context.colors.muted),
          ),
        for (final child in children)
          _ChildStep(
            child: child,
            fallbackStatus: waiting ? 'pending' : 'unknown',
          ),
        if (omitted is Map &&
            ((omitted['runs'] is num && omitted['runs'] > 0) ||
                (omitted['children'] is num && omitted['children'] > 0) ||
                omitted['byteLimitExceeded'] == true))
          Text(
            'Additional workflow activity omitted by Pi.',
            style: context.typo.mono.copyWith(color: context.colors.muted),
          ),
        if (output != null && output.toString().isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('Workflow output', style: context.typo.mono),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  output.toString(),
                  style: context.typo.mono,
                ),
              ),
            ],
          ),
      ],
    );
  }

  static List<Map> _children(Map args, Map details) {
    final rows = <Object, Map>{};
    final inventory = details['workflowChildren'];
    void addRows(dynamic raw) {
      if (raw is! List) return;
      for (var i = 0; i < raw.length; i++) {
        final row = raw[i];
        if (row is! Map) continue;
        // Scripted steps each have their own index space (often all zero).
        final key = inventory is Map
            ? row['workflowKey'] ??
                  row['childId'] ??
                  row['runId'] ??
                  row['index'] ??
                  row['id'] ??
                  i
            : row['index'] ?? row['id'] ?? i;
        rows[key] = {...?rows[key], ...row};
      }
    }

    // Arguments keep queued steps visible before the first progress update.
    addRows(args['chain'] ?? args['tasks']);
    if (rows.isEmpty && args['agent'] is String) rows[0] = args;
    addRows(details['results'] ?? details['runs']);
    addRows(details['progress']);
    if (inventory is Map) addRows(inventory['children']);
    return rows.values.toList();
  }

  static String _text(dynamic value) => value is String ? value : '';
}

class _ChildStep extends StatelessWidget {
  final Map child;
  final String fallbackStatus;

  const _ChildStep({required this.child, required this.fallbackStatus});

  @override
  Widget build(BuildContext context) {
    final progress = child['progress'] is Map
        ? child['progress'] as Map
        : child['progressSummary'] is Map
        ? child['progressSummary'] as Map
        : child['activity'] is Map
        ? child['activity'] as Map
        : child;
    final explicitStatus = child['status'] ?? child['state'];
    final execution = child['execution'];
    final status = explicitStatus is String
        ? explicitStatus
        : execution is Map && execution['status'] is String
        ? execution['status'] as String
        : child['stopped'] == true
        ? 'stopped'
        : child['detached'] == true
        ? 'detached'
        : child['timedOut'] == true || child['interrupted'] == true
        ? 'failed'
        : progress['status'] is String
        ? progress['status'] as String
        : child['exitCode'] is num
        ? (child['exitCode'] == 0 ? 'completed' : 'failed')
        : fallbackStatus;
    final color = switch (status) {
      'completed' || 'complete' => context.colors.success,
      'failed' || 'rejected' => context.colors.error,
      'running' => context.colors.accent,
      _ => context.colors.muted,
    };
    final name =
        child['label'] ??
        child['agent'] ??
        child['workflowKey'] ??
        child['childId'] ??
        (child['parallel'] is List ? 'Parallel group' : 'Agent');
    final task = child['task'];
    final currentTool = progress['currentTool'];
    final output = _childOutput(child);
    final error = child['error'];
    final recent = progress['recentOutput'];
    final nestedChildren = child['children'] ?? child['parallel'];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name · $status',
            style: context.typo.mono.copyWith(color: color),
          ),
          if (task is String && task.isNotEmpty)
            Text(
              task,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.typo.mono,
            ),
          if (currentTool is String && currentTool.isNotEmpty)
            Text(
              'Tool: $currentTool',
              style: context.typo.mono.copyWith(color: context.colors.muted),
            ),
          if (recent is List && recent.isNotEmpty)
            Text(
              recent.whereType<String>().join('\n'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: context.typo.mono.copyWith(color: context.colors.muted),
            ),
          if (error is String && error.isNotEmpty)
            SelectableText(
              error,
              style: context.typo.mono.copyWith(color: context.colors.error),
            ),
          if (output is String && output.isNotEmpty)
            ExpansionTile(
              key: ValueKey('${child['index']}:$name'),
              tilePadding: EdgeInsets.zero,
              title: Text('Child output', style: context.typo.mono),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(output, style: context.typo.mono),
                ),
              ],
            ),
          if (nestedChildren is List)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final nested in nestedChildren)
                    if (nested is Map)
                      _ChildStep(child: nested, fallbackStatus: fallbackStatus),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String? _childOutput(Map child) {
    final output = child['finalOutput'] ?? child['summary'];
    if (output is String) return output;
    final messages = child['messages'];
    if (messages is! List) return null;
    for (final message in messages.reversed) {
      if (message is! Map || message['role'] != 'assistant') continue;
      final content = message['content'];
      if (content is String && content.isNotEmpty) return content;
      if (content is! List) continue;
      final text = content
          .whereType<Map>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'])
          .whereType<String>()
          .join('\n');
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
