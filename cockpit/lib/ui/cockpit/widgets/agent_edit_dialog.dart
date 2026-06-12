import 'package:cockpit/ui/cockpit/session/agent_session.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AgentEditResult = ({String agentName, bool autoStartRelay});

/// Dialog "Editar agente": nome editável + toggle relay + infos do agente.
/// Devolve [AgentEditResult] ou `null` se cancelar.
Future<AgentEditResult?> showAgentEditDialog(
  BuildContext context, {
  required AgentSession session,
}) {
  return showDialog<AgentEditResult>(
    context: context,
    builder: (context) => _AgentEditDialog(session: session),
  );
}

class _AgentEditDialog extends StatefulWidget {
  const _AgentEditDialog({required this.session});
  final AgentSession session;

  @override
  State<_AgentEditDialog> createState() => _AgentEditDialogState();
}

class _AgentEditDialogState extends State<_AgentEditDialog> {
  late final TextEditingController _name;
  late bool _autoStartRelay;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.session.title);
    _autoStartRelay = widget.session.autoStartRelay;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim().replaceAll(' ', '-');
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      (agentName: name, autoStartRelay: _autoStartRelay),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final ctx = session.contextUsage;

    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit agent',
                style: context.typo.title.copyWith(
                  fontSize: 16,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 16),

              _Label('Agent name'),
              const SizedBox(height: 6),
              _Field(
                controller: _name,
                hint: 'Agent name',
                inputFormatters: [
                  FilteringTextInputFormatter(
                    RegExp(r' '),
                    allow: false,
                    replacementString: '-',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _SectionTitle('Relay (remote-pi)'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Auto-connect on start',
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                  Switch(
                    value: _autoStartRelay,
                    activeThumbColor: colors.accent,
                    onChanged: (v) => setState(() => _autoStartRelay = v),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _SectionTitle('Information'),
              const SizedBox(height: 8),
              _InfoRow('Folder', session.workingDirectory),
              _InfoRow('Model', session.model?.name ?? '—'),
              _InfoRow('State', _statusLabel(session.status)),
              _InfoRow(
                'Context',
                ctx?.percent != null
                    ? '${ctx!.percent!.toStringAsFixed(ctx.percent! < 10 ? 1 : 0)}%  (${ctx.tokens ?? "?"}/${ctx.contextWindow})'
                    : '—',
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                    ),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(AgentStatus status) => switch (status) {
    AgentStatus.empty => 'empty',
    AgentStatus.booting => 'starting',
    AgentStatus.idle => 'ready',
    AgentStatus.streaming => 'streaming',
    AgentStatus.crashed => 'ended',
  };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.typo.label.copyWith(
        fontSize: 10.5,
        letterSpacing: 0.7,
        color: context.colors.text3,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.typo.label.copyWith(color: context.colors.text2),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.inputFormatters,
  });
  final TextEditingController controller;
  final String hint;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      inputFormatters: inputFormatters,
      style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: context.typo.body.copyWith(
          fontSize: 13.5,
          color: colors.text3,
        ),
        filled: true,
        fillColor: colors.panel2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: context.typo.mono.copyWith(
                fontSize: 12,
                color: colors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
