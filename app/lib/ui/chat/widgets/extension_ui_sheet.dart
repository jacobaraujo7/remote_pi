import 'dart:async';

import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Plan/51 — full-screen modal rendering an interactive `extension_ui_request`
/// (ask_user via pi-ask).
///
/// Drives the rich `ask` envelope when present (single/multi/preview options +
/// custom text per question), else falls back to the plain SDK method
/// (select/input/confirm). Submits an [ExtensionUiResponse] via [onRespond];
/// the [ChatViewModel] clears the pending request (removing this sheet from the
/// tree) and relays the answer to pi-ask through the bridge.
///
/// Validation follows pi-ask's rules: for non-multi questions a custom text and
/// a selected value can't be combined, so custom text wins when present.
class ExtensionUiSheet extends StatefulWidget {
  final ExtensionUiRequest request;
  /// Plan/51 — submit-result rejection message for [request] (null when none /
  /// resolved). Surfaced so the user can retry instead of hitting a dead end
  /// when pi-ask rejects an answer.
  final String? error;
  final Future<void> Function(ExtensionUiResponse) onRespond;

  const ExtensionUiSheet({
    super.key,
    required this.request,
    this.error,
    required this.onRespond,
  });

  @override
  State<ExtensionUiSheet> createState() => _ExtensionUiSheetState();
}

class _ExtensionUiSheetState extends State<ExtensionUiSheet> {
  // Rich (ask) state: question id → selected option values.
  final Map<String, Set<String>> _selected = {};
  // Rich: question id → custom text controller (lazily created, disposed).
  final Map<String, TextEditingController> _custom = {};
  // Degraded (no ask envelope) state.
  String? _singleValue;
  final TextEditingController _textController = TextEditingController();
  bool _submitting = false;
  // Plan/51 — backstop so a submit/cancel that never gets a `completed`/error
  // (relay drop, pi-ask gone) doesn't strand the user on a spinner forever.
  Timer? _submitTimeout;
  bool _awaitHint = false;

  AskEnrichmentWire? get _ask => widget.request.ask;

  @override
  void didUpdateWidget(covariant ExtensionUiSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Either a different request replaced this one, or an error/clear arrived
    // for the same request — in both cases stop spinning so the user can act.
    if (widget.request.id != oldWidget.request.id ||
        widget.error != oldWidget.error) {
      _submitTimeout?.cancel();
      setState(() {
        _submitting = false;
        _awaitHint = false;
      });
    }
  }

