import 'package:cockpit/app/core/ui/font_catalog.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Resultado do seletor: uma família escolhida, ou `null` para "usar o padrão".
/// Como `null` também é o retorno de um dialog dispensado, o valor vem embrulhado.
class FontChoice {
  const FontChoice(this.family);

  /// `null` = voltar ao padrão do design.
  final String? family;
}

/// Escolhe uma família de fonte a partir das disponíveis na máquina.
///
/// Existe porque o campo de texto livre que havia antes falhava em silêncio:
/// um nome com erro de digitação, ou de uma fonte não instalada, caía no
/// fallback sem avisar. Aqui a lista já é só do que resolve de verdade, cada
/// item é renderizado **na própria fonte**, e o texto livre continua disponível
/// para o que a lista não cobre.
///
/// [monospacedOnly] filtra por avanço uniforme: para código e terminal, uma
/// fonte proporcional é sempre erro.
Future<FontChoice?> showFontPickerDialog(
  BuildContext context, {
  required String? current,
  required String defaultLabel,
  bool monospacedOnly = false,
}) {
  return showDialog<FontChoice>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => _FontPickerDialog(
      current: current,
      defaultLabel: defaultLabel,
      monospacedOnly: monospacedOnly,
    ),
  );
}

class _FontPickerDialog extends StatefulWidget {
  const _FontPickerDialog({
    required this.current,
    required this.defaultLabel,
    required this.monospacedOnly,
  });

  final String? current;
  final String defaultLabel;
  final bool monospacedOnly;

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  /// Medido uma vez por abertura: são dezenas de layouts de texto, barato mas
  /// não de graça, e o resultado não muda enquanto o dialog está aberto.
  late final List<FontOption> _all = availableFonts();
  late final TextEditingController _search = TextEditingController();
  late final TextEditingController _custom = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _search.dispose();
    _custom.dispose();
    super.dispose();
  }

  List<FontOption> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _all
        .where((o) => !widget.monospacedOnly || o.monospaced)
        .where((o) => query.isEmpty || o.family.toLowerCase().contains(query))
        .toList();
  }

  void _pick(String? family) => Navigator.of(context).pop(FontChoice(family));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.settings.page.appearance;
    final options = _visible;

    return AlertDialog(
      title: Text(tr.fontPickerTitle),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              placeholder: Text(tr.fontPickerSearch),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _OptionTile(
              label: widget.defaultLabel,
              preview: null,
              selected: widget.current == null,
              onTap: () => _pick(null),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: options.isEmpty
                  ? Center(
                      child: Text(
                        tr.fontPickerEmpty,
                        style: typo.label.copyWith(color: colors.text3),
                      ),
                    )
                  : ListView.builder(
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final option = options[i];
                        return _OptionTile(
                          label: option.family,
                          preview: option.family,
                          selected: option.family == widget.current,
                          badge: option.bundled ? tr.fontPickerBundled : null,
                          onTap: () => _pick(option.family),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            // Escape hatch: a lista de candidatas nunca vai cobrir tudo que a
            // máquina tem, então digitar o nome continua sendo possível.
            Text(
              tr.fontPickerCustom,
              style: typo.label.copyWith(color: colors.text3),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _custom,
                    placeholder: Text(tr.fontPickerCustomHint),
                    onSubmitted: (value) {
                      final family = value.trim();
                      if (family.isNotEmpty) _pick(family);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PrimaryButton(
                  onPressed: () {
                    final family = _custom.text.trim();
                    if (family.isNotEmpty) _pick(family);
                  },
                  child: Text(tr.fontPickerUse),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;

  /// Família em que o nome é desenhado. `null` = estilo padrão da UI.
  final String? preview;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    return HoverTap(
      color: selected ? colors.panel3 : null,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // O nome desenhado na própria fonte é o que torna a escolha
              // possível sem tentativa e erro.
              style: preview == null
                  ? typo.body.copyWith(fontSize: 14, color: colors.text)
                  : TextStyle(
                      fontFamily: preview,
                      fontSize: 14,
                      color: colors.text,
                    ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Text(badge!, style: typo.label.copyWith(color: colors.text3)),
          ],
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, size: 15, color: colors.accent),
          ],
        ],
      ),
    );
  }
}
