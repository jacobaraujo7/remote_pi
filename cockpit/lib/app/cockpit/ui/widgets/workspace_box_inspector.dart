import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import '../../domain/entities/workspace_graph.dart';
import '../../ui/viewmodels/cockpit_viewmodel.dart';
import '../../ui/session/terminal_session.dart';
import '../../../core/domain/result.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';
import 'workspace_box_list.dart';

class WorkspaceBoxInspector extends StatefulWidget {
  const WorkspaceBoxInspector({
    super.key,
    required this.vm,
    required this.box,
    required this.entry,
    required this.onClose,
  });
  final CockpitViewModel vm;
  final GraphBox box;
  final WorkspaceBoxEntry entry;
  final VoidCallback onClose;
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
  bool _dirty = false;
  String? _message;
  bool _error = false;
  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkspaceBoxInspector old) {
    super.didUpdateWidget(old);
    if (!_dirty && old.box != widget.box) {
      _name.text = widget.box.title;
      _role.text = widget.box.role;
      _model.text = widget.box.model;
      _tool = widget.box.harness == 'claudeCode'
          ? 'claude'
          : widget.box.harness;
    }
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

  void _save() {
    final result = widget.vm.configureGraphBox(
      boxId: widget.box.id,
      title: _name.text,
      role: _role.text,
      harness: _tool,
      model: _model.text,
    );
    if (result is Success) _dirty = false;
    _feedback(result);
  }

  Future<void> _handoff() async {
    final t = context.t.workspaceView;
    final controller = TextEditingController(text: '${widget.box.role}\n\n');
    String? summary;
    try {
      summary = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.handoffTitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.handoffHelp),
                const SizedBox(height: 12),
                TextField(controller: controller, maxLines: 7),
              ],
            ),
          ),
          actions: [
            OutlineButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.cancel),
            ),
            PrimaryButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(t.handoff),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (!mounted || summary == null || summary.isEmpty) return;
    final result = widget.vm.startGraphHandoff(widget.box.id);
    if (result case Success()) {
      await Clipboard.setData(ClipboardData(text: summary));
      if (!mounted) return;
      widget.vm.selectWorkspaceBox(widget.box.id);
      setState(() {
        _message = t.handoffReady;
        _error = false;
      });
    } else {
      _feedback(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.workspaceView;
    final box = widget.box;
    final session = widget.vm.session(box.tabId ?? '');
    final terminal = session is TerminalSession ? session : null;
    final runningAgent =
        terminal != null &&
        !terminal.hasExited &&
        terminal.activeHarness != null;
    final canControl =
        terminal != null &&
        !terminal.hasExited &&
        !terminal.isWorking &&
        !widget.vm.selectedRemoteDisconnected;
    final links = widget.vm.graphLinks
        .where((l) => l.from == box.id || l.to == box.id)
        .toList();
    final names = {for (final b in widget.vm.graphBoxes) b.id: b.title};
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
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
        color: context.colors.panel,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 20),
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: workspaceStatusColor(
                            context,
                            widget.entry.status,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          workspaceStatusLabel(context, widget.entry.status),
                          style: context.typo.label,
                        ),
                      ],
                    ),
                    label(t.configuration),
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
                    const SizedBox(height: 12),
                    PrimaryButton(onPressed: _save, child: Text(t.save)),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _message!,
                          style: context.typo.label.copyWith(
                            color: _error
                                ? context.colors.warn
                                : context.colors.text2,
                          ),
                        ),
                      ),
                    label(t.session),
                    Text(
                      widget.entry.contextPercent == null
                          ? '${t.context}: ${t.unavailable}'
                          : '${t.context}: ${widget.entry.contextPercent!.toStringAsFixed(0)}%',
                      style: context.typo.body.copyWith(
                        color: context.colors.text2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (terminal != null && !terminal.hasExited)
                      OutlineButton(
                        onPressed: () => widget.vm.openBoxInTerminals(box.id),
                        child: Text(t.openTerminal),
                      )
                    else
                      OutlineButton(
                        onPressed: widget.vm.selectedRemoteDisconnected
                            ? null
                            : () async => _feedback(
                                await widget.vm.openBoxShell(box.id),
                              ),
                        child: Text(t.startShell),
                      ),
                    if (!runningAgent) ...[
                      const SizedBox(height: 8),
                      OutlineButton(
                        onPressed:
                            widget.vm.selectedRemoteDisconnected ||
                                box.harness.isEmpty
                            ? null
                            : () =>
                                  _feedback(widget.vm.relaunchGraphBox(box.id)),
                        child: Text(t.startCli),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      OutlineButton(
                        onPressed: canControl
                            ? () => terminal.insertText('/compact\r')
                            : null,
                        child: Text(t.compact),
                      ),
                      const SizedBox(height: 8),
                      OutlineButton(
                        onPressed: canControl ? _handoff : null,
                        child: Text(t.handoff),
                      ),
                    ],
                    if (box.role.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlineButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: box.role)),
                        child: Text(t.copyRole),
                      ),
                    ],
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
