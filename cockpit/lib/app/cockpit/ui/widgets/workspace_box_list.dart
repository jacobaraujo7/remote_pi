import '../../../core/ui/widgets/app_menu.dart';
import '../../../core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../domain/entities/workspace_graph.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';

enum WorkspaceBoxStatus { shell, working, waiting, idle, closed, disconnected }

class WorkspaceBoxEntry {
  const WorkspaceBoxEntry({
    required this.box,
    required this.status,
    required this.tool,
    this.contextPercent,
    this.unseen = false,
  });
  final GraphBox box;
  final WorkspaceBoxStatus status;
  final String tool;
  final bool unseen;
  final double? contextPercent;
}

List<WorkspaceBoxEntry> filterWorkspaceBoxes(
  List<WorkspaceBoxEntry> entries, {
  List<String> order = const [],
  String search = '',
  WorkspaceBoxStatus? status,
}) {
  final query = search.trim().toLowerCase();
  final rank = {for (var i = order.length - 1; i >= 0; i--) order[i]: i};
  return entries
      .where(
        (entry) =>
            (status == null || entry.status == status) &&
            (query.isEmpty ||
                entry.box.title.toLowerCase().contains(query) ||
                entry.box.role.toLowerCase().contains(query)),
      )
      .toList()
    ..sort((a, b) {
      final position = (rank[a.box.id] ?? order.length).compareTo(
        rank[b.box.id] ?? order.length,
      );
      if (position != 0) return position;
      final compared = a.box.title.toLowerCase().compareTo(
        b.box.title.toLowerCase(),
      );
      return compared != 0 ? compared : a.box.id.compareTo(b.box.id);
    });
}

/// Reorder visible slots while leaving filtered-out boxes in their positions.
List<String> reorderWorkspaceBoxIds(
  List<String> all,
  List<String> visible,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 ||
      oldIndex >= visible.length ||
      newIndex < 0 ||
      newIndex >= visible.length) {
    return all;
  }
  final reordered = [...visible];
  reordered.insert(newIndex, reordered.removeAt(oldIndex));
  final visibleIds = visible.toSet();
  var index = 0;
  return [
    for (final id in all) visibleIds.contains(id) ? reordered[index++] : id,
  ];
}

String workspaceStatusLabel(BuildContext context, WorkspaceBoxStatus status) {
  final t = context.t.workspaceView;
  return switch (status) {
    WorkspaceBoxStatus.shell => t.shell,
    WorkspaceBoxStatus.working => t.working,
    WorkspaceBoxStatus.waiting => t.waiting,
    WorkspaceBoxStatus.idle => t.idle,
    WorkspaceBoxStatus.closed => t.closed,
    WorkspaceBoxStatus.disconnected => t.disconnected,
  };
}

Color workspaceStatusColor(BuildContext context, WorkspaceBoxStatus status) =>
    switch (status) {
      WorkspaceBoxStatus.working => context.colors.online,
      WorkspaceBoxStatus.waiting ||
      WorkspaceBoxStatus.disconnected => context.colors.warn,
      _ => context.colors.text3,
    };

class WorkspaceBoxList extends StatefulWidget {
  const WorkspaceBoxList({
    super.key,
    required this.entries,
    this.selectedBoxId,
    required this.onSelect,
    required this.onOpen,
    required this.onConfigure,
    this.boxOrder = const [],
    this.onReorder,
  });
  final List<WorkspaceBoxEntry> entries;
  final List<String> boxOrder;
  final ValueChanged<List<String>>? onReorder;
  final String? selectedBoxId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onConfigure;
  @override
  State<WorkspaceBoxList> createState() => _WorkspaceBoxListState();
}

