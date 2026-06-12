import 'package:app/domain/session_state.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

class AskUserPromptCard extends StatefulWidget {
  final AskUserPromptMsg prompt;

  /// `selections` for mode selection, `freeform` for text answer, `comment` for
  /// optional free comment, `cancelled` to send cancellation.
  final void Function(
    String id,
    List<String>? selections,
    String? freeform,
    String? comment,
    bool cancelled,
  )
  onRespond;

  const AskUserPromptCard({
    super.key,
    required this.prompt,
    required this.onRespond,
  });

  @override
  State<AskUserPromptCard> createState() => _AskUserPromptCardState();
}

class _AskUserPromptCardState extends State<AskUserPromptCard> {
  final _commentCtl = TextEditingController();
  final _freeformCtl = TextEditingController();
  final Set<int> _selected = {};

  @override
  void dispose() {
    _commentCtl.dispose();
    _freeformCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final prompt = widget.prompt;
    final resolved = prompt.resolved || prompt.cancelled;

    final border = resolved
        ? (prompt.cancelled ? colors.muted : colors.success)
        : colors.accent;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'ASK_USER',
                style: TextStyle(
                  fontFamily: kMonoFamily,
                  fontSize: 11,
                  color: border,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (resolved && prompt.cancelled)
                Text('Cancelled', style: TextStyle(color: colors.muted2)),
              if (resolved && !prompt.cancelled)
                Text('Answered', style: TextStyle(color: colors.success)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            prompt.question,
            style: TextStyle(fontFamily: kMonoFamily, color: colors.text),
          ),
          if (prompt.context.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              prompt.context,
              style: TextStyle(fontSize: 12, color: colors.muted2),
            ),
          ],
          if (prompt.answerLabel != null && prompt.answerLabel!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              prompt.answerLabel!,
              style: TextStyle(fontSize: 12, color: colors.text),
            ),
          ],
          if (!resolved && prompt.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildOptions(context),
          ],
          if (!resolved && prompt.allowFreeform) _buildFreeform(context),
          if (!resolved && prompt.allowComment) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtl,
              enabled: !resolved,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Comment (optional)',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: resolved
                ? const []
                : [
                    OutlinedButton(
                      onPressed: () => widget.onRespond(
                        prompt.id,
                        null,
                        null,
                        _commentCtl.text.isEmpty ? null : _commentCtl.text,
                        true,
                      ),
                      child: const Text('Cancel'),
                    ),
                    if (_selected.isNotEmpty)
                      FilledButton(
                        onPressed: () => _submitSelection(),
                        child: const Text('Submit selection'),
                      ),
                    if (prompt.allowFreeform &&
                        _freeformCtl.text.trim().isNotEmpty)
                      FilledButton(
                        onPressed: () => _submitFreeform(),
                        child: const Text('Submit text'),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(BuildContext context) {
    final prompt = widget.prompt;
    if (prompt.options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < prompt.options.length; i++)
          InkWell(
            onTap: prompt.resolved || prompt.cancelled
                ? null
                : () {
                    setState(() {
                      if (prompt.allowMultiple) {
                        if (_selected.contains(i)) {
                          _selected.remove(i);
                        } else {
                          _selected.add(i);
                        }
                      } else {
                        _selected
                          ..clear()
                          ..add(i);
                      }
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    prompt.allowMultiple
                        ? (_selected.contains(i)
                              ? Icons.check_box
                              : Icons.check_box_outline_blank)
                        : (_selected.contains(i)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off),
                    size: 18,
                    color: context.colors.text,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prompt.options[i].title),
                        if (prompt.options[i].description != null &&
                            prompt.options[i].description!.isNotEmpty)
                          Text(
                            prompt.options[i].description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFreeform(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _freeformCtl,
        enabled: !(widget.prompt.resolved || widget.prompt.cancelled),
        decoration: const InputDecoration(isDense: true, labelText: 'Answer'),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  void _submitSelection() {
    final prompt = widget.prompt;
    final selections = [
      for (final idx in _selected)
        if (idx >= 0 && idx < prompt.options.length) prompt.options[idx].title,
    ];
    widget.onRespond(
      prompt.id,
      selections.isEmpty ? null : selections,
      null,
      _commentCtl.text.isEmpty ? null : _commentCtl.text,
      false,
    );
  }

  void _submitFreeform() {
    final prompt = widget.prompt;
    final text = _freeformCtl.text.trim();
    widget.onRespond(
      prompt.id,
      null,
      text.isEmpty ? null : text,
      _commentCtl.text.isEmpty ? null : _commentCtl.text,
      false,
    );
  }
}
