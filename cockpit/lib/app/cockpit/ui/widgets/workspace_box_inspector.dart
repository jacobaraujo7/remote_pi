import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import '../../domain/entities/workspace_graph.dart';
import '../../ui/viewmodels/workspace_graph_context.dart';
import '../../../core/domain/result.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../core/ui/widgets/app_menu.dart';
import '../../../../i18n/strings.g.dart';
import 'workspace_box_list.dart';

/// Portable configuration of one definition (what the `.orc` file stores).
/// Session actions (start, compact, handoff) live in the terminal menu, so
/// this body fits a centered dialog instead of a side drawer.
class WorkspaceBoxInspector extends StatefulWidget {
  const WorkspaceBoxInspector({
    super.key,
    required this.vm,
    required this.box,
    required this.entry,
    required this.onClose,
    this.projectId,
    this.directory = '.',
    this.onSave,
    this.onSuggestRole,
  });
  final Future<Result<String, String>> Function()? onSuggestRole;
  final WorkspaceGraphContext vm;
  final GraphBox box;
  final WorkspaceBoxEntry entry;
  final VoidCallback onClose;
  final String? projectId;
  final String directory;
  final Future<Result<String, String>> Function(
    String,
    String,
    String,
    String,
    String,
  )?
  onSave;
  @override
  State<WorkspaceBoxInspector> createState() => _WorkspaceBoxInspectorState();
}

class _WorkspaceBoxInspectorState extends State<WorkspaceBoxInspector> {
  late final TextEditingController _name = TextEditingController(
    text: widget.box.title,
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.box.role,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.box.model,
  );
  late String _tool = widget.box.harness == 'claudeCode'
      ? 'claude'
      : widget.box.harness;
  late final TextEditingController _directory = TextEditingController(
    text: widget.directory,
  );
  bool _askingRole = false;
  String? _suggestion;
  bool _dirty = false;
  String? _message;
  bool _error = false;
  @override
  void dispose() {
    _directory.dispose();
    _name.dispose();
    _role.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkspaceBoxInspector old) {
    super.didUpdateWidget(old);
    if (!_dirty &&
        (old.box != widget.box || old.directory != widget.directory)) {
      _directory.text = widget.directory;
      _name.text = widget.box.title;
      _role.text = widget.box.role;
      _model.text = widget.box.model;
      _tool = widget.box.harness == 'claudeCode'
          ? 'claude'
          : widget.box.harness;
    }
  }

  Future<void> _suggestRole() async {
    if (_askingRole || widget.onSuggestRole == null) return;
    setState(() {
      _askingRole = true;
      _message = null;
    });
    final result = await widget.onSuggestRole!();
    if (!mounted) return;
    setState(() {
      _askingRole = false;
      switch (result) {
        case Success(:final value):
          _suggestion = value;
        case Failure(:final error):
          _error = true;
          _message = error;
      }
    });
  }

  void _feedback(Result<String, String> result) {
    if (!mounted) return;
    setState(() {
      _error = result is Failure;
      _message = switch (result) {
        Failure(:final error) => error,
        Success() => context.t.workspaceView.saved,
      };
    });
  }

  Future<void> _save() async {
    final result = widget.onSave != null
        ? await widget.onSave!(
            _name.text,
            _role.text,
            _tool,
            _model.text,
            _directory.text,
          )
        : await widget.vm.configureGraphBox(
            boxId: widget.box.id,
            title: _name.text,
            role: _role.text,
            harness: _tool,
            model: _model.text,
          );
    if (!mounted) return;
    if (result is Success) _dirty = false;
    _feedback(result);
  }