class _WorkspaceBoxListState extends State<WorkspaceBoxList> {
  String _search = '';
  WorkspaceBoxStatus? _status;
  @override
  Widget build(BuildContext context) {
    final t = context.t.workspaceView;
    final visible = filterWorkspaceBoxes(
      widget.entries,
      order: widget.boxOrder,
      search: _search,
      status: _status,
    );
    return ColoredBox(
      color: context.colors.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    placeholder: Text(t.search),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (anchor) => OutlineButton(
                    onPressed: () async {
                      final value = await showAppMenu<String>(
                        anchor,
                        items: [
                          AppMenuItem(
                            value: 'all',
                            label: t.allStates,
                            selected: _status == null,
                          ),
                          for (final status in WorkspaceBoxStatus.values)
                            AppMenuItem(
                              value: status.name,
                              label: workspaceStatusLabel(context, status),
                              selected: _status == status,
                            ),
                        ],
                      );
                      if (!mounted || value == null) return;
                      setState(
                        () => _status = WorkspaceBoxStatus.values
                            .where((s) => s.name == value)
                            .firstOrNull,
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _status == null
                              ? t.allStates
                              : workspaceStatusLabel(context, _status!),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 850;
                final medium = constraints.maxWidth >= 620;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              t.name,
                              style: context.typo.label.copyWith(
                                color: context.colors.text3,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              t.state,
                              style: context.typo.label.copyWith(
                                color: context.colors.text3,
                              ),
                            ),
                          ),
                          if (medium)
                            Expanded(
                              flex: 2,
                              child: Text(
                                t.tool,
                                style: context.typo.label.copyWith(
                                  color: context.colors.text3,
                                ),
                              ),
                            ),
                          if (wide)
                            Expanded(
                              flex: 3,
                              child: Text(
                                t.role,
                                style: context.typo.label.copyWith(
                                  color: context.colors.text3,
                                ),
                              ),
                            ),
                          if (medium)
                            SizedBox(
                              width: 100,
                              child: Text(
                                t.context,
                                style: context.typo.label.copyWith(
                                  color: context.colors.text3,
                                ),
                              ),
                            ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(
                                widget.entries.isEmpty
                                    ? t.noBoxes
                                    : t.noMatches,
                                style: context.typo.body.copyWith(
                                  color: context.colors.text3,
                                ),
                              ),
                            )
                          : ReorderableList(
                              onReorderItem: (oldIndex, newIndex) {
                                final all = filterWorkspaceBoxes(
                                  widget.entries,
                                  order: widget.boxOrder,
                                ).map((e) => e.box.id).toList();
                                widget.onReorder?.call(
                                  reorderWorkspaceBoxIds(
                                    all,
                                    visible.map((e) => e.box.id).toList(),
                                    oldIndex,
                                    newIndex,
                                  ),
                                );
                              },
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final entry = visible[index];
                                final selected =
                                    entry.box.id == widget.selectedBoxId;
                                return Semantics(
                                  key: ValueKey('box-row-${entry.box.id}'),
                                  selected: selected,
                                  button: true,
                                  label: entry.box.title,
                                  child: Row(
                                    children: [
                                      if (widget.onReorder != null)
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.grab,
                                            child: SizedBox(
                                              width: 32,
                                              height: 52,
                                              child: Center(
                                                child: Icon(
                                                  Icons.drag_handle,
                                                  size: 18,
                                                  color: context.colors.text3,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: GestureDetector(
                                          onDoubleTap: () =>
                                              widget.onOpen(entry.box.id),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? context.colors.accentSoft
                                                  : null,
                                              border: Border(
                                                left: BorderSide(
                                                  width: 3,
                                                  color: selected
                                                      ? context.colors.accent
                                                      : const Color(0x00000000),
                                                ),
                                                bottom: BorderSide(
                                                  color: context.colors.border,
                                                ),
                                              ),
                                            ),
                                            child: Button(
                                              leading: const Icon(
                                                Icons.terminal,
                                                size: 18,
                                              ),
                                              style: const ButtonStyle.ghost(),
                                              onPressed: () =>
                                                  widget.onSelect(entry.box.id),
                                              child: SizedBox(
                                                height: 44,
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 3,
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  entry
                                                                      .box
                                                                      .title,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                if (!medium)
                                                                  Text(
                                                                    entry
                                                                            .tool
                                                                            .isEmpty
                                                                        ? context
                                                                              .t
                                                                              .orchestration
                                                                              .noCli
                                                                        : entry
                                                                              .tool,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: context
                                                                        .typo
                                                                        .label
                                                                        .copyWith(
                                                                          color: context
                                                                              .colors
                                                                              .text3,
                                                                        ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          WorkspaceAttentionBadge(
                                                            unseen:
                                                                entry.unseen,
                                                            waiting:
                                                                entry.status ==
                                                                WorkspaceBoxStatus
                                                                    .waiting,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.circle,
                                                            size: 8,
                                                            color:
                                                                workspaceStatusColor(
                                                                  context,
                                                                  entry.status,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              workspaceStatusLabel(
                                                                context,
                                                                entry.status,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (medium)
                                                      Expanded(
                                                        flex: 2,
                                                        child: Text(
                                                          entry.tool.isEmpty
                                                              ? context
                                                                    .t
                                                                    .orchestration
                                                                    .noCli
                                                              : entry.tool,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    if (wide)
                                                      Expanded(
                                                        flex: 3,
                                                        child: Text(
                                                          entry.box.role.isEmpty
                                                              ? t.noRole
                                                              : entry.box.role,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: context
                                                              .typo
                                                              .body
                                                              .copyWith(
                                                                color: context
                                                                    .colors
                                                                    .text3,
                                                              ),
                                                        ),
                                                      ),
                                                    if (medium)
                                                      SizedBox(
                                                        width: 100,
                                                        child: Text(
                                                          entry.contextPercent ==
                                                                  null
                                                              ? t.unavailable
                                                              : '${entry.contextPercent!.toStringAsFixed(0)}%',
                                                        ),
                                                      ),
                                                    SizedBox(
                                                      width: 40,
                                                      child: IconButton.ghost(
                                                        icon: const Icon(
                                                          Icons
                                                              .settings_outlined,
                                                          size: 16,
                                                        ),
                                                        onPressed: () =>
                                                            widget.onConfigure(
                                                              entry.box.id,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceAttentionBadge extends StatelessWidget {
  const WorkspaceAttentionBadge({
    super.key,
    required this.unseen,
    required this.waiting,
  });
  final bool unseen, waiting;
  @override
  Widget build(BuildContext context) {
    if (!unseen && !waiting) return const SizedBox.shrink();
    final label = waiting
        ? context.t.orchestration.needsInput
        : context.t.orchestration.newActivity;
    return AppTooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            waiting
                ? Icons.notification_important_outlined
                : Icons.notifications_active_outlined,
            size: 15,
            color: waiting ? context.colors.warn : context.colors.accent,
          ),
        ),
      ),
    );
  }
}
