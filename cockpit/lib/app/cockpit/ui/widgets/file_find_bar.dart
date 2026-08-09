import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Resultado do casamento da busca no arquivo: os ranges e se a regex era
/// inválida (só possível no modo `.*`). `matches` vazio + `invalidRegex` true
/// distingue "0 resultados" de "expressão inválida" na UI.
class FileFindResult {
  const FileFindResult(this.matches, {this.invalidRegex = false});

  final List<MatchSpan> matches;
  final bool invalidRegex;

  static const empty = FileFindResult(<MatchSpan>[]);
}

/// Casa [query] em [text] respeitando as opções (case / palavra inteira /
/// regex) e devolve os ranges em offsets UTF-16. Ignora matches de largura zero
/// (ex.: regex `a*`) pra não travar a navegação.
FileFindResult computeFileMatches(
  String text,
  String query, {
  bool caseSensitive = false,
  bool wholeWord = false,
  bool regex = false,
}) {
  if (query.isEmpty) return FileFindResult.empty;
  final RegExp re;
  try {
    var pattern = regex ? query : RegExp.escape(query);
    if (wholeWord)
      pattern =
          r'\b(?:'
          '$pattern'
          r')\b';
    re = RegExp(pattern, caseSensitive: caseSensitive, multiLine: true);
  } catch (_) {
    return const FileFindResult(<MatchSpan>[], invalidRegex: true);
  }
  final out = <MatchSpan>[];
  for (final m in re.allMatches(text)) {
    if (m.end > m.start) out.add(MatchSpan(m.start, m.end));
  }
  return FileFindResult(out);
}

/// Barra flutuante de **busca no arquivo** (Cmd+F), estilo VSCode: campo +
/// contador "N de M" + navegação (↑/↓) + toggles Aa/ab/.* + fechar. Ancorada no
/// topo-direito do editor. Todo o estado (query, opções, matches) vive no
/// [FileViewer]; esta barra só reflete e emite eventos.
class FileFindBar extends StatelessWidget {
  const FileFindBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.currentIndex,
    required this.caseSensitive,
    required this.wholeWord,
    required this.regex,
    required this.invalidRegex,
    required this.onChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
    required this.onToggleCase,
    required this.onToggleWord,
    required this.onToggleRegex,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Total de matches e índice (base 0) do atual (-1 = nenhum).
  final int matchCount;
  final int currentIndex;

  final bool caseSensitive;
  final bool wholeWord;
  final bool regex;
  final bool invalidRegex;

  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;
  final VoidCallback onToggleCase;
  final VoidCallback onToggleWord;
  final VoidCallback onToggleRegex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final hasQuery = controller.text.isNotEmpty;
    final String counter;
    if (invalidRegex) {
      counter = context.t.cockpit.findBar.badPattern;
    } else if (!hasQuery) {
      counter = '';
    } else if (matchCount == 0) {
      counter = context.t.cockpit.findBar.noResults;
    } else {
      counter = '${currentIndex + 1} of $matchCount';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border2),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): onNext,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    onPrev,
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                placeholder: Text(
                  context.t.cockpit.findBar.find,
                  style: typo.body.copyWith(fontSize: 13, color: colors.text4),
                ),
                style: typo.body.copyWith(fontSize: 13, color: colors.text),
                border: Border.all(
                  color: invalidRegex ? colors.error : colors.border,
                ),
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FindToggle(
            label: 'Aa',
            tooltip: context.t.cockpit.findBar.matchCase,
            active: caseSensitive,
            onTap: onToggleCase,
          ),
          _FindToggle(
            label: 'ab',
            tooltip: context.t.cockpit.findBar.wholeWord,
            active: wholeWord,
            underline: true,
            onTap: onToggleWord,
          ),
          _FindToggle(
            label: '.*',
            tooltip: context.t.cockpit.findBar.useRegex,
            active: regex,
            onTap: onToggleRegex,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 66,
            child: Text(
              counter,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: typo.label.copyWith(
                fontSize: 11,
                color: invalidRegex ? colors.error : colors.text3,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _NavButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: context.t.cockpit.findBar.previous,
            enabled: matchCount > 0,
            onTap: onPrev,
          ),
          _NavButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: context.t.cockpit.findBar.next,
            enabled: matchCount > 0,
            onTap: onNext,
          ),
          _NavButton(
            icon: Icons.close,
            tooltip: context.t.cockpit.findBar.close,
            enabled: true,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// Toggle compacto (Aa / ab / .*) da barra de busca no arquivo.
class _FindToggle extends StatelessWidget {
  const _FindToggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.underline = false,
  });

  final String label;
  final String tooltip;
  final bool active;
  final bool underline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: context.typo.mono.copyWith(
              fontSize: 11,
              color: active ? colors.accentText : colors.text3,
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão de ícone da barra (navegação / fechar).
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? onTap : () {},
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? colors.text2 : colors.text4,
          ),
        ),
      ),
    );
  }
}
