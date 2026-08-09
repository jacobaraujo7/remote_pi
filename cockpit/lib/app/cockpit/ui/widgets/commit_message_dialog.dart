import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/exceptions/automation_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/automation_error_message.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dialog de mensagem de commit (Source Control → "Commit"/"Stage and Commit").
///
/// Valida ao vivo, seguindo as convenções de commit do git:
/// - **subject** (1ª linha): obrigatório, 3–72 caracteres, sem terminar em "."
///   e sem caracteres de controle; contador `n/72` ao vivo;
/// - **corpo** opcional: se existir, a 2ª linha deve ficar em branco
///   (separador subject/corpo do git).
///
/// Ao confirmar, trava com spinner e chama [onCommit] (que roda o
/// `git commit` real): mensagem de erro → mostra inline; `null` → fecha.
Future<void> showCommitMessageDialog(
  BuildContext context, {
  required String fileName,
  required bool staged,
  required Future<String?> Function(String message) onCommit,
  Future<Result<GeneratedCommitMessage, AutomationError>> Function()?
  onGenerate,
  Future<void> Function()? onCancelGenerate,
  String? generatorLabel,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: context.colors.scrim,
    builder: (context) => _CommitMessageDialog(
      fileName: fileName,
      staged: staged,
      onCommit: onCommit,
      onGenerate: onGenerate,
      onCancelGenerate: onCancelGenerate,
      generatorLabel: generatorLabel,
    ),
  );
}

class _CommitMessageDialog extends StatefulWidget {
  const _CommitMessageDialog({
    required this.fileName,
    required this.staged,
    required this.onCommit,
    required this.onGenerate,
    required this.onCancelGenerate,
    required this.generatorLabel,
  });

  final String fileName;
  final bool staged;
  final Future<String?> Function(String message) onCommit;
  final Future<Result<GeneratedCommitMessage, AutomationError>> Function()?
  onGenerate;
  final Future<void> Function()? onCancelGenerate;
  final String? generatorLabel;

  @override
  State<_CommitMessageDialog> createState() => _CommitMessageDialogState();
}

class _CommitMessageDialogState extends State<_CommitMessageDialog> {
  static const int _subjectMax = 72;
  static const int _subjectMin = 3;

  final TextEditingController _message = TextEditingController();
  bool _submitting = false;
  bool _generating = false;
  String? _gitError;
  String? _generationError;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _subject {
    final text = _message.text;
    final nl = text.indexOf('\n');
    return (nl < 0 ? text : text.substring(0, nl)).trim();
  }

  /// Regras da mensagem — `null` = válida (ou campo ainda intacto).
  String? get _reason {
    final text = _message.text;
    if (text.isEmpty) return null; // intacto: sem erro, botão desabilitado
    final tr = context.t.cockpit.commitMessageDialog;
    final subject = _subject;
    if (subject.isEmpty) return tr.errorEmptySubject;
    if (subject.length < _subjectMin) {
      return tr.errorTooShort(min: _subjectMin);
    }
    if (subject.length > _subjectMax) {
      return tr.errorTooLong(max: _subjectMax);
    }
    if (subject.endsWith('.')) {
      return tr.errorTrailingPeriod;
    }
    if (subject.codeUnits.any((c) => c < 0x20)) {
      return tr.errorControlChars;
    }
    final lines = text.split('\n');
    if (lines.length > 1 && lines[1].trim().isNotEmpty) {
      return tr.errorBlankSecondLine;
    }
    return null;
  }

  bool get _canCommit =>
      _message.text.trim().isNotEmpty &&
      _reason == null &&
      !_submitting &&
      !_generating;

  bool get _busy => _generating || _submitting;

  Future<void> _generate() async {
    final generate = widget.onGenerate;
    if (generate == null || _generating || _submitting) return;
    setState(() {
      _generating = true;
      _generationError = null;
      _gitError = null;
    });
    final result = await generate();
    if (!mounted) return;
    result.fold<void>(
      (draft) {
        _message.value = TextEditingValue(
          text: draft.message,
          selection: TextSelection.collapsed(offset: draft.message.length),
        );
        setState(() {
          _generating = false;
          _generationError = draft.warning;
        });
      },
      (error) => setState(() {
        _generating = false;
        // Cancelamento é ação do usuário, não erro a exibir em vermelho.
        _generationError = error.kind == AutomationErrorKind.cancelled
            ? null
            : automationErrorMessage(context, error);
      }),
    );
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_generating) {
      await widget.onCancelGenerate?.call();
      if (!mounted) return;
      setState(() => _generating = false);
    }
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_canCommit) return;
    setState(() {
      _submitting = true;
      _gitError = null;
    });
    final error = await widget.onCommit(_message.text.trim());
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _gitError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reason = _gitError ?? _generationError ?? _reason;
    final showError = reason != null;
    final count = _subject.length;
    final tr = context.t.cockpit.commitMessageDialog;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.staged ? tr.commitTitle : tr.stageAndCommitTitle,
              style: context.typo.title.copyWith(
                fontSize: 15,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr.scopeNote(fileName: widget.fileName),
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _message,
                autofocus: true,
                enabled: !_submitting && !_generating,
                maxLines: 4,
                onChanged: (_) => setState(() {
                  _gitError = null;
                  _generationError = null;
                }),
                placeholder: Text(tr.placeholder),
                style: context.typo.mono.copyWith(
                  fontSize: 13,
                  color: colors.text,
                ),
                borderRadius: BorderRadius.circular(7),
                border: showError ? Border.all(color: colors.error) : null,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (showError)
                    Expanded(
                      child: Text(
                        reason,
                        style: context.typo.label.copyWith(color: colors.error),
                      ),
                    )
                  else
                    const Spacer(),
                  Text(
                    '$count/$_subjectMax',
                    style: context.typo.label.copyWith(
                      fontSize: 11,
                      color: count > _subjectMax ? colors.error : colors.text4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          AppTooltip(
            message: widget.generatorLabel == null
                ? tr.generate
                : tr.generateWith(harness: widget.generatorLabel!),
            child: OutlineButton(
              onPressed: widget.onGenerate == null || _busy ? null : _generate,
              child: _generating
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(size: 14),
                        const SizedBox(width: 8),
                        Text(tr.generating),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome, size: 15),
                        const SizedBox(width: 7),
                        Text(tr.generate),
                      ],
                    ),
            ),
          ),
          OutlineButton(
            onPressed: _submitting ? null : _cancel,
            child: Text(
              _generating ? tr.cancelGeneration : context.t.common.cancel,
            ),
          ),
          PrimaryButton(
            onPressed: _canCommit ? _submit : null,
            child: _submitting
                ? CircularProgressIndicator(
                    size: 16,
                    color: onColor(context.colors.accent),
                  )
                : Text(tr.commitTitle),
          ),
        ],
      ),
    );
  }
}