  void _armSubmitTimeout() {
    _submitTimeout?.cancel();
    _submitTimeout = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_submitting) return;
      setState(() {
        _submitting = false;
        _awaitHint = true;
      });
    });
  }

  @override
  void dispose() {
    _submitTimeout?.cancel();
    for (final c in _custom.values) {
      c.dispose();
    }
    _textController.dispose();
    super.dispose();
  }

  TextEditingController _customFor(String qid) =>
      _custom.putIfAbsent(qid, TextEditingController.new);

  bool _isMulti(AskQuestionWire q) =>
      q.type == AskQuestionWireType.multi ||
      q.presentedType == AskQuestionWireType.multi;

  bool get _canSubmit {
    final ask = _ask;
    if (ask != null) {
      for (final q in ask.questions) {
        if ((_selected[q.id]?.isNotEmpty ?? false) ||
            _customFor(q.id).text.trim().isNotEmpty) {
          return true;
        }
      }
      return false;
    }
    return switch (widget.request.method) {
      ExtensionUiMethod.select => _singleValue != null,
      ExtensionUiMethod.input || ExtensionUiMethod.editor =>
        _textController.text.trim().isNotEmpty,
      ExtensionUiMethod.confirm => true,
      ExtensionUiMethod.notify => false,
    };
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() {
      _submitting = true;
      _awaitHint = false;
    });
    _armSubmitTimeout();
    await widget.onRespond(_buildResponse());
    // The modal stays open until the ChatViewModel clears the pending request
    // on the `completed` dismiss notify (or surfaces an error for retry).
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _awaitHint = false;
    });
    _armSubmitTimeout();
    final ask = _ask;
    await widget.onRespond(
      ExtensionUiResponse(
        id: widget.request.id,
        cancelled: true,
        ask: ask != null
            ? AskResponseEnrichmentWire(flowId: ask.flowId, isCancel: true)
            : null,
      ),
    );
  }

  ExtensionUiResponse _buildResponse() {
    final id = widget.request.id;
    final ask = _ask;
    if (ask != null) {
      final answers = <String, AskAnswerWire>{};
      for (final q in ask.questions) {
        final selected =
            _selected[q.id]?.toList(growable: false) ?? const <String>[];
        final custom = _customFor(q.id).text.trim();
        final multi = _isMulti(q);

        // pi-ask forbids combining value + customText on non-multi questions.
        final values = multi
            ? selected
            : (custom.isNotEmpty ? const <String>[] : selected);
        final customText = custom.isEmpty ? null : custom;
        if (values.isEmpty && customText == null) continue;
        answers[q.id] = AskAnswerWire(values: values, customText: customText);
      }
      return ExtensionUiResponse(
        id: id,
        ask: AskResponseEnrichmentWire(
          flowId: ask.flowId,
          mode: 'submit',
          answers: answers,
        ),
      );
    }
    // Degraded: plain SDK response shape. The bridge maps the select label back
    // to the option value via its per-request table.
    return switch (widget.request.method) {
      ExtensionUiMethod.select =>
        ExtensionUiResponse(id: id, value: _singleValue ?? ''),
      ExtensionUiMethod.input || ExtensionUiMethod.editor =>
        ExtensionUiResponse(id: id, value: _textController.text),
      ExtensionUiMethod.confirm => ExtensionUiResponse(id: id, confirmed: true),
      ExtensionUiMethod.notify => ExtensionUiResponse(id: id, cancelled: true),
    };
  }

  void _toggle(String qid, String value, bool multi) {
    setState(() {
      final set = _selected.putIfAbsent(qid, () => <String>{});
      if (multi) {
        if (set.contains(value)) {
          set.remove(value);
        } else {
          set.add(value);
        }
      } else {
        set
          ..clear()
          ..add(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ask = _ask;
    final title =
        widget.request.title ?? ask?.title ?? 'Clarification needed';

    return Material(
      color: colors.bg,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: colors.bg,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: colors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: _submitting ? null : _cancel,
            ),
            title: Text(title),
          ),
          body: ask != null ? _buildRich(context, ask) : _buildDegraded(context),
          bottomNavigationBar: _buildActions(context),
        ),
      ),
    );
  }

  Widget _buildRich(BuildContext context, AskEnrichmentWire ask) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: ask.questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 24),
      itemBuilder: (context, i) => _buildQuestion(context, ask.questions[i]),
    );
  }

  Widget _buildQuestion(BuildContext context, AskQuestionWire q) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final multi = _isMulti(q);
    final sel = _selected[q.id] ?? <String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(q.prompt, style: text.titleMedium)),
            if (multi)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text(
                  'multi',
                  style: text.labelSmall?.copyWith(color: colors.muted),
                ),
              ),
          ],
        ),
        if (q.label.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(q.label, style: text.labelSmall?.copyWith(color: colors.muted)),
        ],
        const SizedBox(height: 12),
        for (final o in q.options) ...[
          _optionTile(context, q, o, multi, sel),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _customFor(q.id),
          enabled: !_submitting,
          decoration: InputDecoration(
            hintText: 'Type your own…',
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
    BuildContext context,
    AskQuestionWire q,
    AskOptionWire o,
    bool multi,
    Set<String> sel,
  ) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final selected = sel.contains(o.value);
    final isPreview = q.type == AskQuestionWireType.preview;

    return InkWell(
      onTap: _submitting ? null : () => _toggle(q.id, o.value, multi),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.10) : colors.surface,
          border: Border.all(
            color: selected ? colors.accent : colors.border,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  multi
                      ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                      : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                  size: 20,
                  color: selected ? colors.accent : colors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    o.label,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (o.description != null && o.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  o.description!,
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                ),
              ),
            ],
            if (isPreview &&
                o.preview != null &&
                o.preview!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.codeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  o.preview!,
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    fontSize: 12,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDegraded(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final message = widget.request.message ?? widget.request.title ?? '';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.isNotEmpty) ...[
            Text(message, style: text.bodyLarge),
            const SizedBox(height: 16),
          ],
          switch (widget.request.method) {
            ExtensionUiMethod.select => Column(
                children: [
                  for (final opt in widget.request.options)
                    RadioListTile<String>(
                      value: opt,
                      groupValue: _singleValue,
                      title: Text(opt),
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _singleValue = v),
                    ),
                ],
              ),
            ExtensionUiMethod.input || ExtensionUiMethod.editor => TextField(
                controller: _textController,
                maxLines: 5,
                enabled: !_submitting,
                decoration: InputDecoration(
                  hintText: widget.request.placeholder ?? '',
                  border: const OutlineInputBorder(),
                ),
              ),
            ExtensionUiMethod.confirm =>
              Text('Please confirm.', style: text.titleMedium),
            ExtensionUiMethod.notify =>
              Text(widget.request.message ?? '', style: text.bodyLarge),
          },
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colors = context.colors;
    final showError = widget.error != null && widget.error!.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.error!,
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
              )
            else if (_awaitHint)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No response from Pi yet — retry or cancel.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : _cancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_canSubmit && !_submitting) ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
