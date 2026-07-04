import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Mostra um comando git rodando ao vivo num dialog: as linhas de stdout/stderr
/// aparecem conforme chegam (monoespaçadas, **selecionáveis** pra copiar), com um
/// spinner no topo enquanto roda e um estado ✅ **Success** / ❌ **Failed** ao
/// terminar. Sem toast — o feedback vive no dialog. Botão único **Close**, só
/// habilitado quando o processo termina.
///
/// [success] resolve `true`/`false` quando o processo acaba. [finalMessage]
/// (opcional) devolve uma linha extra a exibir no topo conforme o resultado
/// (ex.: "Merge aborted — parent untouched.").
Future<void> showGitProcessDialog(
  BuildContext context, {
  required String title,
  required Stream<String> output,
  required Future<bool> success,
  String Function(bool ok)? finalMessage,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (context) => _GitProcessDialog(
      title: title,
      output: output,
      success: success,
      finalMessage: finalMessage,
    ),
  );
}

class _GitProcessDialog extends StatefulWidget {
  const _GitProcessDialog({
    required this.title,
    required this.output,
    required this.success,
    this.finalMessage,
  });

  final String title;
  final Stream<String> output;
  final Future<bool> success;
  final String Function(bool ok)? finalMessage;

  @override
  State<_GitProcessDialog> createState() => _GitProcessDialogState();
}

class _GitProcessDialogState extends State<_GitProcessDialog> {
  final List<String> _lines = [];
  final ScrollController _scroll = ScrollController();
  StreamSubscription<String>? _sub;
  bool _done = false;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.output.listen(
      (line) {
        if (!mounted) return;
        setState(() => _lines.add(line));
        _autoScroll();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _lines.add('$e'));
      },
    );
    widget.success.then((ok) {
      if (!mounted) return;
      setState(() {
        _done = true;
        _ok = ok;
      });
      _autoScroll();
    });
  }

  void _autoScroll() {
    // Rola pro fim no próximo frame, quando a lista já cresceu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    final Widget statusIcon;
    final String statusText;
    final Color statusColor;
    if (!_done) {
      statusIcon = const CircularProgressIndicator(size: 16);
      statusText = 'Running…';
      statusColor = colors.text3;
    } else if (_ok) {
      statusIcon = Icon(Icons.check_circle, size: 18, color: colors.ok);
      statusText = 'Success';
      statusColor = colors.ok;
    } else {
      statusIcon = Icon(Icons.cancel, size: 18, color: colors.error);
      statusText = 'Failed';
      statusColor = colors.error;
    }
    final extra = _done ? widget.finalMessage?.call(_ok) : null;

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: typo.title.copyWith(fontSize: 15, color: colors.text),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              statusIcon,
              const SizedBox(width: 8),
              Text(
                statusText,
                style: typo.label.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (extra != null) ...[
            const SizedBox(height: 4),
            Text(extra, style: typo.label.copyWith(color: colors.text3)),
          ],
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 360),
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.panel3,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: colors.border),
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            child: SelectableText(
              _lines.isEmpty ? ' ' : _lines.join('\n'),
              style: typo.mono.copyWith(fontSize: 12, color: colors.text2),
            ),
          ),
        ),
      ),
      actions: [
        PrimaryButton(
          onPressed: _done ? () => Navigator.of(context).pop() : null,
          child: Text(_done ? 'Close' : 'Running…'),
        ),
      ],
    );
  }
}