  Future<void> _addLink(BuildContext anchor) async {
    final others = widget.vm.graphBoxes
        .where((b) => b.id != widget.box.id)
        .toList();
    if (others.isEmpty) return;
    final target = await showAppMenu<String>(
      anchor,
      items: [
        for (final other in others)
          AppMenuItem(value: other.id, label: other.title),
      ],
    );
    if (!mounted || target == null) return;
    widget.vm.addGraphLink(widget.box.id, target);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.workspaceView;
    final box = widget.box;
    final links = widget.vm.graphLinks
        .where((l) => l.from == box.id || l.to == box.id)
        .toList();
    final names = {for (final b in widget.vm.graphBoxes) b.id: b.title};
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: context.typo.label.copyWith(color: context.colors.text3),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: ColoredBox(
        color: context.colors.bg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      box.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.title,
                    ),
                  ),
                  IconButton.ghost(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.portableHint,
                      style: context.typo.label.copyWith(
                        color: context.colors.text3,
                        height: 1.4,
                      ),
                    ),
                    label(t.name),
                    TextField(
                      controller: _name,
                      placeholder: Text(t.name),
                      onChanged: (_) => _dirty = true,
                    ),
                    label(t.optionalRole),
                    TextField(
                      controller: _role,
                      maxLines: 5,
                      onChanged: (_) => _dirty = true,
                    ),
                    if (widget.onSuggestRole != null) ...[
                      const SizedBox(height: 10),
                      if (box.role.trim().isEmpty) ...[
                        Text(
                          context.t.orchestration.roleMissing,
                          style: context.typo.label.copyWith(
                            color: context.colors.text2,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlineButton(
                          onPressed:
                              _askingRole ||
                                  widget.entry.tool.isEmpty ||
                                  widget.entry.status != WorkspaceBoxStatus.idle
                              ? null
                              : _suggestRole,
                          child: Text(
                            _askingRole
                                ? context.t.orchestration.askingRole
                                : context.t.orchestration.askRole,
                          ),
                        ),
                      ),
                      if (_suggestion case final suggestion?) ...[
                        label(context.t.orchestration.roleSuggestion),
                        Text(
                          suggestion,
                          style: context.typo.body.copyWith(height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlineButton(
                              onPressed: () => setState(() {
                                _role.text = suggestion;
                                _dirty = true;
                                _suggestion = null;
                              }),
                              child: Text(
                                context.t.orchestration.useSuggestion,
                              ),
                            ),
                            OutlineButton(
                              onPressed: () =>
                                  setState(() => _suggestion = null),
                              child: Text(
                                context.t.orchestration.discardSuggestion,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    label(t.tool),
                    Wrap(
                      spacing: 4,
                      runSpacing: 6,
                      children: [
                        for (final tool in const ['', 'claude', 'codex', 'pi'])
                          OutlineButton(
                            onPressed: () => setState(() {
                              _tool = tool;
                              _dirty = true;
                            }),
                            child: Text(
                              tool.isEmpty ? t.noTool : tool,
                              style: TextStyle(
                                color: _tool == tool
                                    ? context.colors.accent
                                    : context.colors.text2,
                              ),
                            ),
                          ),
                      ],
                    ),
                    label(t.model),
                    TextField(
                      controller: _model,
                      onChanged: (_) => _dirty = true,
                    ),
                    label(context.t.orchestration.directory),
                    TextField(
                      controller: _directory,
                      onChanged: (_) => _dirty = true,
                    ),
                    label(t.connections),
                    if (links.isEmpty)
                      Text(
                        t.noConnections,
                        style: context.typo.body.copyWith(
                          color: context.colors.text3,
                        ),
                      ),
                    for (final link in links)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${names[link.from] ?? link.from} → ${names[link.to] ?? link.to}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.typo.label,
                            ),
                          ),
                          IconButton.ghost(
                            icon: const Icon(Icons.link_off, size: 16),
                            onPressed: () =>
                                widget.vm.removeGraphLink(link.from, link.to),
                          ),
                        ],
                      ),
                    if (widget.vm.graphBoxes.length > 1)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Builder(
                          builder: (anchor) => GhostButton(
                            onPressed: () => _addLink(anchor),
                            child: Text(
                              '+ ${t.addConnection}',
                              style: TextStyle(color: context.colors.accent),
                            ),
                          ),
                        ),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _message!,
                          style: context.typo.label.copyWith(
                            color: _error
                                ? context.colors.warn
                                : context.colors.text2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlineButton(
                          onPressed: widget.onClose,
                          child: Text(t.cancel),
                        ),
                        const SizedBox(width: 8),
                        PrimaryButton(onPressed: _save, child: Text(t.save)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
