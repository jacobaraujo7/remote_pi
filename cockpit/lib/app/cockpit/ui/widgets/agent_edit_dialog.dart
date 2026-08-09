import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;
import 'package:shadcn_flutter/shadcn_flutter.dart';

typedef AgentEditResult = ({String agentName, bool autoStartRelay});

/// Dialog "Editar agente": nome editável + toggle relay + infos do agente.
/// Devolve [AgentEditResult] ou `null` se cancelar.
Future<AgentEditResult?> showAgentEditDialog(
  BuildContext context, {
  required AgentSession session,
}) {
  return showDialog<AgentEditResult>(
    context: context,
    barrierColor: context.colors.scrim,
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
    Navigator.of(
      context,
    ).pop((agentName: name, autoStartRelay: _autoStartRelay));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final ctx = session.contextUsage;
    final tr = context.t.cockpit.agentEditDialog;

    return AlertDialog(
      title: Text(
        tr.title,
        style: context.typo.title.copyWith(fontSize: 16, color: colors.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(tr.agentName),
              const SizedBox(height: 6),
              _Field(
                controller: _name,
                hint: tr.agentName,
                inputFormatters: [
                  FilteringTextInputFormatter(
                    RegExp(r' '),
                    allow: false,
                    replacementString: '-',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _SectionTitle(tr.relaySection),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr.autoConnect,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                  Switch(
                    value: _autoStartRelay,
                    onChanged: (v) => setState(() => _autoStartRelay = v),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _SectionTitle(tr.informationSection),
              const SizedBox(height: 8),
              _InfoRow(tr.folder, session.workingDirectory),
              _InfoRow(tr.model, session.model?.name ?? '—'),
              _InfoRow(tr.state, _statusLabel(context, session.status)),
              _InfoRow(
                tr.context,
                ctx?.percent != null
                    ? '${ctx!.percent!.toStringAsFixed(ctx.percent! < 10 ? 1 : 0)}%  (${ctx.tokens ?? "?"}/${ctx.contextWindow})'
                    : '—',
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(onPressed: _save, child: Text(context.t.common.save)),
      ],
    );
  }

  String _statusLabel(BuildContext context, AgentStatus status) {
    final tr = context.t.cockpit.agentEditDialog;
    return switch (status) {
      AgentStatus.empty => tr.statusEmpty,
      AgentStatus.booting => tr.statusStarting,
      AgentStatus.idle => tr.statusReady,
      AgentStatus.streaming => tr.statusStreaming,
      AgentStatus.crashed => tr.statusEnded,
    };
  }
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
      placeholder: Text(hint),
      style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text),
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
